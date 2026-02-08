#!/usr/bin/env sh
set -eu
set -o pipefail

# ───────── Weekly Exhaustive Prune ─────────────────────────────────────────
# Scans ALL chunks and removes orphans not referenced by any snapshot.
# Regular daily prune only marks chunks as fossils; exhaustive prune
# actually reclaims storage space.
#
# Place this script in /etc/periodic/weekly/ inside the container.
# The daily executor-s3.sh skips normal prune on Saturdays (the default
# CRON_WEEKLY day), so there is no overlap between the two.
# ───────────────────────────────────────────────────────────────────────────

MACHINENAME="${HOST:-$(hostname)}"
SHOUTRRR_URL="${SHOUTRRR_URL:-}"
THREADS="${DUPLICACY_THREADS:-8}"

# ───────── helpers ─────────────────────────────────────────────────────────
notify() {
  [ -n "$SHOUTRRR_URL" ] && /usr/local/bin/shoutrrr send -u "$SHOUTRRR_URL" -m "$1"
}

# ───────── auto-discover repos under /local_shares ─────────────────────────
RESULTS=""
for REPO_DIR in /local_shares/*/; do
  STORAGENAME=$(basename "$REPO_DIR")
  # Skip directories that are not Duplicacy repos
  [ -d "${REPO_DIR}.duplicacy" ] || continue

  echo "=== Exhaustive prune: ${STORAGENAME} ==="
  cd "$REPO_DIR"
  if duplicacy prune -storage "$STORAGENAME" -exhaustive -threads "$THREADS" 2>&1; then
    RESULTS="${RESULTS}\n✅ ${STORAGENAME}: exhaustive prune OK"
  else
    RESULTS="${RESULTS}\n🚨 ${STORAGENAME}: exhaustive prune FAILED"
  fi
done

# ───────── extra repos outside /local_shares ───────────────────────────────
# Unraid boot USB config
if [ -d "/boot_usb/.duplicacy" ]; then
  echo "=== Exhaustive prune: boot ==="
  cd /boot_usb
  if duplicacy prune -storage boot -exhaustive -threads "$THREADS" 2>&1; then
    RESULTS="${RESULTS}\n✅ boot: exhaustive prune OK"
  else
    RESULTS="${RESULTS}\n🚨 boot: exhaustive prune FAILED"
  fi
fi

# Add any additional repo paths here. Each entry needs:
#   EXTRA_DIR  = container path to the repo root
#   EXTRA_NAME = the Duplicacy storage name used in preferences

# ───────── notification ───────────────────────────────────────────────────
MSG="🔧 *${MACHINENAME}* — _Weekly Exhaustive Prune_
---------------------------------------------
$(printf "%b" "$RESULTS")"
echo "$MSG"
notify "$MSG"
