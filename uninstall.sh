#!/bin/sh
# Wham uninstaller.
#
#   curl -fsSL wham.sh/uninstall | sh
#
# Quits Wham (which gives sleep back), removes the app, the `wham` command,
# its settings and the sudoers rule it installed. Removing the rule asks for
# your password, since it lives in /etc.
set -eu

say() { printf '%s\n' "$*"; }

if pgrep -x Wham >/dev/null 2>&1; then
  osascript -e 'tell application id "sh.wham.app" to quit' >/dev/null 2>&1 || killall Wham 2>/dev/null || true
  sleep 1
fi
# In case Wham could not give sleep back itself (the rule allows this without a password).
sudo -n /usr/bin/pmset -a disablesleep 0 >/dev/null 2>&1 || true

for app in /Applications/Wham.app "$HOME/Applications/Wham.app"; do
  [ -d "$app" ] && rm -rf "$app" && say "removed $app"
done
for link in /usr/local/bin/wham "$HOME/.local/bin/wham"; do
  [ -L "$link" ] && rm -f "$link" && say "removed $link"
done
defaults delete sh.wham.app >/dev/null 2>&1 || true
# The login item on macOS 11 and 12 (from 13 on, it goes with the app).
rm -f "$HOME/Library/LaunchAgents/sh.wham.app.plist"

if [ -e /private/etc/sudoers.d/wham ]; then
  say "Removing the sudoers rule (/private/etc/sudoers.d/wham) needs your password:"
  sudo rm -f /private/etc/sudoers.d/wham && say "removed /private/etc/sudoers.d/wham"
fi

if [ "$(pmset -g | awk '/SleepDisabled/ { print $2 }')" = "1" ]; then
  say "Sleep is still disabled. Run: sudo pmset -a disablesleep 0"
fi
say "Wham is uninstalled. Your Mac sleeps as usual."
