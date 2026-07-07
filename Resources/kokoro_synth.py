#!/usr/bin/env python3
import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def newest_wav(directory: Path, prefix: str):
    candidates = sorted(
        directory.glob(f"{prefix}*.wav"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    return candidates[0] if candidates else None


def generate_with_api(args: argparse.Namespace, output_dir: Path, prefix: str) -> None:
    from mlx_audio.tts.generate import generate_audio

    generate_audio(
        text=args.text_file.read_text(encoding="utf-8"),
        model=args.model,
        voice=args.voice,
        speed=args.speed,
        lang_code=args.lang_code,
        output_path=str(output_dir),
        file_prefix=prefix,
        audio_format="wav",
        join_audio=True,
        verbose=False,
    )


def generate_with_cli(args: argparse.Namespace, output_dir: Path, prefix: str) -> None:
    command = [
        sys.executable,
        "-m",
        "mlx_audio.tts.generate",
        "--model",
        args.model,
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
    parser = argparse.ArgumentParser(description="Generate speech with Kokoro through MLX Audio.")
    parser.add_argument("--text-file", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--model", default="mlx-community/Kokoro-82M-bf16")
    parser.add_argument("--voice", default="af_bella")
    parser.add_argument("--lang-code", default="a")
    parser.add_argument("--speed", default=1.0, type=float)
    args = parser.parse_args()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    prefix = f"gallaxy_kokoro_{args.output.stem}"

    with tempfile.TemporaryDirectory(prefix="gallaxy-kokoro-") as tmp:
        output_dir = Path(tmp)
        try:
            generate_with_api(args, output_dir, prefix)
        except Exception as api_error:
            try:
                generate_with_cli(args, output_dir, prefix)
            except Exception as cli_error:
                print(f"Kokoro MLX generation failed: {api_error}; CLI fallback failed: {cli_error}", file=sys.stderr)
                return 1

        wav = newest_wav(output_dir, prefix)
        if wav is None:
            try:
                generate_with_cli(args, output_dir, prefix)
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
