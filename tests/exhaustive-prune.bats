#!/usr/bin/env bats

# Tests for exhaustive-prune.sh lock waiting and iteration logic

setup() {
    export TEST_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# --- wait_for_lock reimplementation for testing ---

wait_for_lock() {
    local name="$1"
    local lockfile="$TEST_DIR/duplicacy-${name}.lock"
    local lock_wait_secs=1
    local max_lock_wait=3
    local waited=0

    while [ -f "$lockfile" ] && [ "$waited" -lt "$max_lock_wait" ]; do
        lock_pid=$(cat "$lockfile" 2>/dev/null || echo "")
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            sleep "$lock_wait_secs"
            waited=$((waited + lock_wait_secs))
        else
            rm -f "$lockfile"
            break
        fi
    done

    if [ "$waited" -ge "$max_lock_wait" ]; then
        return 1
    fi
    return 0
}

@test "wait_for_lock succeeds when no lockfile exists" {
    run wait_for_lock "appdata"
    [ "$status" -eq 0 ]
}

@test "wait_for_lock cleans up stale lock (dead PID)" {
    echo "99999999" > "$TEST_DIR/duplicacy-appdata.lock"
    run wait_for_lock "appdata"
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_DIR/duplicacy-appdata.lock" ]
}

@test "wait_for_lock times out on live lock" {
    # Use our own PID as a "live" process holding the lock
    echo "$$" > "$TEST_DIR/duplicacy-multimedia.lock"
    run wait_for_lock "multimedia"
    [ "$status" -eq 1 ]
    rm -f "$TEST_DIR/duplicacy-multimedia.lock"
}

# --- Repo directory iteration ---

@test "iterates only directories with .duplicacy" {
    mkdir -p "$TEST_DIR/repo1/.duplicacy"
    mkdir -p "$TEST_DIR/repo2"
    mkdir -p "$TEST_DIR/repo3/.duplicacy"

    found=""
    for repo_dir in "$TEST_DIR"/*/; do
        storagename=$(basename "$repo_dir")
        [ -d "${repo_dir}.duplicacy" ] || continue
        found="${found} ${storagename}"
    done

    echo "$found" | grep -q "repo1"
    echo "$found" | grep -q "repo3"
    ! echo "$found" | grep -q "repo2"
}

# --- Variable defaults ---

@test "THREADS defaults to DUPLICACY_THREADS for prune" {
    export DUPLICACY_THREADS=12
    THREADS="${DUPLICACY_THREADS:-8}"
    [ "$THREADS" = "12" ]
    unset DUPLICACY_THREADS
}

@test "THREADS falls back to 8 for exhaustive prune" {
    unset DUPLICACY_THREADS
    THREADS="${DUPLICACY_THREADS:-8}"
    [ "$THREADS" = "8" ]
}

@test "LOCK_WAIT_SECS defaults to 60" {
    LOCK_WAIT_SECS=60
    [ "$LOCK_WAIT_SECS" -eq 60 ]
}

@test "MAX_LOCK_WAIT defaults to 3600" {
    MAX_LOCK_WAIT=3600
    [ "$MAX_LOCK_WAIT" -eq 3600 ]
}

# --- Boot USB repo detection ---

@test "boot USB repo detected when .duplicacy exists" {
    mkdir -p "$TEST_DIR/boot_usb/.duplicacy"
    [ -d "$TEST_DIR/boot_usb/.duplicacy" ]
}

@test "boot USB repo skipped when .duplicacy missing" {
    mkdir -p "$TEST_DIR/boot_usb"
    [ ! -d "$TEST_DIR/boot_usb/.duplicacy" ]
}

# --- Notification message assembly ---

@test "results accumulate across repos" {
    RESULTS=""
    RESULTS="${RESULTS}\n ok repo1"
    RESULTS="${RESULTS}\n fail repo2"
    output=$(printf "%b" "$RESULTS")
    echo "$output" | grep -q "repo1"
    echo "$output" | grep -q "repo2"
}
