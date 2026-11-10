# Voices

## Why the default sounds bad

The `System` engine uses macOS speech voices. The only Russian voice installed by default is
**Milena (Compact)** — Apple's lowest quality tier, and the reason existing chapters sound rough.
Chapter files ending in `.aiff` were produced by it.

Three ways out, cheapest first.

## 1. Better system voice (no tooling)

System Settings → Accessibility → Spoken Content → System Voice → Manage Voices → Russian.
Install **Milena (Enhanced)** or **(Premium)** if offered, then pick it in Settings → Voice.
Still not neural, but a clear step up from Compact.

## 2. Piper (local, offline)

Already installed under `.tools/`. Pick the engine in Settings → Voice → Engine → **Piper**, and
the voice in Settings → Piper voices. Any `*.onnx` + `*.onnx.json` pair dropped into the voices
folder shows up in that menu automatically — no path editing.

Extra Russian voices from [rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices):

```bash
cd .tools/piper-voices
for v in denis dmitri ruslan; do
  mkdir -p "ru_RU-$v-medium"
  base="https://huggingface.co/rhasspy/piper-voices/resolve/main/ru/ru_RU/$v/medium/ru_RU-$v-medium.onnx"
  curl -L "$base"      -o "ru_RU-$v-medium/ru_RU-$v-medium.onnx"
  curl -L "$base.json" -o "ru_RU-$v-medium/ru_RU-$v-medium.onnx.json"
done
```

Piper now lives at [OHF-Voice/piper1-gpl](https://github.com/OHF-Voice/piper1-gpl) (GPL-3; the old
`rhasspy/piper` repo is archived). Update the bundled copy with
`.tools/piper-venv/bin/pip install -U piper-tts` — existing `.onnx` voices keep working.

Quality: clearly better than Milena Compact, roughly "good podcast" level. Fully offline, ~1× realtime on Apple silicon.

## 3. Command engine (anything with a CLI)

Settings → Command engine runs a shell command per chapter:

- `{text_file}` — path to a UTF-8 file holding the chapter text
- `{output}` — path the command must write audio to

Set **Output format** to the container the command writes (`wav`, `mp3`, `m4a`…), since that
determines the chapter file name. The chapter text is passed as a file, never on the command line.

### edge-tts — best Russian quality, needs network

Microsoft's neural voices. Two presets are one click away in Settings.

```bash
pipx install edge-tts   # or: uv tool install edge-tts
```

```
edge-tts --voice ru-RU-SvetlanaNeural --file {text_file} --write-media {output}
```

Output format: `mp3`. Voices: `ru-RU-SvetlanaNeural` (female), `ru-RU-DmitryNeural` (male).
This is a cloud call — the only engine here that leaves the machine.

Needs edge-tts **7.3.1 or newer**: older versions are rejected by Microsoft with `403`
(`pip install -U edge-tts`). It is an unofficial endpoint, so a chapter can occasionally fail with
"No audio was received" — press **Convert** again and it resumes from that chapter.

### Silero v5 — best offline quality for Russian

Built for Russian; the v5 models place stress and resolve homographs by themselves.
Non-commercial license. Latin-script words (English names, titles) are skipped, not read.

```bash
uv venv --python 3.12 .tools/silero-venv
uv pip install -p .tools/silero-venv silero scipy
```

Once that folder exists, Settings → Command → Presets offers **Silero v5, Xenia** and
**Silero v5, Eugene**. They run [`script/silero_tts.py`](../script/silero_tts.py):

```
.tools/silero-venv/bin/python script/silero_tts.py {text_file} {output} xenia
```

Output format: `wav`. Other speakers: `baya`, `kseniya`, `aidar`. The first run downloads the model.

### Qwen3-TTS — most natural offline voice, Apple silicon only

Runs through [mlx-audio](https://github.com/Blaizzy/mlx-audio). Apache-2.0. Reads Russian and
English in the same text. Slower than Piper: about 1.7× faster than real time on an M-series Mac
(a 75-second chapter took 44 seconds here), so a long book takes hours.

```bash
uv venv --python 3.12 .tools/mlx-venv
uv pip install -p .tools/mlx-venv mlx-audio
```

Once that folder exists, Settings → Command → Presets offers **Qwen3-TTS, Serena** and
**Qwen3-TTS, Ryan**. They run [`script/qwen_tts.py`](../script/qwen_tts.py):

```
.tools/mlx-venv/bin/python script/qwen_tts.py {text_file} {output} serena
```

Output format: `wav`. The first run downloads the model (about 1 GB).

### Other models that speak Russian (checked November 2026, not tested in this app)

| Model | Runs | License | Notes |
| --- | --- | --- | --- |
| Chatterbox Multilingual | local, wants a GPU | MIT | 23 languages incl. Russian, voice cloning |
| F5-TTS Russian fine-tunes (ESpeech) | local, wants a GPU | varies | highest-rated open Russian quality in roundups |
| XTTS-v2 (`coqui-tts` fork) | local, slow on CPU | non-commercial | original Coqui is shut down |

Kokoro does **not** support Russian. Anything above works through the Command engine as long as
you wrap it in a command that reads a text file and writes an audio file.

## Word highlight accuracy

The highlight follows timings saved next to each chapter's audio:

| Engine | Timing | How |
| --- | --- | --- |
| System | exact per word | the voice reports where every word starts |
| Piper | exact per sentence or clause | Listr synthesizes piece by piece through Piper's Python API |
| Silero and Qwen3-TTS presets | exact per sentence or clause | the scripts write `{output}.segments.json` |
| Other commands | estimated | spread over the whole chapter by word length and punctuation |

A custom command can opt in by writing `{output}.segments.json`: a JSON array of
`{"location", "length", "start", "end"}` — UTF-16 offsets into the text file, seconds in the audio.
Chapters converted before this existed keep their estimated timings until you **Regenerate Audio**.

## Comparing voices

Settings → **Preview voice** synthesizes one sentence with the current engine and plays it. Use it
to A/B voices before committing to a long book. Converting a book with a different engine means
**Regenerate** on the player bar, which deletes existing audio and rebuilds it.
