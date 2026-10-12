#!/bin/sh
# Checks that the Mac stays awake with the lid closed:
#
#   scripts/lid-test.sh [seconds]    (default 180)
#
# Prints a heartbeat every 2 s. A sleeping Mac runs nothing, so a gap in the
# heartbeat means it slept. The lid sensor (AppleClamshellState) proves the lid
# was really closed. Turn Wham on, unplug any external display, run this, close
# the lid for at least two minutes, then open it.
duration=${1:-180}
start=$(date +%s)
end=$((start + duration))
prev=$start
gaps=0
closed=0
lid() { ioreg -rd1 -c IOPMrootDomain | grep -q '"AppleClamshellState" = Yes' && echo 1 || echo 0; }
echo "Testing for ${duration} s: close the lid for at least 2 minutes meanwhile, then open it."
while [ "$(date +%s)" -lt "$end" ]; do
  sleep 2
  now=$(date +%s)
  if [ $((now - prev)) -gt 8 ]; then
    echo "GAP of $((now - prev)) s, back at $(date -r "$now" +%T): the Mac slept"
    gaps=$((gaps + 1))
  fi
  [ "$(lid)" = 1 ] && closed=$((closed + now - prev))
  prev=$now
done
since=$(date -r "$start" '+%Y-%m-%d %H:%M:%S')
echo "--- sleep events since $since:"
pmset -g log | awk -v s="$since" '$1" "$2 >= s && ($4 == "Sleep" || $4 == "Wake" || $4 == "DarkWake") { print; n++ } END { if (!n) print "(none)" }'
echo "Lid closed for about ${closed} s (measured awake)."
if [ "$gaps" -gt 0 ]; then echo "RESULT: $gaps gap(s), the Mac slept."
elif [ "$closed" -lt 60 ]; then echo "RESULT: inconclusive, the lid was not closed long enough."
else echo "RESULT: lid closed ${closed} s without a single gap, the Mac stayed awake."; fi
