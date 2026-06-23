# Production Readiness Review

## Current State

ListrDesktop is a working native macOS SwiftUI scaffold with FB2, EPUB, and TXT import foundations. The app builds successfully and has a clear service boundary for future text-to-speech engines.

## Must Finish Before Production

1. Persistence
   - Save imported books, chapters, source paths, and conversion state in Application Support.
   - Use JSON for MVP, then move to SQLite when conversion metadata grows.

2. Import Hardening
   - Add parser fixtures for real-world FB2 and EPUB samples.
   - Handle EPUB encodings, nested paths, missing OPF metadata, and malformed XHTML.
   - Preserve paragraph boundaries instead of flattening all text into one line.

3. Conversion Pipeline
   - Implement bounded conversion queue with cancellation.
   - Write audio atomically per chapter.
   - Resume without regenerating completed chapters.
   - Add one-worker default and battery-friendly guardrails.

4. TTS Backends
   - Start with system voice synthesis.
   - Add local neural backend behind `TTSService` after baseline export works.
   - Validate CPU and memory use with long books.

5. Player
   - AVFoundation chapter playback.
   - Queue controls, playback speed, resume position.
   - Later: word or phrase highlighting from timing files.

6. Packaging
   - Build an app bundle, icon, entitlements, sandbox decisions, and notarization flow.
   - Add crash/log export for debugging user reports.

## Production Risks

- EPUB parsing is structurally correct but needs fixture coverage for messy publisher files.
- System TTS export quality and file rendering path must be validated before neural TTS work.
- No persistence exists yet, so imported books are currently session-only.
- No automated tests are present yet.

## Recommended Next Sprint

Implement persistent library storage plus parser tests. That gives a stable base before adding synthesis and playback.
