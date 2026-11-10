#!/usr/bin/env python3
"""Narrate a text file with Qwen3-TTS on Apple silicon (mlx-audio, offline).

Usage: qwen_tts.py <text_file> <output.wav> [voice] [model]
Voices: serena (default), vivian, ryan, aiden, eric, dylan, uncle_fu, ono_anna, sohee.

Besides the WAV it writes <output>.segments.json: where each piece of text starts and ends in
the audio. Listr uses it to keep the word highlight in step with the voice.
"""
import json
import os
import re
import sys
import wave

import numpy as np
from mlx_audio.tts.utils import load_model

text_path, out_path = (os.path.abspath(path) for path in sys.argv[1:3])
voice = sys.argv[3] if len(sys.argv) > 3 else "serena"
repo = sys.argv[4] if len(sys.argv) > 4 else "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit"

text = open(text_path, encoding="utf-8").read()
model = load_model(repo)

# Same splitting as Listr's Piper runner: sentence ends after 30+ characters, commas and
# dashes after 90+. Short pieces also keep the model from drifting on long inputs.
spans, start = [], None
for match in re.finditer(r'.+?(?:[.!?…,;:—–]+["»”)\]]*(?:\s+|$)|$)', text, re.S):
    if start is None:
        start = match.start()
    length = match.end() - start
    strong = re.search(r'[.!?…]["»”)\]]*\s*$', match.group()) is not None
    if length >= 90 or (strong and length >= 30):
        spans.append((start, match.end()))
        start = None
if start is not None:
    spans.append((start, len(text)))


def utf16(value):
    return len(value.encode("utf-16-le")) // 2


segments, frames, rate, offset, previous = [], 0, None, 0, 0
with wave.open(out_path, "wb") as wav:
    for a, b in spans:
        offset += utf16(text[previous:a])
        previous = a
        if not re.search(r"\w", text[a:b]):
            continue  # nothing to pronounce ("* * *")
        written = 0
        for result in model.generate(text=text[a:b].strip(), voice=voice, lang_code="Russian"):
            if rate is None:
                rate = result.sample_rate
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(rate)
            samples = (np.array(result.audio).reshape(-1) * 32767).clip(-32768, 32767).astype(np.int16)
            wav.writeframes(samples.tobytes())
            written += len(samples)
        if written:
            segments.append({
                "location": offset, "length": utf16(text[a:b]),
                "start": frames / rate, "end": (frames + written) / rate,
            })
            frames += written
    if rate is None:
        sys.exit("Qwen3-TTS produced no audio for this text.")

with open(out_path + ".segments.json", "w") as handle:
    json.dump(segments, handle)
