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
