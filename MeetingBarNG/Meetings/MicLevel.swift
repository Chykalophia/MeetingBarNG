//
//  MicLevel.swift
//  MeetingBarNG
//
//  Pure, hostless normalization for the pre-call camera/mic preview meter. Maps
//  a raw dBFS reading (as reported by an `AVCaptureAudioChannel.averagePowerLevel`,
//  roughly -160…0) onto a 0…1 scale for a simple input-level bar. Kept free of
//  AVFoundation/AppKit so it compiles into the MeetingBarLogic test target and is
//  unit-testable without a live capture session.
//
//  Created for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Foundation

/// Normalizes microphone power readings for the preview meter.
public enum MicLevel {
    /// dB reading at or below which the meter reads empty. -60 dBFS is a common
    /// noise-floor choice for a coarse input meter.
    public static let defaultFloorDecibels: Float = -60

    /// Maps a `decibels` reading (dBFS, ≤ 0 at full scale) to a clamped 0…1
    /// value, linear in decibels between `floorDecibels` (→ 0) and 0 dB (→ 1).
    ///
    /// - Non-finite input (NaN / -inf silence) returns 0.
    /// - A non-negative `floorDecibels` is clamped to -1 so the range never
    ///   collapses or divides by zero.
    public static func normalized(
        decibels: Float,
        floorDecibels: Float = defaultFloorDecibels
    ) -> Float {
        guard decibels.isFinite else { return 0 }
        let floor = min(floorDecibels, -1)
        if decibels <= floor { return 0 }
        if decibels >= 0 { return 1 }
        return (decibels - floor) / -floor
    }
}
