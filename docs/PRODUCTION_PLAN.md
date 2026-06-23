# ListrDesktop Production Plan

## Product Goal

ListrDesktop is a native macOS app for turning long-form books into local audio with chapter navigation, resumable conversion, and lightweight system usage. The first production target is a reliable personal desktop app, then packaging and optional cross-platform expansion.

## Recommended Direction

Build native macOS first with SwiftUI and SwiftPM. This keeps the app light, avoids Electron overhead, and gives direct access to files, audio playback, background work, and Apple speech APIs. Local neural TTS can be added behind service interfaces without rewriting the UI.

## Core Principles

- Local-first: books, generated audio, timings, and settings stay on disk.
- Low load by default: one conversion job, pause on battery pressure, resumable chapter output.
- Replaceable TTS backends: system voice first, local neural engines later.
- Durable jobs: every chapter has status, output path, timing path, and error state.
- Plain desktop UX: sidebar library, detail workspace, queue/progress, settings.

## Technology Stack

- App: SwiftUI, macOS 14+, SwiftPM.
- State: Observation framework for UI stores.
- Persistence MVP: JSON app library stored in Application Support.
- Persistence production: SQLite via GRDB or SQLite.swift after schema stabilizes.
- Playback: AVFoundation.
- System TTS MVP: AVSpeechSynthesizer for preview and baseline export experiments.
- Local neural TTS: Piper or Kokoro-style ONNX backend behind `TTSService`.
- Background work: cooperative Swift concurrency with a bounded conversion queue.

## TTS Strategy

Phase 1 uses system voices because they are efficient, already installed, and safe for a desktop MVP.

Phase 2 adds a local neural engine with these constraints:
- model quantization preferred;
- one worker by default;
- chunked chapter synthesis;
- memory cap and cancellation;
- generated WAV or M4A per chapter;
- optional word timing estimation.

Phase 3 adds model management:
- install voices from known URLs;
- validate model files;
- show disk size and expected CPU load;
- allow deleting unused voices.

## Data Model

- `Book`: metadata, source file, import date, selected voice, progress.
- `Chapter`: book id, index, title, raw text, status, audio path, timing path, error.
- `VoiceModel`: engine, language, quality, disk path, validation state.
- `ConversionJob`: book id, queue state, current chapter, cancellation token.

## Production Phases

### Phase 0: Foundation

- SwiftPM macOS app scaffold.
- NavigationSplitView layout.
- Library/detail/settings shell.
- TTS service interface.
- Production plan and build script.

### Phase 1: Import and Library

- File picker for FB2, EPUB, TXT. Initial implementation exists.
- Text extraction pipeline. Initial implementation exists for FB2 XML, EPUB OPF/spine XHTML, and TXT.
- Chapter detection. Initial implementation exists.
- JSON persistence in Application Support.
- Empty, loading, failure, and imported states.

### Phase 2: Baseline Narration

- System TTS chapter synthesis.
- Conversion queue with one job default.
- Per-chapter progress and cancellation.
- Audio output folder per book.
- Resume conversion without regenerating completed chapters.

### Phase 3: Player

- AVFoundation playback.
- Chapter queue.
- Playback speed.
- Resume position.
- Basic word/segment highlight if timings exist.

### Phase 4: Local Neural TTS

- Add Piper or ONNX backend implementation.
- Model install and validation UI.
- CPU and memory guardrails.
- Quality presets: light, balanced, high quality.

### Phase 5: Packaging

- App bundle generation.
- App icon and metadata.
- Sandboxing and entitlements review.
- Notarization path.
- Crash/log export for debugging.

## Load Management

- Default `maxParallelJobs = 1`.
- Disable high-quality concurrent jobs on battery unless user opts in.
- Process text in chunks, never whole books in memory-heavy synthesis calls.
- Write intermediate chapter files atomically.
- Use cancellation checks between chunks.
- Keep UI responsive by keeping conversion off the main actor.

## First MVP Definition

The first useful build imports a text-like book, splits it into chapters, converts one chapter at a time with system TTS, saves audio locally, and plays chapters in order.
