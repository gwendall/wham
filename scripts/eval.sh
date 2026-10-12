#!/bin/sh
# Runs the built app for real, against this Mac's kernel, and holds it to its
# budgets and its promises:
#
#   scripts/eval.sh [path/to/Wham.app]    (default build/Wham.app)
#
# Everywhere:
# - the `wham` command answers in under 0.3 s (after macOS's one-time check)
# - the menu bar app, settled, uses under 0.1 s of CPU per 30 s and under
#   40 MB of memory
# Where sudo sets the flag without a password (CI, or a Mac with Wham's rule),
# on the kernel's real SleepDisabled flag:
# - `wham on/off/toggle`, the switch and every menu item, and the app follows
#   the command at once
# - timed sessions: `wham on 3s`, "Turn On For", one that ran out while the app
#   was closed, the app opened by `wham on 2h` when it is not running
# - the battery and heat guards, read from a stand-in (WHAM_FAKE_POWER), and the
#   real heat signal where macOS lets it be raised (CI)
# - `wham run`: exit statuses, Ctrl-C, hangups, kills, its watchdog
# - however the app ends: killed while on or off, quit from its menu, quit from
#   outside (back on at the next launch within a minute)
#
# The flag is put back as it was. The app plays no sound here, but its switch
# and its notes show in the menu bar meanwhile.
set -eu
cd "$(dirname "$0")/.."
app=$(cd "${1:-build/Wham.app}" && pwd)
bin="$app/Contents/MacOS/Wham"
failures=0
check() {
  if [ "$1" = 1 ]; then echo "ok   $2"; else echo "FAIL $2"; failures=$((failures + 1)); fi
}
is() { if eval "$1"; then echo 1; else echo 0; fi; }
seconds() { awk -F: '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; print s }'; }
flag() { ioreg -rd1 -c IOPMrootDomain | awk -F' = ' '/"SleepDisabled"/ { print ($2 == "Yes") ? 1 : 0 }'; }
ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; }
# Polls, every 50 ms for up to $2 s, until the command $1 succeeds.
until_() { n=$(echo "${2:-3} * 20" | bc | cut -d. -f1); while ! eval "$1" && [ "$n" -gt 0 ]; do sleep 0.05; n=$((n - 1)); done; }
waitflag() { until_ "[ \"\$(flag)\" = $1 ]" "${2:-3}"; }
# The end of the timed session, in seconds from now ("" when untimed).
left() {
  at=$(defaults read sh.wham.app offAt 2>/dev/null) || return 0
  echo $(($(date -j -f "%Y-%m-%d %H:%M:%S %z" "$at" +%s) - $(date +%s)))
}

echo "macOS $(sw_vers -productVersion), $(uname -m)"
start=$(flag)
work=$(mktemp -d)
fake="$work/power"
echo "ac 100" >"$fake"
pid=
guards=

