//
//  URLHandlerTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBarNG

@MainActor
final class URLHandlerTests: XCTestCase {
    func testPreferencesURLRoutesToPreferences() {
        let handler = URLHandler()

        XCTAssertEqual(
            handler.route(for: URL(string: "punctual://preferences")!),
            .preferences
        )
    }

    func testOAuthCallbackRoutesToOAuth() {
        let handler = URLHandler()
        let url = URL(string: "com.googleusercontent.apps.123:/oauthredirect?code=abc")!

        XCTAssertEqual(handler.route(for: url), .oauthCallback(url))
    }

    func testUnknownMeetingBarURLRoutesToUnknown() {
        let handler = URLHandler()
        let url = URL(string: "punctual://calendar/123")!

        XCTAssertEqual(handler.route(for: url), .unknown(url))
    }
}
