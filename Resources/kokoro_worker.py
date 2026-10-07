#!/usr/bin/env python3
import argparse
import contextlib
import io
import json
import sys
from pathlib import Path

from kokoro_runtime import validate_runtime_versions, apply_runtime_compatibility


def synthesize(model, request: dict, default_voice: str, default_lang_code: str) -> None:
    from kokoro_captions import generate_captioned_audio

    text = request["text"].strip()
    if not text:
        raise ValueError("Empty text")
    log_buffer = io.StringIO()
    with contextlib.redirect_stdout(log_buffer), contextlib.redirect_stderr(log_buffer):
        generate_captioned_audio(
            model, text, request["output_file"],
            request.get("voice") or default_voice,
            request.get("lang_code") or default_lang_code,
            float(request.get("speed") or 1.0),
        )


def warm(model, default_voice: str, default_lang_code: str) -> None:
    # The model is loaded before the worker emits "ready"; this request is a cheap keepalive.
    _ = (model, default_voice, default_lang_code)


def main() -> int:
    validate_runtime_versions()
    apply_runtime_compatibility()
    from huggingface_hub import snapshot_download
    from mlx_audio.tts.utils import load_model

    parser = argparse.ArgumentParser(description="Persistent Kokoro worker for Gallaxy TTS.")
    parser.add_argument("--model", default="mlx-community/Kokoro-82M-bf16")
    parser.add_argument("--model-revision", required=True)
    parser.add_argument("--voice", default="af_bella")
    parser.add_argument("--lang-code", default="a")
    args = parser.parse_args()

    log_buffer = io.StringIO()
    with contextlib.redirect_stdout(log_buffer), contextlib.redirect_stderr(log_buffer):
        model_path = Path(
            snapshot_download(
                repo_id=args.model,
                revision=args.model_revision,
            )
        )
        model = load_model(model_path)

    print(
        json.dumps(
            {
                "ready": True,
                "model": args.model,
                "revision": args.model_revision,
                "voice": args.voice,
            }
        ),
        flush=True,
    )

    for line in sys.stdin:
        try:
            request = json.loads(line)
            request_id = request["id"]
            if request.get("kind") == "warm":
                warm(model, args.voice, args.lang_code)
            else:
                synthesize(model, request, args.voice, args.lang_code)
            response = {"id": request_id, "ok": True}
        except Exception as exc:
            response = {
                "id": locals().get("request", {}).get("id"),
                "ok": False,
                "error": str(exc),
            }

        print(json.dumps(response), flush=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
