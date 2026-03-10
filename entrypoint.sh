#!/bin/sh
set -e

# ─────────────────────────────────────────────────────────────────────────────
# Custom crontab generator for staggered backup schedules
# ─────────────────────────────────────────────────────────────────────────────

# Default cron schedules (can be overridden via environment variables)
# Format: "minute hour day month weekday"
CRON_15MIN="${CRON_15MIN:-*/15 * * * *}"
CRON_HOURLY="${CRON_HOURLY:-0 * * * *}"
CRON_DAILY="${CRON_DAILY:-0 2 * * *}"
CRON_WEEKLY="${CRON_WEEKLY:-0 3 * * 6}"
CRON_MONTHLY="${CRON_MONTHLY:-0 5 1 * *}"

# Create custom crontab with staggered schedules
# Redirect output to PID 1 stdout so Docker captures it in container logs
# (busybox crond captures output internally and tries sendmail; without this
# redirect, cron job output never reaches `docker logs`)
cat > /etc/crontabs/root << EOF
# Custom crontab for duplicacy-cli-cron
# Schedules can be configured via environment variables

# 15min jobs
${CRON_15MIN}	run-parts /etc/periodic/15min >> /proc/1/fd/1 2>&1

# Hourly jobs
${CRON_HOURLY}	run-parts /etc/periodic/hourly >> /proc/1/fd/1 2>&1

# Daily jobs (staggered via CRON_DAILY env var)
${CRON_DAILY}	run-parts /etc/periodic/daily >> /proc/1/fd/1 2>&1

# Weekly jobs
${CRON_WEEKLY}	run-parts /etc/periodic/weekly >> /proc/1/fd/1 2>&1

# Monthly jobs
${CRON_MONTHLY}	run-parts /etc/periodic/monthly >> /proc/1/fd/1 2>&1
EOF

echo "Crontab configured with schedule:"
echo "  Daily jobs: ${CRON_DAILY}"
cat /etc/crontabs/root

exec crond -f -L /dev/stdout