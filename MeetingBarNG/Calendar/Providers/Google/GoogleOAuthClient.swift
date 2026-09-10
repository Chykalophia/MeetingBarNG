//
//  GoogleOAuthClient.swift
//  MeetingBarNG
//
//  Which Google OAuth client the app signs in with, as pure hostless logic.
//
//  Two can be in play. The build can carry one (from `XCConfig/GoogleSecrets.xcconfig`,
//  read via Info.plist) so the app works out of the box, and the user can supply
//  their own in Preferences. A user-supplied client wins whenever it is turned
//  on and valid.
//
//  WHY BOTH. A shipped client ID in a distributed binary is extractable — that is
//  inherent to native OAuth, which is why PKCE exists (RFC 7636: "secrets
//  provisioned in client binary applications cannot be considered confidential")
//  and why Google's own docs say the installed-app secret "is obviously not
//  treated as a secret". What an extracted ID actually costs is the project's API
//  quota and the ability to put this app's name on a consent screen; it grants
//  nobody access to anybody's calendar without that person signing in. Letting a
//  user point the app at their own client means their calls are on their quota
//  under their consent screen, which is the right answer for anyone in an org
//  that requires it or anyone who would simply rather not trust ours.
//
//  This file has no AppKit/Defaults/AppAuth dependency so every rule here —
//  precedence, the two accepted ID formats, empty-vs-nil for the secret, and the
//  identity that decides whether stored tokens still belong to this client — is
//  testable with no host.
//

import Foundation

/// A resolved Google OAuth client: what the app will actually authenticate as.
public struct GoogleOAuthClient: Equatable, Sendable {
    /// Where this client came from. Surfaced in Preferences so "whose quota is
    /// this on" is answerable without reading the build settings.
    public enum Origin: String, Equatable, Sendable {
        /// Compiled into this build from `XCConfig/GoogleSecrets.xcconfig`.
        case shipped
        /// Entered by the user in Preferences.
        case userSupplied
    }

    /// The full client ID, always in `<number>.apps.googleusercontent.com` form
    /// regardless of which form it was entered in.
    public let clientID: String
    /// `nil` when the client has no secret.
    ///
    /// Not merely cosmetic: AppAuth branches on `if (_clientSecret)` in
    /// Objective-C, where an empty `NSString` is a non-nil object and therefore
    /// TRUE, so `""` makes it authenticate the token request with HTTP Basic
    /// instead of putting `client_id` in the body — and Google answers
    /// `invalid_client`.
    public let clientSecret: String?
    public let origin: Origin

    public init(clientID: String, clientSecret: String?, origin: Origin) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.origin = origin
    }

    /// Identity of the client the stored OAuth tokens were issued to.
    ///
    /// Tokens are bound to the client that obtained them, so switching from the
    /// shipped client to a user-supplied one (or editing the ID) invalidates
    /// them. Persisting this alongside the token blob lets the store detect that
    /// and start clean, instead of replaying another client's refresh token and
    /// surfacing an `invalid_grant` the user cannot act on.
    ///
    /// The secret is deliberately excluded: correcting a mistyped secret for the
    /// same client ID should not throw away a working session.
    public var tokenIdentity: String { clientID }
}

public enum GoogleOAuthClientResolver {
    /// The client to sign in with, or `nil` when neither source yields a usable
    /// one (in which case the Google source stays unavailable rather than
    /// offering a sign-in that cannot succeed).
    ///
    /// A user-supplied client wins when it is enabled AND valid. Enabled but
    /// invalid does NOT silently fall back to the shipped client: someone who
    /// deliberately pointed the app at their own project should see their
    /// mistake, not have their calls quietly billed to ours.
    public static func resolve(
        shipped: GoogleOAuthClient?,
        userSupplied: GoogleOAuthClient?,
        preferUserSupplied: Bool
    ) -> GoogleOAuthClient? {
        if preferUserSupplied {
            return userSupplied
        }
        return shipped
    }

    /// Builds a client from raw entered/configured strings, or `nil` when the ID
    /// is unusable.
    public static func make(
        clientID rawClientID: String,
        clientSecret rawSecret: String,
        origin: GoogleOAuthClient.Origin
    ) -> GoogleOAuthClient? {
        guard let clientID = normalizedClientID(rawClientID) else { return nil }
        return GoogleOAuthClient(
            clientID: clientID,
            clientSecret: normalizedSecret(rawSecret),
            origin: origin
        )
    }

    /// The Google Cloud Console shows a client ID as
    /// `123456789-abc123.apps.googleusercontent.com`, and the setup docs have
    /// historically asked for only the part before the suffix. Both forms are
    /// accepted and normalized to the full ID, because being told "invalid" for
    /// pasting exactly what the console displayed is a terrible first run.
    ///
    /// Returns `nil` for empty input and for the build placeholder, so a build
    /// that never had credentials substituted reads as "no client" rather than
    /// as a client named `REPLACE_BY_YOUR…`.
    public static func normalizedClientID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix(placeholderPrefix) else { return nil }

        let number = trimmed.hasSuffix(clientIDSuffix)
            ? String(trimmed.dropLast(clientIDSuffix.count))
            : trimmed
        // A bare "." or a value that was nothing but the suffix leaves nothing to
        // identify a client with.
        guard !number.isEmpty, number != "." else { return nil }
        // Reject anything carrying a scheme or path: a pasted console URL is a
        // plausible mistake and would otherwise become a client ID that fails
        // much later, at sign-in, with an opaque error.
        guard !number.contains("/"), !number.contains(":") else { return nil }

        return number + clientIDSuffix
    }

    /// Empty means "this client has no secret" and must reach AppAuth as nil —
    /// see `GoogleOAuthClient.clientSecret`.
    public static func normalizedSecret(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix(placeholderPrefix) else { return nil }
        return trimmed
    }

    /// Whether a raw string would produce a usable client ID. Drives the
    /// inline validation on the Preferences field.
    public static func isValidClientID(_ raw: String) -> Bool {
        normalizedClientID(raw) != nil
    }

    private static let clientIDSuffix = ".apps.googleusercontent.com"
    private static let placeholderPrefix = "REPLACE_BY_YOUR"
}
