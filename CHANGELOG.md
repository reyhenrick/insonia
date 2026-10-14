# Changelog

## 1.0.1 (2026-10-14)

- Insonia prepares its required background services when Keep awake is first enabled, with native macOS authorization when needed.
- Cancelling setup leaves Keep awake off. Another explicit activation retries setup.
- The panel focuses on the session, preferences, and updates. Recovery runs automatically in the background.
- The README panel image uses transparent corners.

## 1.0.0 (2026-10-14)

Initial public release.

- Native macOS menu bar controls for keeping background work active with the lid closed.
- Optional display access for visual agents, with built-in display dimming and brightness restoration.
- Independent recovery services, battery and thermal cutoffs, and manual session restart after a protective interruption.
- English, Portuguese, Spanish, French, German, and Italian interfaces selected from macOS language preferences.
- Separate Open at login and Start active preferences.
- Automatic release checks, a Check for updates button, and optional automatic installation, with signed update feeds and archives.
- Update installation after normal sleep and brightness recovery, followed by an initial launch with Keep awake off.
- Universal Mac downloads as a drag-to-Applications DMG and an app-only ZIP, with checksums and an English user guide.
- MIT-licensed source code, contribution instructions, issue templates, and private security reporting.

Requires macOS 26 or later. The universal build includes Apple silicon and Intel code. See the [installation instructions](README.md#install-and-start) before first use.
