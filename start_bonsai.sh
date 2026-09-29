#!/usr/bin/env bash
set -euo pipefail

MODEL_REPO="${MODEL_REPO:-prism-ml/Ternary-Bonsai-2-27B-gguf}"
MODEL_FILE="${MODEL_FILE:-Ternary-Bonsai-2-27B-PTQ1_0.gguf}"
MODEL_DIR="${MODEL_DIR:-/models}"
MODEL_PATH="${MODEL_DIR}/${MODEL_FILE}"

CONTEXT_SIZE="${CONTEXT_SIZE:-32768}"
GPU_LAYERS="${GPU_LAYERS:-99}"
PARALLEL="${PARALLEL:-1}"
CACHE_RAM_MB="${CACHE_RAM_MB:-24576}"
SERVER_HOST="${SERVER_HOST:-127.0.0.1}"
SERVER_PORT="${SERVER_PORT:-8080}"

mkdir -p "${MODEL_DIR}"

if [[ ! -f "${MODEL_PATH}" ]]; then
  echo "[bonsai] Downloading ${MODEL_REPO}/${MODEL_FILE} to ${MODEL_DIR}"
  python3 - <<'PY'
import os
from huggingface_hub import hf_hub_download

repo = os.environ.get("MODEL_REPO", "prism-ml/Ternary-Bonsai-2-27B-gguf")
filename = os.environ.get("MODEL_FILE", "Ternary-Bonsai-2-27B-PTQ1_0.gguf")
model_dir = os.environ.get("MODEL_DIR", "/models")
token = os.environ.get("HF_TOKEN") or None

hf_hub_download(
    repo_id=repo,
    filename=filename,
    local_dir=model_dir,
    token=token,
)
PY
fi

echo "[bonsai] Starting llama-server with ${MODEL_FILE}"

exec /opt/prism/bin/llama-server \
  -m "${MODEL_PATH}" \
  --host "${SERVER_HOST}" \
  --port "${SERVER_PORT}" \
  -ngl "${GPU_LAYERS}" \
  -c "${CONTEXT_SIZE}" \
  -np "${PARALLEL}" \
  --cache-ram "${CACHE_RAM_MB}" \
  -fa on \
  --jinja \
  --temp 1.0 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.05
