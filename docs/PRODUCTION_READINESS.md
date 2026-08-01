# Production Readiness Review

## Current State

ListrDesktop is a working native macOS SwiftUI app with FB2, EPUB, and TXT import, JSON library persistence, system voice chapter export, resumable per-chapter audio files, and AVFoundation playback. The app builds through SwiftPM and has focused tests for import, persistence, conversion success, conversion failure, cancellation, and resume-position storage.

## Completed Baselines

1. Import
   - FB2, EPUB, and TXT files can be imported into chapter models.
   - Metadata extraction exists for common title and author paths.
   - Synthetic FB2 and EPUB parser fixtures are covered by tests.

2. Conversion
   - System voice synthesis writes one audio file per chapter.
   - Completed chapters are reused instead of regenerated.
   - Audio files are moved into place atomically.
   - Conversion can be cancelled and leaves the book retryable.
   - TTS failures mark only the current chapter as failed and preserve completed audio.

3. Playback
   - AVFoundation playback loads generated chapter audio.
   - Play, pause, seek, 15-second skip, previous/next chapter, playback speed, and resume-position storage are wired.
   - Playback controls are scoped to the selected book so stale state does not leak across sidebar selection changes.

4. Developer Run Path
   - `script/build_and_run.sh` builds the SwiftPM product, stages a local `.app` bundle, and launches it as a foreground macOS app.
   - The Codex Run action points at the same script.

## Must Finish Before Production Release

1. Import Hardening
   - Expand fixtures with messy real-world FB2 and EPUB samples.
   - Handle more EPUB encodings, nested paths, missing OPF metadata, and malformed XHTML.
   - Preserve paragraph boundaries where narration quality depends on pauses.

2. Long-Book Validation
   - Smoke-test full system voice export on long books.
   - Record CPU, memory, disk usage, and cancellation behavior during multi-hour conversion.
   - Add visible per-chapter failure details for user recovery.

3. Packaging
   - Add app icon and bundle metadata.
   - Sandbox decision: App Sandbox is off. It moved the library into a per-app container,
     orphaning the existing `~/Library/Application Support/ListrDesktop` data, and blocked
     Piper from executing out of `.tools/`. Re-enabling it requires migrating the library
     into the container and relocating the Piper install.
   - Build signing, notarization, and release packaging flow.

4. Persistence Evolution
   - Add schema versioning or migration handling before shipping to users.
   - Consider library repair behavior for moved or deleted audio files.

## Production Risks

- EPUB parsing is structurally correct for the test fixture but needs coverage against publisher-specific files.
- System TTS export works through the app boundary, but long-book runtime and output quality still need real usage evidence.
- JSON persistence has no explicit migration story yet.
- Word timing generation is still a planned control, not an implemented timing backend.

## Recommended Next Sprint

Run a real-book hardening sprint: import several representative books, convert one long title end-to-end with system voices, verify playback/resume behavior manually, then package the app with signing and entitlements.
