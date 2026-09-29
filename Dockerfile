# syntax=docker/dockerfile:1

ARG CUDA_VERSION=12.4.1

FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Bonsai 2 PQ2_0/PTQ1_0 requires the PrismML llama.cpp fork.
RUN git clone --depth 1 --branch prism https://github.com/PrismML-Eng/llama.cpp.git

WORKDIR /src/llama.cpp

# Docker builds do not have a real NVIDIA driver mounted. CUDA devel images
# provide libcuda.so as a stub specifically for link-time use. Some linkers
# resolve the transitive SONAME as libcuda.so.1, so provide that alias too.
RUN test -f /usr/local/cuda/lib64/stubs/libcuda.so \
    && ln -sf libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1

ENV LIBRARY_PATH=/usr/local/cuda/lib64/stubs
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64/stubs

# Build for the 24 GB Ampere/Ada GPUs exposed by the Hub presets:
# sm_86 = RTX 3090/A5000, sm_89 = RTX 4090/L4.
RUN cmake -S . -B build \
      -DGGML_CUDA=ON \
      -DLLAMA_CURL=OFF \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CUDA_ARCHITECTURES="86;89" \
      -DCMAKE_EXE_LINKER_FLAGS="-L/usr/local/cuda/lib64/stubs -Wl,-rpath-link,/usr/local/cuda/lib64/stubs" \
      -DCMAKE_SHARED_LINKER_FLAGS="-L/usr/local/cuda/lib64/stubs -Wl,-rpath-link,/usr/local/cuda/lib64/stubs" \
    && cmake --build build --config Release -j"$(nproc)" --target llama-server

FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    MODEL_REPO=prism-ml/Ternary-Bonsai-2-27B-gguf \
    MODEL_FILE=Ternary-Bonsai-2-27B-PTQ1_0.gguf \
    CONTEXT_SIZE=32768 \
    GPU_LAYERS=99 \
    PARALLEL=1 \
    DEFAULT_MAX_TOKENS=16384 \
    DEFAULT_REASONING_EFFORT=medium

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libgomp1 \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Runtime libcuda.so.1 comes from the NVIDIA driver mounted by RunPod.
COPY --from=builder /src/llama.cpp/build/bin/ /opt/prism/bin/
COPY requirements.txt /app/requirements.txt
RUN python3 -m pip install --no-cache-dir -r /app/requirements.txt

COPY start_bonsai.sh /app/start_bonsai.sh
COPY handler.py /app/handler.py
RUN chmod +x /app/start_bonsai.sh && mkdir -p /models

CMD ["python3", "-u", "/app/handler.py"]
