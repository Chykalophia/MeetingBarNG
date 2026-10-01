//
//  GoogleIDTokenTests.swift
//  MeetingBarLogicTests
//
//  THE REGRESSION THIS FILE EXISTS FOR: every Google calendar was filed under
//  "Other" in the calendar list, because the account address could not be read
//  out of the ID token. The payload is base64URL and the decoder used standard
//  base64, which fails — silently, returning nil, so it looked like Google had
//  simply not sent an address.
//

import Foundation
import XCTest

@testable import PunctualLogic

final class GoogleIDTokenTests: XCTestCase {
    /// Builds a JWT the way Google does: base64URL, no padding.
    private func makeToken(payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }

    // MARK: - The actual bug

    func test_emailIsReadFromARealShapedGoogleToken() {
        let token = makeToken(payload: [
            "iss": "https://accounts.google.com",
            "email": "peter@chykalophia.com",
            "email_verified": true,
            "hd": "chykalophia.com"
        ])
        XCTAssertEqual(GoogleIDToken.email(fromIDToken: token), "peter@chykalophia.com")
    }

    /// The specific failure: standard-base64 decoding rejects the URL alphabet.
    /// A payload long enough to contain `-` or `_` after encoding is exactly
    /// what a real token looks like, so this was not an edge case.
    func test_payloadUsingTheURLAlphabetDecodes() {
        // 0xFB 0xFF encodes to "+/8" in standard base64 and "-_8" in base64URL.
        let urlAlphabet = "-_8="
        XCTAssertNotNil(
            GoogleIDToken.decodeBase64URL(urlAlphabet),
            "base64URL characters must be translated before decoding")
        XCTAssertNil(
            Data(base64Encoded: "-_8="),
            "sanity: this is precisely what the previous implementation called")
    }

    /// Padding is stripped from JWT segments, so every length except a multiple
    /// of four has to be restored before decoding.
    func test_unpaddedPayloadsOfEveryLengthDecode() {
        for length in 1...12 {
            let payload = ["email": String(repeating: "a", count: length) + "@x.com"]
            let token = makeToken(payload: payload)
            XCTAssertNotNil(
                GoogleIDToken.email(fromIDToken: token),
                "unpadded payload of interior length \\(length) failed to decode")
        }
    }

    // MARK: - Degrading honestly

    func test_missingTokenIsNil() {
        XCTAssertNil(GoogleIDToken.email(fromIDToken: nil))
        XCTAssertNil(GoogleIDToken.email(fromIDToken: ""))
    }

    func test_nonJWTStringIsNil() {
        XCTAssertNil(GoogleIDToken.email(fromIDToken: "not-a-token"))
        XCTAssertNil(GoogleIDToken.email(fromIDToken: "only.two"))
        XCTAssertNil(GoogleIDToken.email(fromIDToken: "a.b.c.d"))
    }

    func test_tokenWithoutAnEmailClaimIsNil() {
        XCTAssertNil(GoogleIDToken.email(fromIDToken: makeToken(payload: ["sub": "123"])))
    }

    /// An empty claim is no address, not an address that renders as a blank
    /// account heading.
    func test_emptyEmailClaimIsNil() {
        XCTAssertNil(GoogleIDToken.email(fromIDToken: makeToken(payload: ["email": ""])))
    }

    func test_undecodablePayloadIsNil() {
        XCTAssertNil(GoogleIDToken.email(fromIDToken: "header.!!!!.signature"))
    }

    /// A remainder of 1 cannot occur in valid base64; padding it would produce
    /// silently wrong bytes rather than a clean failure.
    func test_impossibleLengthIsRejectedRatherThanMisdecoded() {
        XCTAssertNil(GoogleIDToken.decodeBase64URL("abcde"))
    }

    func test_claimsExposeTheWholePayload() {
        let token = makeToken(payload: ["email": "a@b.com", "hd": "b.com"])
        let claims = GoogleIDToken.claims(fromIDToken: token)
        XCTAssertEqual(claims?["hd"] as? String, "b.com")
    }
}
