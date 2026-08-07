# ListrDesktop

Native macOS app that turns books into local narrated audio.

## Features

- Import **FB2**, **EPUB**, and **TXT**
- Three narration engines: **System**, **Piper**, and **Command**
- Resumable per-chapter conversion with cancel / retry
- Chapter playback with seek, skip, speed, and resume position
- Floating **Reading Overlay** window for listening while you work

## Voice engines

| Engine | Mode | Notes |
| --- | --- | --- |
| **System** | Offline | macOS system voices (AVSpeech) |
| **Piper** | Offline | Local Piper neural voices (onnx) |
| **Command** | Depends on tool | Any CLI that reads `{text_file}` and writes `{output}` — e.g. edge-tts, Silero, XTTS |

Setup details and quality tradeoffs: [`docs/VOICES.md`](docs/VOICES.md).

## Requirements

- macOS 14+
- Xcode / Swift toolchain able to build SwiftPM packages

## Build

```bash
swift build
```

## Run

```bash
swift run ListrDesktop
```

Or as a normal macOS `.app`:

```bash
script/build_and_run.sh
```

## License

MIT
