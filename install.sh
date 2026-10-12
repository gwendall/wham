#!/bin/sh
# Wham installer.
#
#   curl -fsSL wham.sh | sh
#
# Downloads the latest Wham.app from GitHub, checks that it is signed by its
# developer, puts it in /Applications (or ~/Applications), links the `wham`
# command and opens the app. Run it again to update.
#
# Options, as environment variables:
#   WHAM_VERSION=1.0.0   install that release instead of the latest
#   WHAM_ZIP=./Wham.zip  install from a local zip (for development)
set -eu

REPO="gwendall/wham"
TEAM_ID="NQCA86NEA3" # the Developer ID that signs every release

if [ -t 1 ]; then
  bold=$(printf '\033[1m'); pink=$(printf '\033[38;5;213m'); dim=$(printf '\033[2m'); reset=$(printf '\033[0m')
else
  bold=""; pink=""; dim=""; reset=""
fi
say() { printf '%s\n' "$*"; }
fail() { printf '%s\n' "${bold}wham:${reset} $*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Wham is a macOS app."
[ "$(id -u)" != 0 ] || fail "run this as yourself, without sudo: curl -fsSL wham.sh | sh"
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 11 ] || fail "Wham needs macOS 11 Big Sur or later (this Mac runs $(sw_vers -productVersion))."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ -n "${WHAM_ZIP:-}" ]; then
  cp "$WHAM_ZIP" "$tmp/Wham.zip"
else
  if [ -n "${WHAM_VERSION:-}" ]; then
    url="https://github.com/$REPO/releases/download/v${WHAM_VERSION#v}/Wham.zip"
  else
    url="https://github.com/$REPO/releases/latest/download/Wham.zip"
  fi
  say "${pink}${bold}wham${reset} ${dim}downloading $url${reset}"
  curl -fsSL "$url" -o "$tmp/Wham.zip" || fail "could not download $url"
fi

ditto -x -k "$tmp/Wham.zip" "$tmp" || fail "the download is not a valid zip"
app="$tmp/Wham.app"
[ -d "$app" ] || fail "the zip holds no Wham.app"
codesign --verify --deep --strict "$app" 2>/dev/null || fail "Wham.app's signature does not verify, not installing it"
team=$(codesign -dv "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
[ "$team" = "$TEAM_ID" ] || fail "Wham.app is signed by '$team', not by Wham's developer ($TEAM_ID), not installing it"

if [ -w /Applications ]; then dest=/Applications; else dest="$HOME/Applications"; mkdir -p "$dest"; fi

# Stop a running copy without its quit handler, so the sleep setting survives the update.
killall Wham 2>/dev/null || true
rm -rf "$dest/Wham.app"
ditto "$app" "$dest/Wham.app"

# The `wham` command is the app's own binary.
bin="$dest/Wham.app/Contents/MacOS/Wham"
if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
  linkdir=/usr/local/bin
else
  linkdir="$HOME/.local/bin"
  mkdir -p "$linkdir"
fi
ln -sf "$bin" "$linkdir/wham"

open "$dest/Wham.app"

version=$(defaults read "$dest/Wham.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")
say ""
say "  ${pink}${bold}WHAM ${version}${reset} is in your menu bar, at $dest/Wham.app"
say "  Click its switch: your Mac stays awake, even with the lid closed."
say ""
say "  In a terminal: ${bold}wham on${reset}, ${bold}wham off${reset}, ${bold}wham status${reset}"
case ":$PATH:" in
  *":$linkdir:"*) ;;
  *)
    say "  ${dim}To use the wham command, add $linkdir to your PATH:${reset}"
    case "${SHELL:-}" in
      */bash) rc="$HOME/.bash_profile" ;;
      */fish) rc="" ;;
      *) rc="$HOME/.zshrc" ;;
    esac
    if [ -n "$rc" ]; then
      say "    echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> $rc && exec \$SHELL"
    else
      say "    fish_add_path ~/.local/bin"
    fi
    ;;
esac
say "  Uninstall: curl -fsSL wham.sh/uninstall | sh"
say ""
