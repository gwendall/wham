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
# - the open menu, clicked as a mouse would: Check for Updates, Appearance and
#   Battery Limit keep it open, the option checks or says how it went there
#   and then, and only a click outside closes it; its rows look like the
#   menu's own, titles, check marks and grays (with WHAM_SHOTS=dir, pictures
#   of the menu go there)
# Where sudo sets the flag without a password (CI, or a Mac with Wham's rule),
# on the kernel's real SleepDisabled flag:
# - `wham on/off/toggle`, the switch and every menu item, and the app follows
#   the command at once; Turn On, Stay Awake For and Turn Off clicked in the
#   open menu, which stays open and says what the Mac does now
# - timed sessions: `wham on 3s`, "Turn On For", what the menu says is left,
#   No Time Limit, the warning five minutes before the end, one that ran out
#   while the app was closed, the app opened by `wham on 2h` when it is not
#   running
# - the battery and heat guards, read from a stand-in (WHAM_FAKE_POWER), the
#   menu's Battery Limit, and the real heat signal where macOS lets it be
#   raised (CI)
# - `wham run`: exit statuses, Ctrl-C, hangups, kills, its watchdog
# - however the app ends: killed while on or off, quit from its menu, quit from
#   outside (back on at the next launch within a minute), a restart (back on
#   at the next login with Stay On After Restart only, until a timed
#   session's end)
# - Appearance: Monochrome and Compact, and the status item's width
# - the menu's What's New and Check for Updates (scripts/update-test.sh
#   updates for real)
#
# The flag is put back as it was, with the battery limit, the appearance,
# Stay On After Restart, the version the user's Wham last ran as, and a timed
# session running when the evals start. The app plays no sound here, but its
# switch, its menu and its notes show meanwhile, and the pointer moves for
# the clicks in the menu, then goes back.
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
was=$(defaults read sh.wham.app offAt 2>/dev/null || true)
limit=$(defaults read sh.wham.app batteryLimit 2>/dev/null || true)
last=$(defaults read sh.wham.app lastVersion 2>/dev/null || true)
mono=$(defaults read sh.wham.app monochrome 2>/dev/null || true)
compact=$(defaults read sh.wham.app compact 2>/dev/null || true)
restart=$(defaults read sh.wham.app stayOnAfterRestart 2>/dev/null || true)
defaults delete sh.wham.app batteryLimit >/dev/null 2>&1 || true
work=$(mktemp -d)
fake="$work/power"
echo "ac 100" >"$fake"
pid=
guards=

