#!/usr/bin/env sh
set -eu
set -o pipefail

# ───────── Dual-Storage Backup Executor ──────────────────────────────────────
# Sourced by daily cron wrapper scripts. Each wrapper sets:
#   REPO_DIR          – container path to back up (e.g. /local_shares/appdata)
#   STORAGENAME       – Duplicacy storage name   (e.g. appdata)
#   SNAPSHOTID        – snapshot identifier       (e.g. appdata)
#   THREADS_OVERRIDE  – (optional) per-repo thread count
#
# Environment (set in docker-compose):
#   ENDPOINT_2        – (optional) secondary S3 host:port for pre-flight check
#   SECONDARY_RETRIES – (optional) max retry attempts for secondary, default 3
#   SECONDARY_PREFLIGHT_TIMEOUT – (optional) seconds to wait for endpoint, default 120
#
# This script backs up to both primary and secondary (C-suffix) storages,
# prunes old revisions (skipped on Saturdays for the weekly exhaustive prune),
# and sends a Telegram notification via Shoutrrr.
# ─────────────────────────────────────────────────────────────────────────────

STORAGENAME_C="${STORAGENAME}C"
MACHINENAME="${HOST:-$(hostname)}"
SHOUTRRR_URL="${SHOUTRRR_URL:-}"
THREADS="${THREADS_OVERRIDE:-${DUPLICACY_THREADS:-4}}"
MAX_RUNTIME_HOURS="${MAX_RUNTIME_HOURS:-71}"
LOCKFILE="/tmp/duplicacy-${SNAPSHOTID}.lock"
SECONDARY_RETRIES="${SECONDARY_RETRIES:-3}"
SECONDARY_PREFLIGHT_TIMEOUT="${SECONDARY_PREFLIGHT_TIMEOUT:-120}"

# ───────── helpers ───────────────────────────────────────────────────────────

notify() { [ -n "$SHOUTRRR_URL" ] && /usr/local/bin/shoutrrr send -u "$SHOUTRRR_URL" -m "$1" || true; }

cleanup() { rm -f "$LOCKFILE"; }

# Polls a Garage S3 endpoint until it responds.
# Garage returns an XML body even for unauthenticated requests (403);
# any response body means the endpoint is reachable over the network.
wait_for_endpoint() {
  _ep="$1"; _timeout="${2:-120}"; _waited=0
  echo "Pre-flight: checking ${_ep}..."
  while [ "$_waited" -lt "$_timeout" ]; do
    _rc=0
    wget -q -O /dev/null -T 5 "http://${_ep}/" >/dev/null 2>&1 || _rc=$?
    # busybox wget: 0 = success, 8 = HTTP error (e.g. 403) — both mean TCP worked
    if [ "$_rc" -eq 0 ] || [ "$_rc" -eq 8 ]; then
      echo "Pre-flight: ${_ep} reachable"
      return 0
    fi
    sleep 10
    _waited=$((_waited + 10))
    echo "Pre-flight: ${_ep} unreachable (${_waited}/${_timeout}s)"
  done
  echo "Pre-flight: ${_ep} unreachable after ${_timeout}s"
  return 1
}

# Runs a duplicacy backup with retries and exponential backoff.
# Sets RETRY_ATTEMPTS to the number of attempts used.
retry_backup() {
  _storage="$1"; _max="${2:-3}"; _delay=60; _attempt=1
  while [ "$_attempt" -le "$_max" ]; do
    _rc=0
    duplicacy backup -storage "$_storage" -stats -hash -threads "$THREADS" 2>&1 || _rc=$?
    if [ "$_rc" -eq 0 ]; then
      RETRY_ATTEMPTS=$_attempt; return 0
    fi
    if [ "$_attempt" -lt "$_max" ]; then
      echo "Attempt ${_attempt}/${_max} failed (exit $_rc), retrying in ${_delay}s..."
      sleep "$_delay"
      _delay=$((_delay * 2))
    fi
    _attempt=$((_attempt + 1))
  done
  RETRY_ATTEMPTS=$((_attempt - 1))
  return "$_rc"
}

