#!/bin/bash
#
# package-dmg.sh — wrap an exported MeetingBarNG.app in a distributable .dmg.
#
# Uses hdiutil only, deliberately: create-dmg gives a prettier window but is a
# Homebrew dependency that has to be installed on every CI runner, and a broken
# release pipeline is worse than a plain disk image.
#
#   Scripts/package-dmg.sh <path-to-.app> <version> <output.dmg>
#
# The image contains the app plus an /Applications symlink, which is the drag
# target every Mac user already knows.

set -euo pipefail

APP_PATH="${1:-}"
VERSION="${2:-}"
OUTPUT="${3:-}"

if [ -z "$APP_PATH" ] || [ -z "$VERSION" ] || [ -z "$OUTPUT" ]; then
    echo "usage: $0 <path-to-.app> <version> <output.dmg>" >&2
    exit 2
fi

if [ ! -d "$APP_PATH" ]; then
    echo "error: no app bundle at $APP_PATH" >&2
    exit 1
fi

VOLNAME="MeetingBarNG $VERSION"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

echo "==> Staging $APP_PATH"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# ULFO (lzfse) is smaller and faster to decompress than the older UDBZ, and is
# supported on every macOS this app runs on (the deployment floor is macOS 15).
echo "==> Building $OUTPUT"
mkdir -p "$(dirname "$OUTPUT")"
rm -f "$OUTPUT"
hdiutil create \
    -volname "$VOLNAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format ULFO \
    "$OUTPUT"

echo "==> Built $OUTPUT"
hdiutil verify "$OUTPUT"