# Opens the app, out of sight and silent, pressing the WHAM_PRESS steps $1 if
# given, with the arguments after it, its battery and heat read from $fake
# while $guards is set. It would look for an update after a minute: not
# before tomorrow here.
launch() {
  steps=${1:-}
  [ $# = 0 ] || shift
  env ${steps:+"WHAM_PRESS=$steps"} ${guards:+"WHAM_FAKE_POWER=$fake"} "$bin" -muted YES -updateDelay 86400 "$@" >>"$work/out" 2>&1 &
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
  for key in offAt onAt resumeBefore resumeAtLogin batteryLimit monochrome compact stayOnAfterRestart; do
    defaults delete sh.wham.app "$key" >/dev/null 2>&1 || true
  done
  # Monochrome, Compact and Stay On After Restart, as they were (1 or 0).
  [ -z "$mono" ] || defaults write sh.wham.app monochrome -bool "$([ "$mono" = 1 ] && echo yes || echo no)"
  [ -z "$compact" ] || defaults write sh.wham.app compact -bool "$([ "$compact" = 1 ] && echo yes || echo no)"
  [ -z "$restart" ] || defaults write sh.wham.app stayOnAfterRestart -bool "$([ "$restart" = 1 ] && echo yes || echo no)"
  [ -z "$limit" ] || defaults write sh.wham.app batteryLimit -int "$limit"
  if [ -n "$last" ]; then defaults write sh.wham.app lastVersion "$last"; else defaults delete sh.wham.app lastVersion >/dev/null 2>&1 || true; fi
  # The session that was running goes on to its end, through the Wham that
  # was running it (or ends now if its time ran out meanwhile).
  if [ "$start" = 1 ] && [ -n "$was" ] && pgrep -f "/Contents/MacOS/Wham" >/dev/null; then
    secs=$(($(date -j -f "%Y-%m-%d %H:%M:%S %z" "$was" +%s) - $(date +%s)))
    if [ "$secs" -gt 0 ]; then "$bin" on "${secs}s" >/dev/null 2>&1 || true; else "$bin" off >/dev/null 2>&1 || true; fi
  fi
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

# The menu bar app, idle, in the state it finds, then in the other one. It
# settles first: a first launch shows its hello toast and registers at login,
# which a slow runner can stretch past 5 s.
idle() {
  sleep 10
  before=$(ps -o cputime= -p "$pid" | seconds)
  sleep 30
  after=$(ps -o cputime= -p "$pid" | seconds)
  cpu=$(echo "$after - $before" | bc)
  state=$([ "$(flag)" = 1 ] && echo on || echo off)
  check "$(is "kill -0 $pid 2>/dev/null")" "the app is still running ($state)"
  check "$(is "[ \"\$(echo \"$cpu < 0.1\" | bc)\" = 1 ]")" "idle CPU ($state): ${cpu} s over 30 s"
}
# Check for Updates, clicked in the open menu as a mouse would (the pointer
# goes onto it, then back): the menu stays open, the row says it is checking,
# then how it went, here with GitHub out of reach. Its title starts where the
# menu's own do, in the same color: read from the menu's views where it draws with views
# (macOS 14 on, at least), and from a picture of the menu everywhere the screen shows
# (a locked or sleeping screen draws nothing).
[ -z "${WHAM_SHOTS:-}" ] || mkdir -p "$WHAM_SHOTS"
launch "Click Updates" -updateBase http://127.0.0.1:9
until_ "grep -q '^menu ' \"$work/out\"" 20
told=$(grep '^row [a-z]*: \|^row missing\|^row highlighted false' "$work/out" | sed 's/^row //' | paste -sd '>' - | sed 's/>/ > /g')
check "$(is "echo \"$told\" | grep -q '^busy: Checking for Updates.* > said: Can.t check now, try later$' && grep -q '^menu still open' \"$work/out\"")" \
  "Check for Updates in the open menu: the menu stays open, the row checks, then says how it went (${told:-no answer}, $(grep '^menu ' "$work/out" | tail -1))"
views=$(grep '^row title at' "$work/out" | tail -1)
ink=$(grep '^ink ' "$work/out" | tail -1)
check "$(is "echo \"$views\" | awk '{ exit !(\$1 == \"row\" && (\$13 == \"-,\" || (\$5 + 0 == \$13 + 0 && \$6 + 0 == \$14 + 0))) }' && echo \"$ink\" | awk '/not drawn/ { exit 0 } { d = \$5 - \$7; c = \$12 - \$14; exit !(\$5 ~ /^[0-9.]+\$/ && \$7 ~ /^[0-9.]+\$/ && d >= -1 && d <= 1 && \$12 ~ /^[0-9.]+\$/ && \$14 ~ /^[0-9.]+\$/ && c >= -0.03 && c <= 0.03) }'")" \
  "and its title starts where the menu's own do, as dark (${views:-no answer}; ${ink:-no picture})"
