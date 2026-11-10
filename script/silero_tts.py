#!/usr/bin/env python3
"""Narrate a text file with Silero v5 (Russian, offline).

Usage: silero_tts.py <text_file> <output.wav> [speaker]
Speakers: xenia (default), baya, kseniya, aidar, eugene.

Besides the WAV it writes <output>.segments.json: where each piece of text starts and ends in
the audio. Listr uses it to keep the word highlight in step with the voice.
"""
import json
import os
import re
import sys
import tempfile
import wave

import numpy as np
from silero import silero_tts

text_path, out_path = (os.path.abspath(path) for path in sys.argv[1:3])
os.chdir(tempfile.gettempdir())  # silero drops a models list into the working directory
speaker = sys.argv[3] if len(sys.argv) > 3 else "xenia"
rate = 48000

text = open(text_path, encoding="utf-8").read()
loaded = silero_tts(language="ru", speaker="v5_ru")
model = loaded[0] if isinstance(loaded, tuple) else loaded

# Same splitting as Listr's Piper runner: sentence ends after 30+ characters, commas and
# dashes after 90+. Silero also refuses very long inputs, so short pieces are required here.
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


segments, frames, offset, previous = [], 0, 0, 0
with wave.open(out_path, "wb") as wav:
    wav.setnchannels(1)
    wav.setsampwidth(2)
    wav.setframerate(rate)
    for a, b in spans:
        offset += utf16(text[previous:a])
        previous = a
        try:
            audio = model.apply_tts(text=text[a:b], speaker=speaker, sample_rate=rate)
        except Exception:  # nothing pronounceable in this piece ("* * *", bare numbers)
            continue
        samples = (audio.numpy() * 32767).clip(-32768, 32767).astype(np.int16)
        wav.writeframes(samples.tobytes())
        segments.append({
            "location": offset, "length": utf16(text[a:b]),
            "start": frames / rate, "end": (frames + len(samples)) / rate,
        })
        frames += len(samples)

if not frames:
    sys.exit("Silero produced no audio for this text.")

with open(out_path + ".segments.json", "w") as handle:
    json.dump(segments, handle)
