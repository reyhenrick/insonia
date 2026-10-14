# Changelog

## 1.3.0 (2026-10-14)

- Add **Check for updates…** to the panel and check for new releases automatically.
- Add **Install updates automatically** to the **…** menu, off by default. Available updates otherwise ask before installation.
- Wait for Keep awake to be off, normal sleep and brightness recovery to finish, and protection operations to complete before installing an update.
- Start with Keep awake off on the first launch after an update, preserving the Start active preference for later launches.
- Verify the update feed and archives with Sparkle 2.10 and Ed25519 signatures, using a signing key kept in the maintainer's local Keychain.
- Remove the Help button from the panel. The English installation and usage guide remains included in the disk image and app resources.
- Explain system protection, update preferences, GitHub network access, and the release-signing process in the English documentation.
- Include only the app in the ZIP archive so it can be installed by the updater.

**Upgrading from 1.2.0:** download this version, quit Insonia, and replace the app in Applications once. Future releases can update from inside the app. Update signing is separate from Apple Developer ID signing and notarization; this download still has neither.

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
