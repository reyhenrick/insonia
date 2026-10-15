**English** · [Português (Brasil)](docs/readme/README_pt-BR.md) · [Español](docs/readme/README_es.md) · [Français](docs/readme/README_fr.md) · [Deutsch](docs/readme/README_de.md) · [Italiano](docs/readme/README_it.md)

<p align="center">
  <img src="docs/assets/icon.png" width="96" height="96" alt="Insonia app icon">
</p>

# Insonia

**Keep your coding agents running with the lid closed.**

Insonia keeps your Mac awake while local agents, builds, and tests run. You can close the laptop and step away without putting the machine to sleep. If you use remote access to follow your agents from your phone, your Mac can stay available at home while you're out.

**[Download for Mac](https://github.com/reyhenrick/insonia/releases/latest/download/Insonia-macOS.dmg)**

macOS 26 or later · Apple silicon and Intel · Free and open source

<p align="center">
  <img src="docs/assets/panel.png" width="380" alt="Insonia menu bar panel with Keep awake enabled">
</p>

<a id="install-and-start"></a>

## Install

1. Open the DMG and drag **Insonia** to **Applications**.
2. Open Insonia and click the lightning bolt in the menu bar.
3. Turn on **Keep awake**, approve the macOS administrator prompt if asked, and wait for activation.

The app is not notarized by Apple. If macOS blocks the first launch, follow [Apple's instructions](https://support.apple.com/en-us/102445) to open it from **System Settings → Privacy & Security → Open Anyway**.

## Use with coding agents

Start your agent as usual and turn on **Keep awake** before closing the lid. Turn it off when you're done to restore normal sleep.

For agents that interact with browser or app windows, also enable **Allow agents to use the display** while the lid is open and the Mac is unlocked. Insonia dims the built-in display when you close the lid and restores its brightness when you reopen it. Locking the Mac can pause this visual access.

For access while you're away, keep the Mac connected to the internet and use your agent's remote controls or your existing remote-access tool. Insonia handles the Mac's sleep behavior; remote access is configured separately.

Keep the Mac on a ventilated surface while it works. Insonia pauses at 15% battery or less when unplugged, or when macOS reports serious thermal pressure.

## Updates

Insonia checks for updates automatically. Use **Check for updates…** in the panel to install a release. Installation waits until Keep awake is off and the session has finished.

## Contribute

The project is released under the [MIT license](LICENSE). See [CONTRIBUTING.md](CONTRIBUTING.md) for build instructions and contributions, or [open an issue](https://github.com/reyhenrick/insonia/issues/new/choose) to report a problem.

[Uninstall](CONTRIBUTING.md#remove-a-local-installation) · [Security](SECURITY.md) · [Releases](https://github.com/reyhenrick/insonia/releases)
