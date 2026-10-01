//
//  PresetNumberPicker.swift
//  MeetingBarNG
//
//  A reusable "preset chips + Custom" control for numeric preferences, built for
//  Phase 3 of the Preferences overhaul. Replaces the bare ↕ Steppers the user
//  found confusing: common values are one-tap segments, and picking "Custom"
//  reveals the familiar stepper for an arbitrary value. Used by the menu-bar
//  look-ahead threshold and by the menu-bar / dropdown title-length settings.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//  macOS 12-safe (segmented picker + Stepper are both 10.15+).
//

import SwiftUI

/// A segmented control of preset numbers plus a "Custom" segment. Selecting a
/// preset writes it straight to `value`; selecting "Custom" reveals the existing
/// stepper so the user can dial in any value in `range`.
///
/// The control is presentation-only: it reads and writes a single `Int` binding
/// and never changes what the underlying setting does. Presets outside `range`
/// are filtered out, so one call site can pass a shared preset list even when
/// its bound setting has a narrower limit.
struct PresetNumberPicker: View {
    /// Sentinel tag for the "Custom" segment. `Int.min` can never collide with a
    /// real preference value.
    private static let customTag = Int.min

    /// Preset values already filtered to `range`.
    private let presets: [Int]
    private let presetLabel: (Int) -> String
    private let customLabel: String
    @Binding private var value: Int
    private let range: ClosedRange<Int>
    private let step: Int
    private let stepperLabel: (Int) -> String
    private let example: String?
    private let isEnabled: Bool

    /// Whether the "Custom" segment is active (the stepper is revealed). Seeded
    /// once from whether the initial value matches a preset, then sticky: dialing
    /// the stepper to a value that happens to equal a preset does not collapse
    /// the control back to that segment.
    @State private var isCustom: Bool

    init(
        presets: [Int],
        presetLabel: @escaping (Int) -> String,
        customLabel: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        stepperLabel: @escaping (Int) -> String,
        example: String? = nil,
        isEnabled: Bool = true
    ) {
        let available = presets.filter { range.contains($0) }
        self.presets = available
        self.presetLabel = presetLabel
        self.customLabel = customLabel
        self._value = value
        self.range = range
        self.step = step
        self.stepperLabel = stepperLabel
        self.example = example
        self.isEnabled = isEnabled
        self._isCustom = State(initialValue: !available.contains(value.wrappedValue))
    }

    /// Maps the segmented selection to/from the value binding: presets write
    /// through; the sentinel flips into Custom mode without touching `value`.
    private var selection: Binding<Int> {
        Binding(
            get: { isCustom ? Self.customTag : value },
            set: { newValue in
                if newValue == Self.customTag {
                    isCustom = true
                } else {
                    isCustom = false
                    value = newValue
                }
            }
        )
    }

    var body: some View {
        Group {
            Picker("", selection: selection) {
                ForEach(presets, id: \.self) { preset in
                    Text(presetLabel(preset)).tag(preset)
                }
                Text(customLabel).tag(Self.customTag)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .preferenceIndent()
            .disabled(!isEnabled)

            if isCustom {
                HStack {
                    Spacer()
                    Stepper(value: $value, in: range, step: step) {
                        Text(stepperLabel(value)).monospacedDigit()
                    }
                    .fixedSize()
                }
                .preferenceIndent()
                .disabled(!isEnabled)
            }

            if let example {
                Text(example)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .preferenceIndent()
            }
        }
    }
}
