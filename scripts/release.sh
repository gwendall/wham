#!/bin/sh
# Publishes a Wham release, from a clean main:
#
#   scripts/release.sh 1.1.0
#
# Tests, stamps the version, builds and signs the universal app, has Apple
# notarize the zip and the disk image, tags, publishes the GitHub release,
# updates the Homebrew cask and prints the npm command to run last.
#
# Needs the Developer ID certificate in the keychain and a notarytool profile:
#   xcrun notarytool store-credentials wham-notary --apple-id <apple id> --team-id NQCA86NEA3
set -eu
cd "$(dirname "$0")/.."

say() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf 'release: %s\n' "$*" >&2; exit 1; }

version=${1:-}
[ -n "$version" ] || fail "usage: scripts/release.sh <version>"
version=${version#v}
tag="v$version"
identity="Developer ID Application: The Atelier (NQCA86NEA3)"
profile=${NOTARY_PROFILE:-wham-notary}
repo=gwendall/wham
tap=gwendall/homebrew-tap

[ "$(git branch --show-current)" = main ] || fail "release from main"
[ -z "$(git status --porcelain)" ] || fail "commit or stash your changes first"
git fetch -q origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "main is not in sync with origin/main"
! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || fail "$tag already exists"
security find-identity -v -p codesigning | grep -q "$identity" || fail "no '$identity' in the keychain"
xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1 ||
  fail "no notarytool profile '$profile' (see the top of this script)"

say "Testing"
scripts/test.sh >/dev/null

say "Stamping $version"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" app/Info.plist
sed -i '' "s/\"version\": \"[^\"]*\"/\"version\": \"$version\"/" npm/package.json
if [ -n "$(git status --porcelain)" ]; then
  git commit -qam "Release $tag"
fi

say "Building"
VERSION=$version SIGN=$identity scripts/build.sh

notarize() {
  xcrun notarytool submit "$1" --keychain-profile "$profile" --wait --timeout 30m | tee build/notary.log
  grep -q "status: Accepted" build/notary.log || fail "Apple did not accept $1 (see build/notary.log)"
}

say "Notarizing the app"
rm -f build/Wham.zip
ditto -c -k --keepParent build/Wham.app build/Wham.zip
notarize build/Wham.zip
xcrun stapler staple build/Wham.app
# The zip again, now with the ticket stapled inside the app.
rm -f build/Wham.zip
ditto -c -k --keepParent build/Wham.app build/Wham.zip
spctl --assess --type execute --verbose build/Wham.app

say "Making the disk image"
[ -x build/.venv/bin/dmgbuild ] || { python3 -m venv build/.venv && build/.venv/bin/pip install -q dmgbuild; }
mkdir -p build/dmg
swift scripts/dmg-background.swift app/Resources/Silkscreen-Regular.ttf build/dmg
tiffutil -cathidpicheck build/dmg/background.png build/dmg/background@2x.png -out build/dmg/background.tiff
rm -f build/Wham.dmg
build/.venv/bin/dmgbuild -s scripts/dmg.py -D app=build/Wham.app -D background=build/dmg/background.tiff Wham build/Wham.dmg
codesign --force --timestamp --sign "$identity" build/Wham.dmg
notarize build/Wham.dmg
xcrun stapler staple build/Wham.dmg
spctl --assess --type open --context context:primary-signature --verbose build/Wham.dmg

(cd build && shasum -a 256 Wham.zip Wham.dmg > checksums.txt)
zip_sha=$(awk '/Wham.zip/ { print $1 }' build/checksums.txt)

say "Publishing $tag"
git tag -a "$tag" -m "Wham $version"
git push -q origin main "$tag"
gh release create "$tag" build/Wham.zip build/Wham.dmg build/checksums.txt \
  --repo "$repo" --title "Wham $version" --generate-notes

say "Updating the Homebrew cask"
rm -rf build/tap
gh repo clone "$tap" build/tap -- -q
mkdir -p build/tap/Casks
sed -e "s/@VERSION@/$version/" -e "s/@SHA256@/$zip_sha/" packaging/wham.rb > build/tap/Casks/wham.rb
git -C build/tap add Casks/wham.rb
git -C build/tap commit -qm "wham $version"
git -C build/tap push -q

say "Done. Wham $version is out:"
echo "  https://github.com/$repo/releases/tag/$tag"
echo "  brew upgrade --cask gwendall/tap/wham"
echo "Last step, publish the npm package (asks for your one-time password):"
echo "  cd npm && npm publish"
