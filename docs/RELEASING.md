# Releasing Punctual

How a tag becomes a signed, notarized `.dmg` that a stranger can download and run.

**Current status (2026-10-01):** the pipeline is built but has never run. `v0.2.0` and
`v0.3.0` shipped as MeetingBarNG, before the rename to Punctual, with release notes and no
artifact. The first signed release is the first one under the Punctual name and bundle id
`com.chykalophia.Punctual`; do not re-run the workflow against those old tags. Before
tagging, work through the brand checklist in §5.

Two things are outstanding, and they run in parallel — start the second one first, since
its clock is not yours:

1. **Apple** (§1–2): a Developer ID Application certificate and an app-specific password.
   Same-day work.
2. **Google** (§2a): sensitive-scope verification, so Google Calendar works for someone
   who is not on your test-user list. Days to weeks, in Google's queue.

---

## 1. What you need from Apple, once

### A "Developer ID Application" certificate

This is the one that matters, and it is easy to get wrong: **"Apple Development" and "Mac
Developer" certificates cannot sign for direct download.** They only work for builds run on
registered devices. The workflow checks for this and fails with a named error rather than
producing an app that Gatekeeper rejects on someone else's Mac.

1. Create it in the **developer portal**, not Xcode: Certificates ▸ **+** ▸ **Developer ID
   Application** ▸ choose the **G2 Sub-CA**. Upload a CSR from Keychain Access ▸
   Certificate Assistant ▸ Request a Certificate From a Certificate Authority (saved to
   disk), then double-click the downloaded `.cer` to install it.

   Why not Xcode's **+**: on 2026-10-01 it issued from the *previous* sub-CA, whose own
   certificate expires **2027-02-01**, capping ours at four months. Builds signed and
   notarized before then keep launching (the signature is timestamped), but no new release
   can be signed after it. Check any certificate before relying on it:
   `security find-certificate -c "Developer ID Application" -p | openssl x509 -noout -issuer -enddate`
   (a G2 issuer reads `Developer ID Certification Authority, OU=G2`).

   Keep exactly ONE Developer ID Application identity in the keychain. Two with the same
   name make `codesign --sign "Developer ID Application"` fail as ambiguous.
2. Keychain Access ▸ **My Certificates** ▸ find *Developer ID Application: … (66CMG54L8U)*.
3. Right-click ▸ **Export** ▸ `.p12`. Set a password — you will need it in step 2.
   Export the certificate row (it carries the private key), not the bare key.

### An app-specific password for notarization

Never the real Apple ID password — Apple rejects it, and it would be a far worse thing to
put in a CI secret.

1. <https://appleid.apple.com> ▸ Sign-In and Security ▸ **App-Specific Passwords** ▸ **+**.
2. Name it something identifiable, e.g. `Punctual notarization`.
3. Copy the `xxxx-xxxx-xxxx-xxxx` value.

### A provisioning profile — optional, but read this

The app's real entitlements
(`Punctual/Punctual.entitlements`) request
`com.apple.developer.usernotifications.time-sensitive`, which Apple gates behind a
provisioning profile. **Without a profile, the release is built against
`XCConfig/DeveloperID.entitlements`, which drops that key** — meeting notifications still
fire, but they cannot break through a Focus mode.

For a meeting-reminder app that is a real regression: "notify me even though I'm in Focus"
is close to the whole point. Recommended, therefore, but not required to ship:

1. Developer portal ▸ Identifiers ▸ `com.chykalophia.Punctual` ▸ enable
   **Time Sensitive Notifications**.
2. Profiles ▸ **+** ▸ Distribution ▸ **Developer ID** ▸ select that App ID and your
   Developer ID Application certificate.
3. Download the `.provisionprofile`.

The workflow logs a `::warning::` on every run made without one, so this cannot be
forgotten silently.

---

## 2. Repository secrets

Settings ▸ Secrets and variables ▸ Actions ▸ **New repository secret**.

| Secret | Required | How to produce it |
|---|---|---|
| `MACOS_CERTIFICATE_P12` | **yes** | `base64 -i Certificates.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PASSWORD` | **yes** | the password you set exporting the `.p12` |
| `AC_APPLE_ID` | **yes** | the Apple ID email on the team |
| `AC_PASSWORD` | **yes** | the app-specific password from above |
| `AC_TEAM_ID` | no | defaults to `66CMG54L8U` |
| `MACOS_PROVISIONING_PROFILE` | no | `base64 -i Punctual.provisionprofile \| pbcopy` |
| `GOOGLE_CLIENT_ID` | no | the Desktop-app client id from Google Cloud Console — see §2a |
| `GOOGLE_CLIENT_SECRET` | no | that client's secret |

