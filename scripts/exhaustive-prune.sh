#!/usr/bin/env sh
set -eu
set -o pipefail

# Weekly exhaustive prune: scans ALL chunks and removes orphans not referenced by any snapshot.
# Regular daily prune only marks chunks as fossils; this actually reclaims space.
# Prunes BOTH primary and secondary (C) storages.
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
for REPO_DIR in /local_shares/*/; do
  STORAGENAME=$(basename "$REPO_DIR")
  [ -d "${REPO_DIR}.duplicacy" ] || continue

  if ! wait_for_lock "$STORAGENAME"; then
    RESULTS="${RESULTS}\n⏭️ ${STORAGENAME}: skipped (lock timeout)"
    continue
  fi

  cd "$REPO_DIR"
  for SUFFIX in ""; do
    STORE="${STORAGENAME}${SUFFIX}"
    echo "=== Exhaustive prune: ${STORE} ==="
    if duplicacy prune -storage "$STORE" -exhaustive -threads "$THREADS" 2>&1; then
      RESULTS="${RESULTS}\n✅ ${STORE}: exhaustive prune OK"
    else
      RESULTS="${RESULTS}\n🚨 ${STORE}: exhaustive prune FAILED"
    fi
  done
done

# Also prune boot USB repo (primary + secondary)
if [ -d "/boot_usb/.duplicacy" ]; then
  if wait_for_lock "boot"; then
    cd /boot_usb
    for SUFFIX in ""; do
      STORE="boot${SUFFIX}"
      echo "=== Exhaustive prune: ${STORE} ==="
      if duplicacy prune -storage "$STORE" -exhaustive -threads "$THREADS" 2>&1; then
        RESULTS="${RESULTS}\n✅ ${STORE}: exhaustive prune OK"
      else
        RESULTS="${RESULTS}\n🚨 ${STORE}: exhaustive prune FAILED"
      fi
    done
  else
    RESULTS="${RESULTS}\n⏭️ boot: skipped (lock timeout)"
  fi
fi

MSG="🔧 *${MACHINENAME}* — _Weekly Exhaustive Prune_
---------------------------------------------
$(printf "%b" "$RESULTS")"
echo "$MSG"
notify "$MSG"
