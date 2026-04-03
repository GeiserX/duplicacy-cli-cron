#!/usr/bin/env sh
set -eu
set -o pipefail

# ───────── Backup Executor ───────────────────────────────────────────────────
# Sourced by daily cron wrapper scripts. Each wrapper sets:
#   REPO_DIR          – container path to back up (e.g. /local_shares/appdata)
#   STORAGENAME       – Duplicacy storage name   (e.g. appdata)
#   SNAPSHOTID        – snapshot identifier       (e.g. appdata)
#   THREADS_OVERRIDE  – (optional) per-repo thread count
#
# Environment (set in docker-compose):
#   HOST              – machine name for notifications
#   DUPLICACY_THREADS – default thread count
#   SHOUTRRR_URL      – Telegram notification URL
#
# Garage S3 replication factor 3 handles redundancy across all 3 nodes.
# No secondary Duplicacy backup needed — single backup, triple replication.
# ─────────────────────────────────────────────────────────────────────────────

MACHINENAME="${HOST:-$(hostname)}"
SHOUTRRR_URL="${SHOUTRRR_URL:-}"
THREADS="${THREADS_OVERRIDE:-${DUPLICACY_THREADS:-4}}"
MAX_RUNTIME_HOURS="${MAX_RUNTIME_HOURS:-71}"
LOCKFILE="/tmp/duplicacy-${SNAPSHOTID}.lock"

# ───────── helpers ───────────────────────────────────────────────────────────

notify() { [ -n "$SHOUTRRR_URL" ] && /usr/local/bin/shoutrrr send -u "$SHOUTRRR_URL" -m "$1" || true; }

cleanup() { rm -f "$LOCKFILE"; }

# ───────── lock check ────────────────────────────────────────────────────────
# Prevents duplicate runs. If a previous backup is still running:
#   - Within MAX_RUNTIME_HOURS: skip with notification
#   - Exceeds MAX_RUNTIME_HOURS: kill the stuck process and start fresh

if [ -f "$LOCKFILE" ]; then
  LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null || echo "")
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCKFILE" 2>/dev/null || echo "0") ))
    if [ "$LOCK_AGE" -ge $(( MAX_RUNTIME_HOURS * 3600 )) ]; then
      kill "$LOCK_PID" 2>/dev/null || true; sleep 5; kill -9 "$LOCK_PID" 2>/dev/null || true
      rm -f "$LOCKFILE"
      notify "⚠️ *${MACHINENAME}* — _${SNAPSHOTID}_
Killed after ${MAX_RUNTIME_HOURS}h timeout (PID: $LOCK_PID)"
    else
      notify "⏭️ *${MACHINENAME}* — _${SNAPSHOTID}_
Skipped — previous run still in progress (PID: $LOCK_PID)"; exit 0
    fi
  else rm -f "$LOCKFILE"; fi
fi

echo $$ > "$LOCKFILE"; trap cleanup EXIT INT TERM

# ───────── backup ────────────────────────────────────────────────────────────
cd "$REPO_DIR"

echo "--- Backup -> Primary ($STORAGENAME) ---"
B1=0; duplicacy backup -storage $STORAGENAME -stats -hash -threads $THREADS 2>&1 || B1=$?

B1M=$( [ $B1 -eq 0 ] && echo "✅" || echo "❌" )

# ───────── prune ─────────────────────────────────────────────────────────────
# Skip on Saturdays — the weekly exhaustive prune handles it
if [ "$(date +%u)" != "6" ]; then
  echo "--- Prune Primary ---"
  duplicacy prune -storage $STORAGENAME -keep 0:180 -keep 30:90 -keep 7:30 -keep 1:7 2>&1 || true
  PM="🔄 Pruned"
else PM="⏭️ Prune skipped (Saturday)"; fi

# ───────── notification ──────────────────────────────────────────────────────
ICON=$( [ $B1 -eq 0 ] && echo "🟢" || echo "🔴" )
MSG="${ICON} *${MACHINENAME}* — _${SNAPSHOTID}_
${B1M} ${PM}"
echo "$MSG"; notify "$MSG"
