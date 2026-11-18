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

try:
    from num2words import num2words
except ImportError:  # older setups: numbers stay digits, which Silero skips
    num2words = None

# Silero reads no digits at all, so numbers are spelled out first: years and centuries as
# ordinals in the case their noun asks for ("в 1945 году" -> "в тысяча девятьсот сорок
# пятом году"), the rest as plain numbers. ponytail: cardinals stay nominative ("с 5 книгами"
# reads "с пять книгами"); agreeing them with the next word would need a morphology library.
NOUN_CASE = {  # noun form -> (case, plural)
    "год": ("n", False), "года": ("g", False), "году": ("p", False), "годом": ("i", False), "годе": ("p", False),
    "годы": ("n", True), "годов": ("g", True), "годах": ("p", True), "годам": ("d", True), "г.": ("p", False),
    "век": ("n", False), "века": ("g", False), "веке": ("p", False), "веку": ("d", False), "веком": ("i", False),
    "веков": ("g", True), "веках": ("p", True), "векам": ("d", True), "в.": ("p", False), "вв.": ("p", True),
}
SUFFIX_CASE = {"й": "n", "ый": "n", "ой": "n", "ий": "n", "го": "g", "му": "d", "м": "p", "х": "p"}
ROMAN = {"I": 1, "V": 5, "X": 10, "L": 50, "C": 100}


def roman(value):
    total = 0
    for a, b in zip(value, value[1:] + " "):
        total += -ROMAN[a] if ROMAN.get(b, 0) > ROMAN[a] else ROMAN[a]
    return total


def ordinal(number, case, plural=False, before=""):
    if case == "p" and plural is False and re.search(r"(?:^|\s)(?:к|по)\s*$", before):
        case = "d"  # "к 1945 году"
    return num2words(number, lang="ru", to="ordinal", case=case, plural=plural)


def spell_numbers(text):
    if num2words is None:
        return text
    nouns = "|".join(re.escape(noun) for noun in sorted(NOUN_CASE, key=len, reverse=True))
    number = r"(\d{1,4}|[IVXLC]+)"
    suffix = r"(?:\s*-\s*(?:[а-я]{1,2}))?"

    def dated(m):
        case, plural = NOUN_CASE[m.group(3)]
        noun = {"г.": "году", "в.": "веке", "вв.": "веках"}.get(m.group(3), m.group(3))
        before = m.string[:m.start()]
        values = [roman(v) if v.isalpha() else int(v) for v in (m.group(1), m.group(2)) if v]
        words = " — ".join(ordinal(v, case, plural and len(values) == 1, before) for v in values)
        return f"{words} {noun}"

    # "1945 году", "1941–1945 годах", "XIX век", "1990-х годов"
    text = re.sub(rf"\b(?:{number}{suffix}\s*[-–—]\s*)?{number}{suffix}\s+({nouns})(?![а-я])",
                  dated, text)
    # "1990-х", "5-й", "21-го"
    text = re.sub(r"\b(\d+)\s*-\s*(ый|ой|ий|й|го|му|м|х)(?![а-я])",
                  lambda m: ordinal(int(m.group(1)), SUFFIX_CASE[m.group(2)], m.group(2) == "х", m.string[:m.start()]), text)
    text = re.sub(r"\b(\d{1,3}(?:[   ]\d{3})+)\b", lambda m: re.sub(r"\D", "", m.group()), text)  # "10 000"
    text = re.sub(r"\b(\d+)[.,](\d+)\b", lambda m: num2words(float(f"{m.group(1)}.{m.group(2)}"), lang="ru"), text)
    return re.sub(r"\d+", lambda m: num2words(int(m.group()), lang="ru"), text)


if sys.argv[1:] == ["--check"]:
    for source, expected in [
        ("в 1945 году", "в тысяча девятьсот сорок пятом году"),
        ("к 1945 году", "к тысяча девятьсот сорок пятому году"),
        ("весна 1945 года", "весна тысяча девятьсот сорок пятого года"),
        ("в 1941–1945 годах", "в тысяча девятьсот сорок первом — тысяча девятьсот сорок пятом годах"),
        ("в 1990-х годах", "в тысяча девятьсот девяностых годах"),
        ("в XIX веке", "в девятнадцатом веке"),
        ("в 1812 г.", "в тысяча восемьсот двенадцатом году"),
        ("21-го числа", "двадцать первого числа"),
        ("ему 42, а ей 3,5", "ему сорок два, а ей три целых пять десятых"),
        ("10 000 книг", "десять тысяч книг"),
    ]:
        assert spell_numbers(source) == expected, (source, spell_numbers(source))
    print("ok")
    sys.exit(0)

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
            audio = model.apply_tts(text=spell_numbers(text[a:b]), speaker=speaker, sample_rate=rate)
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
