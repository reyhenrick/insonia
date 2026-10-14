#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$PWD/build/Insonia.app"
[ -d "$APP" ] || { echo 'Run ./build.sh first.' >&2; exit 1; }
./scripts/verify-release.sh --app "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGING=$(mktemp -d "$PWD/build/.release.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
DISK="$STAGING/disk"
OUTPUT="$STAGING/output"
mkdir -p "$DISK" "$OUTPUT"
/usr/bin/ditto -c -k --norsrc --keepParent "$APP" "$OUTPUT/Insonia-macOS.zip"
/usr/bin/ditto "$APP" "$DISK/Insonia.app"
cp "$APP/Contents/Resources/Help/index.html" "$DISK/README-install.html"
ln -s /Applications "$DISK/Applications"
cp "$APP/Contents/Resources/Insonia.icns" "$DISK/.VolumeIcon.icns"
xcrun SetFile -a C "$DISK"
hdiutil create -quiet -volname "Insonia $VERSION" -srcfolder "$DISK" -fs HFS+ -format UDZO \
    "$OUTPUT/Insonia-macOS.dmg"
if [ "${SIGNING_IDENTITY:--}" != '-' ]; then
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$OUTPUT/Insonia-macOS.dmg"
fi
./scripts/verify-release.sh --metadata "$APP" "$OUTPUT/Insonia-macOS.dmg" "$OUTPUT/Insonia-macOS.zip" \
    > "$OUTPUT/release-metadata.json"
(
    cd "$OUTPUT"
    shasum -a 256 Insonia-macOS.dmg Insonia-macOS.zip release-metadata.json > SHA256SUMS.txt
)
./scripts/verify-release.sh "$OUTPUT"
mkdir -p dist
for artifact in Insonia-macOS.dmg Insonia-macOS.zip release-metadata.json SHA256SUMS.txt; do
    mv "$OUTPUT/$artifact" "dist/$artifact"
done
if [ -e dist/appcast.xml ]; then
    rm dist/appcast.xml
fi
echo "Verified downloads: $PWD/dist"
echo 'These local packages have no signed update feed. Run ./scripts/sign-release.sh before publishing.'
echo 'These scripts do not submit builds for Apple notarization. See release-metadata.json for actual signing and ticket status.'
