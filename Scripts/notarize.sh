#!/bin/bash
#
# notarize.sh — submit a .dmg to Apple's notary service, wait, then staple.
#
#   Scripts/notarize.sh <path.dmg>
#
# Credentials come from the environment (same names locally and in CI):
#   AC_APPLE_ID   Apple ID email of an account on the team
#   AC_PASSWORD   an APP-SPECIFIC password (appleid.apple.com), never the real one
#   AC_TEAM_ID    the 10-character team id (KGH289N6T8)
#
# Stapling matters: without it the app still passes Gatekeeper, but only while the
# machine can reach Apple. A stapled image installs correctly offline and on a
# locked-down network, which is exactly when a first-run failure is most costly.

set -euo pipefail

DMG="${1:-}"

if [ -z "$DMG" ]; then
    echo "usage: $0 <path.dmg>" >&2
    exit 2
fi

if [ ! -f "$DMG" ]; then
    echo "error: no disk image at $DMG" >&2
    exit 1
fi

: "${AC_APPLE_ID:?AC_APPLE_ID is not set}"
: "${AC_PASSWORD:?AC_PASSWORD is not set (use an app-specific password)}"
: "${AC_TEAM_ID:?AC_TEAM_ID is not set}"

echo "==> Submitting $DMG to the notary service (this waits; typically 1-5 min)"
set +e
xcrun notarytool submit "$DMG" \
    --apple-id "$AC_APPLE_ID" \
    --password "$AC_PASSWORD" \
    --team-id "$AC_TEAM_ID" \
    --wait \
    --timeout 30m
SUBMIT_STATUS=$?
set -e

if [ $SUBMIT_STATUS -ne 0 ]; then
    echo "error: notarization failed. Fetching the log for the most recent submission." >&2
    # The rejection reason is ONLY in this log — the submit output just says
    # "Invalid", which tells you nothing actionable.
    xcrun notarytool history \
        --apple-id "$AC_APPLE_ID" \
        --password "$AC_PASSWORD" \
        --team-id "$AC_TEAM_ID" \
        --limit 1 >&2 || true
    echo "Run: xcrun notarytool log <submission-id> --apple-id ... --password ... --team-id ..." >&2
    exit $SUBMIT_STATUS
fi

echo "==> Stapling the ticket"
xcrun stapler staple "$DMG"

echo "==> Verifying"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature -vv "$DMG"

echo "==> Notarized and stapled: $DMG"