There is deliberately **no** `KEYCHAIN_PASSWORD` secret — the workflow makes a throwaway
keychain with a random password and deletes it afterwards. One less credential to rotate.

---

## 2a. Google Calendar — and why it gates the release

`XCConfig/GoogleSecrets.xcconfig` is git-ignored, so a release carries Google
credentials only if CI writes them in. The workflow does that from the two optional
secrets above, and **skips it with a warning when they are absent** — a build without
them still ships, with Google Calendar available only to users who supply their own
OAuth client under Preferences ▸ Calendars ▸ "Use my own Google credentials".

That fallback is real and works. It is not, however, a public release: expecting a
stranger to create a Google Cloud project is not shipping a feature.

### Testing mode is not a soft limit

The consent screen starts in **Testing**, and this is the part that surprises people:
it does not mean "the first 100 users". It means only Google accounts you have
manually added to the **Test users** list can sign in **at all**. Everyone else is
refused. Shipping credentials while in Testing therefore looks *broken* to every
stranger — strictly worse than shipping without them, where at least the UI explains
itself.

So a release where Google works out of the box requires the consent screen to be
**published**, which for Calendar scopes requires verification.

### Sensitive-scope verification

Calendar scopes are **sensitive**, not **restricted**. The practical difference is
large: no third-party CASA security assessment, which is what makes Gmail- and
Drive-level scopes a months-long project. What Google does ask for:

- a **verified domain** you own (`chykalophia.com`), matching the app's homepage
- a **privacy policy URL** on that domain
- a **homepage** describing the app
- a **demo video** showing the OAuth consent flow and what the app does with the data
- a justification for each scope

The app requests `calendar.calendarlist.readonly`, `calendar.events.readonly` and
`email` — all read-only, which is a materially easier review than any write scope.
Keep it that way: adding a write scope for event editing turns this into a different
conversation with Google, so decide that deliberately rather than as a side effect.

Turnaround is days to weeks and is entirely Google's queue. Start it before you need it.

**Once verified:** add the two secrets, cut a release, and Google works for everyone
with no code change — the workflow step is already conditional.

**Locally, `make release-local` ships NO Google credentials by default**, even when your
git-ignored `XCConfig/GoogleSecrets.xcconfig` holds real ones (those are for your own dev
builds). Opt in only after verification: `make release-local SHIP_GOOGLE_CREDENTIALS=1`.
The export step reads the finished app's Info.plist and fails if what shipped does not
match the flag. 1.0.0 shipped without them. 1.0.1 shipped WITH them before the data-access review
finished (a deliberate call, 2026-10-01): users see Google's "unverified app" screen and
must choose Advanced, and sign-ins are capped at 100 users until verification completes.
The warning disappears on Google's side once verified; no app update is needed.

---

## 3. Cutting a release

**The release path in use is local** (`make release-local`, below). Every Punctual release
so far was cut that way.

```bash
# 1. Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in the Xcode project.
#    CURRENT_PROJECT_VERSION must go UP every release: Sparkle compares it.
# 2. Add the version to CHANGELOG.md and the in-app What's New (ReleaseNotes.swift;
#    a test fails if its newest entry doesn't match the app version).
# 3. Write build/release-notes-<version>.md (no em dashes): it becomes both the
#    GitHub release notes and the notes shown in the update window.
# 4. make release-local NOTARY_PROFILE=punctual-notary SHIP_GOOGLE_CREDENTIALS=1
#    -> build/Punctual-<version>.dmg, .dmg.sha256, build/appcast.xml
# 5. PR dev -> master, merge, tag the merge commit, then publish with the script:
gh pr merge <n> -R Chykalophia/Punctual --merge --admin
git fetch origin && git tag -s v<version> origin/master -m "Punctual <version>" && git push origin v<version>
Scripts/publish-release.sh <version>
```

Run these from the repo root. `publish-release.sh` creates the release as a **draft** with
the dmg, `.sha256` and `appcast.xml`, checks every upload's size, and only then makes it
public and latest. It then re-downloads the appcast and dmg through the public "latest"
URLs a user's Mac uses and checks they match the local files and pass Gatekeeper. So there
is never a public latest release without its appcast.

