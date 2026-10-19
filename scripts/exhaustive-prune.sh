#!/usr/bin/env sh
set -eu
set -o pipefail

# Weekly exhaustive prune: scans ALL chunks and removes orphans not referenced by any snapshot.
# Regular daily prune only marks chunks as fossils; this actually reclaims space.
# Respects per-repo lockfiles from dual-executor.sh to avoid conflicts with daily backups.

MACHINENAME="${HOST:-$(hostname)}"
SHOUTRRR_URL="${SHOUTRRR_URL:-}"
THREADS="${DUPLICACY_THREADS:-8}"
LOCK_WAIT_SECS=60
MAX_LOCK_WAIT=3600

notify() { [ -n "$SHOUTRRR_URL" ] && /usr/local/bin/shoutrrr send -u "$SHOUTRRR_URL" -m "$1" || true; }

wait_for_lock() {
  LOCKFILE="/tmp/duplicacy-$1.lock"
  WAITED=0
  while [ -f "$LOCKFILE" ] && [ "$WAITED" -lt "$MAX_LOCK_WAIT" ]; do
    LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null || echo "")
    if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
      echo "Waiting for $1 backup (PID $LOCK_PID) to finish..."
      sleep "$LOCK_WAIT_SECS"
      WAITED=$((WAITED + LOCK_WAIT_SECS))
    else
      rm -f "$LOCKFILE"
      break
    fi
  done
  if [ "$WAITED" -ge "$MAX_LOCK_WAIT" ]; then
    echo "WARNING: Timed out waiting for $1 lock after ${MAX_LOCK_WAIT}s, skipping."
    return 1
  fi
  return 0
}

RESULTS=""

# Discover duplicacy repos from both path layouts:
#   Unraid servers: /local_shares/Multimedia/, /local_shares/appdata/, etc.
#   Pis/CT:         /local_etc/, /local_home/, /local_tailscale/, etc.
for REPO_DIR in /local_shares/*/ /local_*/; do
  [ -d "${REPO_DIR}.duplicacy" ] || continue

  # Read storage name from preferences (authoritative -- directory basename may differ)
  STORAGENAME=$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${REPO_DIR}.duplicacy/preferences" | head -1)
  [ -z "$STORAGENAME" ] && continue

  if ! wait_for_lock "$STORAGENAME"; then
    RESULTS="${RESULTS}\n⏭️ ${STORAGENAME}: skipped (lock timeout)"
    continue
  fi

  cd "$REPO_DIR"
  echo "=== Exhaustive prune: ${STORAGENAME} ==="
  if duplicacy prune -storage "$STORAGENAME" -exhaustive -threads "$THREADS" 2>&1; then
    RESULTS="${RESULTS}\n✅ ${STORAGENAME}: exhaustive prune OK"
  else
    RESULTS="${RESULTS}\n🚨 ${STORAGENAME}: exhaustive prune FAILED"
  fi
done

# Also prune boot USB repo (Unraid only)
if [ -d "/boot_usb/.duplicacy" ]; then
  if wait_for_lock "boot"; then
    cd /boot_usb
    echo "=== Exhaustive prune: boot ==="
    if duplicacy prune -storage "boot" -exhaustive -threads "$THREADS" 2>&1; then
      RESULTS="${RESULTS}\n✅ boot: exhaustive prune OK"
    else
      RESULTS="${RESULTS}\n🚨 boot: exhaustive prune FAILED"
    fi
  else
    RESULTS="${RESULTS}\n⏭️ boot: skipped (lock timeout)"
  fi
fi

MSG="🔧 *${MACHINENAME}* — _Weekly Exhaustive Prune_
---------------------------------------------
$(printf "%b" "$RESULTS")"
echo "$MSG"
notify "$MSG"
