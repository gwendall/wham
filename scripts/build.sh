#!/bin/sh
# Builds build/Wham.app: one universal binary (Apple silicon and Intel), the
# pixel font, the icon, signed.
#
#   scripts/build.sh                  sign with this Mac's Developer ID, or ad hoc without one
#   SIGN=- scripts/build.sh           sign ad hoc (enough to run it on this Mac)
#   VERSION=1.2.0 scripts/build.sh    stamp that version
set -eu
cd "$(dirname "$0")/.."

APP=build/Wham.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp app/Info.plist "$APP/Contents/Info.plist"
cp app/Resources/* "$APP/Contents/Resources/"

plist="$APP/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION#v}" "$plist"
fi
build_number=$(git rev-list --count HEAD 2>/dev/null || echo 1)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$plist"

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos11.0" -o "build/Wham-$arch" app/Sources/*.swift
done
lipo -create -output "$APP/Contents/MacOS/Wham" build/Wham-arm64 build/Wham-x86_64
rm -f build/Wham-arm64 build/Wham-x86_64

identity=${SIGN:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}
if [ -z "$identity" ] || [ "$identity" = "-" ]; then
  codesign --force --sign - "$APP"
  echo "built $APP (signed ad hoc: runs on this Mac only)"
else
  # Hardened runtime and a secure timestamp: what notarization asks for.
  # Apple's timestamp server has bad minutes, so try three times.
  for attempt in 1 2 3; do
    codesign --force --options runtime --timestamp --sign "$identity" "$APP" && break
    [ "$attempt" = 3 ] && exit 1
    echo "signing failed, retrying in 10 s"
    sleep 10
  done
  echo "built $APP (signed by $identity)"
fi
codesign --verify --deep --strict "$APP"
