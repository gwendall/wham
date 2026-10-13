#!/bin/sh
# Updates Wham for real, on this Mac, from a local stand-in for GitHub:
#
#   scripts/update-test.sh
#
# - a 1.0.99 copy finds 9.9.9, swaps it in where it stands and reopens as
#   9.9.9, with the kernel's sleep flag left as it was: when on, the old copy's
#   watchdog stands down and the new copy puts out its own
# - a 9.9.9 not signed by Wham's developer is downloaded and refused
# - with Update Automatically off, 1.0.99 downloads nothing and its menu offers
#   Update to Wham 9.9.9, which installs it
# - Check for Updates says when the copy is the latest, and when GitHub does
#   not answer
#
# Needs this Mac's Developer ID certificate (the updater only takes Wham signed
# by its developer). A second switch shows in the menu bar for about a minute,
# and build/Wham.app is left as the 9.9.9 test build.
set -eu
cd "$(dirname "$0")/.."
failures=0
check() {
  if [ "$1" = 1 ]; then echo "ok   $2"; else echo "FAIL $2"; failures=$((failures + 1)); fi
}
is() { if eval "$1"; then echo 1; else echo 0; fi; }
flag() { ioreg -rd1 -c IOPMrootDomain | awk -F' = ' '/"SleepDisabled"/ { print ($2 == "Yes") ? 1 : 0 }'; }
version() { /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist"; }
# Only the copies this test opened: they run from its own folder.
running() { pgrep -f "$app/Contents/MacOS/Wham" || true; }

work=$(mktemp -d)
app="$work/Applications/Wham.app"
served="$work/github/releases/download/v9.9.9"
mkdir -p "$work/Applications" "$served"
server=
start=$(flag)
# Each copy records its version, which the user's own Wham reads: put back after.
last=$(defaults read sh.wham.app lastVersion 2>/dev/null || true)
# Killing a copy while on sets off its watchdog: the flag is put back after.
restore() {
  sleep 1
  [ "$(flag)" = "$start" ] || sudo -n /usr/bin/pmset -a disablesleep "$start" >/dev/null 2>&1 \
    || echo "note: could not put SleepDisabled back to $start"
}
cleanup() {
  for pid in $(running); do kill "$pid" 2>/dev/null || true; done
  [ -n "$server" ] && kill "$server" 2>/dev/null || true
  restore
  if [ -n "$last" ]; then defaults write sh.wham.app lastVersion "$last"; else defaults delete sh.wham.app lastVersion >/dev/null 2>&1 || true; fi
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

build() {
  VERSION=$1 scripts/build.sh >/dev/null
  codesign -dvv build/Wham.app 2>&1 | grep -q "^Authority=Developer ID Application" \
    || { echo "no Developer ID certificate in the keychain: the updater would refuse every build" >&2; exit 1; }
}
build 1.0.99
ditto build/Wham.app "$work/old.app"
build 9.9.9
ditto -c -k --keepParent build/Wham.app "$work/genuine.zip"
ditto build/Wham.app "$work/stranger/Wham.app"
codesign --force --sign - "$work/stranger/Wham.app" 2>/dev/null
ditto -c -k --keepParent "$work/stranger/Wham.app" "$work/stranger.zip"

# GitHub answers /releases/latest with a redirect to the latest tag, here the
# one in github/latest. Each request is appended to $work/requests, so emptying
# it starts the list over.
echo v9.9.9 >"$work/github/latest"
python3 -I -c '
import http.server, os, sys
class GitHub(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=sys.argv[1], **kwargs)
    def do_GET(self):
        print(self.path, file=sys.stderr, flush=True)
        if self.path == "/releases/latest":
            with open(os.path.join(sys.argv[1], "latest")) as latest:
                tag = latest.read().strip()
            self.send_response(302)
            self.send_header("Location", "/releases/tag/" + tag)
            self.end_headers()
        else:
            super().do_GET()
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(("127.0.0.1", 0), GitHub)
print(server.server_port, flush=True)
server.serve_forever()
' "$work/github" >"$work/port" 2>>"$work/requests" &
server=$!
for _ in $(seq 50); do [ -s "$work/port" ] && break; sleep 0.1; done
base="http://127.0.0.1:$(cat "$work/port")"

# Opens the 1.0.99 copy, which looks for an update a second after launch.
launch() {
  rm -rf "$app"
  ditto "$work/old.app" "$app"
  : >"$work/requests"
  open -n "$app" --args -updateBase "$base" -updateDelay 1
  for _ in $(seq 50); do [ -n "$(running)" ] && break; sleep 0.1; done
  old=$(running)
}
downloaded() { grep -q "^/releases/download/v9.9.9/Wham.zip" "$work/requests"; }
# Runs a fresh 1.0.99 copy from its binary, so its output lands in $work/out,
# pressing the WHAM_PRESS steps $1, with the defaults that follow.
run() {
  steps=$1
  shift
  rm -rf "$app"
  ditto "$work/old.app" "$app"
  : >"$work/requests"
  : >"$work/out"
  WHAM_PRESS=$steps "$app/Contents/MacOS/Wham" -muted YES "$@" >>"$work/out" 2>&1 &
  old=$!
}
said() { grep -q "$1" "$work/out"; }
# Stops whatever this test opened, and waits for it to be gone.
quit() {
  for pid in $(running); do kill "$pid" 2>/dev/null || true; done
  for _ in $(seq 50); do [ -z "$(running)" ] && break; sleep 0.1; done
  restore
}

cp "$work/stranger.zip" "$served/Wham.zip"
launch
for _ in $(seq 300); do downloaded && break; sleep 0.1; done
check "$(is downloaded)" "1.0.99 asks for the latest release and downloads 9.9.9"
sleep 5
check "$(is "[ \"\$(version)\" = 1.0.99 ] && [ \"\$(running)\" = \"$old\" ]")" \
  "a 9.9.9 not signed by Wham's developer is refused: 1.0.99 stays, still running"
kill "$old"
for _ in $(seq 50); do [ -z "$(running)" ] && break; sleep 0.1; done
restore

cp "$work/genuine.zip" "$served/Wham.zip"
before=$(flag)
launch
for _ in $(seq 600); do
  now=$(running)
  [ "$(version)" = 9.9.9 ] && [ -n "$now" ] && [ "$now" != "$old" ] && break
  sleep 0.1
done
check "$(is "[ \"\$(version)\" = 9.9.9 ]")" "9.9.9 takes the place of 1.0.99"
check "$(is "codesign --verify --deep --strict \"$app\" 2>/dev/null")" "the new copy's signature holds"
check "$(is "[ \"\$(\"$app/Contents/MacOS/Wham\" version)\" = 'wham 9.9.9' ]")" "the new copy runs: wham 9.9.9"
check "$(is "! kill -0 $old 2>/dev/null")" "the old copy is gone"
check "$(is "[ -n \"\$(running)\" ]")" "the new copy opened in its place ($(running | tr '\n' ' '))"
check "$(is "[ \"\$(flag)\" = $before ]")" "the sleep flag is as it was ($before)"
sleep 2
check "$(is "[ \"\$(flag)\" = $before ]")" "and stays so"
if [ "$before" = 1 ]; then
  check "$(is "pgrep -P \"\$(running | head -1)\" -f stand-down >/dev/null")" "the new copy has its watchdog out"
