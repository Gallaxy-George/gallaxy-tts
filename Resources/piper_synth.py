#!/usr/bin/env python3
import argparse
import shutil
import sys
import wave
from pathlib import Path

from piper import PiperVoice, SynthesisConfig


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--output_file", "--output-file", required=True)
    parser.add_argument("--length_scale", "--length-scale", type=float)
    args = parser.parse_args()

    resource_dir = Path(__file__).resolve().parent
    bundled_espeak_data = (
        resource_dir
        / "PiperRuntime"
        / "venv"
        / "lib"
        / "python3.9"
        / "site-packages"
        / "piper"
        / "espeak-ng-data"
    )
    support_dir = Path.home() / "Library" / "Application Support" / "Gallaxy TTS"
    espeak_data = support_dir / "espeak-ng-data"
    marker = espeak_data / ".gallaxy.tts-ready"
    if not marker.exists():
        if espeak_data.exists():
            shutil.rmtree(espeak_data)
        support_dir.mkdir(parents=True, exist_ok=True)
        shutil.copytree(bundled_espeak_data, espeak_data)
        marker.write_text("ok\n", encoding="utf-8")

    text = sys.stdin.read().strip()
    if not text:
        return 2

    voice = PiperVoice.load(
        args.model,
        config_path=args.config,
        espeak_data_dir=espeak_data,
    )
    synth_config = SynthesisConfig(length_scale=args.length_scale)

    with wave.open(args.output_file, "wb") as wav_file:
        wav_params_set = False
        for chunk in voice.synthesize(text, synth_config):
            if not wav_params_set:
                wav_file.setframerate(chunk.sample_rate)
                wav_file.setsampwidth(chunk.sample_width)
                wav_file.setnchannels(chunk.sample_channels)
                wav_params_set = True
            wav_file.writeframes(chunk.audio_int16_bytes)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
