#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
SOURCE="$PWD/build/Insonia.app"
TARGET='/Applications/Insonia.app'
[ -d "$SOURCE" ] || { echo 'Run ./build.sh first.' >&2; exit 1; }
codesign --verify --deep --strict "$SOURCE"
RESUME=0
if /usr/bin/pmset -g | /usr/bin/awk '$1 == "SleepDisabled" { exit ($2 == 1 ? 0 : 1) }'; then RESUME=1; fi
if /usr/bin/pgrep -f '^/Applications/Insonia.app/Contents/MacOS/Insonia( |$)' >/dev/null; then
    /usr/bin/osascript -e 'tell application id "com.henrick.insonia" to quit'
    for attempt in 1 2 3 4 5; do
        if ! /usr/bin/pgrep -f '^/Applications/Insonia.app/Contents/MacOS/Insonia( |$)' >/dev/null; then break; fi
        sleep 1
    done
    if /usr/bin/pgrep -f '^/Applications/Insonia.app/Contents/MacOS/Insonia( |$)' >/dev/null; then
        echo 'The current application did not quit; installation was not changed.' >&2
        exit 1
    fi
fi
/bin/launchctl bootout "gui/$(id -u)/com.henrick.insonia.guardian" 2>/dev/null || true
STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p build/installed-backups
BACKUP="$PWD/build/installed-backups/Insonia-$STAMP.app"
STAGED="/Applications/.Insonia-$STAMP.app"
/usr/bin/ditto "$SOURCE" "$STAGED"
codesign --verify --deep --strict "$STAGED"
if [ -d "$TARGET" ]; then mv "$TARGET" "$BACKUP"; fi
if ! mv "$STAGED" "$TARGET"; then
    if [ -d "$BACKUP" ]; then mv "$BACKUP" "$TARGET"; fi
    exit 1
fi
codesign --verify --deep --strict "$TARGET"
ARGS=(--open-panel)
if [ "$RESUME" -eq 1 ]; then ARGS+=(--resume-active); fi
OPENED=0
for attempt in 1 2 3; do
    if open -a "$TARGET" --args "${ARGS[@]}"; then OPENED=1; break; fi
    # LaunchServices can retain the just-terminated instance briefly after a
    # bundle replacement. Refresh registration and retry without force-quitting.
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$TARGET"
    sleep 1
done
[ "$OPENED" -eq 1 ] || { echo 'Installed, but macOS could not open Insonia. Open it from Applications.' >&2; exit 1; }
echo "Installed: $TARGET"
echo "Previous installation: $BACKUP"
