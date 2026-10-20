#!/usr/bin/env sh
# Controls for the stall guard. Run inside the duplicacy-cli-cron image.
# STALL_MINUTES=1 here, so the guard kills after ~2 min of no progress; every
# control that must SURVIVE therefore has to run longer than that window.
set -eu
set -o pipefail

FAIL=0
ok()  { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; FAIL=1; }

STALL_MINUTES=1 . /config/stall-guard.sh

# ---- 1. positive control: a process doing nothing at all is killed ----
T0=$(date +%s); RC=0
run_guarded "idle sleeper" sleep 600 || RC=$?
E=$(( $(date +%s) - T0 ))
if [ "$RC" -eq 143 ] && [ "$E" -ge 60 ] && [ "$E" -le 200 ]; then
  ok "wedged process killed after ${E}s, rc=${RC}"
else
  bad "expected rc=143 in 60-200s, got rc=${RC} after ${E}s"
fi

# ---- 2. negative control: a process that keeps working is left alone ----
# Runs 180s, three times the detection window. Moves the child's own CPU and,
# through reaped grandchildren, its cutime/cstime and IO counters.
T0=$(date +%s); RC=0
run_guarded "busy worker" sh -c 'e=$(( $(date +%s) + 180 )); while [ "$(date +%s)" -lt "$e" ]; do cat /usr/local/bin/duplicacy > /dev/null; done' || RC=$?
E=$(( $(date +%s) - T0 ))
if [ "$RC" -eq 0 ] && [ "$E" -ge 175 ]; then
  ok "busy process ran ${E}s untouched, rc=${RC}"
else
  bad "busy process: expected rc=0 after ~180s, got rc=${RC} after ${E}s"
fi

# ---- 3. negative control: CPU-only work, no file IO, is left alone ----
# This is the directory-walk case: getdents bytes never reach rchar, so CPU is
# the only signal that says the process is alive.
T0=$(date +%s); RC=0
run_guarded "cpu-only worker" sh -c 'e=$(( $(date +%s) + 150 )); i=0; while [ "$(date +%s)" -lt "$e" ]; do i=$((i+1)); done' || RC=$?
E=$(( $(date +%s) - T0 ))
if [ "$RC" -eq 0 ] && [ "$E" -ge 145 ]; then
  ok "cpu-only process ran ${E}s untouched, rc=${RC}"
else
  bad "cpu-only process: expected rc=0 after ~150s, got rc=${RC} after ${E}s"
fi

# ---- 4. a real failure's exit status survives the wrapper ----
RC=0
run_guarded "failing command" sh -c 'sleep 2; exit 7' || RC=$?
[ "$RC" -eq 7 ] && ok "exit status passed through (7)" || bad "expected rc=7, got ${RC}"

# ---- 5. STALL_MINUTES=0 turns the guard off ----
STALL_MINUTES=0 . /config/stall-guard.sh
T0=$(date +%s); RC=0
run_guarded "unguarded sleeper" sleep 150 || RC=$?
E=$(( $(date +%s) - T0 ))
if [ "$RC" -eq 0 ] && [ "$E" -ge 145 ]; then
  ok "STALL_MINUTES=0 left an idle process alone for ${E}s"
else
  bad "STALL_MINUTES=0 did not disable the guard (rc=${RC}, ${E}s)"
fi

# ---- 6. a Ctrl-C on the wrapper really stops the guarded child ----
# POSIX has a command started with & and no job control ignore SIGINT, so
# without stop_guarded the wrapper dies and duplicacy keeps running behind it.
sh -c 'STALL_MINUTES=0 . /config/stall-guard.sh
       trap "stop_guarded; exit 130" INT TERM
       run_guarded "victim" sleep 400' >/dev/null 2>&1 &