stop
# Every option, clicked in the open menu as a mouse would: the menu stays
# open, the option checks or unchecks there and then, the switch changes at
# once, and only a click outside closes the menu. The battery is the
# stand-in's, on power.
defaults delete sh.wham.app monochrome >/dev/null 2>&1 || true
defaults delete sh.wham.app compact >/dev/null 2>&1 || true
: >"$work/out"
guards=1
export WHAM_CLICKS="Appearance/Monochrome,Appearance/Compact,Battery Limit/20%,Battery Limit/10%,Appearance/Monochrome,Appearance/Compact"
launch "Click Rows"
until_ "grep -q '^outside\\|^menu closed\\|^menu missing' \"$work/out\"" 30
clicked=$(grep '^click ' "$work/out" | sed 's/^click [^:]*: //; s/, status .*//' | paste -sd ';' -)
check "$(is "[ \"$clicked\" = 'menu open, Monochrome checked, look monochrome wide 50;menu open, Compact checked, look monochrome compact 23;menu open, 20% checked, look monochrome compact 23;menu open, 10% checked, look monochrome compact 23;menu open, Monochrome, look color compact 23;menu open, Compact, look color wide 50' ]")" \
  "Appearance and Battery Limit clicked in the open menu: it stays open, the option checks, the switch follows (${clicked:-no answer})"
check "$(is "grep -q '^menu still open' \"$work/out\" && grep -q '^outside: menu closed' \"$work/out\"")" \
  "a click outside closes it ($(grep '^menu \|^outside' "$work/out" | paste -sd ',' - | sed 's/,/, /g'))"
check "$(is "[ \"\$(defaults read sh.wham.app monochrome)\" = 0 ] && [ \"\$(defaults read sh.wham.app compact)\" = 0 ] && ! defaults read sh.wham.app batteryLimit >/dev/null 2>&1")" \
  "and the options clicked are remembered"
stop
unset WHAM_CLICKS
guards=
# The menu's own rows over Wham's that say the same, plain, checked and gray:
# alike, their text where the menu's starts (where the screen shows).
: >"$work/out"
launch Rows
until_ "grep -q '^pairs\\|^pair Gray' \"$work/out\"" 10
pairs=$(grep '^pair' "$work/out" | paste -sd ';' - | sed 's/;/; /g')
if echo "$pairs" | grep -q 'not drawn'; then
  echo "skip the rows' pictures (${pairs})"
else
  check "$(is "grep '^pair ' \"$work/out\" | awk '{ n++; d = \$8 - \$12; if (!(\$3 ~ /^[0-9.]+\$/ && \$3 <= 0.02 && \$8 ~ /^[0-9.]+\$/ && \$12 ~ /^[0-9.]+\$/ && d >= -0.5 && d <= 0.5)) bad++ } END { exit !(n == 3 && !bad) }'")" \
    "Wham's rows look like the menu's own (${pairs:-no answer})"
fi
stop
: >"$work/out"

launch Menu
idle
# The menu, opened for real at launch, shows whole under the switch: a point
# too high and macOS hides its first line behind a scroll arrow.
menu=$(grep '^menu ' "$work/out" | tail -1)
check "$(is "[ \"$menu\" = 'menu whole' ]")" "the menu opens whole under the switch (${menu:-no answer})"
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
# A restart, a shutdown or a logout: macOS says so, then quits the app.
defaults delete sh.wham.app stayOnAfterRestart >/dev/null 2>&1 || true
launch "Turn On,Restart"
waitflag 1
until_ "! kill -0 $pid 2>/dev/null" 5
check "$(is "[ \"\$(flag)\" = 0 ] && ! defaults read sh.wham.app resumeAtLogin >/dev/null 2>&1 && ! defaults read sh.wham.app resumeBefore >/dev/null 2>&1")" \
  "a restart while on: sleep comes back, nothing saved for later"
stop
launch
sleep 2
check "$(is "[ \"\$(flag)\" = 0 ]")" "and it stays off after the restart, by default"
stop
defaults write sh.wham.app stayOnAfterRestart -bool YES
launch "Turn On,Restart"
waitflag 1
until_ "! kill -0 $pid 2>/dev/null" 5
check "$(is "[ \"\$(flag)\" = 0 ] && [ \"\$(defaults read sh.wham.app resumeAtLogin 2>/dev/null)\" = 1 ]")" \
  "with Stay On After Restart, a restart while on gives sleep back and remembers"
