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

# ---- 6. nothing left running afterwards ----
LEFT=$(ps -o args= 2>/dev/null | grep -c '[s]leep 600' || true)
[ "$LEFT" -eq 0 ] && ok "no orphaned work left behind" || bad "${LEFT} orphans left behind"

echo "----"
[ "$FAIL" -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit "$FAIL"