# Opens the app, out of sight and silent, pressing the WHAM_PRESS steps $1 if
# given, with its battery and heat read from $fake while $guards is set.
launch() {
  set -- ${1:+"WHAM_PRESS=$1"} ${guards:+"WHAM_FAKE_POWER=$fake"}
  env "$@" "$bin" -muted YES >/dev/null 2>&1 &
  pid=$!
  sleep 1
}
# Ends the app with signal $1 (KILL by default, as a crash would), then waits
# for what it leaves running (its watchdog) to finish.
stop() {
  [ -n "$pid" ] || return 0
  children=$(pgrep -P "$pid" 2>/dev/null || true)
  kill "-${1:-KILL}" "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  for _ in $(seq 60); do
    alive=0
    for child in $children; do kill -0 "$child" 2>/dev/null && alive=1; done
    [ "$alive" = 0 ] && break
    sleep 0.05
  done
  pid=
}
# Whether the app has its watchdog out.
dog() { pgrep -P "$pid" -f stand-down >/dev/null 2>&1; }
cleanup() {
  stop
  [ "$(flag)" = "$start" ] || sudo -n /usr/bin/pmset -a disablesleep "$start" >/dev/null 2>&1 \
    || echo "note: could not put SleepDisabled back to $start"
  defaults delete sh.wham.app offAt >/dev/null 2>&1 || true
  defaults delete sh.wham.app resumeBefore >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

# The command line. The first run of a new binary waits for macOS to check its
# signature, once: time the second.
"$bin" version >/dev/null
real=$(/usr/bin/time -p "$bin" version 2>&1 >/dev/null | awk '/^real/ { print $2 }')
check "$(is "[ \"\$(echo \"$real < 0.3\" | bc)\" = 1 ]")" "wham version answers in ${real} s"
"$bin" status >/dev/null 2>&1 && status_ok=1 || status_ok=0
check "$status_ok" "wham status reads the flag ($("$bin" status 2>&1 || true))"

# The menu bar app, idle, in the state it finds, then in the other one.
idle() {
  sleep 5
  before=$(ps -o cputime= -p "$pid" | seconds)
  sleep 30
  after=$(ps -o cputime= -p "$pid" | seconds)
  cpu=$(echo "$after - $before" | bc)
  state=$([ "$(flag)" = 1 ] && echo on || echo off)
  check "$(is "kill -0 $pid 2>/dev/null")" "the app is still running ($state)"
  check "$(is "[ \"\$(echo \"$cpu < 0.1\" | bc)\" = 1 ]")" "idle CPU ($state): ${cpu} s over 30 s"
}
launch
idle
# footprint picks its unit (KB on a small process, MB above): convert to MB.
memory=$(footprint "$pid" 2>/dev/null | awk '/phys_footprint:/ { v = $2; if ($3 == "KB") v /= 1024; if ($3 == "GB") v *= 1024; print int(v + 0.5); exit }')
[ -n "$memory" ] || memory=$(ps -o rss= -p "$pid" | awk '{ print int($1 / 1024) }')
check "$(is "[ ${memory%.*} -lt 40 ]")" "memory: ${memory} MB"

if [ -z "$start" ] || ! sudo -n /usr/bin/pmset -a disablesleep "$start" >/dev/null 2>&1; then
  echo "skip the real flag (sudo asks for a password here)"
  stop
  echo
  if [ "$failures" = 0 ]; then echo "all evals passed"; else echo "$failures eval(s) failed"; exit 1; fi
  exit 0
fi

# --- The command line and the app, together.
if [ "$start" = 1 ]; then "$bin" off >/dev/null; else "$bin" on >/dev/null; fi
idle
"$bin" off >/dev/null
until_ "! dog" 1
check "$(is "[ \"\$(flag)\" = 0 ] && ! dog")" "wham off clears the flag; the app's watchdog stands down"
t0=$(ms)
"$bin" on >/dev/null
until_ dog 1
t1=$(ms)
check "$(is "[ \"\$(flag)\" = 1 ] && dog")" "wham on sets the flag; the app follows and arms its watchdog in $((t1 - t0)) ms"
"$bin" toggle >/dev/null
check "$(is "[ \"\$(flag)\" = 0 ]")" "wham toggle turns it off"
"$bin" toggle >/dev/null
check "$(is "[ \"\$(flag)\" = 1 ]")" "and on again"
"$bin" off >/dev/null

# --- Timed sessions.
t0=$(ms)
"$bin" on 3s >/dev/null
check "$(is "\"$bin\" status | grep -q ' until '")" "wham status says until when ($("$bin" status))"
check "$(is "[ -n \"\$(left)\" ]")" "the end is shared with the app"
waitflag 0 10
t1=$(ms)
check "$(is "[ \"\$(flag)\" = 0 ] && [ $((t1 - t0)) -ge 3000 ] && [ $((t1 - t0)) -le 7000 ]")" \
  "wham on 3s: the app turns it off $((t1 - t0)) ms later"
check "$(is "[ -z \"\$(left)\" ] && ! \"$bin\" status | grep -q until")" "the ended session is cleared"
"$bin" on 1h >/dev/null
check "$(is "[ \"\$(left)\" -ge 3590 ] && [ \"\$(left)\" -le 3600 ]")" "wham on 1h ends in an hour"
"$bin" on >/dev/null
check "$(is "[ -z \"\$(left)\" ] && [ \"\$(flag)\" = 1 ]")" "wham on without a duration drops the end"
"$bin" on 1h >/dev/null
"$bin" off >/dev/null
check "$(is "[ -z \"\$(left)\" ] && [ \"\$(flag)\" = 0 ]")" "wham off drops it too"
"$bin" on 2x >/dev/null 2>&1 && code=0 || code=$?
check "$(is "[ $code = 64 ] && [ \"\$(flag)\" = 0 ]")" "wham on 2x is refused (64), nothing changes"

# --- However the app ends.
stop
check "$(is "[ \"\$(flag)\" = 0 ]")" "the app killed with -9 while off: nothing changes"
launch Switch
waitflag 1
until_ dog 1
check "$(is "[ \"\$(flag)\" = 1 ] && dog")" "a click on the switch turns it on"
stop
waitflag 0
check "$(is "[ \"\$(flag)\" = 0 ]")" "the app killed with -9 while on: its watchdog gives sleep back"
launch Switch
waitflag 1
sleep 0.5
stop TERM
waitflag 0
check "$(is "[ \"\$(flag)\" = 0 ]")" "the app sent TERM while on: sleep comes back"
launch "Turn On,Quit Wham (lets your Mac sleep)"
waitflag 1
until_ "! kill -0 $pid 2>/dev/null" 5
check "$(is "[ \"\$(flag)\" = 0 ] && ! kill -0 $pid 2>/dev/null")" "Quit from the menu while on: the app leaves, sleep comes back"
stop
launch
sleep 2
check "$(is "[ \"\$(flag)\" = 0 ]")" "and stays back at the next launch"
stop
launch "Turn On,Terminate"
waitflag 1
until_ "! kill -0 $pid 2>/dev/null" 5
check "$(is "[ \"\$(flag)\" = 0 ] && ! kill -0 $pid 2>/dev/null")" "quit from outside while on (a logout, an upgrade): sleep comes back"
stop
launch
waitflag 1
check "$(is "[ \"\$(flag)\" = 1 ]")" "opened again within a minute, it turns back on"
stop
waitflag 0

