#!/usr/bin/env sh
set -eu
set -o pipefail

# ───────── constants ────────────────────────────────────────────────
REPO_DIR="/local_shares/..."
STORAGENAME="..."
SNAPSHOTID="..."

MACHINENAME="${HOST:-$(hostname)}"
SHOUTRRR_URL="${SHOUTRRR_URL:-}"

# Thread count - reduced from 8 to 4 to prevent resource contention
THREADS="${DUPLICACY_THREADS:-4}"

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
    echo "⏭️ Backup for ${SNAPSHOTID} already running (PID: $LOCK_PID), skipping..."
    MSG="⏭️ *${MACHINENAME}* — _${SNAPSHOTID}_
---------------------------------------------
Backup skipped — previous run still in progress (PID: $LOCK_PID)"
    notify "$MSG"
    exit 0
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