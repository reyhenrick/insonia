#!/bin/bash
# Root watchdog v3. Input is a request plus a recent user-owned heartbeat.
# Periodic reconciliation covers dropped WatchPaths events, crashes, and logout.
set -euo pipefail
umask 022
STATE_FILE='__STATE_FILE__'
HEARTBEAT_FILE='__HEARTBEAT_FILE__'
OWNER_UID='__OWNER_UID__'
BOOT_MARKER='/var/run/insonia-helper-v3-booted'
STATUS_FILE='/var/run/insonia-helper-v3-status'
ROOT_UID='0'
WORK_DIR=''
trap '[ -z "$WORK_DIR" ] || /bin/rm -rf "$WORK_DIR"' EXIT

prepare_staging() {
    if [ -z "$WORK_DIR" ]; then
        WORK_DIR=$(/usr/bin/mktemp -d "$(/usr/bin/dirname "$0")/.runtime.XXXXXX")
    fi
}

safe_runtime_file() {
    local path="$1" mode
    if [ -e "$path" ] || [ -L "$path" ]; then
        [ -f "$path" ] && [ ! -L "$path" ] || return 1
        [ "$(/usr/bin/stat -f '%u' "$path")" = "$ROOT_UID" ] || return 1
        [ "$(/usr/bin/stat -f '%l' "$path")" = 1 ] || return 1
        mode=$(/usr/bin/stat -f '%Lp' "$path") || return 1
        case "$mode" in ''|*[!0-7]*) return 1 ;; esac
        [ "$((8#$mode & 8#022))" -eq 0 ] || return 1
    fi
}
read_power() {
    /usr/bin/pmset -g | /usr/bin/awk '$1 == "SleepDisabled" { print $2 }'
}
if ! safe_runtime_file "$BOOT_MARKER" || ! safe_runtime_file "$STATUS_FILE"; then
    /usr/bin/pmset -a disablesleep 0
    exit 3
fi

want=0
token='-'
state=''
stamp=''
first_boot=0
read_state() {
    if [ -f "$STATE_FILE" ] && [ ! -L "$STATE_FILE" ]; then
        /usr/bin/head -c 16 "$STATE_FILE" 2>/dev/null || true
    fi
}
read_token() {
    if [ -f "$HEARTBEAT_FILE" ] && [ ! -L "$HEARTBEAT_FILE" ]; then
        /usr/bin/head -c 80 "$HEARTBEAT_FILE" 2>/dev/null || true
    fi
}
if [ ! -f "$BOOT_MARKER" ]; then
    first_boot=1
    /usr/bin/pmset -a disablesleep 0
    [ "$(read_power)" = 0 ] || exit 5
    prepare_staging
    BOOT_TMP="$WORK_DIR/boot"
    : > "$BOOT_TMP"
    /bin/chmod 644 "$BOOT_TMP"
    /bin/mv -fh "$BOOT_TMP" "$BOOT_MARKER"
else
    state=$(read_state)
    token=$(read_token)
    stamp=$(/usr/bin/stat -f '%m' "$HEARTBEAT_FILE" 2>/dev/null || true)
    raw_stamp="$stamp"
    if [ -f "$STATE_FILE" ] && [ ! -L "$STATE_FILE" ] &&
       [ -f "$HEARTBEAT_FILE" ] && [ ! -L "$HEARTBEAT_FILE" ]; then
        owner=$(/usr/bin/stat -f '%u' "$HEARTBEAT_FILE" 2>/dev/null || true)
        state_owner=$(/usr/bin/stat -f '%u' "$STATE_FILE" 2>/dev/null || true)
        boot=$(/usr/bin/stat -f '%m' "$BOOT_MARKER")
        case "$stamp" in ''|*[!0-9]*) stamp=0 ;; esac
        # Read the clock after the heartbeat snapshot, otherwise a legitimate
        # renewal across a second boundary looks like a timestamp from the future.
        now=$(/bin/date +%s)
        if [[ "$token" =~ ^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$ ]] &&
           [ "$state" = 1 ] && [ "$owner" = "$OWNER_UID" ] && [ "$state_owner" = "$OWNER_UID" ] &&
           [ "$stamp" -ge "$boot" ] && [ "$stamp" -le "$now" ] && [ "$((now - stamp))" -le 30 ]; then
            want=1
        fi
    fi
fi

# Never apply an observation belonging to a session which changed while this
# helper was scheduled. launchd serializes invocations; the next tick retries.
latest_state=$(read_state)
latest_token=$(read_token)
latest_stamp=$(/usr/bin/stat -f '%m' "$HEARTBEAT_FILE" 2>/dev/null || true)
if [ "$first_boot" = 0 ]; then
    if [ "$state" != "$latest_state" ] || { [ "$want" = 1 ] && [ "$token" != "$latest_token" ]; } ||
       { [ "$want" = 0 ] && [ "$state" = 1 ] && { [ "$raw_stamp" != "$latest_stamp" ] || [ "$token" != "$latest_token" ]; }; }; then
        exit 0
    fi
fi

current=$(read_power)
if [ "$current" != "$want" ]; then
    /usr/bin/pmset -a disablesleep "$want"
fi
[ "$(read_power)" = "$want" ] || exit 5
# Root-owned receipt proves the version is actually executing, not merely copied.
prepare_staging
STATUS_TMP="$WORK_DIR/status"
now=$(/bin/date +%s)
if [ "$want" = 0 ]; then token='-'; fi
printf '3 %s %s %s\n' "$now" "$want" "$token" > "$STATUS_TMP"
/bin/chmod 644 "$STATUS_TMP"
/bin/mv -fh "$STATUS_TMP" "$STATUS_FILE"
