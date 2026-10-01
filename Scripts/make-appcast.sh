#!/bin/bash
#
# make-appcast.sh — write and sign the Sparkle appcast.xml for one release.
#
#   Scripts/make-appcast.sh <notarized.dmg> <out appcast.xml> [release-notes.md]
#
# The appcast is uploaded as an asset of the GitHub release, next to the dmg.
# Shipped apps read https://github.com/Chykalophia/Punctual/releases/latest/download/appcast.xml,
# so whichever release is "latest" is the one offered.
#
# Everything is read from the app INSIDE the dmg being signed, never from a
# separate export folder, so the feed can only describe the bytes it signs.
# Refuses to write a feed unless:
#   - the dmg is notarized, stapled, and accepted by Gatekeeper;
#   - the app inside uses the official feed and the keychain key matches the
#     app's SUPublicEDKey (the key installed copies verify against);
#   - its version and build equal the project's, and the build is newer than
#     the published latest (a too-high build number would block every later
#     update, because Sparkle compares CFBundleVersion).
# The dmg's EdDSA signature is verified, and the feed itself is signed
# (the app sets SURequireSignedFeed).
#
#   APPCAST_ALLOW_TEST_FEED=1  local update tests only: allow a non-official
#                     feed/URL base and skip the project/published checks
#   APPCAST_URL_BASE  test only: where the dmg will be served from
#   SPARKLE_BIN       directory holding sign_update/generate_keys
#   SPARKLE_ACCOUNT   keychain account of the EdDSA key (default: punctual)

set -euo pipefail

DMG="${1:?usage: $0 <dmg> <out.xml> [notes.md]}"
OUT="${2:?missing output path}"
NOTES="${3:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_BIN="${SPARKLE_BIN:-$ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin}"
ACCOUNT="${SPARKLE_ACCOUNT:-punctual}"
TEST="${APPCAST_ALLOW_TEST_FEED:-0}"
OFFICIAL_FEED="https://github.com/Chykalophia/Punctual/releases/latest/download/appcast.xml"
OFFICIAL_BASE="https://github.com/Chykalophia/Punctual/releases/download"

fail() { echo "error: $*" >&2; exit 1; }
[ -x "$SPARKLE_BIN/sign_update" ] || fail "no sign_update in $SPARKLE_BIN (resolve packages first)"
[ -f "$DMG" ] || fail "no dmg at $DMG"

# --- 1. the dmg must be what users will actually get -------------------------
xcrun stapler validate "$DMG" >/dev/null 2>&1 || fail "$DMG has no stapled notarization ticket"
spctl -a -t open --context context:primary-signature "$DMG" 2>/dev/null \
    || fail "Gatekeeper does not accept $DMG"

# --- 2. read the app inside it ----------------------------------------------
MOUNT="$(mktemp -d)"
cleanup() { hdiutil detach -quiet "$MOUNT" 2>/dev/null || true; rmdir "$MOUNT" 2>/dev/null || true; }
trap cleanup EXIT
hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$MOUNT" "$DMG" >/dev/null
PLIST="$MOUNT/Punctual.app/Contents/Info.plist"
[ -f "$PLIST" ] || fail "no Punctual.app inside $DMG"
SHORT="$(plutil -extract CFBundleShortVersionString raw "$PLIST")"
BUILD="$(plutil -extract CFBundleVersion raw "$PLIST")"
MIN_OS="$(plutil -extract LSMinimumSystemVersion raw "$PLIST")"
APP_FEED="$(plutil -extract SUFeedURL raw "$PLIST")"
APP_KEY="$(plutil -extract SUPublicEDKey raw "$PLIST")"
cleanup
trap - EXIT

DMG_NAME="$(basename "$DMG")"
[ "$DMG_NAME" = "Punctual-$SHORT.dmg" ] || fail "$DMG_NAME does not match the app inside ($SHORT)"
case "$BUILD" in ''|*[!0-9]*) fail "CFBundleVersion '$BUILD' is not a plain integer" ;; esac

# --- 3. the key that signs must be the key installed copies trust ------------
KEYCHAIN_KEY="$("$SPARKLE_BIN/generate_keys" --account "$ACCOUNT" -p 2>&1 | tail -1)" \
    || fail "no Sparkle key in the keychain under account '$ACCOUNT' (restore it: generate_keys --account $ACCOUNT -f <backup>)"
