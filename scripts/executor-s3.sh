#!/usr/bin/env sh
set -eu
set -o pipefail

# ───────── constants ────────────────────────────────────────────────
REPO_DIR="/local_shares/..."
STORAGENAME="..."
SNAPSHOTID="..."

MACHINENAME="${HOST:-$(hostname)}"
SHOUTRRR_URL="${SHOUTRRR_URL:-}"

# Thread count for parallel uploads
THREADS="${DUPLICACY_THREADS:-8}"

# Maximum runtime in hours before killing a stuck backup
MAX_RUNTIME_HOURS="${MAX_RUNTIME_HOURS:-71}"

# Lock file to prevent duplicate runs
LOCKFILE="/tmp/duplicacy-${SNAPSHOTID}.lock"

# ───────── helper ───────────────────────────────────────────────────
notify() {
  [ -n "$SHOUTRRR_URL" ] && /usr/local/bin/shoutrrr send -u "$SHOUTRRR_URL" -m "$1"
}

run_and_capture() {               # $1 = log-header, $2 = command…
  header="$1"; shift
  echo "--- ${header} ---"
  tmp=$(mktemp)
  # shellcheck disable=SC2086
  /bin/sh -c "$*" 2>&1 | tee "$tmp"
  code=$?
  out=$(cat "$tmp"); rm "$tmp"
  echo
  return $code
}

cleanup() {
  rm -f "$LOCKFILE"
}

# ───────── lock check ───────────────────────────────────────────────
# Check if another instance is already running
if [ -f "$LOCKFILE" ]; then
  LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null || echo "")
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    # Check how long the lock file has existed (proxy for runtime)
    LOCK_AGE_SEC=$(( $(date +%s) - $(stat -c %Y "$LOCKFILE" 2>/dev/null || stat -f %m "$LOCKFILE" 2>/dev/null || echo "0") ))
    MAX_RUNTIME_SEC=$(( MAX_RUNTIME_HOURS * 3600 ))

    if [ "$LOCK_AGE_SEC" -ge "$MAX_RUNTIME_SEC" ]; then
      echo "⚠️ Backup for ${SNAPSHOTID} (PID: $LOCK_PID) exceeded ${MAX_RUNTIME_HOURS}h runtime (${LOCK_AGE_SEC}s). Killing..."
      # Kill the stuck duplicacy process tree
      kill "$LOCK_PID" 2>/dev/null || true
      sleep 5
      kill -9 "$LOCK_PID" 2>/dev/null || true
      # Also kill any orphaned duplicacy backup processes for this storage
      pkill -f "duplicacy backup -storage $STORAGENAME" 2>/dev/null || true
      rm -f "$LOCKFILE"
      MSG="⚠️ *${MACHINENAME}* — _${SNAPSHOTID}_
---------------------------------------------
Previous backup killed after ${MAX_RUNTIME_HOURS}h timeout (PID: $LOCK_PID)
Starting fresh backup..."
      notify "$MSG"
    else
      echo "⏭️ Backup for ${SNAPSHOTID} already running (PID: $LOCK_PID, age: ${LOCK_AGE_SEC}s), skipping..."
      MSG="⏭️ *${MACHINENAME}* — _${SNAPSHOTID}_
---------------------------------------------
Backup skipped — previous run still in progress (PID: $LOCK_PID)"
      notify "$MSG"
      exit 0
    fi
  else
    echo "🧹 Stale lock file found, removing..."
    rm -f "$LOCKFILE"
  fi
fi

# Create lock file with current PID
echo $$ > "$LOCKFILE"
trap cleanup EXIT INT TERM

# ───────── run backup ───────────────────────────────────────────────
cd "$REPO_DIR"

run_and_capture "Backup Output" "duplicacy backup -storage $STORAGENAME -stats -hash -threads $THREADS"
BACKUP_EXIT=$?; BACKUP_MSG=$( [ $BACKUP_EXIT -eq 0 ] && \
  echo "✅ Backup completed successfully" || \
  echo "🚨 Backup failed — check logs" )

# ───────── prune old revisions ──────────────────────────────────────
run_and_capture "Prune Output" \
  "duplicacy prune -storage $STORAGENAME -keep 0:360 -keep 30:180 -keep 7:30 -keep 1:7"
PRUNE_EXIT=$?; PRUNE_MSG=$( [ $PRUNE_EXIT -eq 0 ] && \
  echo "✅ Prune completed successfully" || \
  echo "🚨 Prune failed — check logs" )

# ───────── notification ────────────────────────────────────────────
MSG="🟢 *${MACHINENAME}* — _${SNAPSHOTID}_
---------------------------------------------
${BACKUP_MSG}
${PRUNE_MSG}"

echo "--- Notification Sent ---"
printf "%s\n" "$MSG"
notify "$MSG"