stop
: >"$work/out"
launch
waitflag 1 4
check "$(is "[ \"\$(flag)\" = 1 ] && ! defaults read sh.wham.app resumeAtLogin >/dev/null 2>&1 && grep -q '^toast MAC STAYS AWAKE: Back on after the restart$' \"$work/out\"")" \
  "and turns back on at the next launch, saying why ($(grep '^toast' "$work/out" | tail -1))"
stop
waitflag 0
launch "Turn On For/1 Hour,Restart"
waitflag 1
until_ "! kill -0 $pid 2>/dev/null" 5
stop
launch
waitflag 1 4
check "$(is "[ \"\$(flag)\" = 1 ] && [ \"\$(left)\" -ge 3580 ] && [ \"\$(left)\" -le 3600 ]")" "a timed session comes back with the same end"
stop
waitflag 0
defaults write sh.wham.app resumeAtLogin -date "2001-01-01 00:00:00 +0000"
launch
sleep 2
check "$(is "[ \"\$(flag)\" = 0 ] && ! defaults read sh.wham.app resumeAtLogin >/dev/null 2>&1")" "one whose end passed meanwhile stays off"
stop
defaults write sh.wham.app resumeAtLogin -bool YES
defaults write sh.wham.app stayOnAfterRestart -bool NO
launch
sleep 2
check "$(is "[ \"\$(flag)\" = 0 ] && ! defaults read sh.wham.app resumeAtLogin >/dev/null 2>&1")" "turned off since: stays off"
stop
defaults delete sh.wham.app stayOnAfterRestart >/dev/null 2>&1 || true
# The option itself, pressed in the menu, only where it is no one's setting.
if [ -n "${CI:-}" ]; then
  launch "Stay On After Restart"
  sleep 1.5
  check "$(is "[ \"\$(defaults read sh.wham.app stayOnAfterRestart 2>/dev/null)\" = 1 ]")" "Stay On After Restart in the menu turns the option on"
  stop
  defaults delete sh.wham.app stayOnAfterRestart >/dev/null 2>&1 || true
fi

# --- Appearance: each option on its own, then both, then back.
: >"$work/out"
launch "Look,Appearance/Compact,Look,Appearance/Monochrome,Look,Appearance/Compact,Look,Appearance/Monochrome,Look"
until_ "[ \"\$(grep -c '^look ' \"$work/out\")\" -ge 5 ]" 12
seen=$(grep '^look ' "$work/out" | sed 's/^look //' | tr '\n' ',' | sed 's/,$//')
check "$(is "[ \"$seen\" = 'color wide 50,color compact 23,monochrome compact 23,monochrome wide 50,color wide 50' ]")" \
  "Appearance: Compact takes 23 points instead of 50, Monochrome on its own or with it (${seen:-no answer})"
check "$(is "[ \"\$(defaults read sh.wham.app compact)\" = 0 ] && [ \"\$(defaults read sh.wham.app monochrome)\" = 0 ]")" "and they are remembered"
stop
defaults write sh.wham.app compact -bool YES
defaults write sh.wham.app monochrome -bool YES
: >"$work/out"
launch "Look,Switch"
waitflag 1
check "$(is "grep -q '^look monochrome compact 23$' \"$work/out\" && [ \"\$(flag)\" = 1 ]")" "opened with both, it starts with both, and its switch still works"
"$bin" off >/dev/null
stop
defaults delete sh.wham.app compact >/dev/null 2>&1 || true
defaults delete sh.wham.app monochrome >/dev/null 2>&1 || true

# --- The menu.
: >"$work/out"
launch "Turn On For/1 Hour,Status"
waitflag 1
until_ "[ -n \"\$(left)\" ]"
check "$(is "[ \"\$(flag)\" = 1 ] && [ \"\$(left)\" -ge 3590 ] && [ \"\$(left)\" -le 3600 ] && defaults read sh.wham.app onAt >/dev/null 2>&1")" \
  "Turn On For 1 Hour: on, ends in an hour, its start shared"
