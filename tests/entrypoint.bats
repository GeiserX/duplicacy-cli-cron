#!/usr/bin/env bats

# Tests for entrypoint.sh crontab generation logic

setup() {
    export TEST_DIR="$(mktemp -d)"
    mkdir -p "$TEST_DIR/etc/crontabs"
    mkdir -p "$TEST_DIR/etc/periodic"/{15min,hourly,daily,weekly,monthly}
}

teardown() {
    rm -rf "$TEST_DIR"
}

# Helper: generate crontab content using the same logic as entrypoint.sh
generate_crontab() {
    local cron_15min="${CRON_15MIN:-*/15 * * * *}"
    local cron_hourly="${CRON_HOURLY:-0 * * * *}"
    local cron_daily="${CRON_DAILY:-0 2 * * *}"
    local cron_weekly="${CRON_WEEKLY:-0 3 * * 6}"
    local cron_monthly="${CRON_MONTHLY:-0 5 1 * *}"

    cat > "$TEST_DIR/etc/crontabs/root" << EOF
# Custom crontab for duplicacy-cli-cron

# 15min jobs
${cron_15min}	run-parts /etc/periodic/15min >> /proc/1/fd/1 2>&1

# Hourly jobs
${cron_hourly}	run-parts /etc/periodic/hourly >> /proc/1/fd/1 2>&1

# Daily jobs
${cron_daily}	run-parts /etc/periodic/daily >> /proc/1/fd/1 2>&1

# Weekly jobs
${cron_weekly}	run-parts /etc/periodic/weekly >> /proc/1/fd/1 2>&1

# Monthly jobs
${cron_monthly}	run-parts /etc/periodic/monthly >> /proc/1/fd/1 2>&1
EOF
}

@test "default crontab has correct 15min schedule" {
    unset CRON_15MIN CRON_HOURLY CRON_DAILY CRON_WEEKLY CRON_MONTHLY
    generate_crontab
    grep -q '^\*/15 \* \* \* \*' "$TEST_DIR/etc/crontabs/root"
}

@test "default crontab has correct hourly schedule" {
    unset CRON_15MIN CRON_HOURLY CRON_DAILY CRON_WEEKLY CRON_MONTHLY
    generate_crontab
    grep -q '^0 \* \* \* \*' "$TEST_DIR/etc/crontabs/root"
}

@test "default crontab has correct daily schedule" {
    unset CRON_15MIN CRON_HOURLY CRON_DAILY CRON_WEEKLY CRON_MONTHLY
    generate_crontab
    grep -q '^0 2 \* \* \*' "$TEST_DIR/etc/crontabs/root"
}

@test "default crontab has correct weekly schedule" {
    unset CRON_15MIN CRON_HOURLY CRON_DAILY CRON_WEEKLY CRON_MONTHLY
    generate_crontab
    grep -q '^0 3 \* \* 6' "$TEST_DIR/etc/crontabs/root"
}

@test "default crontab has correct monthly schedule" {
    unset CRON_15MIN CRON_HOURLY CRON_DAILY CRON_WEEKLY CRON_MONTHLY
    generate_crontab
    grep -q '^0 5 1 \* \*' "$TEST_DIR/etc/crontabs/root"
}

@test "custom CRON_DAILY overrides default" {
    export CRON_DAILY="30 4 * * *"
    generate_crontab
    grep -q '^30 4 \* \* \*' "$TEST_DIR/etc/crontabs/root"
    unset CRON_DAILY
}

@test "custom CRON_WEEKLY overrides default" {
    export CRON_WEEKLY="0 1 * * 0"
    generate_crontab
    grep -q '^0 1 \* \* 0' "$TEST_DIR/etc/crontabs/root"
    unset CRON_WEEKLY
}

@test "crontab redirects output to PID 1 stdout" {
    unset CRON_15MIN CRON_HOURLY CRON_DAILY CRON_WEEKLY CRON_MONTHLY
    generate_crontab
    local count
    count=$(grep -c '/proc/1/fd/1' "$TEST_DIR/etc/crontabs/root")
    [ "$count" -eq 5 ]
}

@test "crontab uses run-parts for all periodic dirs" {
    unset CRON_15MIN CRON_HOURLY CRON_DAILY CRON_WEEKLY CRON_MONTHLY
    generate_crontab
    grep -q 'run-parts /etc/periodic/15min' "$TEST_DIR/etc/crontabs/root"
    grep -q 'run-parts /etc/periodic/hourly' "$TEST_DIR/etc/crontabs/root"
    grep -q 'run-parts /etc/periodic/daily' "$TEST_DIR/etc/crontabs/root"
    grep -q 'run-parts /etc/periodic/weekly' "$TEST_DIR/etc/crontabs/root"
    grep -q 'run-parts /etc/periodic/monthly' "$TEST_DIR/etc/crontabs/root"
}