fi

quit

# Update Automatically off: it still asks, downloads nothing, and offers the
# new version in its menu; a click on it installs it anyway.
run "Pause,Pause,Items,Update to Wham 9.9.9" -updateBase "$base" -updateDelay 1 -noAutoUpdate YES
for _ in $(seq 100); do said "^items" && break; sleep 0.1; done
check "$(is "grep -q '^/releases/latest' \"$work/requests\" && ! downloaded")" "Update Automatically off: 1.0.99 asks for the latest, downloads nothing"
check "$(is "said '| Update to Wham 9.9.9 |'")" "and its menu offers it ($(sed -n 's/^items //p' "$work/out" | tr '|' '\n' | grep -i -E 'update|new' | tr '\n' '|'))"
for _ in $(seq 600); do
  now=$(running)
  [ "$(version)" = 9.9.9 ] && [ -n "$now" ] && [ "$now" != "$old" ] && break
  sleep 0.1
done
check "$(is "said 'toast UPDATING: To Wham 9.9.9, back in a moment'")" "a click on it says it is updating"
check "$(is "[ \"\$(version)\" = 9.9.9 ] && [ -n \"\$(running)\" ] && ! kill -0 $old 2>/dev/null")" "and installs 9.9.9, which opens in its place"
for _ in $(seq 50); do [ "$(defaults read sh.wham.app lastVersion 2>/dev/null)" = 9.9.9 ] && break; sleep 0.1; done
check "$(is "[ \"\$(defaults read sh.wham.app lastVersion 2>/dev/null)\" = 9.9.9 ]")" "9.9.9 knows it was just updated, and says so"
quit

# Check for Updates on the latest version, then with GitHub out of reach.
echo v1.0.99 >"$work/github/latest"
run "Check for Updates" -updateBase "$base" -updateDelay 3600
for _ in $(seq 100); do said "^toast UP" && break; sleep 0.1; done
check "$(is "said 'toast UP TO DATE: Wham 1.0.99 is the latest' && ! downloaded")" "Check for Updates on the latest: says so"
quit
run "Check for Updates" -updateBase "http://127.0.0.1:9" -updateDelay 3600
for _ in $(seq 100); do said "^toast CAN" && break; sleep 0.1; done
check "$(is "said \"toast CAN'T CHECK: GitHub did not answer, try again later\"")" "Check for Updates with GitHub out of reach: says so"
quit

if [ "$failures" != 0 ]; then echo "$failures failed"; exit 1; fi
echo "all checks passed"
