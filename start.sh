#!/usr/bin/env bash
set -Eeuo pipefail

VOLUME_ROOT='/runpod-volume/runpod-huihui-qwen38'
TARGET_MODEL_DIR="$VOLUME_ROOT/models/huihui-qwen38-nvfp4"
DRAFT_MODEL_DIR="$VOLUME_ROOT/models/qwen38-dflash2-bf16"
STATUS_DIR="$VOLUME_ROOT/status"
CACHE_KEY="${GPU_CACHE_KEY:-sm120-pro6000}"
CACHE_ROOT="$VOLUME_ROOT/runtime-cache/$CACHE_KEY"
SERVED_MODEL_NAME='sakamakismile/Huihui-Qwen3.8-27B-abliterated-NVFP4'
TARGET_REVISION='36276309d30211d9babf72f22d1605dc2dc6357c'
DRAFT_REVISION='50307d4c4cde6860d4eee73e2547cd786fe8e8a4'
DFLASH_DRAFT_TOKENS="${DFLASH_DRAFT_TOKENS:-8}"
PORT='30000'
PORT_HEALTH='8001'

export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
export HF_HUB_DISABLE_TELEMETRY=1
export TOKENIZERS_PARALLELISM=false
export PYTORCH_CUDA_ALLOC_CONF='expandable_segments:True'
export TORCHINDUCTOR_CACHE_DIR="$CACHE_ROOT/torchinductor"
export TRITON_CACHE_DIR="$CACHE_ROOT/triton"
export XDG_CACHE_HOME="$CACHE_ROOT/xdg"
export FLASHINFER_WORKSPACE_BASE="$CACHE_ROOT/flashinfer"
mkdir -p "$TORCHINDUCTOR_CACHE_DIR" "$TRITON_CACHE_DIR" "$XDG_CACHE_HOME" "$FLASHINFER_WORKSPACE_BASE"

echo "BOOT stage=validate-volume target=$TARGET_MODEL_DIR draft=$DRAFT_MODEL_DIR cache=$CACHE_ROOT"
test -f "$STATUS_DIR/STAGING_COMPLETE"
test "$(cat "$TARGET_MODEL_DIR/REVISION")" = "$TARGET_REVISION"
test "$(cat "$DRAFT_MODEL_DIR/REVISION")" = "$DRAFT_REVISION"
test -s "$TARGET_MODEL_DIR/model.safetensors"
test -s "$TARGET_MODEL_DIR/model-mtp-bf16.safetensors"
test -s "$TARGET_MODEL_DIR/config.json"
test -s "$DRAFT_MODEL_DIR/model.safetensors"
test -s "$DRAFT_MODEL_DIR/config.json"

# Read target and draft exactly once from the HP volume into the host page cache.
# SGLang's subsequent safetensors mapping then measures RAM/page-cache -> VRAM,
# while this stage separately reports volume -> RAM throughput.
weight_bytes=$(find "$TARGET_MODEL_DIR" "$DRAFT_MODEL_DIR" -type f -name '*.safetensors' -printf '%s\n' | awk '{s+=$1} END {printf "%.0f", s}')
preload_start_ns=$(date +%s%N)
echo "BOOT stage=volume-preload-start bytes=$weight_bytes at=$(date -u +%FT%TZ)"
find "$TARGET_MODEL_DIR" "$DRAFT_MODEL_DIR" -type f -name '*.safetensors' -print0 \
  | sort -z \
  | xargs -0 -n 1 cat >/dev/null
preload_end_ns=$(date +%s%N)
preload_ms=$(( (preload_end_ns - preload_start_ns) / 1000000 ))
preload_mib_s=$(awk -v b="$weight_bytes" -v ms="$preload_ms" 'BEGIN { if (ms > 0) printf "%.2f", b / 1048576 / (ms / 1000); else print "0" }')
echo "BOOT stage=volume-preload-complete bytes=$weight_bytes elapsed_ms=$preload_ms mib_s=$preload_mib_s at=$(date -u +%FT%TZ)"

