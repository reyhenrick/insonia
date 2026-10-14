# Changelog

## 1.2.0 (2026-10-14)

- Follow the Mac's language automatically, with English, Portuguese, Spanish, French, German, and Italian interfaces and English fallback.
- Use the name **Insonia** consistently, without an accent.
- Distinguish a previous interruption from the current protection status and provide a monitor repair action.
- Update system protection to helper v3. Existing users need to approve the protection update once.
- Add bundled English help and an in-app protection removal flow.
- Add universal macOS downloads, a drag-to-Applications disk image, a ZIP archive, and SHA-256 checksums.
- Open the project under the MIT license with contribution instructions and issue templates.

The download requires macOS 26 or later. It is not Developer ID signed or notarized. Intel code is included in the universal build; physical Intel validation is separate from compilation.

## 1.1

- Add optional visual-agent access with the lid closed, minimum built-in display brightness, and brightness restoration.
- Add a separate recovery monitor, session identity checks, and an independent helper watchdog.
- Add battery and thermal cutoffs, with manual restart after protection stops a session.
