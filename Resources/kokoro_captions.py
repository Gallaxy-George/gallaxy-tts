"""Audio and model-derived caption cues for the pinned MLX Kokoro runtime."""
import json
import math
from pathlib import Path


def phrase_cues(tokens, offset, duration):
    # Group tokens into whitespace-delimited units first: opening/closing quotes,
    # apostrophes and punctuation must travel with their original word.
    units = []
    unit, unit_start = "", None
    for token in tokens:
        timestamp = getattr(token, "start_ts", None)
        if timestamp is not None and math.isfinite(float(timestamp)) and unit_start is None:
            unit_start = max(0, min(float(timestamp), duration))
        unit += token.text + token.whitespace
        if token.whitespace:
            units.append((unit, unit_start))
            unit, unit_start = "", None
    if unit:
        units.append((unit, unit_start))

    cues = []
    phrase, start = "", None
    for text, timestamp in units:
        if phrase.strip() and timestamp is not None and (
            len(phrase) + len(text) > 42
            or phrase.rstrip().rstrip('"”’)]').endswith(('.', '!', '?', ';', ':', ','))
        ):
            cues.append({"text": phrase.strip(), "start": offset + (start or 0)})
            phrase, start = "", None
        if start is None and timestamp is not None:
            start = timestamp
        phrase += text
    if phrase.strip():
        cues.append({"text": phrase.strip(), "start": offset + (start or 0)})
    return cues


def generate_captioned_audio(model, text, output_file, voice, lang_code, speed):
    import numpy as np
    import soundfile as sf

    # model.generate discards Result.tokens. Use the same cached pipeline to
    # retain its predicted-duration timestamps; no second inference/alignment.
    pipeline = model._get_pipeline(lang_code)
    audio_chunks, cues = [], []
    samples = 0
    sample_rate = model.sample_rate
    for result in pipeline(text, voice=voice, speed=speed, split_pattern=r"\n+"):
        audio = np.asarray(result.audio).reshape(-1)
        if not len(audio):
            continue
        offset = samples / sample_rate
        segment_cues = phrase_cues(result.tokens or [], offset, len(audio) / sample_rate)
        if not segment_cues:
            # No token alignment for this segment: keep its whole text visible.
            segment_cues = [{"text": result.graphemes, "start": offset}]
        segment_cues[0]["start"] = offset
        cues.extend(segment_cues)
        audio_chunks.append(audio)
        samples += len(audio)
    if not audio_chunks:
        raise RuntimeError("Kokoro did not generate audio.")
    output_file = Path(output_file)
    output_file.parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(output_file), np.concatenate(audio_chunks), sample_rate, subtype="PCM_16")
    output_file.with_suffix(".captions.json").write_text(json.dumps(cues), encoding="utf-8")