# ───────── lock check ────────────────────────────────────────────────────────
# Prevents duplicate runs. If a previous backup is still running:
#   - Within MAX_RUNTIME_HOURS: skip with notification
#   - Exceeds MAX_RUNTIME_HOURS: kill the stuck process and start fresh

if [ -f "$LOCKFILE" ]; then
  LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null || echo "")
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCKFILE" 2>/dev/null || echo "0") ))
    if [ "$LOCK_AGE" -ge $(( MAX_RUNTIME_HOURS * 3600 )) ]; then
      kill "$LOCK_PID" 2>/dev/null || true; sleep 5; kill -9 "$LOCK_PID" 2>/dev/null || true
      rm -f "$LOCKFILE"
      notify "⚠️ *${MACHINENAME}* — _${SNAPSHOTID}_
Killed after ${MAX_RUNTIME_HOURS}h timeout (PID: $LOCK_PID)"
    else
      notify "⏭️ *${MACHINENAME}* — _${SNAPSHOTID}_
Skipped — previous run still in progress (PID: $LOCK_PID)"; exit 0
    fi
  else rm -f "$LOCKFILE"; fi
fi

echo $$ > "$LOCKFILE"; trap cleanup EXIT INT TERM

# ───────── backup ────────────────────────────────────────────────────────────
cd "$REPO_DIR"

echo "--- Backup -> Primary ($STORAGENAME) ---"
B1=0; duplicacy backup -storage $STORAGENAME -stats -hash -threads $THREADS 2>&1 || B1=$?

echo "--- Backup -> Secondary ($STORAGENAME_C) ---"
B2=0; B2_NOTE=""; SECONDARY_REACHABLE=true
SECONDARY_EP="${ENDPOINT_2:-}"

if [ -n "$SECONDARY_EP" ]; then
  if ! wait_for_endpoint "$SECONDARY_EP" "$SECONDARY_PREFLIGHT_TIMEOUT"; then
    B2=1; B2_NOTE=" _(unreachable)_"; SECONDARY_REACHABLE=false
  fi
fi

if [ "$SECONDARY_REACHABLE" = true ]; then
  RETRY_ATTEMPTS=1
  retry_backup "$STORAGENAME_C" "$SECONDARY_RETRIES" || B2=$?
  if [ "$RETRY_ATTEMPTS" -gt 1 ]; then
    B2_NOTE=" _(${RETRY_ATTEMPTS} attempts)_"
  fi
fi

B1M=$( [ $B1 -eq 0 ] && echo "✅" || echo "❌" )
B2M=$( [ $B2 -eq 0 ] && echo "✅" || echo "❌" )

# ───────── prune ─────────────────────────────────────────────────────────────
# Skip on Saturdays — the weekly exhaustive prune handles it
if [ "$(date +%u)" != "6" ]; then
  echo "--- Prune Primary ---"
  duplicacy prune -storage $STORAGENAME -keep 0:180 -keep 30:90 -keep 7:30 -keep 1:7 2>&1 || true
  if [ "$SECONDARY_REACHABLE" = true ]; then
    echo "--- Prune Secondary ---"
    duplicacy prune -storage $STORAGENAME_C -keep 0:180 -keep 30:90 -keep 7:30 -keep 1:7 2>&1 || true
  else
    echo "--- Prune Secondary (skipped — endpoint unreachable) ---"
  fi
  PM="🔄 Pruned"
else PM="⏭️ Prune skipped (Saturday)"; fi

# ───────── notification ──────────────────────────────────────────────────────
ICON=$( [ $B1 -eq 0 ] && [ $B2 -eq 0 ] && echo "🟢" || echo "🔴" )
MSG="${ICON} *${MACHINENAME}* — _${SNAPSHOTID}_
Primary: ${B1M}
Secondary: ${B2M}${B2_NOTE}
${PM}"
echo "$MSG"; notify "$MSG"