until_ "grep -q '^lengths ' \"$work/out\"" 4
status=$(grep '^status ' "$work/out" | tail -1)
lengths=$(grep '^lengths ' "$work/out" | tail -1)
check "$(is "echo \"$status\" | grep -q 'until .*(1 hr left)'")" "the menu says until when and what is left (${status:-no answer})"
check "$(is "echo \"$lengths\" | grep -Eq '^lengths 1 Hour.+[0-9]:[0-9][0-9].* \\| - \\| No Time Limit$'")" \
  "each length says when it would end, then No Time Limit (${lengths:-no answer})"
stop
waitflag 0
: >"$work/out"
launch "Turn On For/1 Hour,Stay Awake For/No Time Limit,Status"
until_ "grep -q '^lengths ' \"$work/out\"" 6
check "$(is "[ \"\$(flag)\" = 1 ] && [ -z \"\$(left)\" ] && ! defaults read sh.wham.app onAt >/dev/null 2>&1 && grep -q 'Until you turn it off' \"$work/out\"")" \
  "No Time Limit: stays on, with no end"
lengths=$(grep '^lengths ' "$work/out" | tail -1)
check "$(is "[ -n \"$lengths\" ] && ! echo \"$lengths\" | grep -q 'No Time Limit'")" "and No Time Limit is gone from the menu (${lengths:-no answer})"
stop
waitflag 0
: >"$work/out"
launch Status,Items
until_ "grep -q '^items ' \"$work/out\"" 5
lengths=$(grep '^lengths ' "$work/out" | tail -1)
check "$(is "[ -n \"$lengths\" ] && ! echo \"$lengths\" | grep -q 'No Time Limit'")" "off, the lengths have no No Time Limit"
items=$(grep '^items ' "$work/out" | tail -1)
check "$(is "echo \"$items\" | grep -q '| About Wham [^|]* | What.s New | Check for Updates | Made by Gwendall |'")" \
  "the menu has What's New and Check for Updates ($(echo "$items" | sed 's/.*| - | About/About/; s/ | - | Quit.*//'))"
stop
# The switch's own options, clicked in the open menu: it stays open, its
# first line says what the Mac does now, and the kernel's flag follows.
: >"$work/out"
export WHAM_CLICKS="Turn On,Stay Awake For/1 Hour,Stay Awake For/No Time Limit,Turn Off"
launch "Click Rows"
until_ "grep -q '^click Turn On:' \"$work/out\"" 10
waitflag 1
on=$(flag)
until_ "grep -q '^outside\\|^menu closed\\|^menu missing' \"$work/out\"" 30
waitflag 0
clicked=$(grep '^click ' "$work/out" | sed 's/^click //; s/, look [^,]*,/,/' | paste -sd ';' -)
check "$(is "echo \"$clicked\" | grep -Eq '^Turn On: menu open, Turn Off, status Mac stays awake, even with the lid closed;Stay Awake For/1 Hour: menu open, 1 Hour, status Mac stays awake until .*\\(1 hr left\\);Stay Awake For/No Time Limit: menu open, No Time Limit, status Mac stays awake, even with the lid closed;Turn Off: menu open, Turn On, status Mac sleeps as usual$' && grep -q '^outside: menu closed' \"$work/out\"")" \
  "Turn On, Stay Awake For, No Time Limit and Turn Off clicked in the open menu: it stays open and says so ($(echo "$clicked" | sed 's/;/; /g'))"
