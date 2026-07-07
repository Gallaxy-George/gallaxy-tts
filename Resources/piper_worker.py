#!/usr/bin/env python3
import argparse
import json
import shutil
import sys
import wave
from pathlib import Path
from typing import Optional

from piper import PiperVoice, SynthesisConfig


def espeak_data_dir() -> Path:
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
    return espeak_data


def write_wav(voice: PiperVoice, text: str, output_file: str, length_scale: Optional[float]) -> None:
    synth_config = SynthesisConfig(length_scale=length_scale)
    with wave.open(output_file, "wb") as wav_file:
        wav_params_set = False
        for chunk in voice.synthesize(text, synth_config):
            if not wav_params_set:
                wav_file.setframerate(chunk.sample_rate)
                wav_file.setsampwidth(chunk.sample_width)
                wav_file.setnchannels(chunk.sample_channels)
                wav_params_set = True
            wav_file.writeframes(chunk.audio_int16_bytes)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--config", required=True)
    args = parser.parse_args()

    voice = PiperVoice.load(
        args.model,
        config_path=args.config,
        espeak_data_dir=espeak_data_dir(),
    )

    print(json.dumps({"ready": True}), flush=True)

    for line in sys.stdin:
        try:
            request = json.loads(line)
            request_id = request["id"]
            text = request["text"].strip()
            output_file = request["output_file"]
            length_scale = request.get("length_scale")
            if not text:
                raise ValueError("Empty text")
            write_wav(voice, text, output_file, length_scale)
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
