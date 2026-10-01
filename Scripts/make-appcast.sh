#!/bin/bash
#
# make-appcast.sh — write the Sparkle appcast.xml for one release.
#
#   Scripts/make-appcast.sh <notarized.dmg> <exported Punctual.app> <out appcast.xml> [release-notes.md]
#
# The appcast is uploaded as an asset of the GitHub release, next to the dmg.
# Shipped apps read https://github.com/Chykalophia/Punctual/releases/latest/download/appcast.xml,
# so whichever release is "latest" is the one offered.
#
# Versions are read from the BUILT app, never the project file, so the feed
# always describes exactly what ships. Sparkle compares CFBundleVersion.
#
# The dmg is signed with the EdDSA private key in the login keychain (made once
# with generate_keys; back it up), and the signature is VERIFIED before the feed
# is written, so a bad signature cannot be published.
#
#   SPARKLE_BIN       directory holding sign_update (default: the SPM artifact)
#   APPCAST_URL_BASE  where the dmg will be downloadable (default: this
#                     version's GitHub release). A local update test overrides it.

set -euo pipefail

DMG="${1:?usage: $0 <dmg> <app> <out.xml> [notes.md]}"
APP="${2:?missing exported app}"
OUT="${3:?missing output path}"
NOTES="${4:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_BIN="${SPARKLE_BIN:-$ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin}"
SIGN="$SPARKLE_BIN/sign_update"
[ -x "$SIGN" ] || { echo "error: no sign_update at $SIGN (resolve packages first)" >&2; exit 1; }
[ -f "$DMG" ] || { echo "error: no dmg at $DMG" >&2; exit 1; }

PLIST="$APP/Contents/Info.plist"
SHORT="$(plutil -extract CFBundleShortVersionString raw "$PLIST")"
BUILD="$(plutil -extract CFBundleVersion raw "$PLIST")"
MIN_OS="$(plutil -extract LSMinimumSystemVersion raw "$PLIST")"
DMG_NAME="$(basename "$DMG")"
URL_BASE="${APPCAST_URL_BASE:-https://github.com/Chykalophia/Punctual/releases/download/v$SHORT}"

# The app inside must match the version we are about to advertise.
case "$DMG_NAME" in
    *"-$SHORT.dmg") ;;
    *) echo "error: $DMG_NAME does not match app version $SHORT" >&2; exit 1 ;;
esac

echo "==> Signing $DMG_NAME for Sparkle"
SIGNATURE="$("$SIGN" -p "$DMG")"
LENGTH="$(stat -f %z "$DMG")"
"$SIGN" --verify "$DMG" "$SIGNATURE" >/dev/null \
    || { echo "error: Sparkle signature did not verify" >&2; exit 1; }

DESCRIPTION=""
if [ -n "$NOTES" ]; then
    [ -f "$NOTES" ] || { echo "error: no release notes at $NOTES" >&2; exit 1; }
    if grep -q ']]>' "$NOTES"; then
        echo "error: release notes contain ']]>', which would break the CDATA block" >&2
        exit 1
    fi
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
echo "==> Appcast: $OUT (Punctual $SHORT, build $BUILD)"
