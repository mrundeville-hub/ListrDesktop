# Production Readiness Review

## Current State

ListrDesktop is a working native macOS SwiftUI scaffold with FB2, EPUB, and TXT import, JSON library persistence, and parser/persistence tests. The app builds successfully and has a clear service boundary for future text-to-speech engines.

## Must Finish Before Production

1. Import Hardening
   - Expand parser fixtures with real-world FB2 and EPUB samples.
   - Handle more EPUB encodings, nested paths, missing OPF metadata, and malformed XHTML.
   - Preserve paragraph boundaries instead of flattening all text into one line.

2. Conversion Pipeline
   - Implement bounded conversion queue with cancellation.
   - Write audio atomically per chapter.
   - Resume without regenerating completed chapters.
   - Add one-worker default and battery-friendly guardrails.

3. TTS Backends
   - Start with system voice synthesis.
   - Add local neural backend behind `TTSService` after baseline export works.
   - Validate CPU and memory use with long books.

4. Player
   - AVFoundation chapter playback.
   - Queue controls, playback speed, resume position.
   - Later: word or phrase highlighting from timing files.

5. Packaging
   - Build an app bundle, icon, entitlements, sandbox decisions, and notarization flow.
   - Add crash/log export for debugging user reports.

## Production Risks

- EPUB parsing is structurally correct and covered by a synthetic fixture, but needs coverage for messy publisher files.
- System TTS export quality and file rendering path must be validated before neural TTS work.
- JSON persistence exists, but no migration/versioning scheme exists yet.
- Automated tests cover core import and persistence only.

## Recommended Next Sprint

Implement system TTS chapter export plus a resumable conversion queue. That turns imported books into usable audio output.
