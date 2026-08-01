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

### Silero — best offline quality

```bash
uv tool install torch  # heavy; a venv with torch + a small wrapper script
```

Write `silero.py` that reads `sys.argv[1]`, synthesizes with the `v4_ru` model, writes `sys.argv[2]`, then:

```
python3 /path/to/silero.py {text_file} {output}
```

Output format: `wav`.

### Any other model

XTTS-v2, F5-TTS, Kokoro, Vosk-TTS — all work the same way as long as they expose a command that
reads a text file and writes an audio file.

## Comparing voices

Settings → **Preview voice** synthesizes one sentence with the current engine and plays it. Use it
to A/B voices before committing to a long book. Converting a book with a different engine means
**Regenerate** on the player bar, which deletes existing audio and rebuilds it.
