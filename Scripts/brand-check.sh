#!/bin/bash
#
# brand-check.sh — release gate for Punctual's identity and its attribution.
#
#   Scripts/brand-check.sh
#
# Punctual is built on MeetingBar by Andrii Leitsius, and says so. This check
# holds both halves of that at once:
#
#   1. Nothing a user sees presents the app AS MeetingBar or MeetingBarNG
#      (name, URL scheme, homepage, the original's App Store listing).
#   2. The attribution we owe is still there (NOTICE, the README credit,
#      the About box copyright line).
#
# Only user-facing surfaces are scanned. Source headers ("Created by Andrii
# Leitsius") and internal identifiers (the MeetingBarLogic module, file names)
# are deliberately out of scope: the first are required by Apache-2.0 §4, the
# second are invisible to users.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

fail=0
bad() { echo "FAIL: $*" >&2; fail=1; }

STRINGS_DIR="MeetingBarNG/Resources /Localization "

# --- 1. No upstream identity on user-facing surfaces ------------------------

# Localized string VALUES (lines starting with a key). The one sanctioned
# mention is the credit line naming Andrii Leitsius.
hits="$(grep -rn --include=Localizable.strings -E '^"[^"]*" *= *"[^"]*MeetingBar' "$STRINGS_DIR" \
    | grep -v 'Andrii')"
[ -z "$hits" ] || bad "old app name in localized strings:
$hits"

hits="$(grep -n -E '<string>[^<]*MeetingBar' MeetingBarNG/Info.plist | grep -v 'Andrii')"
[ -z "$hits" ] || bad "old app name in Info.plist:
$hits"

grep -q '<string>meetingbar</string>' MeetingBarNG/Info.plist \
    && bad "Info.plist still registers the meetingbar:// URL scheme (upstream's)"

hits="$(grep -n -E 'title="[^"]*MeetingBar' MeetingBarNG/Base.lproj/Main.storyboard)"
[ -z "$hits" ] || bad "old app name in storyboard menu titles:
$hits"

hits="$(grep -rn -E '"[^"]*(meetingbar://|MeetingBarNG\.|github\.com/Chykalophia/MeetingBarNG)' \
    --include='*.swift' MeetingBarNG | grep -v -E '^\S+:[0-9]+:\s*//')"
[ -z "$hits" ] || bad "old identifiers in Swift string literals:
$hits"

# The original app's homepage and Mac App Store listing are not ours to send
# people to as an install option.
hits="$(grep -n -E 'meetingbar\.app|apps\.apple\.com/[a-z/]*id1532419400' README.md)"
[ -z "$hits" ] || bad "README points users at the original app:
$hits"

grep -q 'PRODUCT_BUNDLE_IDENTIFIER = com.chykalophia.Punctual;' MeetingBarNG.xcodeproj/project.pbxproj \
    || bad "app bundle id is not com.chykalophia.Punctual"

# --- 2. Attribution is still present -----------------------------------------

grep -q 'Andrii Leitsius' NOTICE || bad "NOTICE lost the upstream copyright (Apache-2.0 §4)"
grep -q 'github.com/leits/MeetingBar' NOTICE || bad "NOTICE lost the upstream project link"
grep -q 'Andrii Leitsius' README.md || bad "README no longer credits Andrii Leitsius"
grep -q 'github.com/leits/MeetingBar' README.md || bad "README no longer links the original MeetingBar"
grep -q 'Andrii Leitsius' MeetingBarNG/Info.plist || bad "About box copyright lost the MeetingBar credit"
[ -f LICENSE ] || bad "LICENSE is missing"

if [ "$fail" -eq 0 ]; then
    echo "brand-check: OK (Punctual identity clean, MeetingBar attribution present)"
fi
exit "$fail"
