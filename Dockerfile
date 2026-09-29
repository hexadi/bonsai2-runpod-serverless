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
# The prism branch is the active low-bit runtime line.
RUN git clone --depth 1 --branch prism https://github.com/PrismML-Eng/llama.cpp.git

WORKDIR /src/llama.cpp

RUN cmake -S . -B build \
      -DGGML_CUDA=ON \
      -DLLAMA_CURL=OFF \
      -DCMAKE_BUILD_TYPE=Release \
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
    CACHE_RAM_MB=24576 \
    DEFAULT_MAX_TOKENS=16384 \
    DEFAULT_REASONING_EFFORT=medium

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libgomp1 \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the server plus all shared libraries produced by the matching build.
COPY --from=builder /src/llama.cpp/build/bin/ /opt/prism/bin/
COPY requirements.txt /app/requirements.txt
RUN python3 -m pip install --no-cache-dir -r /app/requirements.txt

COPY start_bonsai.sh /app/start_bonsai.sh
COPY handler.py /app/handler.py
RUN chmod +x /app/start_bonsai.sh && mkdir -p /models

CMD ["python3", "-u", "/app/handler.py"]
