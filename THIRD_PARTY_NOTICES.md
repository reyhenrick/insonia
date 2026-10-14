# Third-party notices

Insonia includes [Sparkle 2.10.0](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0), the open-source software update framework for macOS.

Sparkle is distributed under the MIT license and includes third-party components with their own notices. The unmodified upstream license, including all bundled external license notices, is in [Resources/Sparkle-LICENSE.txt](Resources/Sparkle-LICENSE.txt) and is included in the application's Resources directory.

The exact release archive and SHA-256 checksum used by the build are pinned in [dependencies.json](dependencies.json). `scripts/fetch-sparkle.sh` verifies the archive before extracting it and verifies cached extracted files against that archive before returning its path. The build embeds the official framework and re-signs its nested executables with the application's signing identity; it does not rebuild Sparkle from source.
