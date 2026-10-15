# Security policy

## Report a vulnerability privately

Please use [GitHub's private vulnerability report](https://github.com/reyhenrick/insonia/security/advisories/new) for security issues. Do not publish exploit details or sensitive logs in a public issue while a report is being assessed. If private reporting is unavailable, open an issue asking the maintainer to enable a private reporting channel, without the vulnerability details.

Include the affected version, macOS version, relevant configuration, reproduction steps, expected impact, and a minimal proof of concept when useful. Remove credentials and personal data. There is no guaranteed response time.

Security fixes target the latest release. When the privileged helper needs an update, Insonia requests administrator approval during the next explicit Keep awake activation.

## Relevant boundaries

Insonia has an unprivileged menu bar app, a user recovery monitor, and a privileged helper that changes the system sleep setting. The installed helper resides in `/Library/PrivilegedHelperTools/com.henrick.insonia`. Changes crossing that boundary must authenticate session ownership, reject invalid state, and recover to normal sleep when a valid active session expires.

The recovery services are required for an active session. Insonia prepares them as part of Keep awake activation and uses the native macOS authorization prompt when elevated installation is needed. Cancelling authorization leaves Keep awake off; retrying requires another explicit user action. Automatic startup and background recovery must not create an authorization loop. Removing the app requires the [complete removal procedure](CONTRIBUTING.md#remove-a-local-installation), including the privileged helper and the user's recovery monitor.

The app must preserve manual locking and system authentication. It must not unlock a session, enter passwords, bypass FileVault, or grant another app Screen Recording or Accessibility access.

Recovery timing depends on macOS scheduling. Closed-lid display access depends on macOS and the hardware; brightness control uses private `DisplayServices` interfaces that may change with OS updates. A universal binary includes Apple silicon and Intel code, but compilation alone does not establish physical behavior on either architecture.

The current downloadable build is signed ad hoc, not with Apple Developer ID, and is not notarized. Download it from the [repository's Releases page](https://github.com/reyhenrick/insonia/releases). Checksums detect changed download bytes when compared with the published value; they do not replace publisher authentication or notarization.

## Update integrity

Insonia uses Sparkle 2.10 to check GitHub Releases and verify the update feed and archives with Ed25519 signatures before installation. The public key is embedded in the app. The corresponding private key stays in the maintainer's local macOS Keychain under `com.henrick.insonia.sparkle`; it is not available to CI. Automated workflows validate code and packages without publishing releases.

The stable feed is `https://github.com/reyhenrick/insonia/releases/latest/download/appcast.xml`. Each entry references a version-specific archive URL and includes the archive's signature and length. Released archives are immutable: a correction requires a new version. Publication uploads and verifies the archives before making their signed feed available. These signatures authenticate updates against the key trusted by the installed app. They do not provide Apple Developer ID signing or notarization for the first manual installation.

Automatic checks are enabled by default. Automatic downloading and installation are off by default and can be enabled in the app. Installation waits for Keep awake to be off, normal sleep and brightness to be restored, and setup to finish. Updating the app does not bypass the administrator approval required when the privileged helper needs an update.

## Privacy

Insonia needs no account and collects no analytics. Its power and recovery functions run locally. Update checks and downloads contact GitHub and its release-download infrastructure, which receive ordinary connection metadata such as the IP address. Sparkle system profiling is disabled. Links opened from the app or guide use the user's browser.

Recovery records stay on the Mac and contain power and session events, not screenshots or window contents. Review any diagnostic material before sharing it.
