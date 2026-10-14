<p align="center">
  <img src="docs/assets/icon.png" width="96" height="96" alt="Insonia app icon">
</p>

# Insonia

**Keep your Mac awake, even with the lid closed.**

A native macOS menu bar app for long-running work, with optional display access for visual agents, automatic recovery, and an interface that follows your Mac's language.

**[Download for Mac](https://github.com/reyhenrick/insonia/releases/latest/download/Insonia-macOS.dmg)** · [All releases](https://github.com/reyhenrick/insonia/releases)

macOS **26 or later**. Universal binary for Apple silicon and compatible Intel Macs. Free and open source under the [MIT license](LICENSE).

## Install and start

1. Download and open **Insonia-macOS.dmg**.
2. Drag **Insonia** to **Applications**, then open it from Applications. You can eject the disk image afterward.
3. Click the **lightning bolt in the menu bar** to open the panel.
4. Choose **Install system protection** or **Update system protection**, then approve the native macOS administrator prompt. This installs the helper that changes sleep behavior and restores it after a failure.
5. Turn on **Keep awake** and wait for activation to be confirmed.

Insonia lives in the menu bar, so it does not need a permanent Dock icon. Right-click the menu bar icon to toggle Keep awake. **Help** opens the guide bundled with the app, including installation, troubleshooting, and removal.

### First opening and Gatekeeper

The download is **not signed with an Apple Developer ID and is not notarized by Apple**. macOS may block its first launch. If you trust this release, first try opening it, then go to **System Settings → Privacy & Security → Open Anyway** and confirm **Open**. This grants an exception for this app. Managed Macs may restrict this option. Follow [Apple's instructions for opening downloaded apps](https://support.apple.com/en-us/102445).

If macOS says the app is damaged or will harm your computer, stop and download a fresh copy from this repository's Releases page. Report a persistent problem; do not disable macOS security checks.

### Other download options

- [ZIP archive](https://github.com/reyhenrick/insonia/releases/latest/download/Insonia-macOS.zip): unzip it, move Insonia to Applications, and follow the same steps above.
- [SHA-256 checksums](https://github.com/reyhenrick/insonia/releases/latest/download/SHA256SUMS.txt): compare the hash of your download with the matching filename in this file. On macOS, run `shasum -a 256 Insonia-macOS.dmg` in the folder containing the download. A matching checksum verifies the downloaded bytes; it is not Apple notarization.

## Choose how you work

**Keep awake** keeps background tasks running with the lid closed. With agent access turned off, the display can sleep.

**Allow agents to use the display** also preserves an already unlocked graphical session. Enable it with the lid open and the Mac unlocked, then turn on Keep awake. When you close the lid, Insonia reduces the built-in display's brightness to at most 1%. It restores the saved brightness when you open the lid or end the session. External displays are not dimmed.

Agent mode does not unlock your Mac, enter passwords, or change FileVault. Locking the Mac manually, switching users, or a system policy can pause visual access. Screen Recording and Accessibility permissions belong to the agent that uses them, not to Insonia. Test an actual capture, click, and typing action with your agent before relying on closed-lid visual work.

**Open at login** launches the app when you sign in. **Start active** requests Keep awake when the app launches. They are separate preferences. A protective shutdown requires you to start a new session yourself; Insonia does not silently reactivate it.

## Your Mac's language, automatically

Insonia supports **English, Portuguese, Spanish, French, German, and Italian**. It chooses a supported language from your macOS language preferences and uses English when none matches. To change your preference, use **System Settings → General → Language & Region**, then reopen Insonia. Documentation and the bundled guide are in English.

## Recovery and limits

Insonia checks battery, temperature, and the health of its recovery services. It stops keeping the Mac awake when:

- The Mac is on battery at **15% or less**, or the battery level cannot be checked.
- macOS reports **serious or critical thermal pressure**.
- The app or its recovery monitor cannot maintain a healthy session.

An independent privileged helper returns the Mac to normal sleep behavior when the active session's signal expires. Brightness recovery keeps the saved value until restoration is confirmed. These are recovery mechanisms, not a real-time guarantee; macOS scheduling can delay them. Keep an active Mac on a ventilated surface, not inside a closed bag.

Closed-lid display access depends on macOS and the hardware. Brightness control currently uses private `DisplayServices` interfaces, so a future macOS release can change this behavior. The universal build includes Intel code, but that does **not** constitute a physical test on Intel hardware.

## If something needs attention

**“The recovery monitor lost its signal.”** Insonia turned off Keep awake. Read the current protection status: a previous interruption can remain visible after protection recovers. Use **Repair monitor** if offered, or quit and reopen the app from Applications. If asked, update system protection. When the panel confirms protection is ready, start a new session manually. Repeated failures should be [reported with the app and macOS versions](https://github.com/reyhenrick/insonia/issues/new/choose).

**The agent cannot see or use the display.** Open the lid, unlock the Mac, check the agent's Screen Recording and Accessibility permissions, and enable agent access before closing the lid again. A running background process alone does not confirm graphical access.

**The app stopped on battery or while warm.** Connect power or let the Mac cool down, then turn Keep awake on again. The app will not restart a session automatically after a protective cutoff.

**Updating an older version.** Quit Insonia, replace the app in Applications, and open it again. Version 1.2 requires a one-time system protection update to helper v3. Use the update button in the panel and approve the macOS administrator prompt.

## Remove Insonia

1. Turn off **Keep awake** and **Open at login**.
2. Open the panel's **…** menu, choose **Remove protection…**, and approve the macOS administrator prompt. Insonia restores normal sleep, removes the protection services, and quits when removal succeeds. Wait for the app to close.
3. Move **Insonia.app** from Applications to the Trash.

Remove protection before deleting the app so its privileged service can be removed through the supported flow.

## Local by design

Insonia works locally. It has no account, analytics, or background network requests. Links you choose to open, such as the source repository, use your browser. Local recovery records contain power and session events, not screenshots or window contents.

## Build and contribute

Bug reports, translations, documentation improvements, and code contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) for setup, checks, and the pull request workflow. Report security issues privately through [SECURITY.md](SECURITY.md).

With Xcode and a macOS 26 SDK or newer available:

```sh
git clone https://github.com/reyhenrick/insonia.git
cd insonia
./test.sh
./build.sh
scripts/package-release.sh
```

The build creates `build/Insonia.app`. Release packaging creates the DMG, ZIP, checksums, and signing metadata in `dist/`. These commands do not publish a release or install the system helper. By default, the locally built app is signed ad hoc; that signature is not an Apple Developer ID signature.

The app is written in Swift and SwiftUI. `PowerCore.swift` coordinates the interface and session, `PowerRuntime.swift` owns recovery state, `PowerPolicy.swift` defines safety rules, `guardian/main.swift` supervises the app, and the privileged helper applies and restores the system sleep setting.

[Release notes](CHANGELOG.md) · [Report an issue](https://github.com/reyhenrick/insonia/issues/new/choose) · [MIT license](LICENSE)
