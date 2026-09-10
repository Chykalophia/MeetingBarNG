//
//  OAuthCompletionPageTests.swift
//  MeetingBarNGTests
//
//  The page the browser lands on after Google hands back the code, replacing
//  AppAuth's hardcoded "Authorization complete. Return to the app."
//

import XCTest

@testable import MeetingBarNG

@MainActor
final class OAuthCompletionPageTests: XCTestCase {
    // MARK: - Content

    func test_pageNamesTheConnectedAccount() {
        let html = OAuthCompletionPage.html(accountEmail: "peter@example.com")
        XCTAssertTrue(html.contains("peter@example.com"))
    }

    /// The account is optional — the ID token may carry no email — and the page
    /// must not render an empty line where an address would be.
    func test_pageOmitsTheAccountLineWhenThereIsNoEmail() {
        for empty in [nil, ""] as [String?] {
            let html = OAuthCompletionPage.html(accountEmail: empty)
            XCTAssertFalse(html.contains("class=\"account\""))
        }
    }

    func test_pageTellsTheUserWhatToDoNext() {
        // The specific failing of AppAuth's page: it says the authorization
        // finished but not that the tab is now disposable.
        let html = OAuthCompletionPage.html(accountEmail: nil)
        XCTAssertTrue(html.lowercased().contains("close this tab"))
    }

    func test_pageIsSelfContained() {
        // The socket closes immediately after this response, so a second
        // request for a stylesheet or an image would simply fail.
        let html = OAuthCompletionPage.html(accountEmail: "a@b.com")
        XCTAssertFalse(html.contains("<link"))
        XCTAssertFalse(html.contains("src=\"http"))
        XCTAssertTrue(html.contains("<style>"))
    }

    func test_pageAdaptsToTheSystemTheme() {
        let html = OAuthCompletionPage.html(accountEmail: nil)
        XCTAssertTrue(html.contains("prefers-color-scheme: dark"))
    }

    // MARK: - Escaping
    //
    // The address comes out of Google's ID token, so it is not ours to trust
    // unescaped in markup.

    func test_accountEmailIsHTMLEscaped() {
        let html = OAuthCompletionPage.html(accountEmail: "<script>alert(1)</script>@x.com")
        XCTAssertFalse(html.contains("<script>alert(1)</script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }

    func test_escapeCoversTheAttributeBreakingCharacters() {
        XCTAssertEqual(
            OAuthCompletionPage.escape("&<>\"'"),
            "&amp;&lt;&gt;&quot;&#39;"
        )
    }

    /// Ampersand must be replaced FIRST or the escapes of the other characters
    /// get double-escaped into visible mojibake.
    func test_ampersandIsNotDoubleEscaped() {
        XCTAssertEqual(OAuthCompletionPage.escape("a&lt;b"), "a&amp;lt;b")
    }

    // MARK: - Serving

    func test_serverBindsLoopbackAndServesThePage() async throws {
        let server = OAuthCompletionPageServer()
        defer { server.stop() }

        server.setAccountEmail("peter@example.com")
        guard let url = await server.start() else {
            return XCTFail("completion page listener did not bind")
        }

        XCTAssertEqual(url.host, "127.0.0.1", "must never bind a routable address")
        XCTAssertNotNil(url.port)

        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(
            http.value(forHTTPHeaderField: "Content-Type"),
            "text/html; charset=utf-8"
        )
        // The page names an account, so it must not be cached.
        XCTAssertEqual(http.value(forHTTPHeaderField: "Cache-Control"), "no-store")

        let body = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(body.contains("peter@example.com"))
        XCTAssertTrue(body.contains("<!doctype html>"))
    }

    /// Any path gets the page: the only client is a browser this app just
    /// redirected, and a 404 on a stray path would be a worse outcome than an
    /// extra copy of a static page.
    func test_anyPathServesThePage() async throws {
        let server = OAuthCompletionPageServer()
        defer { server.stop() }
        guard let url = await server.start() else {
            return XCTFail("completion page listener did not bind")
        }

        let other = try XCTUnwrap(URL(string: "http://127.0.0.1:\(url.port!)/anything"))
        let (data, response) = try await URLSession.shared.data(from: other)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(try XCTUnwrap(String(data: data, encoding: .utf8)).contains("<!doctype html>"))
    }

    func test_stoppingReleasesThePort() async throws {
        let server = OAuthCompletionPageServer()
        guard let url = await server.start() else {
            return XCTFail("completion page listener did not bind")
        }
        let port = try XCTUnwrap(url.port)
        server.stop()

        // Restarting must bind a fresh port rather than fail on the old one.
        let restarted = await server.start()
        defer { server.stop() }
        XCTAssertNotNil(restarted)
        XCTAssertNotEqual(restarted?.port, port)
    }
}
