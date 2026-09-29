# Bonsai 2 27B on RunPod Serverless\n\n[![Runpod](https://api.runpod.io/badge/hexadi/bonsai2-runpod-serverless)](https://console.runpod.io/hub/listing/hexadi/bonsai2-runpod-serverless)

Run **PrismML Bonsai 2 27B** on RunPod Serverless using the PrismML `llama.cpp` fork and its OpenAI-compatible chat-completions server.

The repository is structured so it can be selected directly with **RunPod Serverless → Add your repo**. The root `Dockerfile` builds the CUDA runtime, and `handler.py` exposes the model through RunPod's queue worker API.

## What this uses

- Model: `prism-ml/Ternary-Bonsai-2-27B-gguf`
- Default packing: `Ternary-Bonsai-2-27B-PTQ1_0.gguf` (~5.95 GB)
- Runtime: `PrismML-Eng/llama.cpp` branch `prism`
- Backend: CUDA
- Default context: 32,768 tokens
- Default output cap: 16,384 tokens
- Default reasoning effort: `medium`

Bonsai 2's PQ2_0/PTQ1_0 files require PrismML's llama.cpp fork. Do not replace it with stock llama.cpp for these model files.

## Deploy from GitHub in RunPod

1. Open **RunPod → Serverless**.
2. Create a new endpoint/worker and choose **Add your repo**.
3. Connect GitHub if needed.
4. Select this repository:
   `hexadi/bonsai2-runpod-serverless`
5. Use the root `Dockerfile`.
6. Select an NVIDIA GPU with enough VRAM. A 16 GB+ GPU is a practical starting point; 24 GB provides more headroom for context and cache.
7. Deploy.

### Strongly recommended: attach a Network Volume

The model is downloaded when a worker starts. If a RunPod Network Volume is mounted at `/runpod-volume`, the worker automatically stores the model at:

`/runpod-volume/models/bonsai2`

This prevents downloading the 5.95 GB model again every time a replacement worker starts.

Without a Network Volume, the worker uses `/models`, which is local to that worker.

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `MODEL_REPO` | `prism-ml/Ternary-Bonsai-2-27B-gguf` | Hugging Face repository |
| `MODEL_FILE` | `Ternary-Bonsai-2-27B-PTQ1_0.gguf` | GGUF packing |
| `MODEL_DIR` | auto | Model cache path |
| `HF_TOKEN` | empty | Optional Hugging Face token |
| `CONTEXT_SIZE` | `32768` | llama.cpp context size |
| `GPU_LAYERS` | `99` | GPU offload layers |
| `PARALLEL` | `1` | llama-server slots |
| `CACHE_RAM_MB` | `24576` | prompt cache RAM target |
| `DEFAULT_MAX_TOKENS` | `16384` | output cap when omitted |
| `DEFAULT_REASONING_EFFORT` | `medium` | default Bonsai reasoning effort |
| `STARTUP_TIMEOUT` | `900` | seconds allowed for model startup/download |
| `REQUEST_TIMEOUT` | `1800` | upstream inference timeout |

### Switch to PQ2_0

For GPUs where PQ2_0 performs better, set:

```
MODEL_FILE=Ternary-Bonsai-2-27B-PQ2_0.gguf
```

PQ2_0 is larger (~7.21 GB) but is often faster at prompt processing and is a good choice for A100/H100/Blackwell-class GPUs.

## Request examples

### Messages API

Send to RunPod:

`POST https://api.runpod.ai/v2/<ENDPOINT_ID>/runsync`

Body:

```json
{
  "input": {
    "messages": [
      {
        "role": "user",
        "content": "Write a Python FastAPI hello-world server."
      }
    ],
    "max_tokens": 4096,
    "reasoning_effort": "medium"
  }
}
```

The `output` field returned by RunPod contains the normal llama.cpp/OpenAI chat-completions JSON.

### Simple prompt

```json
{
  "input": {
    "prompt": "Explain CUDA unified memory in simple terms.",
    "max_tokens": 4096
  }
}
```

### Forward an OpenAI-compatible payload

```json
{
  "input": {
    "payload": {
      "messages": [
        {
          "role": "user",
          "content": "Create a TypeScript debounce function."
        }
      ],
      "temperature": 1.0,
      "max_tokens": 8192,
      "reasoning_effort": "medium"
    }
  }
}
```

Fields such as `tools`, `tool_choice`, `response_format`, and other llama.cpp-supported OpenAI fields can be passed through the payload.

## Notes for Bonsai 2 reasoning

Bonsai 2 can spend a substantial part of its output budget on reasoning. Very small `max_tokens` values may stop it before the final answer. PrismML currently recommends allowing a large output budget or using a lower reasoning effort such as `medium`.

For larger context sizes, increase `CONTEXT_SIZE` only after checking available VRAM/RAM.

## Files

```text
.
├── Dockerfile
├── handler.py
├── start_bonsai.sh
├── requirements.txt
├── .dockerignore
├── .gitignore
└── README.md
```

## Upstream references

- PrismML Bonsai 2 model: https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf
- PrismML llama.cpp fork: https://github.com/PrismML-Eng/llama.cpp
- Bonsai demo/source of truth: https://github.com/PrismML-Eng/Bonsai-demo
- RunPod Serverless docs: https://docs.runpod.io/serverless/quickstart
