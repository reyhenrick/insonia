#!/bin/bash
set -euo pipefail
umask 022
LABEL='com.henrick.insonia.helper'
DAEMON_DIR='/Library/LaunchDaemons'
DAEMON_PLIST="$DAEMON_DIR/$LABEL.plist"
HELPER_PARENT='/Library/PrivilegedHelperTools'
INSTALL_DIR="$HELPER_PARENT/com.henrick.insonia"
HELPER_BIN="$INSTALL_DIR/helper.sh"
VERSION_FILE="$INSTALL_DIR/version"
BOOT_MARKER='/var/run/insonia-helper-v3-booted'
STATUS_FILE='/var/run/insonia-helper-v3-status'
LEGACY_DIR='/usr/local/libexec'
REAL_USER="${SUDO_USER:-}"
UNINSTALL=0
SERVICE_WAS_RUNNING=0
fail() { printf '%s\n' "$2" >&2; exit "$1"; }
while [ "$#" -gt 0 ]; do
    case "$1" in
        --user)
            [ "$#" -ge 2 ] || fail 2 'Specify the non-root app user with --user.'
            REAL_USER="$2"; shift 2 ;;
        --uninstall) UNINSTALL=1; shift ;;
        *) fail 2 'usage: install-helper.sh --user USER [--uninstall]' ;;
    esac
