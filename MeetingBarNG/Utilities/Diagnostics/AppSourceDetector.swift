//
//  AppSourceDetector.swift
//  MeetingBar
//
//  Detects whether the running build was installed from the Mac App Store.
//  Relocated from the (removed) PatronageService by MeetingBarNG; the only
//  remaining consumer is the diagnostics report.
//

import Foundation

enum AppSourceDetector {
    static func isAppStoreBuild(
        receiptURL: URL? = Bundle.main.appStoreReceiptURL,
        fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) -> Bool {
        guard let receiptURL else { return false }
        return fileExists(receiptURL.path)
    }
}
