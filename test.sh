#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
/usr/bin/ditto Resources build/Resources
xcrun swiftc -target "$(uname -m)-apple-macos26.0" Localization.swift PowerPolicy.swift PowerRuntime.swift UpdatePolicy.swift tests/RuntimeTests.swift -o build/runtime-tests
./build/runtime-tests
SPARKLE_DISTRIBUTION=$(./scripts/fetch-sparkle.sh)
xcrun swiftc -target "$(uname -m)-apple-macos26.0" -framework AppKit -framework IOKit \
    -F "$SPARKLE_DISTRIBUTION" -framework Sparkle -Xlinker -rpath -Xlinker "$SPARKLE_DISTRIBUTION" \
    Localization.swift PowerPolicy.swift PowerRuntime.swift SystemServices.swift UpdatePolicy.swift \
    PowerCore.swift AppUpdater.swift tests/UpdaterContractTests.swift -o build/updater-contract-tests
./build/updater-contract-tests
/usr/bin/python3 tests/test_localizations.py
/usr/bin/python3 tests/test_helper.py
/usr/bin/python3 tests/test_installer.py
/usr/bin/python3 tests/test_update_signatures.py
bash -n build.sh install-app.sh install-helper.sh helper/insonia-helper.sh scripts/fetch-sparkle.sh scripts/package-release.sh scripts/verify-release.sh scripts/sign-release.sh
plutil -lint Info.plist helper/com.henrick.insonia.helper.plist
