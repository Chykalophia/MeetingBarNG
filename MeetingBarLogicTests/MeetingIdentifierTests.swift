//
//  MeetingIdentifierTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for meeting-ID extraction (MeetingBarNG): which URLs yield a
//  usable identifier, which correctly yield nothing, and which must NOT yield a
//  confidently-wrong one.
//

import XCTest

@testable import MeetingBarLogic

final class MeetingIdentifierTests: XCTestCase {
    private func identifier(_ string: String) -> MeetingIdentifier? {
        guard let url = URL(string: string) else {
            XCTFail("test URL did not parse: \(string)")
            return nil
        }
        return MeetingIdentifierPolicy.identifier(from: url)
    }

    // MARK: - Zoom

    func testZoomJoinURLYieldsNumericID() {
        let result = identifier("https://us02web.zoom.us/j/12345678901")
        XCTAssertEqual(result?.value, "12345678901")
        XCTAssertEqual(result?.kind, .meetingID)
    }

    func testZoomIDSurvivesAQueryPassword() {
        // The password belongs to the link, not the id — copying it into a
        // dial-in prompt would be wrong.
        XCTAssertEqual(identifier("https://us02web.zoom.us/j/98765432?pwd=aBcDeF")?.value, "98765432")
    }

    func testZoomTenantPrefixDoesNotHideTheID() {
        // `/company/j/<id>` is common on business accounts; a positional parse
        // would read "j" as the id here.
        XCTAssertEqual(identifier("https://zoom.us/chykalophia/j/5551234567")?.value, "5551234567")
    }

    func testZoomWebinarAndPersonalLinkForms() {
        XCTAssertEqual(identifier("https://zoom.us/w/1112223333")?.value, "1112223333")
        XCTAssertEqual(identifier("https://zoom.us/s/4445556666")?.value, "4445556666")
    }

    func testZoomPersonalRoomIsARoomNotAnID() {
        let result = identifier("https://zoom.us/my/peter.krzyzek")
        XCTAssertEqual(result?.value, "peter.krzyzek")
        XCTAssertEqual(result?.kind, .room, "a named personal room is not a dial-in id")
    }

    func testZoomGovAndZhumuShareTheGrammar() {
        XCTAssertEqual(identifier("https://www.zoomgov.com/j/1602222333")?.value, "1602222333")
        XCTAssertEqual(identifier("https://welink.zhumu.com/j/7778889990")?.value, "7778889990")
    }

    func testZoomWithoutADigitRunYieldsNothing() {
        XCTAssertNil(identifier("https://zoom.us/download"))
        XCTAssertNil(identifier("https://zoom.us/j/not-a-number"))
    }

    // MARK: - Google Meet

    func testGoogleMeetCodeKeepsItsHyphens() {
        // The hyphenated form is canonical for Meet — stripping them would make
        // the value harder to use, not easier.
        let result = identifier("https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(result?.value, "abc-defg-hij")
        XCTAssertEqual(result?.kind, .meetingID)
    }

    func testGoogleMeetNonCodePathsYieldNothing() {
        XCTAssertNil(identifier("https://meet.google.com/new"))
        XCTAssertNil(identifier("https://meet.google.com/landing"))
        // Right shape, wrong group lengths.
        XCTAssertNil(identifier("https://meet.google.com/ab-cdef-ghi"))
        // Digits are not part of a Meet code.
        XCTAssertNil(identifier("https://meet.google.com/abc-1234-hij"))
    }

    // MARK: - Teams: the deliberate nil

    func testTeamsYieldsNothingRatherThanAThreadID() {
        // The thread id in a Teams URL is NOT the conference ID a dial-in prompt
        // asks for. Offering it under "Copy meeting ID" would be confidently
        // wrong, which is worse than offering nothing.
        XCTAssertNil(identifier(
            "https://teams.microsoft.com/l/meetup-join/19%3ameeting_ZGJhY2Q%40thread.v2/0"
        ))
    }

    // MARK: - Webex

    func testWebexPersonalRoomIsExtractable() {
        let result = identifier("https://chykalophia.webex.com/meet/peter")
        XCTAssertEqual(result?.value, "peter")
        XCTAssertEqual(result?.kind, .room)
    }

    func testWebexScheduledMeetingTokenIsNotAnID() {
        // MTID is an opaque token, not the meeting number.
        XCTAssertNil(identifier("https://chykalophia.webex.com/webappng/sites/x/j.php?MTID=m1234"))
    }

    // MARK: - Other numeric services

    func testChimeGoToAndBlueJeans() {
        XCTAssertEqual(identifier("https://chime.aws/1234567890")?.value, "1234567890")
        XCTAssertEqual(identifier("https://www.gotomeeting.com/join/123456789")?.value, "123456789")
        XCTAssertEqual(identifier("https://bluejeans.com/123456789")?.value, "123456789")
    }

    // MARK: - Named rooms

    func testNamedRoomServices() {
        XCTAssertEqual(identifier("https://meet.jit.si/chykalophia-standup")?.kind, .room)
        XCTAssertEqual(identifier("https://whereby.com/chykalophia")?.value, "chykalophia")
        XCTAssertEqual(identifier("https://8x8.vc/daily")?.value, "daily")
    }

    func testRoomHostMarketingPagesAreNotRooms() {
        // Otherwise a link to the pricing page offers to copy "pricing".
        XCTAssertNil(identifier("https://whereby.com/pricing"))
        XCTAssertNil(identifier("https://whereby.com/about"))
    }

    func testDeepPathOnARoomHostIsNotARoom() {
        // A settings or recording page, not something anyone can join.
        XCTAssertNil(identifier("https://whereby.com/chykalophia/settings"))
    }

    // MARK: - Nothing to extract

    func testUnknownHostsAndBarePathsYieldNothing() {
        XCTAssertNil(identifier("https://example.com/some/meeting"))
        XCTAssertNil(identifier("https://zoom.us"))
        XCTAssertNil(identifier("https://meet.google.com"))
    }

    func testLinkConvenienceMatchesTheURLForm() {
        let url = URL(string: "https://us02web.zoom.us/j/12345678901")!
        let viaLink = MeetingIdentifierPolicy.identifier(from: MeetingLink(service: .zoom, url: url))
        XCTAssertEqual(viaLink, MeetingIdentifierPolicy.identifier(from: url))
    }
}
