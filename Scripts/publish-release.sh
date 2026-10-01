#!/bin/bash
#
# publish-release.sh — publish a built release to GitHub without ever exposing
# a "latest" release that lacks its appcast.
#
#   Scripts/publish-release.sh <version>
#
# Expects, from `make release-local`:
#   build/Punctual-<version>.dmg, build/Punctual-<version>.dmg.sha256,
#   build/appcast.xml, build/release-notes-<version>.md
# and the tag v<version> already pushed (on the merge commit in master).
#
# 1. Creates the release as a DRAFT with all three assets.
# 2. Checks every asset arrived with the local file's exact size.
# 3. Only then publishes it and marks it latest.
# 4. Smoke test through the public URLs a user's Mac uses: the latest appcast
#    must be byte-identical to build/appcast.xml, and the dmg it points at must
#    match the local sha256 and pass Gatekeeper.
#
# Installed copies check releases/latest/download/appcast.xml, so a latest
# release without that file would break every update check.

set -euo pipefail

VERSION="${1:?usage: $0 <version>}"
REPO="Chykalophia/Punctual"
TAG="v$VERSION"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DMG="build/Punctual-$VERSION.dmg"
SHA="$DMG.sha256"
APPCAST="build/appcast.xml"
NOTES="build/release-notes-$VERSION.md"
fail() { echo "error: $*" >&2; exit 1; }

for f in "$DMG" "$SHA" "$APPCAST" "$NOTES"; do [ -f "$f" ] || fail "missing $f"; done
grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$APPCAST" \
    || fail "$APPCAST does not describe $VERSION"
(cd build && shasum -a 256 -c "$(basename "$SHA")" >/dev/null) || fail "$SHA does not match $DMG"
ENCLOSURE="https://github.com/$REPO/releases/download/$TAG/Punctual-$VERSION.dmg"
grep -q "<enclosure url=\"$ENCLOSURE\" length=\"$(stat -f %z "$DMG")\"" "$APPCAST" \
    || fail "$APPCAST does not point at $ENCLOSURE with this dmg's exact length"
SPARKLE_BIN="${SPARKLE_BIN:-build/SourcePackages/artifacts/sparkle/Sparkle/bin}"
"$SPARKLE_BIN/sign_update" --account "${SPARKLE_ACCOUNT:-punctual}" --verify "$APPCAST" >/dev/null 2>&1 \
    || fail "$APPCAST is not validly signed (run make appcast)"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || fail "tag $TAG does not exist locally"
[ "$(git rev-parse "$TAG^{commit}")" = "$(git ls-remote origin "refs/tags/$TAG^{}" | cut -f1)" ] \
    || fail "local tag $TAG differs from (or is missing on) origin"
gh release view "$TAG" -R "$REPO" >/dev/null 2>&1 && fail "a release for $TAG already exists"

echo "==> Creating draft release $TAG"
gh release create "$TAG" -R "$REPO" --draft --verify-tag \
    --title "Punctual $VERSION" --notes-file "$NOTES" \
    "$DMG" "$SHA" "$APPCAST"

echo "==> Checking uploaded assets"
for f in "$DMG" "$SHA" "$APPCAST"; do
    name="$(basename "$f")"
    local_size="$(stat -f %z "$f")"
    remote_size="$(gh release view "$TAG" -R "$REPO" --json assets \
        --jq ".assets[] | select(.name == \"$name\") | .size")"
    [ "$remote_size" = "$local_size" ] || fail "$name: uploaded $remote_size bytes, local $local_size"
    echo "    $name ok ($local_size bytes)"
done

echo "==> Publishing $TAG as latest"
gh release edit "$TAG" -R "$REPO" --draft=false --latest >/dev/null

echo "==> Smoke test through the public latest URLs"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for attempt in 1 2 3 4 5 6; do
    if curl -fsSL -o "$TMP/appcast.xml" "https://github.com/$REPO/releases/latest/download/appcast.xml" \
        && cmp -s "$TMP/appcast.xml" "$APPCAST"; then
        break
    fi
    [ "$attempt" -eq 6 ] && fail "public latest appcast does not match build/appcast.xml"
    sleep 10
done
echo "    latest appcast matches"
# Through the enclosure URL in the feed: exactly what Sparkle downloads.
curl -fsSL -o "$TMP/Punctual-$VERSION.dmg" "$ENCLOSURE"
cp "$SHA" "$TMP/"
(cd "$TMP" && shasum -a 256 -c "$(basename "$SHA")" >/dev/null) || fail "public dmg sha256 mismatch"
xattr -w com.apple.quarantine "0081;$(printf %x "$(date +%s)");Safari;" "$TMP/Punctual-$VERSION.dmg"
spctl -a -t open --context context:primary-signature "$TMP/Punctual-$VERSION.dmg" 2>/dev/null \
    || fail "Gatekeeper rejects the public dmg"
echo "    public dmg matches sha256 and passes Gatekeeper"
echo "==> Published: https://github.com/$REPO/releases/tag/$TAG"
