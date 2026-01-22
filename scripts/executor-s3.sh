#!/usr/bin/env sh
set -eu
set -o pipefail

# ───────── constants ────────────────────────────────────────────────
REPO_DIR="/local_shares/..."
STORAGENAME="..."
SNAPSHOTID="..."

MACHINENAME="${HOST:-$(hostname)}"
SHOUTRRR_URL="${SHOUTRRR_URL:-}"

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

# ───────── run backup ───────────────────────────────────────────────
cd "$REPO_DIR"

run_and_capture "Backup Output" "duplicacy backup -storage $STORAGENAME -stats -hash"
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
MSG=$(cat <<EOF
🖥️ *${MACHINENAME}* — _${SNAPSHOTID}_
---------------------------------------------
${BACKUP_MSG}
${PRUNE_MSG}
EOF
)

echo "--- Notification Sent ---"
printf "%s\n" "$MSG"
notify "$MSG"