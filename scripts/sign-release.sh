#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

[ "$#" -le 1 ] || { echo 'Usage: scripts/sign-release.sh [dist-directory]' >&2; exit 1; }
[ "${CI:-}" != true ] && [ "${GITHUB_ACTIONS:-}" != true ] || { echo 'Sign releases locally with the private key in Keychain.' >&2; exit 1; }
RELEASE_DIRECTORY="${1:-$PWD/dist}"
SPARKLE_DISTRIBUTION=$(./scripts/fetch-sparkle.sh)
GENERATOR="$SPARKLE_DISTRIBUTION/bin/generate_appcast"
[ ! -e "$RELEASE_DIRECTORY/appcast.xml" ] || { echo 'This directory already includes a signed feed. Package a new release before signing again.' >&2; exit 1; }
./scripts/verify-release.sh "$RELEASE_DIRECTORY"

STAGING=$(mktemp -d "$PWD/build/.signed-release.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ARCHIVES="$STAGING/archives"
OUTPUT="$STAGING/output"
mkdir -p "$ARCHIVES" "$OUTPUT" "$STAGING/unpacked"
for artifact in Insonia-macOS.dmg Insonia-macOS.zip release-metadata.json SHA256SUMS.txt; do
    cp "$RELEASE_DIRECTORY/$artifact" "$OUTPUT/$artifact"
done
./scripts/verify-release.sh "$OUTPUT"
/usr/bin/ditto -x -k "$OUTPUT/Insonia-macOS.zip" "$STAGING/unpacked"
APP="$STAGING/unpacked/Insonia.app"
INFO="$APP/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO")
RELEASE_TAG="${INSONIA_RELEASE_TAG:-v$VERSION}"
if [ "$RELEASE_TAG" != "v$VERSION" ] && [ "$RELEASE_TAG" != "v$VERSION-build.$BUILD_NUMBER" ]; then
    echo 'The release tag must match the bundle version, optionally followed by -build. and its build number.' >&2
    exit 1
fi
PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO")
REQUIRE_SIGNED_FEED=$(/usr/libexec/PlistBuddy -c 'Print :SURequireSignedFeed' "$INFO")
[ "$REQUIRE_SIGNED_FEED" = true ] || { echo 'The application must require signed feeds.' >&2; exit 1; }
cp "$OUTPUT/Insonia-macOS.zip" "$ARCHIVES/Insonia-macOS.zip"
/usr/bin/python3 - "$VERSION" "$PWD/CHANGELOG.md" "$ARCHIVES/Insonia-macOS.txt" <<'PY'
from pathlib import Path
import re
import sys

version, source, output = sys.argv[1:]
changelog = Path(source).read_text()
section = re.search(r'^## ' + re.escape(version) + r'(?:\s[^\n]*)?\n(.*?)(?=^## |\Z)', changelog, re.M | re.S)
notes = section.group(1).strip() if section else f'Insonia {version}'
Path(output).write_text(notes + '\n')
PY
"$GENERATOR" --account com.henrick.insonia.sparkle \
    --download-url-prefix "https://github.com/reyhenrick/insonia/releases/download/$RELEASE_TAG/" \
    --link 'https://github.com/reyhenrick/insonia' --embed-release-notes \
    --maximum-deltas 0 --maximum-versions 1 --versions "$BUILD_NUMBER" \
    -o "$ARCHIVES/appcast.xml" "$ARCHIVES"
cmp -s "$OUTPUT/Insonia-macOS.zip" "$ARCHIVES/Insonia-macOS.zip" || { echo 'The archive changed during signing.' >&2; exit 1; }
cp "$ARCHIVES/appcast.xml" "$OUTPUT/appcast.xml"
xcrun swift scripts/verify-update.swift "$OUTPUT/appcast.xml" "$OUTPUT/Insonia-macOS.zip" "$PUBLIC_KEY" "$BUILD_NUMBER" "$VERSION"
./scripts/verify-release.sh --metadata "$APP" "$OUTPUT/Insonia-macOS.dmg" "$OUTPUT/Insonia-macOS.zip" "$OUTPUT/appcast.xml" \
    > "$OUTPUT/release-metadata.json"
(
    cd "$OUTPUT"
    shasum -a 256 Insonia-macOS.dmg Insonia-macOS.zip release-metadata.json appcast.xml > SHA256SUMS.txt
)
./scripts/verify-release.sh --require-feed "$OUTPUT"
for artifact in appcast.xml release-metadata.json SHA256SUMS.txt; do
    mv "$OUTPUT/$artifact" "$RELEASE_DIRECTORY/$artifact"
done
./scripts/verify-release.sh --require-feed "$RELEASE_DIRECTORY"
echo "Signed update artifacts: $RELEASE_DIRECTORY"
echo 'Update signatures verify the feed and ZIP. Apple signing and notarization remain recorded separately in release-metadata.json.'
