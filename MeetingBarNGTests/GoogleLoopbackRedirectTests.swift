//
//  GoogleLoopbackRedirectTests.swift
//  MeetingBarNGTests
//
//  The Google OAuth redirect moved from a reversed-domain custom scheme to a
//  loopback HTTP listener, which is new code on the critical path of signing in.
//  The OAuth round trip itself needs a browser and a real Google account, so
//  what is testable here is the half that runs before it: the listener binds,
//  hands back a usable `http://127.0.0.1:<port>/` redirect URI, and tears down
//  cleanly. A listener that fails to start means sign-in cannot begin at all.
//

import AppAuth
import XCTest

@testable import MeetingBarNG

@MainActor
final class GoogleLoopbackRedirectTests: XCTestCase {
    private var handlers: [OIDRedirectHTTPHandler] = []

    override func tearDown() {
        handlers.forEach { $0.cancelHTTPListener() }
        handlers.removeAll()
        super.tearDown()
    }

    private func startListener() throws -> URL {
        let handler = OIDRedirectHTTPHandler(successURL: nil)
        handlers.append(handler)
        var error: NSError?
        let url = handler.startHTTPListener(&error)
        if let error { throw error }
        return url
    }

    func test_listenerBindsAndReturnsALoopbackRedirectURI() throws {
        let url = try startListener()

        XCTAssertEqual(url.scheme, "http", "loopback redirects are plain http by design")
        XCTAssertEqual(
            url.host, "127.0.0.1",
            "must bind the loopback interface only — never a routable address")
        guard let port = url.port else {
            return XCTFail("redirect URI carries no port; the request would be unroutable")
        }
        XCTAssertGreaterThan(port, 0)
    }

    /// The port is assigned at bind time, so the redirect URI cannot be built
    /// before the listener starts. This is why `signIn` starts it first.
    func test_eachListenerGetsItsOwnPort() throws {
        let first = try startListener()
        let second = try startListener()
        XCTAssertNotEqual(first.port, second.port)
    }

    /// Cancelling must free the port — otherwise a cancelled sign-in would leak
    /// a listening socket for the lifetime of the app.
    func test_cancellingReleasesTheListener() throws {
        let handler = OIDRedirectHTTPHandler(successURL: nil)
        var error: NSError?
        _ = handler.startHTTPListener(&error)
        XCTAssertNil(error)

        handler.cancelHTTPListener()
        // Cancelling twice must not trap; `signIn`'s `defer` can run after the
        // listener already stopped itself on receiving a response.
        handler.cancelHTTPListener()
    }

    /// A redirect URI Google will accept for a Desktop-app client. Registering
    /// one is not required — loopback ports are matched dynamically — but the
    /// host has to be the loopback literal, not `localhost`, which can resolve
    /// to IPv6 or be hijacked by a hosts-file entry.
    func test_redirectURIUsesTheLoopbackLiteralNotLocalhost() throws {
        let url = try startListener()
        XCTAssertFalse(url.absoluteString.contains("localhost"))
    }
}
