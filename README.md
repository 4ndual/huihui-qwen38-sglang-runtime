# Huihui Qwen3.8 SGLang DFlash2 runtime

Pinned, model-free RunPod Serverless runtime for the Huihui Qwen3.8-27B
NVFP4 target and the Qwen3.8 DFlash2 BF16 draft.

- SGLang source commit: `5f55db35e926d50676f75b812640ea2410b0fe0e`
- Validated source image: `lmsysorg/sglang@sha256:b91d664a8e4825afc16ab831c6035a6c88ac20ef8bd26da4fe2b9813a9f44376`
- CUDA userspace base: `nvidia/cuda:13.0.3-runtime-ubuntu24.04` linux/amd64 digest `sha256:1d66a0c2041af1dfff8a13072a2e8f0543bbdf7a44224c2c96fd9d6445fb7c9a`
- Models are never embedded; startup reads the exact pinned revisions from the
  attached RunPod High-Performance Network Volume.
- The runtime intentionally uses Ubuntu's built-in `C.UTF-8` locale and carries
  no locale-generation or CUDA compiler payload.

The image exposes SGLang directly on port 30000 and publishes a readiness-only
`/ping` endpoint on port 8001 after models, DFlash, graphs, and a local health
inference have completed.
