# Releasing MeetingBarNG

How a tag becomes a signed, notarized `.dmg` that a stranger can download and run.

**Current status:** the pipeline is built but has never run. `v0.2.0` and `v0.3.0` were
tagged before it existed and carry release notes with no artifact. Once the secrets below
are in place, either re-run the workflow against an existing tag or cut `v0.4.0`.

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

1. Xcode ▸ Settings ▸ Accounts ▸ your team ▸ **Manage Certificates** ▸ **+** ▸
   **Developer ID Application**. (Or the Certificates section of the developer portal.)
2. Keychain Access ▸ **My Certificates** ▸ find *Developer ID Application: … (KGH289N6T8)*.
3. Right-click ▸ **Export** ▸ `.p12`. Set a password — you will need it in step 2.
   Export the certificate row (it carries the private key), not the bare key.

### An app-specific password for notarization

Never the real Apple ID password — Apple rejects it, and it would be a far worse thing to
put in a CI secret.

1. <https://appleid.apple.com> ▸ Sign-In and Security ▸ **App-Specific Passwords** ▸ **+**.
2. Name it something identifiable, e.g. `MeetingBarNG notarization`.
3. Copy the `xxxx-xxxx-xxxx-xxxx` value.

### A provisioning profile — optional, but read this

The app's real entitlements
(`MeetingBarNG/MeetingBarNG.entitlements`) request
`com.apple.developer.usernotifications.time-sensitive`, which Apple gates behind a
provisioning profile. **Without a profile, the release is built against
`XCConfig/DeveloperID.entitlements`, which drops that key** — meeting notifications still
fire, but they cannot break through a Focus mode.

For a meeting-reminder app that is a real regression: "notify me even though I'm in Focus"
is close to the whole point. Recommended, therefore, but not required to ship:

1. Developer portal ▸ Identifiers ▸ `com.chykalophia.MeetingBarNG` ▸ enable
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
| `AC_TEAM_ID` | no | defaults to `KGH289N6T8` |
| `MACOS_PROVISIONING_PROFILE` | no | `base64 -i MeetingBarNG.provisionprofile \| pbcopy` |
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

---

## 3. Cutting a release

```bash
# 1. Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in the Xcode project.
# 2. Move CHANGELOG.md's "Unreleased" section under the new version heading.
# 3. Land that on master through a PR (master is protected; see STATE.md).
# 4. Tag it.
git tag v0.4.0
git push origin v0.4.0
```

The tag push runs `.github/workflows/release.yml`, which archives, signs, exports,
packages, notarizes, staples, and uploads `MeetingBarNG-0.4.0.dmg` plus a `.sha256`
to the release.

If the tag already has a release with hand-written notes, the workflow **uploads into it
without touching the notes**. It only creates a release when none exists.

### Re-running without a new version

Notarization fails for reasons unrelated to your code — expired credentials, an Apple
outage, a rejected entitlement. Actions ▸ **Release** ▸ **Run workflow** ▸ enter the
existing tag. It rebuilds and re-publishes with `--clobber`.

### Locally, without CI

```bash
export AC_APPLE_ID="peter@chykalophia.com"
export AC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export AC_TEAM_ID="KGH289N6T8"

make release-local          # archive -> export -> dmg -> notarize
```

With a provisioning profile installed, keep the time-sensitive entitlement:

```bash
make release-local \
  RELEASE_ENTITLEMENTS=MeetingBarNG/MeetingBarNG.entitlements \
  PROFILE_SPECIFIER="MeetingBarNG Developer ID"
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

**Notarization returns `Invalid` with no reason**
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
spctl --assess --type open --context context:primary-signature -vv MeetingBarNG-0.4.0.dmg
```

A clean `accepted / source=Notarized Developer ID` is what a first-run user gets.
