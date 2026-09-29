import atexit
import os
import subprocess
import time
from typing import Any, Dict

import requests
import runpod

SERVER_HOST = os.getenv("SERVER_HOST", "127.0.0.1")
SERVER_PORT = int(os.getenv("SERVER_PORT", "8080"))
SERVER_URL = f"http://{SERVER_HOST}:{SERVER_PORT}"
STARTUP_TIMEOUT = int(os.getenv("STARTUP_TIMEOUT", "900"))
REQUEST_TIMEOUT = int(os.getenv("REQUEST_TIMEOUT", "1800"))

_server: subprocess.Popen | None = None


def _start_server() -> None:
    global _server
    env = os.environ.copy()

    # If a RunPod Network Volume is attached, use it automatically so the
    # 5.95/7.21 GB model download is reused across worker replacements.
    if "MODEL_DIR" not in env:
        if os.path.isdir("/runpod-volume"):
            env["MODEL_DIR"] = "/runpod-volume/models/bonsai2"
        else:
            env["MODEL_DIR"] = "/models"

    _server = subprocess.Popen(
        ["/app/start_bonsai.sh"],
        env=env,
        stdout=None,
        stderr=None,
    )

    deadline = time.time() + STARTUP_TIMEOUT
    last_error: Exception | None = None

    while time.time() < deadline:
        if _server.poll() is not None:
            raise RuntimeError(
                f"llama-server exited during startup with code {_server.returncode}"
            )

        try:
            response = requests.get(f"{SERVER_URL}/health", timeout=5)
            if response.ok:
                print("[worker] Bonsai 2 server is ready", flush=True)
                return
        except requests.RequestException as exc:
            last_error = exc

        time.sleep(2)

    raise RuntimeError(
        f"Timed out waiting for llama-server after {STARTUP_TIMEOUT}s: {last_error}"
    )


def _stop_server() -> None:
    if _server is not None and _server.poll() is None:
        _server.terminate()


atexit.register(_stop_server)
_start_server()


def _normalize_payload(job_input: Dict[str, Any]) -> Dict[str, Any]:
    # Accept a complete OpenAI-compatible JSON body under input.payload/request.
    payload = job_input.get("payload") or job_input.get("request")
    if isinstance(payload, dict):
        return dict(payload)

    # Or accept OpenAI fields directly under input.
    if "messages" in job_input:
        payload = dict(job_input)
    elif "prompt" in job_input:
        payload = {
            "messages": [{"role": "user", "content": job_input["prompt"]}]
        }
        for key in (
            "temperature",
            "top_p",
            "top_k",
            "min_p",
            "max_tokens",
            "reasoning_effort",
            "tools",
            "tool_choice",
            "response_format",
            "seed",
            "stop",
        ):
            if key in job_input:
                payload[key] = job_input[key]
    else:
        raise ValueError(
            "input must contain 'messages', 'prompt', or an OpenAI body in "
            "'payload'/'request'"
        )

    # Bonsai 2 is a reasoning model. A tiny output cap can terminate during its
    # thinking trace, so use a practical default while still allowing overrides.
    payload.setdefault("max_tokens", int(os.getenv("DEFAULT_MAX_TOKENS", "16384")))
    payload.setdefault("temperature", 1.0)
    payload.setdefault("top_p", 0.95)
    payload.setdefault("top_k", 20)
    payload.setdefault("min_p", 0.05)

    # Medium is a useful serverless default. Callers can request xhigh explicitly.
    payload.setdefault(
        "reasoning_effort", os.getenv("DEFAULT_REASONING_EFFORT", "medium")
    )

    return payload


def handler(job: Dict[str, Any]) -> Dict[str, Any]:
    try:
        job_input = job.get("input") or {}
        if not isinstance(job_input, dict):
            return {"error": "RunPod input must be a JSON object"}

        payload = _normalize_payload(job_input)

        response = requests.post(
            f"{SERVER_URL}/v1/chat/completions",
            json=payload,
            timeout=REQUEST_TIMEOUT,
        )

        try:
            body = response.json()
        except ValueError:
            body = {"error": response.text}

        if not response.ok:
            return {
                "error": "llama-server request failed",
                "status_code": response.status_code,
                "detail": body,
            }

        return body

    except Exception as exc:
        return {"error": type(exc).__name__, "detail": str(exc)}


runpod.serverless.start({"handler": handler})
