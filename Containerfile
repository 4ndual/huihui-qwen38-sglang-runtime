ARG VALIDATED_IMAGE=lmsysorg/sglang@sha256:b91d664a8e4825afc16ab831c6035a6c88ac20ef8bd26da4fe2b9813a9f44376
FROM ${VALIDATED_IMAGE} AS validated

# Repackage the exact validated DFlash2 commit into a C1/TP1 production
# runtime. The CUDA 13.0.3 runtime image is pinned to its linux/amd64 digest;
# compiler/devel payloads are intentionally absent unless a real JIT miss
# proves they are required.
FROM nvidia/cuda@sha256:1d66a0c2041af1dfff8a13072a2e8f0543bbdf7a44224c2c96fd9d6445fb7c9a AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
    CUDA_HOME=/usr/local/cuda \
    PATH=/opt/sglang/bin:/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/cuda/nvvm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/local/cuda/lib64 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    SGLANG_BUILD_COMMIT=5f55db35e926d50676f75b812640ea2410b0fe0e \
    SGLANG_IMAGE_TAG=ghcr.io/4ndual/huihui-qwen38-sglang-runtime:dflash2-5f55db35-sm120-runtime-v2

RUN apt-get update && apt-get install -y --no-install-recommends --allow-change-held-packages \
    python3.12-full ca-certificates curl procps libnuma1 libunwind8 libgomp1 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 2 \
    && update-alternatives --set python3 /usr/bin/python3.12 \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

RUN mkdir -p /opt/sglang/bin /opt/sglang/lib/python3.12/site-packages \
    && ln -s /usr/bin/python3.12 /opt/sglang/bin/python3 \
    && ln -s python3 /opt/sglang/bin/python \
    && ln -s python3 /opt/sglang/bin/python3.12
COPY --from=validated /opt/sglang/lib/python3.12/site-packages /opt/sglang/lib/python3.12/site-packages
COPY --from=validated /sgl-workspace /sgl-workspace
COPY --from=validated /opt/sglang/bin/sglang /opt/sglang/bin/sglang
COPY --from=validated /root/.cache/sglang /root/.cache/sglang

COPY start.sh /opt/runpod/start.sh
RUN chmod 0755 /opt/runpod/start.sh \
    && test -d /opt/sglang/lib/python3.12/site-packages/sglang \
    && test -x /opt/sglang/bin/python3 \
    && rm -rf /sgl-workspace/sglang/test /sgl-workspace/sglang/tests \
              /sgl-workspace/sglang/docs /sgl-workspace/sglang/.git

WORKDIR /sgl-workspace/sglang
LABEL org.opencontainers.image.source=https://github.com/4ndual/huihui-qwen38-sglang-runtime \
      org.opencontainers.image.revision=5f55db35e926d50676f75b812640ea2410b0fe0e \
      ai.sglang.source-image=lmsysorg/sglang@sha256:b91d664a8e4825afc16ab831c6035a6c88ac20ef8bd26da4fe2b9813a9f44376 \
      ai.cuda.runtime-image=nvidia/cuda@sha256:1d66a0c2041af1dfff8a13072a2e8f0543bbdf7a44224c2c96fd9d6445fb7c9a
ENTRYPOINT ["/opt/nvidia/nvidia_entrypoint.sh"]
CMD ["/opt/runpod/start.sh"]
