//
//  GoogleOAuthClient+MeetingBar.swift
//  MeetingBarNG
//
//  Reads the two possible Google OAuth clients out of their storage and hands
//  the hostless resolver the raw values. The precedence rules and the parsing
//  live in `GoogleOAuthClient`; this file only knows where things are kept.
//

import Defaults
import Foundation

/// The user-supplied ("bring your own") Google OAuth client.
///
/// The id lives in Defaults — it is not a secret; it ships in the binary of
/// every native OAuth app by design. The optional secret lives in the Keychain
/// instead, because a value Google names a secret should not sit in a plist that
/// gets copied around in backups, regardless of how little it actually protects.
@MainActor
enum GoogleUserOAuthClientStore {
    private static let keychainService = "MeetingBarNG.GoogleUserOAuthClientSecret"

    static var isEnabled: Bool {
        get { Defaults[.googleUseUserOAuthClient] }
        set { Defaults[.googleUseUserOAuthClient] = newValue }
    }

    static var clientID: String {
        get { Defaults[.googleUserOAuthClientID] }
        set { Defaults[.googleUserOAuthClientID] = newValue }
    }

    static var clientSecret: String {
        get {
            guard let data = Keychain.load(for: keychainService) else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }
        set {
            guard !newValue.isEmpty else {
                Keychain.delete(for: keychainService)
                return
            }
            Keychain.save(data: Data(newValue.utf8), for: keychainService)
        }
    }

    /// The user's client, or `nil` when what they entered cannot be used.
    static var client: GoogleOAuthClient? {
        GoogleOAuthClientResolver.make(
            clientID: clientID,
            clientSecret: clientSecret,
            origin: .userSupplied
        )
    }

    /// Forgets the entered credentials entirely — used when switching back to
    /// the shipped client so a stale secret cannot linger in the Keychain.
    static func clear() {
        Defaults[.googleUserOAuthClientID] = ""
        clientSecret = ""
    }
}

extension GoogleOAuthConfig {
    /// The client compiled into this build, or `nil` when it carries none.
    @MainActor
    static var shippedClient: GoogleOAuthClient? {
        GoogleOAuthClientResolver.make(
            clientID: clientNumber,
            clientSecret: clientSecret,
            origin: .shipped
        )
    }

    /// The client the app will actually sign in with, or `nil` when there is
    /// none to use — in which case the Google source stays unavailable rather
    /// than offering a sign-in that cannot succeed.
    @MainActor
    static var effectiveClient: GoogleOAuthClient? {
        GoogleOAuthClientResolver.resolve(
            shipped: shippedClient,
            userSupplied: GoogleUserOAuthClientStore.client,
            preferUserSupplied: GoogleUserOAuthClientStore.isEnabled
        )
    }
}
