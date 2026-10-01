//
//  GoogleOAuthClientTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for Google OAuth client resolution (MeetingBarNG).
//

import XCTest

@testable import PunctualLogic

final class GoogleOAuthClientTests: XCTestCase {
    private let suffix = ".apps.googleusercontent.com"

    // MARK: - Client ID normalization

    func test_bareClientNumberGainsTheSuffix() {
        XCTAssertEqual(
            GoogleOAuthClientResolver.normalizedClientID("1234567890-abc123"),
            "1234567890-abc123\(suffix)"
        )
    }

    /// The Cloud Console displays the FULL id, so pasting exactly what is on
    /// screen has to work. Being told "invalid" for that is a terrible first run.
    func test_fullClientIDIsAcceptedUnchanged() {
        let full = "1234567890-abc123\(suffix)"
        XCTAssertEqual(GoogleOAuthClientResolver.normalizedClientID(full), full)
    }

    func test_surroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(
            GoogleOAuthClientResolver.normalizedClientID("  1234567890-abc123\n"),
            "1234567890-abc123\(suffix)"
        )
    }

    func test_emptyIsNotAClient() {
        XCTAssertNil(GoogleOAuthClientResolver.normalizedClientID(""))
        XCTAssertNil(GoogleOAuthClientResolver.normalizedClientID("   "))
    }

    /// A build whose credentials were never substituted must read as "no
    /// client", not as a client literally named REPLACE_BY_YOUR…
    func test_buildPlaceholderIsNotAClient() {
        XCTAssertNil(
            GoogleOAuthClientResolver.normalizedClientID("REPLACE_BY_YOUR_GOOGLE_CLIENT_NUMBER"))
    }

    func test_suffixAloneIsNotAClient() {
        XCTAssertNil(GoogleOAuthClientResolver.normalizedClientID(suffix))
    }

    /// Pasting the console URL instead of the id is a plausible mistake, and
    /// accepting it would fail much later at sign-in with an opaque error.
    func test_pastedURLIsRejected() {
        XCTAssertNil(GoogleOAuthClientResolver.normalizedClientID(
            "https://console.cloud.google.com/apis/credentials"))
        XCTAssertNil(GoogleOAuthClientResolver.normalizedClientID("1234-abc/extra"))
    }

    func test_isValidClientIDTracksNormalization() {
        XCTAssertTrue(GoogleOAuthClientResolver.isValidClientID("1234567890-abc"))
        XCTAssertFalse(GoogleOAuthClientResolver.isValidClientID(""))
    }

    // MARK: - Secret normalization

    func test_emptySecretIsNil() {
        XCTAssertNil(GoogleOAuthClientResolver.normalizedSecret(""))
        XCTAssertNil(GoogleOAuthClientResolver.normalizedSecret("  "))
    }

    func test_placeholderSecretIsNil() {
        XCTAssertNil(
            GoogleOAuthClientResolver.normalizedSecret("REPLACE_BY_YOUR_GOOGLE_CLIENT_SECRET"))
    }

    func test_realSecretSurvives() {
        XCTAssertEqual(GoogleOAuthClientResolver.normalizedSecret(" GOCSPX-x "), "GOCSPX-x")
    }

    // MARK: - Building

    func test_makeReturnsNilWhenTheIDIsUnusable() {
        XCTAssertNil(GoogleOAuthClientResolver.make(
            clientID: "", clientSecret: "GOCSPX-x", origin: .shipped))
    }

    func test_makeNormalizesBothFields() {
        let client = GoogleOAuthClientResolver.make(
            clientID: "1234-abc", clientSecret: "", origin: .userSupplied)
        XCTAssertEqual(client?.clientID, "1234-abc\(suffix)")
        XCTAssertNil(client?.clientSecret, "no secret must reach AppAuth as nil, not \"\"")
        XCTAssertEqual(client?.origin, .userSupplied)
    }

    // MARK: - Precedence

    private func shipped() -> GoogleOAuthClient {
        GoogleOAuthClientResolver.make(
            clientID: "shipped-1", clientSecret: "s", origin: .shipped)!
    }

    private func mine() -> GoogleOAuthClient {
        GoogleOAuthClientResolver.make(
            clientID: "mine-1", clientSecret: "", origin: .userSupplied)!
    }

    func test_shippedClientIsUsedByDefault() {
        let resolved = GoogleOAuthClientResolver.resolve(
            shipped: shipped(), userSupplied: mine(), preferUserSupplied: false)
        XCTAssertEqual(resolved?.origin, .shipped)
    }

    func test_userSuppliedClientWinsWhenTurnedOn() {
        let resolved = GoogleOAuthClientResolver.resolve(
            shipped: shipped(), userSupplied: mine(), preferUserSupplied: true)
        XCTAssertEqual(resolved?.origin, .userSupplied)
        XCTAssertEqual(resolved?.clientID, "mine-1\(suffix)")
    }

    /// Turning BYO on with an unusable id must NOT quietly bill the calls to the
    /// shipped client. Someone who deliberately pointed the app at their own
    /// project needs to see the mistake.
    func test_invalidUserSuppliedClientDoesNotFallBackToShipped() {
        let resolved = GoogleOAuthClientResolver.resolve(
            shipped: shipped(), userSupplied: nil, preferUserSupplied: true)
        XCTAssertNil(resolved)
    }

    func test_noClientAtAllResolvesToNil() {
        XCTAssertNil(GoogleOAuthClientResolver.resolve(
            shipped: nil, userSupplied: nil, preferUserSupplied: false))
    }

    /// A build with no shipped credentials is still fully usable by supplying
    /// your own — that is the whole point of the BYO path.
    func test_userSuppliedClientWorksWithNoShippedCredentials() {
        let resolved = GoogleOAuthClientResolver.resolve(
            shipped: nil, userSupplied: mine(), preferUserSupplied: true)
        XCTAssertEqual(resolved?.origin, .userSupplied)
    }

    // MARK: - Token identity

    /// Tokens belong to the client that obtained them. Switching clients must
    /// invalidate them rather than replaying another client's refresh token.
    func test_switchingClientChangesTokenIdentity() {
        XCTAssertNotEqual(shipped().tokenIdentity, mine().tokenIdentity)
    }

    /// Correcting a mistyped secret for the SAME client must not throw away a
    /// working session.
    func test_changingOnlyTheSecretKeepsTokenIdentity() {
        let before = GoogleOAuthClientResolver.make(
            clientID: "same-1", clientSecret: "wrong", origin: .userSupplied)!
        let after = GoogleOAuthClientResolver.make(
            clientID: "same-1", clientSecret: "right", origin: .userSupplied)!
        XCTAssertEqual(before.tokenIdentity, after.tokenIdentity)
    }

    /// The two accepted id forms are the same client, so entering one and then
    /// the other must not force a re-sign-in.
    func test_theTwoIDFormsShareATokenIdentity() {
        let bare = GoogleOAuthClientResolver.make(
            clientID: "same-1", clientSecret: "", origin: .userSupplied)!
        let full = GoogleOAuthClientResolver.make(
            clientID: "same-1\(suffix)", clientSecret: "", origin: .userSupplied)!
        XCTAssertEqual(bare.tokenIdentity, full.tokenIdentity)
    }
}
