#!/bin/sh
# Runs the built app for real and holds it to its budgets:
#
#   scripts/eval.sh [path/to/Wham.app]    (default build/Wham.app)
#
# - the `wham` command answers in under 0.3 s (after macOS's one-time check)
# - the menu bar app, once settled, uses under 0.1 s of CPU per 30 s idle and
#   under 40 MB of memory, and is still running
# - where sudo needs no password (CI), `wham on` and `wham off` really flip the
#   kernel's SleepDisabled flag, and the state it started in is restored
#
# Locally the app shows a second switch in the menu bar for about 40 seconds.
set -eu
cd "$(dirname "$0")/.."
app=${1:-build/Wham.app}
bin="$app/Contents/MacOS/Wham"
failures=0
check() {
  if [ "$1" = 1 ]; then echo "ok   $2"; else echo "FAIL $2"; failures=$((failures + 1)); fi
}
is() { if eval "$1"; then echo 1; else echo 0; fi; }
seconds() { awk -F: '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; print s }'; }
flag() { ioreg -rd1 -c IOPMrootDomain | awk -F' = ' '/"SleepDisabled"/ { print ($2 == "Yes") ? 1 : 0 }'; }

echo "macOS $(sw_vers -productVersion), $(uname -m)"

# The command line. The first run of a new binary waits for macOS to check its
# signature, once: time the second.
"$bin" version >/dev/null
real=$(/usr/bin/time -p "$bin" version 2>&1 >/dev/null | awk '/^real/ { print $2 }')
check "$(is "[ \"\$(echo \"$real < 0.3\" | bc)\" = 1 ]")" "wham version answers in ${real} s"
"$bin" status >/dev/null 2>&1 && status_ok=1 || status_ok=0
check "$status_ok" "wham status reads the flag ($("$bin" status 2>&1 || true))"

# The menu bar app, idle.
"$bin" >/dev/null 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT
sleep 6
before=$(ps -o cputime= -p "$pid" | seconds)
sleep 30
after=$(ps -o cputime= -p "$pid" | seconds)
idle=$(echo "$after - $before" | bc)
check "$(is "kill -0 $pid 2>/dev/null")" "the app is still running after 36 s"
check "$(is "[ \"\$(echo \"$idle < 0.1\" | bc)\" = 1 ]")" "idle CPU: ${idle} s over 30 s"
# footprint picks its unit (KB on a small process, MB above): convert to MB.
memory=$(footprint "$pid" 2>/dev/null | awk '/phys_footprint:/ { v = $2; if ($3 == "KB") v /= 1024; if ($3 == "GB") v *= 1024; print int(v + 0.5); exit }')
[ -n "$memory" ] || memory=$(ps -o rss= -p "$pid" | awk '{ print int($1 / 1024) }')
check "$(is "[ ${memory%.*} -lt 40 ]")" "memory: ${memory} MB"

# The real flag, where sudo asks for nothing.
if sudo -n true 2>/dev/null; then
  start=$(flag)
  "$bin" on >/dev/null
  check "$(is "[ \"\$(flag)\" = 1 ]")" "wham on sets SleepDisabled"
  sleep 3
  check "$(is "kill -0 $pid 2>/dev/null")" "the app follows the change without trouble"
  "$bin" off >/dev/null
  check "$(is "[ \"\$(flag)\" = 0 ]")" "wham off clears SleepDisabled"
  if [ "$start" = 1 ]; then "$bin" on >/dev/null; fi
else
  echo "skip flipping the flag (sudo asks for a password here)"
fi

kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
echo
if [ "$failures" = 0 ]; then echo "all evals passed"; else echo "$failures eval(s) failed"; exit 1; fi