done
[ "$(/usr/bin/id -u)" -eq 0 ] || fail 1 'Administrator authorization is required.'
case "$REAL_USER" in ''|root|*[!a-zA-Z0-9._-]*) fail 2 'Specify the non-root app user with --user.' ;; esac
REAL_UID=$(/usr/bin/id -u "$REAL_USER") || fail 2 'The app user does not exist.'
[ "$REAL_UID" -ge 501 ] || fail 2 'A regular local user is required.'
REAL_HOME=$(/usr/bin/dscl . -read "/Users/$REAL_USER" NFSHomeDirectory | /usr/bin/sed -n 's/^NFSHomeDirectory: //p')
case "$REAL_HOME" in /*) ;; *) fail 2 'Invalid user home.' ;; esac
case "$REAL_HOME" in *"'"*|*$'\n'*) fail 2 'Unsupported home path.' ;; esac
STATE_DIR="$REAL_HOME/Library/Application Support/Insonia"

secure_node() {
    local path="$1" mode owner permissions
    [ ! -L "$path" ] || return 1
    owner=$(/usr/bin/stat -f '%u' "$path") || return 1
    mode=$(/usr/bin/stat -f '%Lp' "$path") || return 1
    [ "$owner" = 0 ] || return 1
    case "$mode" in ''|*[!0-7]*) return 1 ;; esac
    [ "$((8#$mode & 8#022))" -eq 0 ] || return 1
    permissions=$(/bin/ls -lde "$path") || return 1
    printf '%s\n' "$permissions" | /usr/bin/awk '
        /^[[:space:]]*[0-9]+: / && / allow / && /(^|[ ,])(write|write_data|append|append_data|add_file|add_subdirectory|delete|delete_child|writeattr|writeextattr|writesecurity|chown)(,|$)/ { exit 1 }
    '
}
secure_directory() {
    local path="$1"
    while :; do
        [ -d "$path" ] && secure_node "$path" || return 1
        [ "$path" != / ] || return 0
        path="${path%/*}"
        [ -n "$path" ] || path=/
    done
}
ensure_directory() {
    local path="$1" parent="${1%/*}"
    secure_directory "$parent" || fail 3 "Unsafe installation parent: $parent"
    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
        /usr/bin/install -d -o root -g wheel -m 755 "$path"
    fi
    secure_directory "$path" || fail 3 "Unsafe installation directory: $path"
}
safe_file() {
    local path="$1"
    if [ -e "$path" ] || [ -L "$path" ]; then
        [ -f "$path" ] && secure_node "$path" &&
            [ "$(/usr/bin/stat -f '%l' "$path")" = 1 ] || return 1
    fi
}
validate_files() {
    local path
    for path in "$DAEMON_PLIST" "$HELPER_BIN" "$VERSION_FILE" "$BOOT_MARKER" "$STATUS_FILE"; do
        safe_file "$path" || fail 3 "Unsafe installed file: $path"
    done
}
stop_service() {
    if /bin/launchctl print "system/$LABEL" >/dev/null 2>&1; then
        SERVICE_WAS_RUNNING=1
        /bin/launchctl bootout "system/$LABEL" || fail 4 'Unable to stop the installed helper.'
    fi
}
restore_sleep() {
    local current=''
    if /usr/bin/pmset -a disablesleep 0; then
        current=$(/usr/bin/pmset -g | /usr/bin/awk '$1 == "SleepDisabled" { print $2 }') || current=''
    fi
    if [ "$current" != 0 ]; then
        if [ "$SERVICE_WAS_RUNNING" = 1 ] && [ -f "$DAEMON_PLIST" ]; then
            /bin/launchctl bootstrap system "$DAEMON_PLIST" >/dev/null 2>&1 || true
        fi
        fail 5 'Normal system sleep could not be verified; the installed helper files were preserved.'
    fi
}
cleanup_legacy() {
    local path
    for path in "$LEGACY_DIR/insonia-helper.sh" "$LEGACY_DIR/insonia-helper.version"; do
        if [ -e "$path" ] || [ -L "$path" ]; then
            if secure_directory "$LEGACY_DIR" && safe_file "$path"; then
                /bin/rm -f "$path"
            else
                printf 'Legacy file retained because its path is not trusted: %s\n' "$path" >&2
            fi
        fi
    done
    for path in /var/run/insonia-helper-v2-booted /var/run/insonia-helper-v2-status; do
        if [ -e "$path" ] || [ -L "$path" ]; then
            printf 'Obsolete runtime file retained; helper v3 does not use it: %s\n' "$path" >&2
        fi
    done
}

if [ "$UNINSTALL" -eq 1 ]; then
    secure_directory "$DAEMON_DIR" || fail 3 "Unsafe installation directory: $DAEMON_DIR"
    if [ -e "$HELPER_PARENT" ] || [ -L "$HELPER_PARENT" ]; then
        secure_directory "$HELPER_PARENT" || fail 3 "Unsafe installation directory: $HELPER_PARENT"
    fi
    if [ -e "$INSTALL_DIR" ] || [ -L "$INSTALL_DIR" ]; then
        secure_directory "$INSTALL_DIR" || fail 3 "Unsafe installation directory: $INSTALL_DIR"
    fi
    validate_files
    stop_service
    restore_sleep
    /bin/rm -f "$DAEMON_PLIST" "$HELPER_BIN" "$VERSION_FILE" "$BOOT_MARKER" "$STATUS_FILE"
    if [ -d "$INSTALL_DIR" ]; then /bin/rmdir "$INSTALL_DIR" 2>/dev/null || true; fi
    cleanup_legacy
    echo 'Helper removed; normal system sleep restored and verified.'
    exit 0
fi

ensure_directory "$DAEMON_DIR"
ensure_directory "$HELPER_PARENT"
ensure_directory "$INSTALL_DIR"
validate_files
cd "$(/usr/bin/dirname "$0")"
/usr/bin/sudo -u "$REAL_USER" /bin/mkdir -p "$STATE_DIR/runtime"
STAGING=$(/usr/bin/mktemp -d "$INSTALL_DIR/.install.XXXXXX")
trap '/bin/rm -rf "$STAGING"' EXIT
escape_sed() { printf '%s' "$1" | /usr/bin/sed 's/[\\&|]/\\&/g'; }
/usr/bin/sed \
    -e "s|__STATE_FILE__|$(escape_sed "$STATE_DIR/desired-state")|g" \
    -e "s|__HEARTBEAT_FILE__|$(escape_sed "$STATE_DIR/runtime/heartbeat")|g" \
    -e "s|__OWNER_UID__|$REAL_UID|g" \
    helper/insonia-helper.sh > "$STAGING/helper.sh"
/bin/cp "helper/$LABEL.plist" "$STAGING/helper.plist"
/usr/libexec/PlistBuddy -c "Set :WatchPaths:0 $STATE_DIR" "$STAGING/helper.plist"
/bin/bash -n "$STAGING/helper.sh"
/usr/bin/plutil -lint "$STAGING/helper.plist" >/dev/null
printf '3\n' > "$STAGING/version"
stop_service
restore_sleep
/usr/bin/install -o root -g wheel -m 755 "$STAGING/helper.sh" "$HELPER_BIN"
/usr/bin/install -o root -g wheel -m 644 "$STAGING/helper.plist" "$DAEMON_PLIST"
/bin/rm -f "$BOOT_MARKER" "$STATUS_FILE"
/bin/launchctl enable "system/$LABEL" || fail 4 'Unable to enable the helper.'
/bin/launchctl bootstrap system "$DAEMON_PLIST" || fail 4 'Unable to start the helper.'
for attempt in 1 2 3 4 5; do
    if [ -f "$STATUS_FILE" ]; then break; fi
    /bin/sleep 1
done
/bin/launchctl print "system/$LABEL" >/dev/null || fail 4 'The helper is not running.'
safe_file "$STATUS_FILE" && [ -f "$STATUS_FILE" ] || fail 6 'Watchdog did not acknowledge startup.'
read -r receipt_version receipt_time receipt_state receipt_token < "$STATUS_FILE" || fail 6 'Watchdog returned an invalid startup receipt.'
[ "$receipt_version" = 3 ] && [ "$receipt_state" = 0 ] && [ "$receipt_token" = '-' ] || fail 6 'Watchdog returned an invalid startup receipt.'
case "$receipt_time" in ''|*[!0-9]*) fail 6 'Watchdog returned an invalid startup timestamp.' ;; esac
now=$(/bin/date +%s)
[ "$receipt_time" -le "$now" ] && [ "$((now - receipt_time))" -le 30 ] || fail 6 'Watchdog returned an expired startup receipt.'
/usr/bin/install -o root -g wheel -m 644 "$STAGING/version" "$VERSION_FILE"
cleanup_legacy
echo 'Insonia helper v3 installed and running.'
