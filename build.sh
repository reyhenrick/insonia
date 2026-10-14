#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
STAGING=$(mktemp -d "$PWD/build/.stage.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Insonia.app"
SDK=$(xcrun --sdk macosx --show-sdk-path)
COMMON=(Localization.swift PowerPolicy.swift PowerRuntime.swift SystemServices.swift)
SIGNING_ARGS=(--force --sign "${SIGNING_IDENTITY:--}")
if [ "${SIGNING_IDENTITY:--}" = '-' ]; then
    SIGNING_ARGS+=(--timestamp=none)
else
    SIGNING_ARGS+=(--options runtime --timestamp)
fi

for source in "${COMMON[@]}" PowerCore.swift PanelView.swift main.swift guardian/main.swift LICENSE; do
    [ -f "$source" ] || { echo "Missing build input: $source" >&2; exit 1; }
done
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
for architecture in arm64 x86_64; do
    SWIFT_FLAGS=(-O -sdk "$SDK" -target "$architecture-apple-macos26.0" -framework AppKit -framework IOKit)
    xcrun --sdk macosx swiftc "${SWIFT_FLAGS[@]}" -framework SwiftUI "${COMMON[@]}" \
        PowerCore.swift PanelView.swift main.swift -o "$STAGING/Insonia-$architecture"
    xcrun --sdk macosx swiftc "${SWIFT_FLAGS[@]}" "${COMMON[@]}" \
        guardian/main.swift -o "$STAGING/InsoniaGuard-$architecture"
done
xcrun lipo -create "$STAGING/Insonia-arm64" "$STAGING/Insonia-x86_64" -output "$APP/Contents/MacOS/Insonia"
xcrun lipo -create "$STAGING/InsoniaGuard-arm64" "$STAGING/InsoniaGuard-x86_64" -output "$APP/Contents/Helpers/InsoniaGuard"

/usr/bin/ditto Resources "$APP/Contents/Resources"
mkdir -p "$STAGING/icons" "$APP/Contents/Resources/helper-install/helper"
xcrun actool --compile "$STAGING/icons" --platform macosx --minimum-deployment-target 26.0 \
    --app-icon Insonia --output-partial-info-plist "$STAGING/icons/icon.plist" --target-device mac Insonia.icon >/dev/null
cp "$STAGING/icons/Assets.car" "$STAGING/icons/Insonia.icns" "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Merge $STAGING/icons/icon.plist" "$APP/Contents/Info.plist" >/dev/null
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp install-helper.sh "$APP/Contents/Resources/helper-install/"
cp helper/insonia-helper.sh helper/com.henrick.insonia.helper.plist "$APP/Contents/Resources/helper-install/helper/"
codesign "${SIGNING_ARGS[@]}" "$APP/Contents/Helpers/InsoniaGuard"
codesign "${SIGNING_ARGS[@]}" "$APP"
./scripts/verify-release.sh --app "$APP"

if [ -e build/Insonia.app ]; then
    mkdir -p build/previous
    mv build/Insonia.app "build/previous/Insonia-$(date -u +%Y%m%dT%H%M%SZ)-$$.app"
fi
mv "$APP" build/Insonia.app
echo "Built and verified: $PWD/build/Insonia.app"
echo 'Create downloads with ./scripts/package-release.sh.'
