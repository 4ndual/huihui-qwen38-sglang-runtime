# Huihui Qwen3.8 SGLang DFlash2 runtime

Pinned, model-free RunPod Serverless runtime for the Huihui Qwen3.8-27B
NVFP4 target and the Qwen3.8 DFlash2 BF16 draft.

- SGLang source commit: `5f55db35e926d50676f75b812640ea2410b0fe0e`
- Validated source image: `lmsysorg/sglang@sha256:b91d664a8e4825afc16ab831c6035a6c88ac20ef8bd26da4fe2b9813a9f44376`
- CUDA userspace base: `nvidia/cuda@sha256:a85c9f5af049f0ab679c1669ae6fa8393022886739af7361e85bb96878e8cdd4`
- Models are never embedded; startup reads the exact pinned revisions from the
  attached RunPod High-Performance Network Volume.

The image exposes SGLang directly on port 30000 and publishes a readiness-only
`/ping` endpoint on port 8001 after models, DFlash, graphs, and a local health
inference have completed.
