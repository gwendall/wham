#!/bin/sh
# Builds the release files in build/: Wham.zip, Wham.dmg and checksums.txt,
# the app and the disk image signed with Developer ID, notarized and stapled.
#
#   scripts/package.sh 1.2.0
#
# The release workflow runs it on every tag. It needs the Developer ID
# certificate in a keychain and an App Store Connect API key for notarytool:
#   NOTARY_KEY      path to the .p8 key
#   NOTARY_KEY_ID   its key ID
#   NOTARY_ISSUER   its issuer ID
set -eu
cd "$(dirname "$0")/.."

version=${1:?usage: scripts/package.sh <version>}
identity="Developer ID Application: The Atelier (NQCA86NEA3)"
: "${NOTARY_KEY:?}" "${NOTARY_KEY_ID:?}" "${NOTARY_ISSUER:?}"

notarize() {
  xcrun notarytool submit "$1" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" \
    --wait --timeout 30m | tee build/notary.log
  grep -q "status: Accepted" build/notary.log || { echo "Apple did not accept $1" >&2; exit 1; }
}

# Fetches the ticket from Apple's CDN, which sometimes drops the connection.
staple() {
  for attempt in 1 2 3 4 5; do
    xcrun stapler staple "$1" && return
    echo "stapling failed (attempt $attempt), retrying in 20 s"
    sleep 20
  done
  exit 1
}

VERSION=$version SIGN=$identity scripts/build.sh

echo "Notarizing the app"
rm -f build/Wham.zip
ditto -c -k --keepParent build/Wham.app build/Wham.zip
notarize build/Wham.zip
staple build/Wham.app
# The zip again, now with the ticket stapled inside the app.
rm -f build/Wham.zip
ditto -c -k --keepParent build/Wham.app build/Wham.zip
spctl --assess --type execute --verbose build/Wham.app

echo "Making the disk image"
[ -x build/.venv/bin/dmgbuild ] || { python3 -m venv build/.venv && build/.venv/bin/pip install -q dmgbuild==1.6.7; }
mkdir -p build/dmg
swift scripts/dmg-background.swift app/Resources/Silkscreen-Regular.ttf build/dmg
tiffutil -cathidpicheck build/dmg/background.png build/dmg/background@2x.png -out build/dmg/background.tiff
rm -f build/Wham.dmg
build/.venv/bin/dmgbuild -s scripts/dmg.py -D app=build/Wham.app -D background=build/dmg/background.tiff Wham build/Wham.dmg
codesign --force --timestamp --sign "$identity" build/Wham.dmg
notarize build/Wham.dmg
staple build/Wham.dmg
spctl --assess --type open --context context:primary-signature --verbose build/Wham.dmg

(cd build && shasum -a 256 Wham.zip Wham.dmg > checksums.txt)
cat build/checksums.txt