# --- The menu.
launch "Turn On For/1 Hour"
waitflag 1
until_ "[ -n \"\$(left)\" ]"
check "$(is "[ \"\$(flag)\" = 1 ] && [ \"\$(left)\" -ge 3590 ] && [ \"\$(left)\" -le 3600 ]")" "Turn On For 1 Hour: on, ends in an hour"
stop
waitflag 0
launch "Turn On,Stay Awake For/2 Hours,Turn Off"
until_ "[ -n \"\$(left)\" ]" 4
check "$(is "[ \"\$(flag)\" = 1 ] && [ \"\$(left)\" -ge 7190 ] && [ \"\$(left)\" -le 7200 ]")" "Stay Awake For 2 Hours while on: ends in two hours"
waitflag 0
check "$(is "[ \"\$(flag)\" = 0 ] && [ -z \"\$(left)\" ]")" "Turn Off: off, no end left"
stop
# Started with sleep blocked and an end that passed while the app was closed.
sudo -n /usr/bin/pmset -a disablesleep 1
defaults write sh.wham.app offAt -date "2001-01-01 00:00:00 +0000"
launch
waitflag 0
check "$(is "[ \"\$(flag)\" = 0 ] && [ -z \"\$(left)\" ]")" "a session that ran out while the app was closed ends when it opens"
stop
sudo -n /usr/bin/pmset -a disablesleep 1
defaults write sh.wham.app offAt -date "$(date -u -v+3S '+%Y-%m-%d %H:%M:%S +0000')"
launch
sleep 1
check "$(is "[ \"\$(flag)\" = 1 ]")" "one still running when the app opens goes on"
waitflag 0 6
check "$(is "[ \"\$(flag)\" = 0 ]")" "and ends on time"
stop
# `wham on 2h` with the app closed opens it, since the app ends the session.
if pgrep -fl "/Contents/MacOS/Wham" | grep -v "$bin" | grep -q .; then
  echo "skip wham on 3s opening the app (another Wham is running)"
else
  "$bin" on 3s >/dev/null
  until_ "pgrep -f \"$bin\" >/dev/null" 5
  pid=$(pgrep -f "$bin" | head -1)
  check "$(is "[ -n \"$pid\" ]")" "wham on 3s opens the app when it is closed"
  waitflag 0 10
  check "$(is "[ \"\$(flag)\" = 0 ]")" "which ends the session"
  stop
fi

# --- The battery and the heat, from the stand-in.
guards=1
echo "battery 9" >"$fake"
launch "Switch,Turn On,Turn On For/2 Hours"
sleep 4
check "$(is "[ \"\$(flag)\" = 0 ] && [ -z \"\$(left)\" ]")" "on battery at 9%: the switch and the menu refuse to turn on"
stop
echo "ac 100 critical" >"$fake"
launch Switch
sleep 2
check "$(is "[ \"\$(flag)\" = 0 ]")" "critically hot: the switch refuses too"
stop
echo "ac 100" >"$fake"
launch Switch
waitflag 1
echo "battery 50" >"$fake"
sleep 3
check "$(is "[ \"\$(flag)\" = 1 ]")" "on battery at 50%: stays on"
echo "battery 10" >"$fake"
waitflag 0 5
check "$(is "[ \"\$(flag)\" = 0 ]")" "down to 10%: the app gives sleep back"
echo "ac 100" >"$fake"
sleep 3
check "$(is "[ \"\$(flag)\" = 0 ]")" "plugged back in: stays off until asked"
"$bin" on >/dev/null
echo "ac 100 critical" >"$fake"
waitflag 0 5
check "$(is "[ \"\$(flag)\" = 0 ]")" "critically hot while on: the app gives sleep back"
echo "battery 9" >"$fake"
WHAM_FAKE_POWER=$fake "$bin" on >/dev/null 2>"$work/err" && code=0 || code=$?
check "$(is "[ $code = 1 ] && grep -q 'battery at 9%, plug in first' \"$work/err\" && [ \"\$(flag)\" = 0 ]")" \
  "wham on refuses on a low battery: $(cat "$work/err")"
