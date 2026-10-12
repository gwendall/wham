#!/bin/sh
# Starts a release: tags main and pushes the tag.
#
#   scripts/release.sh 1.2.0
#
# GitHub Actions does the rest (.github/workflows/release.yml): builds and
# signs the app, has Apple notarize it, makes the disk image, publishes the
# GitHub release and updates the Homebrew cask. The version comes from the tag.
set -eu
cd "$(dirname "$0")/.."

fail() { printf 'release: %s\n' "$*" >&2; exit 1; }

version=${1:-}
[ -n "$version" ] || fail "usage: scripts/release.sh <version>"
tag="v${version#v}"

[ "$(git branch --show-current)" = main ] || fail "release from main"
[ -z "$(git status --porcelain)" ] || fail "commit or stash your changes first"
git fetch -q origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "main is not in sync with origin/main"
! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || fail "$tag already exists"

scripts/test.sh >/dev/null
git tag -a "$tag" -m "Wham ${tag#v}"
git push -q origin "$tag"
echo "Pushed $tag. Follow the release with: gh run watch"
