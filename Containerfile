ARG VALIDATED_IMAGE=lmsysorg/sglang@sha256:b91d664a8e4825afc16ab831c6035a6c88ac20ef8bd26da4fe2b9813a9f44376
FROM ${VALIDATED_IMAGE} AS validated

# Repackage the exact validated DFlash2 commit into the official production
# runtime layout. This avoids recompiling SGLang while dropping framework-only
# development tooling. The CUDA image is pinned to the linux/amd64 digest.
FROM nvidia/cuda@sha256:a85c9f5af049f0ab679c1669ae6fa8393022886739af7361e85bb96878e8cdd4 AS runtime

ARG GDRCOPY_VERSION=2.5.1
ENV DEBIAN_FRONTEND=noninteractive \
    CUDA_HOME=/usr/local/cuda \
    GDRCOPY_HOME=/usr/src/gdrdrv-${GDRCOPY_VERSION}/ \
    PATH=/opt/sglang/bin:/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/cuda/nvvm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/local/cuda/lib64 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    SGLANG_BUILD_COMMIT=5f55db35e926d50676f75b812640ea2410b0fe0e \
    SGLANG_IMAGE_TAG=ghcr.io/4ndual/huihui-qwen38-sglang-runtime:sm120-runtime

RUN apt-get update && apt-get install -y --no-install-recommends --allow-change-held-packages \
    python3.12-full python3.12-dev ca-certificates curl git locales netcat-openbsd procps \
    libopenmpi3 libnuma1 libibverbs1 libibumad3 librdmacm1 libnl-3-200 \
    libnl-route-3-200 ibverbs-providers libgoogle-glog0v6t64 libunwind8 \
    libboost-system1.83.0 libboost-thread1.83.0 libboost-filesystem1.83.0 \
    libgrpc++1.51t64 libprotobuf32t64 libhiredis1.1.0 libcurl4 libczmq4 \
    libfabric1 libssl-dev rdma-core infiniband-diags perftest ninja-build \
    libnccl2 libnccl-dev gnupg2 linux-libc-dev \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 2 \
    && update-alternatives --set python3 /usr/bin/python3.12 \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

RUN python3 -m venv /opt/sglang
COPY --from=validated /opt/sglang/lib/python3.12/site-packages /opt/sglang/lib/python3.12/site-packages
COPY --from=validated /sgl-workspace /sgl-workspace
COPY --from=validated /opt/sglang/bin/sglang /opt/sglang/bin/sglang
COPY --from=validated /root/.cache/huggingface /root/.cache/huggingface
COPY --from=validated /root/.cache/sglang /root/.cache/sglang
COPY --from=validated /usr/lib/libgdrapi.so* /usr/lib/
COPY --from=validated /usr/bin/gdrcopy_* /usr/bin/
COPY --from=validated /usr/src/gdrdrv-2.5.1 /usr/src/gdrdrv-2.5.1

RUN ln -sf /usr/lib/$(uname -m)-linux-gnu/libmlx5.so.1 /usr/lib/$(uname -m)-linux-gnu/libmlx5.so

COPY runtime/start-pro6000.sh /opt/runpod/start.sh
RUN chmod 0755 /opt/runpod/start.sh \
    && test -d /opt/sglang/lib/python3.12/site-packages/sglang \
    && test -x /opt/sglang/bin/python3 \
    && rm -rf /sgl-workspace/sglang/test /sgl-workspace/sglang/tests \
              /sgl-workspace/sglang/docs /sgl-workspace/sglang/.git

WORKDIR /sgl-workspace/sglang
LABEL org.opencontainers.image.source=https://github.com/4ndual/huihui-qwen38-sglang-runtime \
      org.opencontainers.image.revision=5f55db35e926d50676f75b812640ea2410b0fe0e \
      ai.sglang.source-image=lmsysorg/sglang@sha256:b91d664a8e4825afc16ab831c6035a6c88ac20ef8bd26da4fe2b9813a9f44376
ENTRYPOINT ["/opt/nvidia/nvidia_entrypoint.sh"]
CMD ["/opt/runpod/start.sh"]
