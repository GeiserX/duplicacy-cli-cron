#!/usr/bin/env sh
set -eu
set -o pipefail

# Monthly integrity check: verify all backup chunks exist and are valid.
# Also triggers a Garage data scrub on BOTH target storage nodes.
#
# This script should be placed in /etc/periodic/monthly/ inside the container.
# It iterates over all repos (auto-detected from /local_shares/ or explicit list)
# and runs `duplicacy check` against both primary and secondary storages.
#
# Environment variables:
#   HOST               - Machine name for notifications (default: hostname)
#   SHOUTRRR_URL       - Shoutrrr notification URL (optional)
#   DUPLICACY_THREADS  - Number of threads for check operations (default: 4)
#   ENDPOINT_1         - Primary Garage S3 endpoint (host:port) for scrub trigger
#   ENDPOINT_2         - Secondary Garage S3 endpoint (host:port) for scrub trigger
#   GARAGE_ADMIN_TOKEN - Garage admin API token (default: my_admin_tokensuper)

MACHINENAME="${HOST:-$(hostname)}"
SHOUTRRR_URL="${SHOUTRRR_URL:-}"
THREADS="${DUPLICACY_THREADS:-4}"
GARAGE_ADMIN_TOKEN="${GARAGE_ADMIN_TOKEN:-my_admin_tokensuper}"

notify() { [ -n "$SHOUTRRR_URL" ] && /usr/local/bin/shoutrrr send -u "$SHOUTRRR_URL" -m "$1" || true; }

RESULTS=""

# --- Duplicacy chunk verification ---

# Auto-detect repos under /local_shares (Unraid layout)
for REPO_DIR in /local_shares/*/; do
  STORAGENAME=$(basename "$REPO_DIR")
  [ -d "${REPO_DIR}.duplicacy" ] || continue
  cd "$REPO_DIR"
  for SUFFIX in "" "C"; do
    STORE="${STORAGENAME}${SUFFIX}"
    echo "=== Check: ${STORE} ==="
    if duplicacy check -storage "$STORE" -threads "$THREADS" 2>&1; then
      RESULTS="${RESULTS}\n✅ ${STORE}: check OK"
    else
      RESULTS="${RESULTS}\n🚨 ${STORE}: check FAILED"
    fi
  done
done

# Check boot USB repo if it exists
if [ -d "/boot_usb/.duplicacy" ]; then
  cd /boot_usb
  for SUFFIX in "" "C"; do
    STORE="boot${SUFFIX}"
    echo "=== Check: ${STORE} ==="
    if duplicacy check -storage "$STORE" -threads "$THREADS" 2>&1; then
      RESULTS="${RESULTS}\n✅ ${STORE}: check OK"
    else
      RESULTS="${RESULTS}\n🚨 ${STORE}: check FAILED"
    fi
  done
fi

# --- Garage scrub on BOTH target storage nodes ---
# Each server backs up to two Garage nodes (ENDPOINT_1 and ENDPOINT_2).
# Scrubbing both ensures full coverage when monthly runs are staggered
# across servers (e.g., WT on 1st, GB on 2nd, CT on 3rd).

for EP_VAR in ENDPOINT_1 ENDPOINT_2; do
  eval EP_VAL="\${${EP_VAR}:-}"
  if [ -n "$EP_VAL" ]; then
    GARAGE_HOST=$(echo "$EP_VAL" | cut -d: -f1)
    echo "=== Triggering Garage scrub on ${GARAGE_HOST} (${EP_VAR}) ==="
    if wget -q -O- --post-data='' "http://${GARAGE_HOST}:3903/v2/RepairScrubStart" --header="Authorization: Bearer ${GARAGE_ADMIN_TOKEN}" 2>&1; then
      RESULTS="${RESULTS}\n✅ Garage scrub triggered on ${GARAGE_HOST}"
    else
      RESULTS="${RESULTS}\n🚨 Garage scrub FAILED on ${GARAGE_HOST}"
    fi
  fi
done

MSG="🔍 *${MACHINENAME}* — _Monthly Integrity Check_
---------------------------------------------
$(printf "%b" "$RESULTS")"
echo "$MSG"
notify "$MSG"
