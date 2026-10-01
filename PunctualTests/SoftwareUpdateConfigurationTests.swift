//
//  SoftwareUpdateConfigurationTests.swift
//  Punctual
//
//  Pins the Sparkle configuration that decides whether an update can be found,
//  trusted and installed. Reads the BUILT app's Info.plist (the test host) and
//  the entitlement files every signing path uses.
//
//  Original work for Punctual by Peter Krzyzek / Chykalophia, 2026.
//

import XCTest

@testable import Punctual

final class SoftwareUpdateConfigurationTests: XCTestCase {
    private func info(_ key: String) -> Any? {
        Bundle.main.object(forInfoDictionaryKey: key)
    }

    /// The feed every shipped build checks. HTTPS only, and the "latest
    /// release" alias, so each published release's own appcast.xml is the one
    /// served. A local test build may override it; a shipped one must not.
    func testFeedIsTheLatestGitHubReleaseOverHTTPS() {
        XCTAssertEqual(
            info("SUFeedURL") as? String,
            "https://github.com/Chykalophia/Punctual/releases/latest/download/appcast.xml"
        )
    }

    /// Every update must carry an EdDSA signature that verifies against this
    /// key. A missing or malformed key would make Sparkle refuse all updates,
    /// or (worse, in older Sparkle) fall back to weaker checks.
    func testPublicKeyIsAValidEd25519Key() throws {
        let base64 = try XCTUnwrap(info("SUPublicEDKey") as? String)
        let raw = try XCTUnwrap(Data(base64Encoded: base64), "SUPublicEDKey is not base64")
        XCTAssertEqual(raw.count, 32, "an Ed25519 public key is 32 bytes")
    }

    /// The app is sandboxed, so Sparkle can only install through its installer
    /// launcher service.
    func testSandboxInstallerServiceIsEnabled() {
        XCTAssertEqual(info("SUEnableInstallerLauncherService") as? Bool, true)
    }

    /// The installer service is reachable only with these mach-lookup
    /// exceptions. Every entitlements file a build can be signed with must have
    /// them, or updates fail only in that kind of build.
    func testEveryEntitlementsFileAllowsSparklesInstaller() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // PunctualTests
            .deletingLastPathComponent()  // repo root
        let files = [
            "Punctual/Punctual.entitlements",
            "XCConfig/DeveloperID.entitlements",
            "XCConfig/LocalSigning.entitlements"
        ]
        for file in files {
            let url = repoRoot.appendingPathComponent(file)
            let plist = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: Any], file)
            let names = plist["com.apple.security.temporary-exception.mach-lookup.global-name"] as? [String]
            XCTAssertEqual(
                Set(names ?? []),
                ["$(PRODUCT_BUNDLE_IDENTIFIER)-spks", "$(PRODUCT_BUNDLE_IDENTIFIER)-spki"],
                "\(file) is missing Sparkle's installer exceptions"
            )
        }
    }
}
