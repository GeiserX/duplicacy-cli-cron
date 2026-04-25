#!/usr/bin/env bash
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
# Discover repos from both path layouts:
#   Unraid servers: /local_shares/Multimedia/, /local_shares/appdata/, etc.
#   Pis/CT:         /local_etc/, /local_home/, /local_tailscale/, etc.
for REPO_DIR in /local_shares/*/ /local_*/; do
  [ -d "${REPO_DIR}.duplicacy" ] || continue

  # Read storage name from preferences (authoritative -- directory basename may differ)
  STORAGENAME=$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${REPO_DIR}.duplicacy/preferences" | head -1)
  [ -z "$STORAGENAME" ] && continue
  cd "$REPO_DIR"
  echo "=== Check: ${STORAGENAME} ==="
  if duplicacy check -storage "$STORAGENAME" -threads "$THREADS" 2>&1; then
    RESULTS="${RESULTS}\n✅ ${STORAGENAME}: check OK"
  else
    RESULTS="${RESULTS}\n🚨 ${STORAGENAME}: check FAILED"
  fi
done

# Check boot USB repo
if [ -d "/boot_usb/.duplicacy" ]; then
  cd /boot_usb
  echo "=== Check: boot ==="
  if duplicacy check -storage "boot" -threads "$THREADS" 2>&1; then
    RESULTS="${RESULTS}\n✅ boot: check OK"
  else
    RESULTS="${RESULTS}\n🚨 boot: check FAILED"
  fi
fi

# --- Garage scrub on storage endpoints (v2 API) ---
for EP_VAL in "${ENDPOINT_1:-}"; do
  [ -z "$EP_VAL" ] && continue
  GARAGE_HOST=$(echo "$EP_VAL" | cut -d: -f1)
  echo "=== Triggering Garage scrub on ${GARAGE_HOST} ==="
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
done

MSG="🔍 *${MACHINENAME}* — _Monthly Integrity Check_
---------------------------------------------
$(printf "%b" "$RESULTS")"
echo "$MSG"
notify "$MSG"
