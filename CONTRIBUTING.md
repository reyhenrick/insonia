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

`./test.sh` runs runtime and helper checks using isolated test state. `./build.sh` creates `build/Insonia.app`; it does not replace an installed app or install privileged services. Build output is signed ad hoc for local use. It is not Developer ID signed or notarized.

To produce the downloadable archives after a successful build:

```sh
scripts/package-release.sh
```

Packaging creates `dist/Insonia-macOS.dmg`, `dist/Insonia-macOS.zip`, `dist/SHA256SUMS.txt`, and `dist/release-metadata.json`. The metadata records the actual signing and notarization-ticket status. Packaging does not upload anything to GitHub. Do not commit build products, local logs, recovery state, or installed-app backups.

## Work with the current contract

- `PowerCore.swift` coordinates activation, preferences, and user-visible state.
- `PowerRuntime.swift` owns the session and brightness recovery journal; `PowerPolicy.swift` defines safety and session validity.
- `SystemServices.swift` adapts macOS power, display, and process services.
- `guardian/main.swift` supervises recovery independently of the app.
- `helper/` and `install-helper.sh` contain the privileged sleep service and its installer.
- `PanelView.swift`, `main.swift`, `Localization.swift`, and `Resources/` provide the interface, language selection, and bundled help.

Inspect both sides of a contract before changing it. A successful power command is not enough to confirm a session: activation must belong to the current session, and recovery must remain possible if a process exits or stops responding. Keep UI messages consistent with states the runtime actually confirms.

Do not remove manual-lock handling, battery and thermal cutoffs, session identity checks, or recovery records to make a test pass. Preserve the saved brightness until restoration is verified. Privileged code must not execute scripts from locations writable by an unprivileged user.

## Add or improve a translation

The interface uses `Resources/<language>.lproj/Localizable.strings`. The current languages are `en`, `pt`, `es`, `fr`, `de`, and `it`; English is the fallback. Use the English file as the key inventory.

1. Keep every key and placeholder, including `{0}` and `{1}`, unchanged. Translate their values.
2. Keep **Insonia** unaccented in every language. Preserve factual macOS API and file names.
3. Keep the English documentation in `Resources/Help/index.html` and `README.md` consistent when instructions or UI labels change. The app interface is multilingual; project documentation is in English.
4. Run `./test.sh` and `./build.sh`, then check the real panel and help at the selected language. Check long messages, buttons, and error states for clipping.

For a new interface language, update language selection and bundle registration as well as the strings. A new `.strings` file by itself does not establish complete support. Include the language and region you tested in your pull request.

## Verify behavior

Run `./test.sh` and `./build.sh` after your change. Include the commands and results in the pull request, with failures or skipped checks called out. Add focused behavior tests when you change a session, recovery, installer, or localization contract.

For UI changes, inspect the actual panel with long translations and both system appearances. For recovery changes, exercise stale and invalid state, process failure, and restoration errors in isolated tests before using a live system helper.

A universal binary is not proof of hardware compatibility. For changes to closed-lid agent access, record the Mac model, chip, macOS version, power source, and what you tested. Physical verification means performing a real screenshot, click, and typing action while the lid is closed, then checking brightness restoration after reopening. Do not describe a terminal heartbeat or successful build as a physical display test.

Installing or changing the privileged helper affects your Mac's sleep behavior and asks for administrator approval. Use the app's installation and removal controls for a live test; keep a path back to normal sleep and do not test with the Mac inside a bag.

## Open a useful issue or pull request

Search existing [issues](https://github.com/reyhenrick/insonia/issues) first. For a bug, include the app version, macOS version, chip, power source, whether agent mode was enabled, the steps, and what happened. Screenshots help with interface problems. Review diagnostics before attaching them and remove personal paths, names, and unrelated information.

For a larger change, open an issue describing the problem and proposed behavior before implementation. A pull request should explain the user-visible result, relevant tradeoffs, tests, and remaining limits. Keep unrelated formatting or refactoring separate. Never include credentials, personal files, or unrelated logs.

If the issue concerns privilege escalation, unauthorized commands, or another vulnerability, use the private reporting route in [SECURITY.md](SECURITY.md).
