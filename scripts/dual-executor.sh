#!/usr/bin/env bash
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
#   BACKUP_ATTEMPTS   – backup tries before giving up (default 2)
#   BACKUP_RETRY_DELAY– seconds to wait between tries (default 120)
#   HASH_DAY          – day-of-week (1-7) to run with -hash; "*" = every run,
#                       "0" = never (default 7 = Sunday)
#
# Garage S3 replication factor 2 handles redundancy across cluster nodes.
# No secondary Duplicacy backup needed — single backup, two-copy replication.
# ─────────────────────────────────────────────────────────────────────────────

MACHINENAME="${HOST:-$(hostname)}"
SHOUTRRR_URL="${SHOUTRRR_URL:-}"
THREADS="${THREADS_OVERRIDE:-${DUPLICACY_THREADS:-4}}"
MAX_RUNTIME_HOURS="${MAX_RUNTIME_HOURS:-71}"
BACKUP_ATTEMPTS="${BACKUP_ATTEMPTS:-2}"
BACKUP_RETRY_DELAY="${BACKUP_RETRY_DELAY:-120}"
HASH_DAY="${HASH_DAY:-7}"

# Reject invalid settings up front: a non-numeric BACKUP_ATTEMPTS would make the
# retry loop's comparison fail every time and spin until killed externally.
case "$BACKUP_ATTEMPTS" in
  ''|*[!0-9]*) echo "BACKUP_ATTEMPTS must be a positive integer" >&2; exit 2 ;;
esac
[ "$BACKUP_ATTEMPTS" -ge 1 ] || { echo "BACKUP_ATTEMPTS must be at least 1" >&2; exit 2; }

case "$BACKUP_RETRY_DELAY" in
  ''|*[!0-9]*) echo "BACKUP_RETRY_DELAY must be a non-negative integer" >&2; exit 2 ;;
esac

case "$HASH_DAY" in
  0|1|2|3|4|5|6|7|\*) ;;
  *) echo "HASH_DAY must be 0, 1-7, or *" >&2; exit 2 ;;
esac
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
# Explicit, machine-readable label contract for duplicacy-exporter (parsed by
# RE_META_LINE). Makes snapshot_id/machine deterministic instead of relying on
# section-header/notification heuristics. storage_target is still derived from
# the "Storage set to" line the duplicacy backup emits below.
echo "DUPLICACY_META snapshot_id=$SNAPSHOTID machine=$MACHINENAME"
# -hash makes Duplicacy re-read and re-hash EVERY file instead of using
# size+mtime to detect changes. It is thorough but expensive: it turns each run
# into a full read of the repository, which lengthens runtimes and widens the
# window in which a transient storage error can abort the backup. Run it weekly
# (Sunday by default) and use normal change detection the rest of the week.
HASHFLAG=""
if [ "$HASH_DAY" = "*" ] || { [ "$HASH_DAY" != "0" ] && [ "$HASH_DAY" = "$(date +%u)" ]; }; then
  HASHFLAG="-hash"
fi

# A transient storage error (e.g. an S3 chunk upload reset mid-PUT) leaves an
# incomplete snapshot. Duplicacy resumes from it, so a second attempt continues
# where the first stopped rather than restarting from zero.
B1=0
ATTEMPT=1
while : ; do
  B1=0
  duplicacy backup -storage $STORAGENAME -stats $HASHFLAG -threads $THREADS 2>&1 || B1=$?
  if [ "$B1" -eq 0 ]; then break; fi
  if [ "$ATTEMPT" -ge "$BACKUP_ATTEMPTS" ]; then break; fi
  echo "Backup attempt ${ATTEMPT}/${BACKUP_ATTEMPTS} failed (exit ${B1}); retrying in ${BACKUP_RETRY_DELAY}s"
  ATTEMPT=$((ATTEMPT + 1))
  sleep "$BACKUP_RETRY_DELAY"
done
if [ "$B1" -eq 0 ] && [ "$ATTEMPT" -gt 1 ]; then
  echo "Backup succeeded on attempt ${ATTEMPT}/${BACKUP_ATTEMPTS}"
elif [ "$B1" -ne 0 ]; then
  echo "Backup failed after ${ATTEMPT} attempt(s) (exit ${B1})"
fi

B1M=$( [ $B1 -eq 0 ] && echo "✅" || echo "❌" )

# ───────── prune ─────────────────────────────────────────────────────────────
# Skip on Saturdays — the weekly exhaustive prune handles it
# Only prune if backup succeeded to avoid deleting snapshots after a failed backup
if [ "$B1" -ne 0 ]; then
  PM="⏭️ Prune skipped (backup failed)"
elif [ "$(date +%u)" = "6" ]; then
  PM="⏭️ Prune skipped (Saturday)"
else
  SNAP_COUNT=$(duplicacy list -storage "$STORAGENAME" 2>&1 | grep -c "^Snapshot" || true)
  if [ "$SNAP_COUNT" -lt 2 ]; then
    PM="⏭️ Prune skipped (only ${SNAP_COUNT} snapshot(s))"
  else
    echo "--- Prune Primary ---"
    duplicacy prune -storage "$STORAGENAME" -keep 0:180 -keep 30:90 -keep 7:30 -keep 1:7 2>&1 || true
    PM="🔄 Pruned"
  fi
fi

# ───────── notification ──────────────────────────────────────────────────────
ICON=$( [ $B1 -eq 0 ] && echo "🟢" || echo "🔴" )
MSG="${ICON} *${MACHINENAME}* — _${SNAPSHOTID}_
${B1M} ${PM}"
echo "$MSG"; notify "$MSG"
