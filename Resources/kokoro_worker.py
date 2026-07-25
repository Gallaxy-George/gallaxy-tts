#!/usr/bin/env python3
import argparse
import contextlib
from importlib.metadata import PackageNotFoundError, version
import io
import json
import shutil
import sys
import tempfile
from pathlib import Path

REQUIRED_RUNTIME_VERSIONS = {
    "mlx-audio": "0.4.4",
    "misaki": "0.9.4",
    "soundfile": "0.14.0",
    "Pillow": "12.3.0",
    "setuptools": "83.0.0",
    "torch": "2.13.0",
}


def validate_runtime_versions() -> None:
    problems = []
    for package, required in REQUIRED_RUNTIME_VERSIONS.items():
        try:
            installed = version(package)
        except PackageNotFoundError:
            problems.append(f"{package} is missing")
            continue
        if installed != required:
            problems.append(f"{package} is {installed}; expected {required}")

    if problems:
        raise RuntimeError(
            "Kokoro runtime needs an update. Run scripts/download_kokoro_assets.sh. "
            + "; ".join(problems)
        )


def newest_wav(directory: Path, prefix: str):
    candidates = sorted(
        directory.glob(f"{prefix}*.wav"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    return candidates[0] if candidates else None


def synthesize(model, request: dict, default_voice: str, default_lang_code: str) -> None:
    from mlx_audio.tts.generate import generate_audio

    text = request["text"].strip()
    output_file = Path(request["output_file"])
    voice = request.get("voice") or default_voice
    lang_code = request.get("lang_code") or default_lang_code
    speed = float(request.get("speed") or 1.0)

    if not text:
        raise ValueError("Empty text")

    output_file.parent.mkdir(parents=True, exist_ok=True)
    prefix = f"gallaxy_kokoro_{output_file.stem}"

    with tempfile.TemporaryDirectory(prefix="gallaxy-kokoro-worker-") as tmp:
        output_dir = Path(tmp)
        log_buffer = io.StringIO()
        with contextlib.redirect_stdout(log_buffer), contextlib.redirect_stderr(log_buffer):
            try:
                generate_audio(
                    text=text,
                    model=model,
                    voice=voice,
                    speed=speed,
                    lang_code=lang_code,
                    output_path=str(output_dir),
                    file_prefix=prefix,
                    audio_format="wav",
                    join_audio=True,
                    verbose=False,
                )
            except Exception as exc:
                details = log_buffer.getvalue().strip()
                raise RuntimeError(f"{exc}: {details}" if details else str(exc)) from exc

        wav = newest_wav(output_dir, prefix)
        if wav is None:
            raise RuntimeError("Kokoro MLX generation did not create a WAV file.")

        shutil.move(str(wav), str(output_file))


def warm(model, default_voice: str, default_lang_code: str) -> None:
    # The model is loaded before the worker emits "ready"; this request is a cheap keepalive.
    _ = (model, default_voice, default_lang_code)


def main() -> int:
    validate_runtime_versions()
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