`make release-local` refuses to start if `XCODEBUILD_EXTRA`, `APPCAST_ALLOW_TEST_FEED` or
`APPCAST_URL_BASE` is set: those exist only for local update tests.

### Sparkle: never publish a release without `appcast.xml`

Installed copies (1.1.0 and later) check
`https://github.com/Chykalophia/Punctual/releases/latest/download/appcast.xml`. That
address follows whichever release is **latest**, so a latest release missing its
`appcast.xml` makes every installed copy's update check fail. If one slips out, upload the
appcast to it (`gh release upload v<version> build/appcast.xml`), or mark the previous
release latest again.

`Scripts/make-appcast.sh` (run by `make release-local`) reads everything from the app
**inside** the dmg it signs, and refuses unless: the dmg is notarized, stapled and accepted
by Gatekeeper; the app uses the official feed; the keychain key matches that app's
`SUPublicEDKey`; its version and build equal the project's; and the build is newer than the
published latest (a too-high build number would block every later update). It signs the
dmg, verifies the signature, writes the feed, and **signs the feed** too: the app sets
`SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction`.

### The Sparkle key

The EdDSA private key lives in the login keychain under the account **`punctual`** (not
Sparkle's default account, which every Sparkle app on a Mac shares). Its public half,
`generate_keys --account punctual -p`, must equal `SUPublicEDKey` in Info.plist.

- **Back it up** to 1Password: `generate_keys --account punctual -x <file>`, store the
  file's contents, delete the file.
- **Restore** on a new Mac: `generate_keys --account punctual -f <file>`, then delete it.
- **If it is lost:** new feeds can't be signed with it, so installed copies reject them.
  Sparkle has one way back, read in its source (`SUAppcastDriver.m`): after a feed has failed
  signature validation continuously for 20 days (`SUSignedFeedFailureExpirationInterval`),
  it accepts the feed again, provided the update itself still passes the EdDSA **or**
  same-team Developer ID check. So a Developer ID signed release carrying a new key would
  reach users, but only after up to 20 days of failed checks. Don't lose it.

What Sparkle accepts, read in its source (`SUUpdateValidator.m`): an update installs if its
EdDSA signature verifies against the installed app's key, **or** its Developer ID signature
matches the installed app's team. The "or" is Sparkle's design, for key rotation, and no
setting removes it. So the Developer ID certificate is as sensitive as the EdDSA key: whoever
holds it and can publish to this repo can ship an update. Every release is signed both ways.
The signed feed means an altered feed is refused (tested: a one-word change to a signed
feed was rejected and nothing was downloaded), with the 20-day recovery rule above as the
one exception: an attacker able to replace the feed would also have to keep it failing for
20 days, unnoticed.

### CI (manual only, not Sparkle-ready)

`.github/workflows/release.yml` runs **only** when started by hand (workflow_dispatch). It
no longer runs on tag pushes: it would rebuild and overwrite the locally signed dmg, and the
published appcast would stop matching it. It does not produce an appcast or hold the Sparkle
key, and it refuses to touch a release that already has `appcast.xml`. Do not use it to
publish a release until Sparkle signing is added to it.

If the tag already has a release with hand-written notes, the workflow **uploads into it
without touching the notes**. It only creates a release when none exists.

### Re-running without a new version

Notarization fails for reasons unrelated to your code: expired credentials, an Apple
outage, a rejected entitlement. Locally, resume the same submission without rebuilding
(see "notarize.sh exits 75" below), then run `make appcast` and publish. Never rebuild a
dmg that is already published with an appcast: its EdDSA signature would no longer match.

### Locally, without CI

Locally the certificate is used straight from the login keychain, so there is no `.p12`
to export. Store the notarization credentials in the keychain once, so the app-specific
password never sits in an env var or shell history:

```bash
xcrun notarytool store-credentials punctual-notary \
  --apple-id <Apple ID on team 66CMG54L8U> --team-id 66CMG54L8U
# prompts for the app-specific password. Run it in Terminal.app: the password prompt
# needs a real TTY, and without one it sends an empty password and Apple answers 401.

make release-local NOTARY_PROFILE=punctual-notary   # archive -> export -> dmg -> notarize
```

`AC_APPLE_ID` / `AC_PASSWORD` / `AC_TEAM_ID` in the environment still work, and are what
CI uses.

By default this signs with the full entitlements against the **"Punctual Developer ID"**
provisioning profile, so meeting alerts can break through Focus. Install the profile by
copying it to `~/Library/Developer/Xcode/UserData/Provisioning Profiles/<UUID>.provisionprofile`
(the UUID is in `security cms -D -i <file>`). Double-clicking it may open System Settings'
device-profile pane instead, which xcodebuild never reads.

Only as a deliberate fallback, without the profile (alerts will NOT break through Focus):

```bash
make release-local NOTARY_PROFILE=punctual-notary \
  RELEASE_ENTITLEMENTS=XCConfig/DeveloperID.entitlements PROFILE_SPECIFIER=
```

---

## 4. When it goes wrong

**`No 'Developer ID Application' identity in the imported certificate`**
The `.p12` holds a development certificate. Re-export the *Developer ID Application* one —
see §1.

**`errSecInternalComponent` during codesign**
The keychain partition list was not set, so codesign is waiting on a GUI prompt nobody can
answer. The workflow handles this; if you hit it locally, run
`security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k <pw> login.keychain-db`.

**`notarize.sh` exits 75: "Apple has not finished yet"**
Not a rejection. The wait (default 30 min, `NOTARY_TIMEOUT` to change) ran out while
Apple was still processing; the submission keeps going on Apple's side. A team's first
submission can take hours (2026-10-01: over an hour). Resume without re-uploading, using
the id the script printed:

```bash
NOTARY_SUBMISSION_ID=<id> NOTARY_PROFILE=punctual-notary NOTARY_TIMEOUT=3h \
  Scripts/notarize.sh build/Punctual-<version>.dmg
```

Do not rebuild the dmg in between: the ticket is keyed to the file's hash, so a rebuilt
image would no longer match the submission.

**Notarization returns `Invalid` with no reason**
`notarize.sh` now prints the notary log itself on any non-`Accepted` result.
The submit output never carries the reason — only the log does:

```bash
xcrun notarytool log <submission-id> \
  --apple-id "$AC_APPLE_ID" --password "$AC_PASSWORD" --team-id "$AC_TEAM_ID"
```

Usual causes: the hardened runtime is off (the workflow pre-checks this), a nested binary
is unsigned, or an entitlement has no matching profile.

**The app opens on your Mac but users see "damaged and can't be opened"**
The image was not stapled, and their machine could not reach Apple to check. `stapler
staple` is part of `Scripts/notarize.sh`; confirm with `xcrun stapler validate <dmg>`.

**Verifying a build the way a user's Mac will**

```bash
spctl --assess --type open --context context:primary-signature -vv Punctual-0.4.0.dmg
```

A clean `accepted / source=Notarized Developer ID` is what a first-run user gets.

---

## 5. Brand and attribution checklist

Punctual is built on MeetingBar by Andrii Leitsius and credits it openly. What it must
never do is look like MeetingBar. `make brand-check` (run automatically by
`make release-local`) enforces the code-side half of both: it fails if the old name,
the `meetingbar://` scheme or the original app's links reach a user-facing surface, and
it also fails if the attribution in `NOTICE`, the README or the About box goes missing.

The rest lives outside the repo and has to be checked by hand, once, before the first
Punctual release:

- [x] GitHub repo renamed `MeetingBarNG` → `Punctual` (old URLs redirect).
- [x] Fork relationship detached via GitHub Support, so the page no longer says
      "forked from leits/MeetingBar". The README credit stays.
- [x] Repo homepage set to `https://chykalophia.com/punctual` (was `meetingbar.app`), and
      the description rewritten.
- [x] `chykalophia.com/punctual` page live, with a privacy policy (Google verification
      needs both on the verified domain).
- [x] Google OAuth consent screen: app name Punctual, Punctual icon, that homepage.
- [x] Developer portal: App ID `com.chykalophia.Punctual` with Time Sensitive
      Notifications, and a Developer ID provisioning profile for it.
- [x] New app icon in `Assets.xcassets/AppIcon.appiconset` and the menu-bar glyph
      (`menuBarGlyph`, a template image). Sources in `docs/brand`.
- [ ] In-app What's New (`UI/Views/Changelog/ReleaseNotes.swift`) has an entry for this
      version.

Existing installs under the old bundle id (`com.chykalophia.MeetingBarNG`, source builds
only; no binary was ever published) start fresh: the app is sandboxed, so the new id gets
a new container and cannot read the old one's settings.
