#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
/usr/bin/ditto Resources build/Resources
xcrun swiftc -target "$(uname -m)-apple-macos26.0" Localization.swift PowerPolicy.swift PowerRuntime.swift tests/RuntimeTests.swift -o build/runtime-tests
./build/runtime-tests
/usr/bin/python3 tests/test_localizations.py
/usr/bin/python3 tests/test_helper.py
/usr/bin/python3 tests/test_installer.py
bash -n build.sh install-app.sh install-helper.sh helper/insonia-helper.sh scripts/package-release.sh scripts/verify-release.sh
plutil -lint Info.plist helper/com.henrick.insonia.helper.plist
