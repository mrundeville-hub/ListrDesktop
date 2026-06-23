# ListrDesktop

Native macOS desktop app for converting books into local narrated audio.

## Current State

Phase 0 foundation is in place:

- SwiftPM macOS app scaffold.
- SwiftUI `NavigationSplitView` library/detail layout.
- Settings surface for narration defaults and low-load conversion controls.
- Replaceable `TTSService` interface for system and local neural engines.
- FB2, EPUB, and TXT file import foundation.
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

Finish Phase 1: JSON persistence in Application Support, import progress states, and parser fixtures/tests for FB2 and EPUB edge cases.
