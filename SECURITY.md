# Security policy

## Report a vulnerability privately

Please use [GitHub's private vulnerability report](https://github.com/reyhenrick/insonia/security/advisories/new) for security issues. Do not publish exploit details or sensitive logs in a public issue while a report is being assessed. If private reporting is unavailable, open an issue asking the maintainer to enable a private reporting channel, without the vulnerability details.

Include the affected version, macOS version, relevant configuration, reproduction steps, expected impact, and a minimal proof of concept when useful. Remove credentials and personal data. There is no guaranteed response time.

Security fixes target the latest release. Users of an older version may need to update both the app and system protection.

## Relevant boundaries

Insonia has an unprivileged menu bar app, a user recovery monitor, and a privileged helper that changes the system sleep setting. The installed helper resides in `/Library/PrivilegedHelperTools/com.henrick.insonia`. Changes crossing that boundary must authenticate session ownership, reject invalid state, and recover to normal sleep when a valid active session expires.

The app must preserve manual locking and system authentication. It must not unlock a session, enter passwords, bypass FileVault, or grant another app Screen Recording or Accessibility access.

The current downloadable build is signed ad hoc, not with Apple Developer ID, and is not notarized. Download it from the [repository's Releases page](https://github.com/reyhenrick/insonia/releases). Checksums detect changed download bytes when compared with the published value; they do not replace publisher authentication or notarization.

Insonia does not collect analytics or send background network requests. Recovery records stay on the Mac and contain power and session events. Review any diagnostic material before sharing it.
