#!/usr/bin/env sh
# ───────── stall guard ───────────────────────────────────────────────────────
# Duplicacy puts no timeout on its S3 connections. When the network drops in the
# middle of a transfer, the uploader goroutines block on sockets that will never
# answer and the process sits there alive and doing nothing at all.
#
# On 2026-10-18 a Multimedia backup on geiserback stayed wedged that way for
# 20.5 hours: zero CPU, zero IO, all 26 threads in futex_do_wait, both S3
# sockets 20 h past their last byte. Nothing killed it. The one existing
# guard, MAX_RUNTIME_HOURS, is read by the lock check at the START of a run, so
# a wedged run is only noticed when the next daily run comes round a day later,
# and only then if the lock is already older than the ceiling. Meanwhile
# DuplicacyBackupStale fires at 26 h and the backup is simply not happening.
#
# run_guarded runs a duplicacy command with a watchdog that samples the child's
# consumed CPU time and its read/write syscall bytes once a minute, and kills it
# when both stay flat for STALL_MINUTES. The caller's own retry loop restarts
# it, resuming from the incomplete snapshot duplicacy leaves behind.
#
# Both signals have to be flat before anything is killed, because either one
# alone is a normal state. A long directory walk burns CPU without moving rchar
# (getdents bytes are not counted there), and a slow upload moves wchar without
# burning CPU. Flat on both for twenty minutes means stuck, not busy.
#
#   STALL_MINUTES – minutes of no progress before the kill (default 20, 0 = off)
# ─────────────────────────────────────────────────────────────────────────────

STALL_MINUTES="${STALL_MINUTES:-20}"

case "$STALL_MINUTES" in
  ''|*[!0-9]*) echo "STALL_MINUTES must be a non-negative integer" >&2; exit 2 ;;
esac

# Consumed CPU jiffies plus bytes moved by read/write syscalls, as one string.
# Fails (and prints nothing) when the process is gone or /proc carries no IO
# accounting, which is how the caller decides whether a guard is possible.
_stall_sample() {
  _ss_cpu=$(awk '{print $14 + $15 + $16 + $17}' "/proc/$1/stat" 2>/dev/null) || _ss_cpu=""
  _ss_io=$(awk '/^rchar|^wchar/ {s += $2} END {print s + 0}' "/proc/$1/io" 2>/dev/null) || _ss_io=""
  [ -n "$_ss_cpu" ] && [ -n "$_ss_io" ] || return 1
  echo "$_ss_cpu $_ss_io"
}

# Watch one PID and kill it once STALL_MINUTES consecutive samples show neither
# CPU time nor IO bytes moving. Runs in the background beside the child and
# returns as soon as the child exits on its own.
_stall_watchdog() {
  _sw_pid="$1"
  _sw_label="$2"
  _sw_prev=""
  _sw_flat=0
  while kill -0 "$_sw_pid" 2>/dev/null; do
    sleep 60
    # An unreadable sample means the process ended between the two checks, or
    # /proc hiccuped. Reset rather than count it as a minute of no progress.
    if ! _sw_now=$(_stall_sample "$_sw_pid"); then
      _sw_prev=""
      _sw_flat=0
      continue
    fi
    if [ "$_sw_now" = "$_sw_prev" ]; then
      _sw_flat=$((_sw_flat + 1))
    else
      _sw_flat=0
    fi
    _sw_prev="$_sw_now"
    if [ "$_sw_flat" -ge "$STALL_MINUTES" ]; then
      echo "Stall guard: ${_sw_label} burned no CPU and moved no bytes for ${STALL_MINUTES} min; killing PID ${_sw_pid}"
      kill "$_sw_pid" 2>/dev/null || true
      sleep 15
      if kill -0 "$_sw_pid" 2>/dev/null; then
        kill -9 "$_sw_pid" 2>/dev/null || true
      fi
      return 0
    fi
  done
}

# Kills whatever run_guarded is running at the moment, if anything, and is a
# no-op when nothing is. Wire it into the caller's INT/TERM trap.
#
# POSIX says a command started with & and no job control ignores SIGINT and
# SIGQUIT, so a Ctrl-C on the wrapper reaches the shell but not duplicacy.
# Without this the wrapper exits, its EXIT trap removes the repository's
# lockfile, and the backup carries on unsupervised behind it.
stop_guarded() {
  [ -n "${GUARDED_WD:-}" ] && kill "$GUARDED_WD" 2>/dev/null || true
  [ -n "${GUARDED_PID:-}" ] && kill "$GUARDED_PID" 2>/dev/null || true
  return 0
}

# run_guarded <label> <command> [args...]
# Returns the command's exit status. A watchdog kill surfaces as 143 (SIGTERM),
# which the caller's retry loop treats like any other failed attempt.
run_guarded() {
  _rg_label="$1"
  shift
  _rg_rc=0
  _rg_wd=""

  "$@" &
  _rg_pid=$!
  GUARDED_PID="$_rg_pid"

  if [ "$STALL_MINUTES" -eq 0 ]; then
    :
  elif _stall_sample "$_rg_pid" >/dev/null 2>&1; then
    _stall_watchdog "$_rg_pid" "$_rg_label" &
    _rg_wd=$!
    GUARDED_WD="$_rg_wd"
  else
    echo "Stall guard: no /proc IO accounting for ${_rg_label}; running it unguarded"
  fi

  wait "$_rg_pid" || _rg_rc=$?

  if [ -n "$_rg_wd" ]; then
    kill "$_rg_wd" 2>/dev/null || true
    wait "$_rg_wd" 2>/dev/null || true
  fi

  GUARDED_PID=""
  GUARDED_WD=""
  return "$_rg_rc"
}
