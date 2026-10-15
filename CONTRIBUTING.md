# Contributing to Insonia

Contributions are welcome: reproducible bug reports, translations, clearer instructions, compatibility testing, and focused code changes all help. You can open an issue or pull request in English or Portuguese. Be respectful, explain your reasoning, and keep feedback about the work.

Insonia is available under the [MIT license](LICENSE). Contributions are made under that same license. You retain copyright to your contributions.

## Get started

Use a Mac running macOS 26 or later, Xcode with the macOS 26 SDK or newer, and Python 3 for the helper tests. Select the Xcode installation with `xcode-select`, or set `DEVELOPER_DIR` for the command you run. Icon compilation requires Xcode's asset tools.

Fork the repository, clone your fork, and make a focused change on a branch:

```sh
git clone https://github.com/YOUR-USERNAME/insonia.git
cd insonia
git switch -c describe-your-change
./test.sh
./build.sh
```

`./test.sh` runs runtime and helper checks using isolated test state. `./build.sh` creates `build/Insonia.app` with the pinned Sparkle 2.10 updater; it does not replace an installed app or install privileged services. Build output is signed ad hoc for local use. It is not Developer ID signed or notarized.

To produce the downloadable archives after a successful build:

```sh
scripts/package-release.sh
```

Packaging creates `dist/Insonia-macOS.dmg`, `dist/Insonia-macOS.zip`, `dist/SHA256SUMS.txt`, and `dist/release-metadata.json`. The ZIP contains only the app so Sparkle can install it. The disk image also includes the English guide. The metadata records the actual signing and notarization-ticket status. Packaging does not upload anything to GitHub. Do not commit build products, local logs, recovery state, or installed-app backups.

## Work with the current contract

- `PowerCore.swift` coordinates activation, preferences, and user-visible state.
- `PowerRuntime.swift` owns the session and brightness recovery journal; `PowerPolicy.swift` defines safety and session validity.
- `SystemServices.swift` adapts macOS power, display, and process services.
- `guardian/main.swift` supervises recovery independently of the app.
- `helper/` and `install-helper.sh` contain the privileged sleep service and its installer.
- `PanelView.swift`, `main.swift`, `Localization.swift`, and `Resources/` provide the interface, language selection, and bundled English guide.

Inspect both sides of a contract before changing it. A successful power command is not enough to confirm a session: activation must belong to the current session, and recovery must remain possible if a process exits or stops responding. Keep UI messages consistent with states the runtime actually confirms.

Do not remove manual-lock handling, battery and thermal cutoffs, session identity checks, or recovery records to make a test pass. Preserve the saved brightness until restoration is verified. Privileged code must not execute scripts from locations writable by an unprivileged user.

Recovery is intrinsic to Keep awake. A user request to activate it starts any required setup, including the native macOS administrator prompt for the privileged helper. Activation must wait for setup and recovery readiness. Cancelling authorization leaves Keep awake off and clears the pending activation; only another explicit activation request retries. Background checks and automatic startup must not repeatedly open authorization prompts.

Update installation must wait until Keep awake is off, normal sleep and brightness recovery are confirmed, and setup has finished. The first launch after an update suppresses Start active once while preserving the preference. Automatic update checks are enabled by default. Automatic downloading and installation are a separate preference, off by default. Keep these defaults, the panel labels, and the documentation consistent. System profiling must remain disabled.

## Add or improve a translation

The interface uses `Resources/<language>.lproj/Localizable.strings`. The current languages are `en`, `pt`, `es`, `fr`, `de`, and `it`; English is the fallback. Use the English file as the key inventory.

1. Keep every key and placeholder, including `{0}` and `{1}`, unchanged. Translate their values.
2. Keep **Insonia** unaccented in every language. Preserve factual macOS API and file names.
3. Keep the English documentation in `Resources/Help/index.html` and `README.md` consistent when instructions or UI labels change. The app interface is multilingual; project documentation is in English.
4. Run `./test.sh` and `./build.sh`, then check the real panel in the selected language. Check long messages, buttons, and error states for clipping. The bundled guide stays in English.

For a new interface language, update language selection and bundle registration as well as the strings. A new `.strings` file by itself does not establish complete support. Include the language and region you tested in your pull request.

## Verify behavior

Run `./test.sh` and `./build.sh` after your change. Include the commands and results in the pull request, with failures or skipped checks called out. Add focused behavior tests when you change a session, recovery, installer, or localization contract.

For UI changes, inspect the actual panel with long translations and both system appearances. For recovery changes, exercise stale and invalid state, process failure, and restoration errors in isolated tests before using a live system helper.

A universal binary is not proof of hardware compatibility. For changes to closed-lid agent access, record the Mac model, chip, macOS version, power source, and what you tested. Physical verification means performing a real screenshot, click, and typing action while the lid is closed, then checking brightness restoration after reopening. Do not describe a terminal heartbeat or successful build as a physical display test.

