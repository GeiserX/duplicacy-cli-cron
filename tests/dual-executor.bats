#!/usr/bin/env bats

# Tests for dual-executor.sh locking, notification, and variable logic

setup() {
    export TEST_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# --- Notify helper tests ---

@test "notify does nothing when SHOUTRRR_URL is empty" {
    notify() { [ -n "$SHOUTRRR_URL" ] && echo "sent" || true; }
    export SHOUTRRR_URL=""
    result=$(notify "test message")
    [ -z "$result" ]
}

@test "notify would send when SHOUTRRR_URL is set" {
    # We simulate the check without actually calling shoutrrr
    export SHOUTRRR_URL="telegram://..."
    [ -n "$SHOUTRRR_URL" ]
}

# --- Lock file tests ---

@test "lockfile is created with PID" {
    LOCKFILE="$TEST_DIR/test.lock"
    echo $$ > "$LOCKFILE"
    [ -f "$LOCKFILE" ]
    pid=$(cat "$LOCKFILE")
    [ "$pid" = "$$" ]
}

@test "stale lockfile with dead PID is detected" {
    LOCKFILE="$TEST_DIR/test.lock"
    echo "99999999" > "$LOCKFILE"
    # PID 99999999 should not exist
    if kill -0 99999999 2>/dev/null; then
        skip "PID 99999999 somehow exists"
    fi
    # The lock should be considered stale
    LOCK_PID=$(cat "$LOCKFILE")
    ! kill -0 "$LOCK_PID" 2>/dev/null
}

@test "cleanup removes lockfile" {
    LOCKFILE="$TEST_DIR/test.lock"
    echo $$ > "$LOCKFILE"
    cleanup() { rm -f "$LOCKFILE"; }
    cleanup
    [ ! -f "$LOCKFILE" ]
}

# --- Variable defaults tests ---

@test "HOST defaults to hostname" {
    unset HOST
    MACHINENAME="${HOST:-$(hostname)}"
    [ -n "$MACHINENAME" ]
}

@test "HOST override works" {
    export HOST="TestMachine"
    MACHINENAME="${HOST:-$(hostname)}"
    [ "$MACHINENAME" = "TestMachine" ]
    unset HOST
}

@test "THREADS defaults to DUPLICACY_THREADS" {
    unset THREADS_OVERRIDE
    export DUPLICACY_THREADS=8
    THREADS="${THREADS_OVERRIDE:-${DUPLICACY_THREADS:-4}}"
    [ "$THREADS" = "8" ]
    unset DUPLICACY_THREADS
}

@test "THREADS_OVERRIDE takes precedence over DUPLICACY_THREADS" {
    export THREADS_OVERRIDE=16
    export DUPLICACY_THREADS=8
    THREADS="${THREADS_OVERRIDE:-${DUPLICACY_THREADS:-4}}"
    [ "$THREADS" = "16" ]
    unset THREADS_OVERRIDE DUPLICACY_THREADS
}

@test "THREADS falls back to 4 when nothing set" {
    unset THREADS_OVERRIDE DUPLICACY_THREADS
    THREADS="${THREADS_OVERRIDE:-${DUPLICACY_THREADS:-4}}"
    [ "$THREADS" = "4" ]
}

@test "MAX_RUNTIME_HOURS defaults to 71" {
    unset MAX_RUNTIME_HOURS
    MAX="${MAX_RUNTIME_HOURS:-71}"
    [ "$MAX" = "71" ]
}

@test "MAX_RUNTIME_HOURS override works" {
    export MAX_RUNTIME_HOURS=24
    MAX="${MAX_RUNTIME_HOURS:-71}"
    [ "$MAX" = "24" ]
    unset MAX_RUNTIME_HOURS
}

# --- Prune skip on Saturday ---

@test "prune skips on Saturday (day 6)" {
    # Simulate Saturday check
    day_of_week=6
    if [ "$day_of_week" = "6" ]; then
        SKIP=true
    else
        SKIP=false
    fi
    [ "$SKIP" = "true" ]
}

@test "prune runs on non-Saturday" {
    day_of_week=3
    if [ "$day_of_week" = "6" ]; then
        SKIP=true
    else
        SKIP=false
    fi
    [ "$SKIP" = "false" ]
}

# --- Notification message format ---

@test "success icon is green circle" {
    B1=0
    ICON=$( [ $B1 -eq 0 ] && echo "green" || echo "red" )
    [ "$ICON" = "green" ]
}

@test "failure icon is red circle" {
    B1=1
    ICON=$( [ $B1 -eq 0 ] && echo "green" || echo "red" )
    [ "$ICON" = "red" ]
}

# --- Backup retry defaults ---

@test "BACKUP_ATTEMPTS defaults to 2" {
    unset BACKUP_ATTEMPTS
    A="${BACKUP_ATTEMPTS:-2}"
    [ "$A" = "2" ]
}

@test "BACKUP_ATTEMPTS override works" {
    export BACKUP_ATTEMPTS=5
    A="${BACKUP_ATTEMPTS:-2}"
    [ "$A" = "5" ]
    unset BACKUP_ATTEMPTS
}

@test "BACKUP_RETRY_DELAY defaults to 120" {
    unset BACKUP_RETRY_DELAY
    D="${BACKUP_RETRY_DELAY:-120}"
    [ "$D" = "120" ]
}

# --- Backup retry loop behaviour ---
# Mirrors the loop in dual-executor.sh. Echoes: "<exit> <attempts> <calls>"
retry_sim() {
    fail_times="$1"
    attempts="${BACKUP_ATTEMPTS:-2}"
    calls=0
    ATTEMPT=1
    while : ; do
        calls=$((calls + 1))
        if [ "$calls" -le "$fail_times" ]; then B1=3; else B1=0; fi
        if [ "$B1" -eq 0 ]; then break; fi
        if [ "$ATTEMPT" -ge "$attempts" ]; then break; fi
        ATTEMPT=$((ATTEMPT + 1))
    done
    echo "$B1 $ATTEMPT $calls"
}

@test "retry loop succeeds on first attempt without retrying" {
    unset BACKUP_ATTEMPTS
    result=$(retry_sim 0)
    [ "$result" = "0 1 1" ]
}

@test "retry loop recovers when the first attempt fails" {
    unset BACKUP_ATTEMPTS
    result=$(retry_sim 1)
    [ "$result" = "0 2 2" ]
}

@test "retry loop gives up after BACKUP_ATTEMPTS failures" {
    unset BACKUP_ATTEMPTS
    result=$(retry_sim 99)
    [ "$result" = "3 2 2" ]
}

@test "retry loop honours a raised BACKUP_ATTEMPTS" {
    export BACKUP_ATTEMPTS=4
    result=$(retry_sim 3)
    [ "$result" = "0 4 4" ]
    unset BACKUP_ATTEMPTS
}

# --- Weekly -hash selection ---
# Mirrors the HASHFLAG logic in dual-executor.sh.
hash_sim() {
    HASH_DAY="$1"
    today="$2"
    HASHFLAG=""
    if [ "$HASH_DAY" = "*" ] || { [ "$HASH_DAY" != "0" ] && [ "$HASH_DAY" = "$today" ]; }; then
        HASHFLAG="-hash"
    fi
    echo "$HASHFLAG"
}

@test "HASH_DAY defaults to 7 (Sunday)" {
    unset HASH_DAY
    H="${HASH_DAY:-7}"
    [ "$H" = "7" ]
}

@test "hash flag is set on the configured day" {
    [ "$(hash_sim 7 7)" = "-hash" ]
}

@test "hash flag is empty on other days" {
    [ "$(hash_sim 7 3)" = "" ]
}

@test "HASH_DAY=* forces hash on every run" {
    [ "$(hash_sim '*' 3)" = "-hash" ]
}

@test "HASH_DAY=0 disables hash entirely" {
    [ "$(hash_sim 0 3)" = "" ]
    [ "$(hash_sim 0 7)" = "" ]
}
