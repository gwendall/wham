#!/bin/sh
# Draws the menu bar switch in each look (Color, Monochrome, Compact, both),
# on a light and a dark menu bar, into a PNG; the pink line under each is the
# status item's width.
#
#   scripts/sheet.sh [out.png]           off, on, and on with half a timed session left
#   scripts/sheet.sh --film [out.png]    turning on, a frame every 40 ms
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -O -swift-version 5 -parse-as-library -o build/sheet scripts/sheet.swift app/Sources/SwitchView.swift app/Sources/Pixels.swift
build/sheet "$@"