Installing or changing the privileged helper affects your Mac's sleep behavior and asks for administrator approval. For a live setup test, turn on Keep awake and follow the native macOS prompt. Exercise approval and cancellation, and verify that cancellation requires another explicit activation request. Keep a path back to normal sleep and do not test with the Mac inside a bag.

## Remove a local installation

Use this procedure from the same macOS account that runs Insonia. It removes the app's background services before you delete the app.

1. Turn off **Keep awake** and **Open at login**. Wait for normal sleep and the original display brightness to be restored, then choose **Quit**. If recovery is still pending, leave Insonia running until it finishes before continuing.
2. Open Terminal as your regular user and run the bundled uninstaller. Enter the administrator password only at the Terminal prompt:

   ```sh
   sudo /bin/bash "/Applications/Insonia.app/Contents/Resources/helper-install/install-helper.sh" --user "$(id -un)" --uninstall
   ```

   If you installed the app in your personal Applications folder, replace `/Applications/Insonia.app` with `$HOME/Applications/Insonia.app`. If your account cannot use `sudo`, ask a Mac administrator to run this command with `--user` set to your short account name, then continue the remaining steps in your own account. Continue only after the command succeeds. It verifies normal system sleep before removing the privileged helper and its launch daemon; if that verification fails, it preserves the helper files.
3. Stop the recovery monitor for your account and remove its launch agent:

   ```sh
   insonia_guardian_target="gui/$(id -u)/com.henrick.insonia.guardian"
   if /bin/launchctl print "$insonia_guardian_target" >/dev/null 2>&1; then
       /bin/launchctl bootout "$insonia_guardian_target" &&
           /bin/rm -f "$HOME/Library/LaunchAgents/com.henrick.insonia.guardian.plist"
   else
       /bin/rm -f "$HOME/Library/LaunchAgents/com.henrick.insonia.guardian.plist"
   fi
   ```

   A stopped monitor may already be absent from `launchctl`; its plist still needs removal so it cannot start at login. If stopping the monitor reports an error, resolve it before deleting the app.
4. Move **Insonia.app** from Applications to the Trash.

Local preferences and recovery records are retained. After the services are stopped and recovery has completed, you can remove the records through Finder at `~/Library/Application Support/Insonia` if you no longer need them.

## Sign and publish an update

The app uses Sparkle's Ed25519 signatures to verify the update feed and archives. The public key is bundled in `Info.plist`. The private key belongs only in the maintainer's local macOS Keychain under `com.henrick.insonia.sparkle`; never export it into a repository, script, log, command-line argument, or CI secret. Contributors can build and test without it. CI validates code and packages without the private key and does not publish releases automatically.

After the final build and packaging checks, the maintainer runs:

```sh
scripts/sign-release.sh
scripts/verify-release.sh --require-feed dist
```

The signing script reads the key directly from Keychain, signs the update feed and ZIP, and refreshes the checksums and metadata in `dist/`. It accepts another prepared output directory as its only optional argument. Sign the exact ZIP that will be published. Repackaging or modifying it afterward invalidates its signature and requires new checksums and signing.

Publish the completed release assets under a new version tag. The appcast must point to the immutable version-specific ZIP URL, such as `https://github.com/reyhenrick/insonia/releases/download/v1.0.0/Insonia-macOS.zip`. Verify those assets are available before publishing the signed `appcast.xml` last. Never replace an archive already referenced by a published feed; correct it in a new version.

The app reads the stable feed at `https://github.com/reyhenrick/insonia/releases/latest/download/appcast.xml`. Preserve that endpoint when publishing a new release. Keep the signed archive's version, length, signature, checksum, and URL consistent with the feed. A public checksum is useful for manual verification, but it does not replace the update signature. Ed25519 update signing is also separate from Apple Developer ID signing and notarization.

Test manual checks, default installation confirmation, the automatic-install preference, and deferred installation during an active or recovering session. A successful package check alone does not verify the installed-app update flow.

## Open a useful issue or pull request

Search existing [issues](https://github.com/reyhenrick/insonia/issues) first. For a bug, include the app version, macOS version, chip, power source, whether agent mode was enabled, the steps, and what happened. Screenshots help with interface problems. Review diagnostics before attaching them and remove personal paths, names, and unrelated information.

For a larger change, open an issue describing the problem and proposed behavior before implementation. A pull request should explain the user-visible result, relevant tradeoffs, tests, and remaining limits. Keep unrelated formatting or refactoring separate. Never include credentials, personal files, or unrelated logs.

If the issue concerns privilege escalation, unauthorized commands, or another vulnerability, use the private reporting route in [SECURITY.md](SECURITY.md).
