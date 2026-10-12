#!/bin/sh
# Runs Wham's checks: the app's pure sources with tests/main.swift, then the
# shell scripts through `sh -n` and shellcheck (when installed).
set -eu
cd "$(dirname "$0")/.."
mkdir -p build

swiftc -swift-version 5 -o build/wham-tests \
  tests/main.swift app/Sources/Chime.swift app/Sources/Sleep.swift app/Sources/Session.swift app/Sources/CLI.swift \
  app/Sources/Pixels.swift app/Sources/Update.swift
build/wham-tests

for script in install.sh uninstall.sh scripts/*.sh; do
  [ -f "$script" ] || continue
  sh -n "$script"
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -s sh install.sh uninstall.sh scripts/*.sh
  echo "shellcheck clean"
fi
