//
//  AppLifecycleConfigurationTests.swift
//  Punctual
//
//  Pins Info.plist settings that decide whether macOS may quit Punctual on
//  its own. Reads the BUILT app's Info.plist (the test host), not the source
//  file, so it checks what actually ships.
//
//  Original work for Punctual by Peter Krzyzek / Chykalophia, 2026.
//

import XCTest

@testable import Punctual

final class AppLifecycleConfigurationTests: XCTestCase {
    /// A menu-bar app looks idle to macOS almost all the time. With automatic
    /// termination on, macOS marked Punctual auto-quittable the moment its
    /// setup window appeared (seen in the system log, 2026-10-01), so it could
    /// be quit while the user was signing in to Google in the browser and
    /// relaunched fresh at the first setup screen. It must stay off.
    func testAutomaticTerminationIsOff() {
        let value = Bundle.main.object(forInfoDictionaryKey: "NSSupportsAutomaticTermination") as? Bool
        XCTAssertEqual(value, false, "Punctual must not let macOS auto-quit it")
    }

    func testRunsAsAMenuBarAgent() {
        // The premise of the test above: an agent (no Dock icon) has no visible
        // window most of the time, which is exactly when auto-quit applies.
        let value = Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool
        XCTAssertEqual(value, true)
    }
}