check "$(is "[ \"$on\" = 1 ] && [ \"\$(flag)\" = 0 ] && [ -z \"\$(left)\" ]")" "and the flag follows: on, then off with no end left"
stop
unset WHAM_CLICKS
# Five minutes before a timed session ends, a pill says so.
sudo -n /usr/bin/pmset -a disablesleep 1
defaults write sh.wham.app onAt -date "$(date -u -v-1H '+%Y-%m-%d %H:%M:%S +0000')"
defaults write sh.wham.app offAt -date "$(date -u -v+5M -v+3S '+%Y-%m-%d %H:%M:%S +0000')"
launch
until_ "grep -q '^toast 5 MINUTES LEFT' \"$work/out\"" 6
warned=$(grep '^toast 5 MINUTES LEFT' "$work/out" | tail -1)
check "$(is "[ -n \"$warned\" ] && [ \"\$(flag)\" = 1 ]")" "five minutes before the end, a pill says so, still on (${warned:-none})"
"$bin" off >/dev/null
stop
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
# `date` drops the fraction of a second: the end is 4 to 5 s away.
defaults write sh.wham.app offAt -date "$(date -u -v+5S '+%Y-%m-%d %H:%M:%S +0000')"
launch
sleep 1
check "$(is "[ \"\$(flag)\" = 1 ]")" "one still running when the app opens goes on"
waitflag 0 8
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
# The battery limit, from the menu: raised over the charge, it ends the
# session at once; lowered, it lets the Mac stay awake further down.
echo "battery 15" >"$fake"
launch "Switch,Battery Limit/20%"
until_ "grep -q 'Battery at 15%' \"$work/out\"" 6
waitflag 0
check "$(is "[ \"\$(flag)\" = 0 ] && [ \"\$(defaults read sh.wham.app batteryLimit)\" = 20 ] && grep -q '^toast MAC CAN SLEEP: Battery at 15%' \"$work/out\"")" \
  "Battery Limit 20% at 15% on battery: the app gives sleep back at once"
WHAM_FAKE_POWER=$fake "$bin" on >/dev/null 2>"$work/err" && code=0 || code=$?
check "$(is "[ $code = 1 ] && grep -q 'battery at 15%, plug in first' \"$work/err\" && \"$bin\" help | grep -q 'at 20% or less'")" \
  "wham on follows the limit, and wham help says it"
stop
echo "battery 8" >"$fake"
launch "Battery Limit/5%,Switch"
waitflag 1 4
check "$(is "[ \"\$(flag)\" = 1 ] && [ \"\$(defaults read sh.wham.app batteryLimit)\" = 5 ]")" "Battery Limit 5%: stays awake at 8%"
stop
waitflag 0
launch "Battery Limit/10%"
sleep 1.5
check "$(is "! defaults read sh.wham.app batteryLimit >/dev/null 2>&1")" "back to 10%, the default, nothing stored"
stop
guards=
echo "ac 100" >"$fake"

# The real heat signal: macOS's thermal pressure level, which its thermal daemon
# posts and root can raise (on CI). 3 is trapping, where Wham lets go.
pressure=com.apple.system.thermalpressurelevel
heat() { sudo -n notifyutil -s "$pressure" "$1" && sudo -n notifyutil -p "$pressure"; }
if [ -n "${CI:-}" ] && heat 0 >/dev/null 2>&1; then
  launch
  "$bin" on >/dev/null
  heat 3
  if [ "$(notifyutil -g "$pressure" | awk '{ print $2 }')" = 3 ]; then
    waitflag 0 4
    check "$(is "[ \"\$(flag)\" = 0 ]")" "the Mac's real thermal pressure at trapping: the app gives sleep back"
    "$bin" on >/dev/null 2>&1 && code=0 || code=$?
    check "$(is "[ $code = 1 ] && [ \"\$(flag)\" = 0 ]")" "and wham on refuses until it cools"
    heat 0
    "$bin" on >/dev/null 2>&1 && code=0 || code=$?
    check "$(is "[ $code = 0 ] && [ \"\$(flag)\" = 1 ]")" "cooled down: it turns on again"
  else
    echo "skip the real heat (macOS kept its thermal pressure level)"
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
