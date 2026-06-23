# ListrDesktop

Native macOS desktop app for converting books into local narrated audio.

## Current State

Phase 0 foundation is in place:

- SwiftPM macOS app scaffold.
- SwiftUI `NavigationSplitView` library/detail layout.
- Settings surface for narration defaults and low-load conversion controls.
- Replaceable `TTSService` interface for system and local neural engines.
- FB2, EPUB, and TXT file import foundation.
- JSON library persistence in Application Support.
- Parser and persistence tests.
- Production plan in `docs/PRODUCTION_PLAN.md`.

## Build

```bash
swift build
```

## Run

```bash
swift run ListrDesktop
```

or use:

```bash
script/build_and_run.sh
```

## Next Milestone

Finish Phase 2: system TTS chapter synthesis, a bounded conversion queue, and resumable per-chapter audio output.
