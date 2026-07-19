//
//  CameraPreviewView.swift
//  MeetingBarNG
//
//  SwiftUI surface for the pre-call "mirror check": a live self-view camera
//  preview (an AVCaptureVideoPreviewLayer wrapped in an NSViewRepresentable), a
//  horizontal microphone input-level meter, camera/mic device pickers, and a
//  permission-denied state with a System Settings affordance. When opened for a
//  specific event it shows a prominent "Join meeting" button; opened standalone
//  it shows Close only. Presentation-only over CameraPreviewController — no
//  recording, saving, or transcription.
//
//  Created for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import AVFoundation
import SwiftUI

/// Closures the preview window needs from the app, injected by AppDelegate /
/// WindowCoordinator. `joinEventID` is non-nil only when the preview was opened
/// for a specific event, which is what gates the "Join meeting" button.
struct CameraPreviewHandlers {
    var joinEventID: String?
    var join: @MainActor (String) -> Void = { _ in }
    var dismiss: @MainActor () -> Void = {}
}

enum CameraPreviewLayout {
    static let contentSize = NSSize(width: 640, height: 560)
    static let minimumSize = NSSize(width: 520, height: 460)
}

struct CameraPreviewView: View {
    @StateObject private var controller = CameraPreviewController()
    let handlers: CameraPreviewHandlers

    var body: some View {
        VStack(spacing: 16) {
            previewArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            micMeter

            controls
        }
        .padding(16)
        .frame(minWidth: CameraPreviewLayout.minimumSize.width,
               minHeight: CameraPreviewLayout.minimumSize.height)
        .task { await controller.startPreview() }
        .onDisappear { controller.stop() }
    }

    // MARK: - Preview area

    @ViewBuilder
    private var previewArea: some View {
        switch controller.cameraAccess {
        case .authorized:
            if controller.hasNoCamera {
                messageOverlay(
                    symbol: "video.slash",
                    title: "camera_preview_no_camera_title".loco(),
                    message: "camera_preview_no_camera_message".loco()
                )
            } else {
                CameraLivePreview(session: controller.session)
            }
        case .denied, .restricted:
            deniedOverlay(
                title: "camera_preview_camera_denied_title".loco(),
                message: "camera_preview_camera_denied_message".loco(),
                openSettings: { controller.openCameraSettings() }
            )
        case .notDetermined:
            messageOverlay(
                symbol: "video",
                title: "camera_preview_requesting_title".loco(),
                message: "camera_preview_requesting_message".loco()
            )
        }
    }

    private func messageOverlay(symbol: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.7))
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func deniedOverlay(
        title: String,
        message: String,
        openSettings: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.7))
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Button("camera_preview_open_settings".loco(), action: openSettings)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Mic meter

    @ViewBuilder
    private var micMeter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.secondary)
                Text("camera_preview_mic_level_label".loco())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if controller.micAccess != .authorized {
                    Button("camera_preview_open_settings".loco()) {
                        controller.openMicrophoneSettings()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }

            if controller.micAccess == .authorized {
                MicLevelBar(level: controller.micLevel)
                    .frame(height: 10)
            } else {
                Text("camera_preview_mic_unavailable".loco())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            if controller.cameraAccess == .authorized, !controller.videoDevices.isEmpty {
                Picker(
                    "camera_preview_camera_picker_label".loco(),
                    selection: Binding(
                        get: { controller.selectedVideoDeviceID ?? "" },
                        set: { controller.selectVideoDevice(id: $0) }
                    )
                ) {
                    ForEach(controller.videoDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
            }

            if controller.micAccess == .authorized, !controller.audioDevices.isEmpty {
                Picker(
                    "camera_preview_mic_picker_label".loco(),
                    selection: Binding(
                        get: { controller.selectedAudioDeviceID ?? "" },
                        set: { controller.selectAudioDevice(id: $0) }
                    )
                ) {
                    ForEach(controller.audioDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
            }

            HStack {
                Spacer()
                Button("camera_preview_close".loco()) {
                    handlers.dismiss()
                }
                .keyboardShortcut(.cancelAction)

                if let joinEventID = handlers.joinEventID {
                    Button("camera_preview_join".loco()) {
                        handlers.join(joinEventID)
                        handlers.dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

/// Simple horizontal mic-level bar filled proportionally to a 0…1 level, with a
/// color that warms as the level climbs — a coarse visual meter, not a precise VU.
struct MicLevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.2))
                RoundedRectangle(cornerRadius: 5)
                    .fill(fillColor)
                    .frame(width: geometry.size.width * CGFloat(clampedLevel))
            }
        }
    }

    private var clampedLevel: Float {
        min(max(level, 0), 1)
    }

    private var fillColor: Color {
        switch clampedLevel {
        case ..<0.6: return .green
        case ..<0.85: return .yellow
        default: return .red
        }
    }
}

/// Wraps an NSView whose backing layer is an `AVCaptureVideoPreviewLayer` fed by
/// the controller's session — the live self-view.
struct CameraLivePreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context _: Context) -> CameraPreviewNSView {
        CameraPreviewNSView(session: session)
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context _: Context) {
        if nsView.previewLayer.session !== session {
            nsView.previewLayer.session = session
        }
    }
}

/// NSView whose backing layer IS the preview layer, so it resizes with the view.
final class CameraPreviewNSView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer {
        previewLayer
    }
}
