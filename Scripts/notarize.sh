#!/bin/bash
#
# notarize.sh — submit a .dmg to Apple's notary service, wait, then staple.
#
#   Scripts/notarize.sh <path.dmg>
#
# Credentials, in order of preference:
#
#   NOTARY_PROFILE  name of a keychain profile made once with
#                   `xcrun notarytool store-credentials <name>`. Preferred locally:
#                   the app-specific password then lives in the login keychain,
#                   never in an env var or shell history.
#
#   or, from the environment (what CI uses):
#   AC_APPLE_ID   Apple ID email of an account on the team
#   AC_PASSWORD   an APP-SPECIFIC password (appleid.apple.com), never the real one
#   AC_TEAM_ID    the 10-character team id (66CMG54L8U)
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

if [ -n "${NOTARY_PROFILE:-}" ]; then
    AUTH=(--keychain-profile "$NOTARY_PROFILE")
else
    : "${AC_APPLE_ID:?Set NOTARY_PROFILE, or AC_APPLE_ID/AC_PASSWORD/AC_TEAM_ID}"
    : "${AC_PASSWORD:?AC_PASSWORD is not set (use an app-specific password)}"
    : "${AC_TEAM_ID:?AC_TEAM_ID is not set}"
    AUTH=(--apple-id "$AC_APPLE_ID" --password "$AC_PASSWORD" --team-id "$AC_TEAM_ID")
fi

RESULT="$(mktemp)"
trap 'rm -f "$RESULT"' EXIT

# Structured output, so the verdict is read from Apple's answer rather than
# inferred from an exit code: a wait that times out exits non-zero exactly
# like a rejection does, but means something entirely different.
if [ -n "${NOTARY_SUBMISSION_ID:-}" ]; then
    # Resume an earlier submission instead of uploading the same bytes again.
    # Stapling works because the ticket is keyed to the file's hash.
    echo "==> Waiting on existing submission $NOTARY_SUBMISSION_ID"
    xcrun notarytool wait "$NOTARY_SUBMISSION_ID" "${AUTH[@]}" \
        --timeout "${NOTARY_TIMEOUT:-30m}" --output-format json > "$RESULT" 2>&1 || true
else
    echo "==> Submitting $DMG to the notary service (usually 1-5 min; a team's first can take hours)"
    xcrun notarytool submit "$DMG" "${AUTH[@]}" \
        --wait --timeout "${NOTARY_TIMEOUT:-30m}" --output-format json > "$RESULT" 2>&1 || true
fi

# Take only the submission id from that output: on a timeout notarytool emits
# {"id":..,"message":"Timeout ..."} on stderr with NO status field. The verdict
# comes from `notarytool info`, which always reports one.
ID="${NOTARY_SUBMISSION_ID:-$(plutil -extract id raw -o - "$RESULT" 2>/dev/null || true)}"
STATUS=""
if [ -n "$ID" ]; then
    STATUS="$(xcrun notarytool info "$ID" "${AUTH[@]}" --output-format json 2>/dev/null \
        | plutil -extract status raw -o - - 2>/dev/null || true)"
fi
echo "    submission: ${ID:-?}  status: ${STATUS:-?}"

case "$STATUS" in
    Accepted)
        ;;
    "In Progress")
        echo "Apple has not finished yet. This is NOT a rejection; processing continues." >&2
        echo "Resume (no re-upload): NOTARY_SUBMISSION_ID=$ID Scripts/notarize.sh \"$DMG\"" >&2
        exit 75   # EX_TEMPFAIL
        ;;
    *)
        echo "error: notarization did not succeed (status: ${STATUS:-unknown})." >&2
        cat "$RESULT" >&2
        if [ -n "$ID" ]; then
            # The rejection reason is ONLY in this log; the status just says
            # "Invalid", which tells you nothing actionable.
            echo "==> Notary log for $ID" >&2
            xcrun notarytool log "$ID" "${AUTH[@]}" >&2 || true
        fi
        exit 1
        ;;
esac

echo "==> Stapling the ticket"
xcrun stapler staple "$DMG"

echo "==> Verifying"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature -vv "$DMG"

echo "==> Notarized and stapled: $DMG"
