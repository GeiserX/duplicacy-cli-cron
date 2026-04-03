#!/usr/bin/env sh
set -eu
set -o pipefail

# Monthly integrity check: verify all backup chunks exist and are valid.
# Also triggers a Garage data scrub on target storage nodes.

MACHINENAME="${HOST:-$(hostname)}"
SHOUTRRR_URL="${SHOUTRRR_URL:-}"
THREADS="${DUPLICACY_THREADS:-4}"
GARAGE_ADMIN_TOKEN="${GARAGE_ADMIN_TOKEN:-my_admin_tokensuper}"

notify() { [ -n "$SHOUTRRR_URL" ] && /usr/local/bin/shoutrrr send -u "$SHOUTRRR_URL" -m "$1" || true; }

RESULTS=""

# --- Duplicacy chunk verification ---
for REPO_DIR in /local_shares/*/; do
  STORAGENAME=$(basename "$REPO_DIR")
  [ -d "${REPO_DIR}.duplicacy" ] || continue
  cd "$REPO_DIR"
  for SUFFIX in ""; do
    STORE="${STORAGENAME}${SUFFIX}"
    echo "=== Check: ${STORE} ==="
    if duplicacy check -storage "$STORE" -threads "$THREADS" 2>&1; then
      RESULTS="${RESULTS}\n✅ ${STORE}: check OK"
    else
      RESULTS="${RESULTS}\n🚨 ${STORE}: check FAILED"
    fi
  done
done

# Check boot USB repo
if [ -d "/boot_usb/.duplicacy" ]; then
  cd /boot_usb
  for SUFFIX in ""; do
    STORE="boot${SUFFIX}"
    echo "=== Check: ${STORE} ==="
    if duplicacy check -storage "$STORE" -threads "$THREADS" 2>&1; then
      RESULTS="${RESULTS}\n✅ ${STORE}: check OK"
    else
      RESULTS="${RESULTS}\n🚨 ${STORE}: check FAILED"
    fi
  done
fi

# --- Garage scrub on storage endpoints (v2 API) ---
for EP_VAR in ENDPOINT_1; do
  eval EP_VAL="\${${EP_VAR}:-}"
  if [ -n "$EP_VAL" ]; then
    GARAGE_HOST=$(echo "$EP_VAL" | cut -d: -f1)
    echo "=== Triggering Garage scrub on ${GARAGE_HOST} (${EP_VAR}) ==="
    NODE_ID=$(wget -q -O- "http://${GARAGE_HOST}:3903/v2/GetClusterStatus" --header="Authorization: Bearer ${GARAGE_ADMIN_TOKEN}" 2>/dev/null | sed -n 's/.*"id": *"\([^"]*\)".*/\1/p' | head -1)
    if [ -n "$NODE_ID" ]; then
      if wget -q -O- --post-data='{"repairType":{"scrub":"start"}}' \
        "http://${GARAGE_HOST}:3903/v2/LaunchRepairOperation?node=${NODE_ID}" \
        --header="Authorization: Bearer ${GARAGE_ADMIN_TOKEN}" \
        --header="Content-Type: application/json" 2>&1; then
        RESULTS="${RESULTS}\n✅ Garage scrub triggered on ${GARAGE_HOST}"
      else
        RESULTS="${RESULTS}\n🚨 Garage scrub FAILED on ${GARAGE_HOST}"
      fi
    else
      RESULTS="${RESULTS}\n🚨 Garage scrub FAILED on ${GARAGE_HOST} (could not get node ID)"
    fi
  fi
done

MSG="🔍 *${MACHINENAME}* — _Monthly Integrity Check_
---------------------------------------------
$(printf "%b" "$RESULTS")"
echo "$MSG"
notify "$MSG"
