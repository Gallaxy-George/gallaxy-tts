#!/usr/bin/env python3
import argparse
from importlib.metadata import PackageNotFoundError, version
import shutil
import subprocess
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


def generate_with_api(
    args: argparse.Namespace,
    model_path: Path,
    output_dir: Path,
    prefix: str,
) -> None:
    from mlx_audio.tts.generate import generate_audio

    generate_audio(
        text=args.text_file.read_text(encoding="utf-8"),
        model=str(model_path),
        voice=args.voice,
        speed=args.speed,
        lang_code=args.lang_code,
        output_path=str(output_dir),
        file_prefix=prefix,
        audio_format="wav",
        join_audio=True,
        verbose=False,
    )


def generate_with_cli(
    args: argparse.Namespace,
    model_path: Path,
    output_dir: Path,
    prefix: str,
) -> None:
    command = [
        sys.executable,
        "-m",
        "mlx_audio.tts.generate",
        "--model",
        str(model_path),
        "--text",
        args.text_file.read_text(encoding="utf-8"),
        "--voice",
        args.voice,
        "--speed",
        str(args.speed),
        "--lang_code",
        args.lang_code,
        "--output_path",
        str(output_dir),
        "--file_prefix",
        prefix,
        "--audio_format",
        "wav",
        "--join_audio",
    ]
    subprocess.run(command, check=True)


def main() -> int:
    validate_runtime_versions()
    from huggingface_hub import snapshot_download

    parser = argparse.ArgumentParser(description="Generate speech with Kokoro through MLX Audio.")
    parser.add_argument("--text-file", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--model", default="mlx-community/Kokoro-82M-bf16")
    parser.add_argument("--model-revision", required=True)
    parser.add_argument("--voice", default="af_bella")
    parser.add_argument("--lang-code", default="a")
    parser.add_argument("--speed", default=1.0, type=float)
    args = parser.parse_args()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    prefix = f"gallaxy_kokoro_{args.output.stem}"
    model_path = Path(
        snapshot_download(
            repo_id=args.model,
            revision=args.model_revision,
        )
    )

    with tempfile.TemporaryDirectory(prefix="gallaxy-kokoro-") as tmp:
        output_dir = Path(tmp)
        try:
            generate_with_api(args, model_path, output_dir, prefix)
        except Exception as api_error:
            try:
                generate_with_cli(args, model_path, output_dir, prefix)
            except Exception as cli_error:
                print(f"Kokoro MLX generation failed: {api_error}; CLI fallback failed: {cli_error}", file=sys.stderr)
                return 1

        wav = newest_wav(output_dir, prefix)
        if wav is None:
            try:
                generate_with_cli(args, model_path, output_dir, prefix)
            except Exception as cli_error:
                print(f"Kokoro MLX CLI fallback failed: {cli_error}", file=sys.stderr)
                return 1
            wav = newest_wav(output_dir, prefix)

        if wav is None:
            print("Kokoro MLX generation did not create a WAV file.", file=sys.stderr)
            return 1

        shutil.move(str(wav), str(args.output))
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