WHAM_FAKE_POWER=$fake "$bin" run /bin/sh -c 'exit 5' 2>"$work/err" && code=0 || code=$?
check "$(is "[ $code = 5 ] && grep -q 'without keeping' \"$work/err\" && [ \"\$(flag)\" = 0 ]")" \
  "wham run still runs its command, says it can't keep the Mac awake"
echo "ac 100 critical" >"$fake"
WHAM_FAKE_POWER=$fake "$bin" on >/dev/null 2>"$work/err" && code=0 || code=$?
check "$(is "[ $code = 1 ] && grep -q 'too hot' \"$work/err\"")" "wham on refuses when too hot: $(cat "$work/err")"
stop
guards=
echo "ac 100" >"$fake"

# The real heat signal, where macOS lets it be raised (as root, on CI).
heat() { sudo -n notifyutil -s com.apple.system.thermalpressurelevel "$1" && sudo -n notifyutil -p com.apple.system.thermalpressurelevel; }
if [ -n "${CI:-}" ] && heat 0 >/dev/null 2>&1; then
  launch
  "$bin" on >/dev/null
  heat 3
  waitflag 0 4
  if [ "$(flag)" = 0 ]; then
    check 1 "the Mac's real thermal pressure at its peak: the app gives sleep back"
    "$bin" on >/dev/null 2>&1 && code=0 || code=$?
    check "$(is "[ $code = 1 ]")" "and wham on refuses until it cools"
  elif "$bin" on 2>&1 | grep -q "too hot"; then
    check 0 "the command feels the heat but the app did not turn off"
  else
    echo "skip the real heat (this Mac's thermal state did not follow)"
  fi
  heat 0
  "$bin" off >/dev/null
  stop
fi

# --- wham run, with the app running.
launch
"$bin" off >/dev/null
"$bin" run /bin/sh -c 'ioreg -rd1 -c IOPMrootDomain | grep -q "\"SleepDisabled\" = Yes"' && during=1 || during=0
check "$(is "[ $during = 1 ] && [ \"\$(flag)\" = 0 ]")" "wham run keeps it on while its command runs, then gives it back"
"$bin" run /bin/sh -c 'exit 3' && code=0 || code=$?
check "$(is "[ $code = 3 ]")" "wham run exits with its command's status (3)"
"$bin" run wham-no-such-command 2>/dev/null && code=0 || code=$?
check "$(is "[ $code = 127 ] && [ \"\$(flag)\" = 0 ]")" "a command that does not exist: 127"
printf 'not a program' >"$work/plain"
"$bin" run "$work/plain" 2>/dev/null && code=0 || code=$?
check "$(is "[ $code = 126 ] && [ \"\$(flag)\" = 0 ]")" "a file that is not a program: 126"
"$bin" run "$bin" off >/dev/null && code=0 || code=$?
check "$(is "[ $code = 0 ] && [ \"\$(flag)\" = 0 ]")" "a command that turns it off itself is left alone"
"$bin" on >/dev/null
"$bin" run /bin/sh -c 'exit 0'
check "$(is "[ \"\$(flag)\" = 1 ]")" "already on: wham run leaves it on"
"$bin" off >/dev/null
# Ctrl-C: the terminal signals the whole foreground group, wham included.
perl -e 'setpgrp(0, 0); exec @ARGV' "$bin" run sleep 30 &
runner=$!
waitflag 1
sleep 0.3
kill -INT -- "-$runner"
wait "$runner" && code=0 || code=$?
check "$(is "[ $code = 130 ] && [ \"\$(flag)\" = 0 ]")" "Ctrl-C: the command stops, wham run exits 130 and gives sleep back"
for signal in TERM HUP; do
  "$bin" run sleep 30 &
  runner=$!
  waitflag 1
  sleep 0.3
  kill "-$signal" "$runner"
  wait "$runner" && code=0 || code=$?
  expected=$((128 + $(kill -l "$signal")))
  check "$(is "[ $code = $expected ] && [ \"\$(flag)\" = 0 ]")" "$signal sent to wham run reaches its command: $code, sleep given back"
done
"$bin" run sleep 30 &
runner=$!
waitflag 1
sleep 0.3
command=$(pgrep -P "$runner" -x sleep || true)
kill -9 "$runner"
wait "$runner" 2>/dev/null || true
waitflag 0
check "$(is "[ \"\$(flag)\" = 0 ] && kill -0 $command 2>/dev/null")" "wham run killed with -9: its watchdog gives sleep back, the command still running"
kill "$command" 2>/dev/null || true
stop

echo
if [ "$failures" = 0 ]; then echo "all evals passed"; else echo "$failures eval(s) failed"; exit 1; fi