[ "$KEYCHAIN_KEY" = "$APP_KEY" ] \
    || fail "keychain key ($ACCOUNT) '$KEYCHAIN_KEY' != app SUPublicEDKey '$APP_KEY'"

# --- 4. release-only checks ---------------------------------------------------
if [ "$TEST" != 1 ]; then
    [ "$APP_FEED" = "$OFFICIAL_FEED" ] || fail "app SUFeedURL is $APP_FEED, not the official feed"
    [ -z "${APPCAST_URL_BASE:-}" ] || fail "APPCAST_URL_BASE is set; only allowed for tests"
    URL_BASE="$OFFICIAL_BASE/v$SHORT"

    PBX="$ROOT/Punctual.xcodeproj/project.pbxproj"
    P_SHORT="$(grep -m1 'MARKETING_VERSION' "$PBX" | sed 's/.*= *//;s/;//')"
    P_BUILD="$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBX" | sed 's/.*= *//;s/;//')"
    [ "$SHORT" = "$P_SHORT" ] || fail "app version $SHORT != project MARKETING_VERSION $P_SHORT"
    [ "$BUILD" = "$P_BUILD" ] || fail "app build $BUILD != project CURRENT_PROJECT_VERSION $P_BUILD"

    # Only a real 404 means "no Sparkle release published yet" (true before the
    # first one). Offline, a 5xx, anything else: stop, rather than silently
    # skipping the newer-than-published check.
    FEED_TMP="$(mktemp)"
    STATUS="$(curl -sSL -o "$FEED_TMP" -w '%{http_code}' "$OFFICIAL_FEED" || echo 000)"
    case "$STATUS" in
        200) PUBLISHED="$(sed -n 's:.*<sparkle\:version>\([0-9]*\)</sparkle\:version>.*:\1:p' "$FEED_TMP" | head -1)"
             [ -n "$PUBLISHED" ] || fail "published appcast has no sparkle:version" ;;
        404) PUBLISHED="" ;;
        *)   rm -f "$FEED_TMP"; fail "could not read the published appcast (HTTP $STATUS); refusing to guess" ;;
    esac
    rm -f "$FEED_TMP"
    if [ -n "$PUBLISHED" ] && [ "$BUILD" -le "$PUBLISHED" ]; then
        fail "build $BUILD is not newer than the published latest ($PUBLISHED)"
    fi
    echo "    published latest build: ${PUBLISHED:-none yet}; this build: $BUILD"
else
    echo "    TEST MODE: non-official feed/URL allowed, release checks skipped"
    URL_BASE="${APPCAST_URL_BASE:?test mode needs APPCAST_URL_BASE}"
fi

# --- 5. sign the dmg, verify against the app's key ---------------------------
echo "==> Signing $DMG_NAME for Sparkle (account $ACCOUNT)"
SIGNATURE="$("$SPARKLE_BIN/sign_update" --account "$ACCOUNT" -p "$DMG")"
LENGTH="$(stat -f %z "$DMG")"
"$SPARKLE_BIN/sign_update" --account "$ACCOUNT" --verify "$DMG" "$SIGNATURE" >/dev/null \
    || fail "Sparkle signature did not verify"

DESCRIPTION=""
if [ -n "$NOTES" ]; then
    [ -f "$NOTES" ] || fail "no release notes at $NOTES"
    if grep -q ']]>' "$NOTES"; then fail "release notes contain ']]>'"; fi
    DESCRIPTION="      <description sparkle:format=\"markdown\"><![CDATA[
$(cat "$NOTES")
]]></description>"
fi

PUBDATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Punctual</title>
    <link>https://www.chykalophia.com/punctual</link>
    <item>
      <title>Punctual $SHORT</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$SHORT</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/Chykalophia/Punctual/releases</sparkle:fullReleaseNotesLink>
$DESCRIPTION
      <enclosure url="$URL_BASE/$DMG_NAME" length="$LENGTH" type="application/octet-stream" sparkle:edSignature="$SIGNATURE"/>
    </item>
  </channel>
</rss>
XML
xmllint --noout "$OUT"

# --- 6. sign the feed (SURequireSignedFeed) -----------------------------------
"$SPARKLE_BIN/sign_update" --account "$ACCOUNT" "$OUT" >/dev/null
"$SPARKLE_BIN/sign_update" --account "$ACCOUNT" --verify "$OUT" >/dev/null \
    || fail "appcast signature did not verify"
echo "==> Appcast: $OUT (Punctual $SHORT, build $BUILD), feed signed"
