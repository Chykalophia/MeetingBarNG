//
//  MeetingPrepLinksTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class MeetingPrepLinksTests: XCTestCase {
    func testReturnsEmptyForNilNotesAndLocation() {
        XCTAssertTrue(
            MeetingPrepLinks.extract(notes: nil, location: nil, excluding: []).isEmpty
        )
    }

    func testReturnsEmptyForEmptyOrLinklessText() {
        XCTAssertTrue(
            MeetingPrepLinks.extract(notes: "", location: "   ", excluding: []).isEmpty
        )
        XCTAssertTrue(
            MeetingPrepLinks.extract(
                notes: "Standup — no links here",
                location: "Conference Room 5",
                excluding: []
            ).isEmpty
        )
    }

    func testExtractsMultipleURLsFromNotesInOrder() {
        let notes = """
        Design: https://www.figma.com/file/ABC/Spec
        Repo: https://github.com/acme/app
        Handbook: https://example.com/handbook
        """
        let links = MeetingPrepLinks.extract(notes: notes, location: nil, excluding: [])
        XCTAssertEqual(links.map(\.kind), [.figma, .github, .generic])
        XCTAssertEqual(links.map(\.url), [
            "https://www.figma.com/file/ABC/Spec",
            "https://github.com/acme/app",
            "https://example.com/handbook"
        ])
    }

    func testClassifiesKnownHosts() {
        let cases: [(String, PrepLinkKind)] = [
            ("https://www.figma.com/file/ABC/Spec", .figma),
            ("https://acme.notion.site/Page-123", .notion),
            ("https://www.notion.so/Page-123", .notion),
            ("https://github.com/acme/app", .github),
            ("https://docs.google.com/document/d/ABC/edit", .googleDoc),
            ("https://docs.google.com/spreadsheets/d/ABC/edit", .googleSheet),
            ("https://docs.google.com/presentation/d/ABC/edit", .googleSlides),
            ("https://drive.google.com/file/d/ABC/view", .googleDrive),
            ("https://linear.app/acme/issue/ABC-1", .linear),
            ("https://acme.atlassian.net/browse/ABC-1", .jira),
            ("https://acme.atlassian.net/wiki/spaces/X", .confluence),
            ("https://www.loom.com/share/ABC", .loom),
            ("https://example.com/notes", .generic)
        ]
        for (url, expected) in cases {
            let links = MeetingPrepLinks.extract(notes: url, location: nil, excluding: [])
            XCTAssertEqual(links.first?.kind, expected, url)
        }
    }

    func testGoogleDocsVsSheetsVsSlidesDistinction() {
        let notes = """
        https://docs.google.com/document/d/1/edit
        https://docs.google.com/spreadsheets/d/2/edit
        https://docs.google.com/presentation/d/3/edit
        """
        let links = MeetingPrepLinks.extract(notes: notes, location: nil, excluding: [])
        XCTAssertEqual(links.map(\.kind), [.googleDoc, .googleSheet, .googleSlides])
        XCTAssertEqual(
            links.map(\.displayTitle),
            ["Google Doc", "Google Sheet", "Google Slides"]
        )
    }

    func testExcludesTheJoinURL() {
        // Simulates a custom (non-well-known-host) meeting link passed via
        // `event.url`, which the join-host list would not otherwise catch.
        let join = "https://example.com/room/42"
        let notes = "Join \(join)\nPrep https://www.figma.com/file/ABC/Spec"
        let links = MeetingPrepLinks.extract(notes: notes, location: nil, excluding: [join])
        XCTAssertEqual(links.map(\.kind), [.figma])
    }

    func testExcludesJoinURLIgnoringTrailingSlashAndCase() {
        let notes = "Prep https://www.figma.com/file/ABC/Spec and https://EXAMPLE.com/room/42/"
        let links = MeetingPrepLinks.extract(
            notes: notes,
            location: nil,
            excluding: ["https://example.com/room/42"]
        )
        XCTAssertEqual(links.map(\.kind), [.figma])
    }

    func testExcludesKnownMeetingJoinHosts() {
        let notes = """
        https://meet.google.com/abc-defg-hij
        https://us02web.zoom.us/j/12345
        https://teams.microsoft.com/l/meetup-join/abc
        https://www.figma.com/file/ABC/Spec
        """
        let links = MeetingPrepLinks.extract(notes: notes, location: nil, excluding: [])
        XCTAssertEqual(links.map(\.kind), [.figma])
    }

    func testGoogleDocsAndDriveAreNotTreatedAsMeetingHosts() {
        // docs.google.com / drive.google.com share the google.com parent but are
        // prep hosts — only meet.google.com is a join host.
        let notes = """
        https://docs.google.com/document/d/1/edit
        https://drive.google.com/file/d/2/view
        """
        let links = MeetingPrepLinks.extract(notes: notes, location: nil, excluding: [])
        XCTAssertEqual(links.map(\.kind), [.googleDoc, .googleDrive])
    }

    func testDedupsCaseInsensitivelyOnFullURL() {
        let notes = """
        https://www.figma.com/file/ABC/Spec
        https://WWW.Figma.com/file/ABC/Spec
        """
        let links = MeetingPrepLinks.extract(notes: notes, location: nil, excluding: [])
        XCTAssertEqual(links.count, 1)
    }

    func testCombinesNotesAndLocationPreservingOrder() {
        let links = MeetingPrepLinks.extract(
            notes: "https://github.com/acme/app",
            location: "https://www.figma.com/file/ABC/Spec",
            excluding: []
        )
        XCTAssertEqual(links.map(\.kind), [.github, .figma])
    }

    func testCapsAtMaxLinks() {
        let urls = (1 ... 12).map { "https://example\($0).com/x" }
        let notes = urls.joined(separator: "\n")
        let links = MeetingPrepLinks.extract(notes: notes, location: nil, excluding: [])
        XCTAssertEqual(links.count, MeetingPrepLinks.maxLinks)
        XCTAssertEqual(links.first?.url, "https://example1.com/x")
    }

    func testGitHubDisplayTitleIncludesOwnerRepo() {
        let links = MeetingPrepLinks.extract(
            notes: "https://github.com/acme/app/pull/7",
            location: nil,
            excluding: []
        )
        XCTAssertEqual(links.first?.displayTitle, "GitHub · acme/app")
    }

    func testGenericDisplayTitleIsHostWithoutWWW() {
        let links = MeetingPrepLinks.extract(
            notes: "https://handbook.example.com/page",
            location: nil,
            excluding: []
        )
        XCTAssertEqual(links.first?.displayTitle, "handbook.example.com")
    }

    func testTrimsTrailingSentencePunctuation() {
        let links = MeetingPrepLinks.extract(
            notes: "See https://www.figma.com/file/ABC/Spec.",
            location: nil,
            excluding: []
        )
        XCTAssertEqual(links.first?.url, "https://www.figma.com/file/ABC/Spec")
    }

    func testExtractsURLFromHTMLHrefWithoutBleedingMarkup() {
        let links = MeetingPrepLinks.extract(
            notes: "<a href=\"https://github.com/acme/app\">Repo</a>",
            location: nil,
            excluding: []
        )
        XCTAssertEqual(links.map(\.url), ["https://github.com/acme/app"])
        XCTAssertEqual(links.first?.kind, .github)
    }
}