WRAP=$!
sleep 3
kill -TERM "$WRAP" 2>/dev/null || true
sleep 3
ORPHAN=$(ps -o args= 2>/dev/null | grep -c '[s]leep 400' || true)
[ "$ORPHAN" -eq 0 ] && ok "interrupted wrapper left no guarded child running" \
  || bad "${ORPHAN} guarded child(ren) survived the interrupt"

# ---- 7. an interrupt must not let the retry loop start another attempt, and
#         must not release the lock before the child is gone ----
# Control 6 above wires a handler that already exits, so it cannot catch the
# wiring dual-executor.sh actually had: `trap 'stop_guarded; cleanup' EXIT INT
# TERM`. That handler RETURNS, bash resumes the interrupted line, and the retry
# loop runs a second attempt with the lockfile already deleted.
#
# The victim here traps TERM and takes 6s to die, which is what duplicacy does
# while it flushes and closes its S3 connections. A stop_guarded that only
# sends the signal lets the wrapper exit, and its lockfile vanish, while the
# child is still running. Both failures are caught below.
#
# It loops on `sleep 1` rather than one long sleep: the trap only runs once the
# current foreground command returns, so a `sleep 400` would both delay the
# handler and outlive its parent as an orphan that looks like a survivor.
LOCK=/tmp/stall-guard-retry.lock
ATT=/tmp/stall-guard-attempts
rm -f "$LOCK" "$ATT"
sh -c 'STALL_MINUTES=0 . /config/stall-guard.sh
       LOCK=/tmp/stall-guard-retry.lock; ATT=/tmp/stall-guard-attempts
       cleanup() { rm -f "$LOCK"; }
       echo $$ > "$LOCK"
       trap cleanup EXIT
       trap "stop_guarded; exit 130" INT
       trap "stop_guarded; exit 143" TERM
       n=1
       while [ "$n" -le 2 ]; do
         echo "attempt $n" >> "$ATT"
         run_guarded "victim $n" sh -c '"'"'SGVICTIM=1; trap "sleep 6; exit 143" TERM; while :; do sleep 1; done'"'"' && break
         n=$((n + 1))
       done' >/dev/null 2>&1 &
WRAP=$!

# Wait for the wrapper to reach run_guarded rather than guessing at 3 seconds.
I=0
while [ ! -s "$ATT" ] && [ "$I" -lt 50 ]; do sleep 0.2; I=$((I + 1)); done
kill -TERM "$WRAP" 2>/dev/null || true

# Wait for the wrapper itself, bounded, and keep its exit status: 143 is the
# contract for the TERM handler. A handler that falls through to the retry
# loop never produces it.
WRC=0
wait "$WRAP" 2>/dev/null || WRC=$?

# Checked the instant the wrapper is gone. If stop_guarded returned before the
# child died, the child is still here now and the lockfile is already deleted.
STILL=$(ps -o args= 2>/dev/null | grep -c '[S]GVICTIM' || true)
ATTEMPTS=$(wc -l < "$ATT" 2>/dev/null | tr -d ' ' || echo 0)
LOCKP=$([ -f "$LOCK" ] && echo yes || echo no)
if [ "$ATTEMPTS" -eq 1 ] && [ "$STILL" -eq 0 ] && [ "$LOCKP" = no ] && [ "$WRC" -eq 143 ]; then
  ok "interrupt: 1 attempt, child gone before the lock was released, rc=143"
else
  bad "interrupt: attempts=${ATTEMPTS} want 1, survivors=${STILL} want 0, lockfile=${LOCKP} want no, rc=${WRC} want 143"
fi
pkill -f 'SGVICTIM' 2>/dev/null || true
rm -f "$LOCK" "$ATT"

# ---- 8. nothing left running afterwards ----
LEFT=$(ps -o args= 2>/dev/null | grep -c '[s]leep 600' || true)
[ "$LEFT" -eq 0 ] && ok "no orphaned work left behind" || bad "${LEFT} orphans left behind"

echo "----"
[ "$FAIL" -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit "$FAIL"