python3 -m sglang.launch_server \
  --model-path "$TARGET_MODEL_DIR" \
  --served-model-name "$SERVED_MODEL_NAME" \
  --host 0.0.0.0 --port "$PORT" \
  --tp-size 1 \
  --context-length 32768 \
  --max-total-tokens 32768 \
  --max-running-requests 1 \
  --mem-fraction-static 0.55 \
  --kv-cache-dtype fp8_e4m3 \
  --attention-backend flashinfer \
  --chunked-prefill-size 8192 \
  --disable-prefill-cuda-graph \
  --cuda-graph-max-bs 1 \
  --disable-flashinfer-autotune \
  --enable-torch-compile \
  --torch-compile-max-bs 1 \
  --num-continuous-decode-steps 2 \
  --mamba-radix-cache-strategy extra_buffer \
  --mamba-ssm-dtype bfloat16 \
  --max-mamba-cache-size 5 \
  --enable-metrics \
  --reasoning-parser qwen3 \
  --trust-remote-code \
  --watchdog-timeout 1200 \
  --speculative-algorithm DFLASH \
  --speculative-draft-model-path "$DRAFT_MODEL_DIR" \
  --speculative-draft-model-quantization unquant \
  --speculative-num-draft-tokens "$DFLASH_DRAFT_TOKENS" \
  2>&1 | tee /tmp/sglang.log &
sglang_pipeline_pid=$!
health_pid=''

terminate() {
  kill "$sglang_pipeline_pid" 2>/dev/null || true
  if [ -n "$health_pid" ]; then kill "$health_pid" 2>/dev/null || true; fi
}
trap terminate TERM INT EXIT

ready=0
for attempt in $(seq 1 900); do
  if ! kill -0 "$sglang_pipeline_pid" 2>/dev/null; then
    wait "$sglang_pipeline_pid"
    exit $?
  fi
  if curl -fsS --max-time 3 "http://127.0.0.1:$PORT/health_generate" >/tmp/sglang-health.json; then
    ready=1
    break
  fi
  sleep 2
done
if [ "$ready" -ne 1 ]; then
  echo 'BOOT stage=failed reason=sglang-readiness-timeout'
  exit 1
fi

echo "BOOT stage=weights-dflash-graphs-ready dflash=$DFLASH_DRAFT_TOKENS at=$(date -u +%FT%TZ)"
printf '%s' 'eyJtb2RlbCI6InNha2FtYWtpc21pbGUvSHVpaHVpLVF3ZW4zLjgtMjdCLWFibGl0ZXJhdGVkLU5WRlA0IiwibWVzc2FnZXMiOlt7InJvbGUiOiJ1c2VyIiwiY29udGVudCI6IlJlcGx5IHdpdGggZXhhY3RseTogcmVhZHkifV0sInRlbXBlcmF0dXJlIjowLCJtYXhfdG9rZW5zIjo4fQ==' \
  | base64 -d >/tmp/local-health.json
curl -fsS --max-time 180 -X POST "http://127.0.0.1:$PORT/v1/chat/completions" \
  -H 'content-type: application/json' \
  --data-binary @/tmp/local-health.json \
  >/tmp/sglang-local-inference.json
grep -q '"choices"' /tmp/sglang-local-inference.json
echo "BOOT stage=local-inference-passed dflash=$DFLASH_DRAFT_TOKENS at=$(date -u +%FT%TZ)"

mkdir -p /tmp/runpod-health
printf 'ok\n' >/tmp/runpod-health/ping
python3 -m http.server "$PORT_HEALTH" --bind 0.0.0.0 --directory /tmp/runpod-health &
health_pid=$!
echo "BOOT stage=lb-ready port=$PORT health_port=$PORT_HEALTH at=$(date -u +%FT%TZ)"
wait "$sglang_pipeline_pid"

