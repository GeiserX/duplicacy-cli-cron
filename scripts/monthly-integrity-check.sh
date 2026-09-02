#!/usr/bin/env bash
set -eu
set -o pipefail

# Monthly integrity check: verify all backup chunks exist and are valid.

MACHINENAME="${HOST:-$(hostname)}"
SHOUTRRR_URL="${SHOUTRRR_URL:-}"
THREADS="${DUPLICACY_THREADS:-4}"

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

# Garage scrubs its own blocks on its own schedule (garage worker get scrub-*). The trigger that
# used to live here needed an admin token this container never had; its failure aborted the
# script under set -e before the report was sent, every month (fleet audit 2026-09-02, wt-11).
MSG="🔍 *${MACHINENAME}* — _Monthly Integrity Check_
---------------------------------------------
$(printf "%b" "$RESULTS")"
echo "$MSG"
notify "$MSG"
