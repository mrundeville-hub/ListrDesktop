# ListrDesktop

Native macOS desktop app for converting books into local narrated audio.

## Current State

Phase 3 listening loop baseline is in place:

- SwiftPM macOS app scaffold.
- SwiftUI `NavigationSplitView` library/detail layout.
- Settings surface for narration defaults and low-load conversion controls.
- Replaceable `TTSService` interface for system and local neural engines.
- FB2, EPUB, and TXT file import foundation.
- JSON library persistence in Application Support.
- System voice chapter export with resumable per-chapter audio files.
- One-book conversion flow with cancel/error handling.
- AVFoundation chapter playback with seek, skip, playback speed, and resume position.
- Parser, persistence, conversion, cancellation, failure, and resume-position tests.
- Production plan in `docs/PRODUCTION_PLAN.md`.

## Build

```bash
swift build
```

## Run

```bash
swift run ListrDesktop
```

For the normal macOS app launch path, use:

```bash
script/build_and_run.sh
```

## Next Milestone

Production hardening: real-book import fixtures, long-book system TTS smoke tests, packaging/signing decisions, and notarization.
