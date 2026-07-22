//
//  CameraPreviewController.swift
//  MeetingBarNG
//
//  Host AVFoundation service backing the pre-call "mirror check" preview: a live
//  self-view camera feed plus a normalized microphone input-level meter, so the
//  user can check their appearance and audio before joining a meeting. This is a
//  raw preview ONLY — no recording, no saving, no transcription/AI of any kind.
//
//  Opt-in like RemindersStore: camera and microphone access are requested ONLY
//  when the preview is opened (`startPreview()`), never at launch, and each is
//  requested independently so the preview works camera-only or mic-only. The
//  session is torn down and the devices released on `stop()` / `deinit` so the
//  camera indicator light turns off when the window closes.
//
//  Created for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import AppKit
import AVFoundation
import CoreMedia
import Foundation

/// Per-device authorization state, surfaced to the view so it can show a live
/// preview, a "request in progress" placeholder, or a denied message + a
/// System Settings affordance.
enum CameraPreviewAccess: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted

    static func from(_ status: AVAuthorizationStatus) -> CameraPreviewAccess {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }
}

/// Flat, Sendable descriptor for a capture device, so device lists can be built
/// on the session queue and published to the main actor without passing a
/// non-Sendable `AVCaptureDevice` across the boundary.
struct CameraDeviceOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

/// Owns the `AVCaptureSession` for the preview window. `@MainActor` for its
/// published UI state; all session mutation happens on a private serial queue
/// (off the main thread so `startRunning()` never hangs the UI), hopping back to
/// the main actor only to publish state. Capture members are `nonisolated(unsafe)`
/// because they are only ever touched from that serial queue (and, for `session`,
/// the final `deinit` release).
@MainActor
final class CameraPreviewController: NSObject, ObservableObject,
    AVCaptureAudioDataOutputSampleBufferDelegate {
    /// The capture session the preview layer renders. Read on the main actor by
    /// the view; mutated only on `sessionQueue`.
    nonisolated(unsafe) let session = AVCaptureSession()

    @Published private(set) var cameraAccess: CameraPreviewAccess = .notDetermined
    @Published private(set) var micAccess: CameraPreviewAccess = .notDetermined
    /// Normalized 0…1 microphone level for the meter. 0 while metering is
    /// unavailable (mic denied, or no audio flowing yet).
    @Published private(set) var micLevel: Float = 0
    @Published private(set) var videoDevices: [CameraDeviceOption] = []
    @Published private(set) var audioDevices: [CameraDeviceOption] = []
    @Published var selectedVideoDeviceID: String?
    @Published var selectedAudioDeviceID: String?
    /// True when camera access is granted but no video device is present
    /// (e.g. a Mac mini with no built-in or attached camera).
    @Published private(set) var hasNoCamera = false
    @Published private(set) var isRunning = false

    nonisolated(unsafe) private var videoInput: AVCaptureDeviceInput?
    nonisolated(unsafe) private var audioInput: AVCaptureDeviceInput?
    nonisolated(unsafe) private let audioOutput = AVCaptureAudioDataOutput()

    nonisolated private let sessionQueue = DispatchQueue(
        label: "com.chykalophia.MeetingBarNG.camera-session"
    )
    nonisolated private let audioSampleQueue = DispatchQueue(
        label: "com.chykalophia.MeetingBarNG.mic-samples"
    )

    // MARK: - Lifecycle

    /// Entry point when the preview opens: request access (opt-in prompt), then
    /// enumerate devices, build inputs, and start the session on the session
    /// queue. Safe to call once per window presentation.
    func startPreview() async {
        let access = await requestAccess()
        let videoID = selectedVideoDeviceID
        let audioID = selectedAudioDeviceID
        sessionQueue.async { [weak self] in
            self?.reloadDevicesAndConfigure(
                cameraGranted: access.camera,
                micGranted: access.mic,
                requestedVideoID: videoID,
                requestedAudioID: audioID
            )
        }
    }

    /// Stops the session and releases the camera + microphone. Called from the
    /// view's `onDisappear` when the window closes so the camera light turns off.
    func stop() {
        micLevel = 0
        isRunning = false
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            for input in self.session.inputs {
                self.session.removeInput(input)
            }
            if self.session.outputs.contains(self.audioOutput) {
                self.audioOutput.setSampleBufferDelegate(nil, queue: nil)
                self.session.removeOutput(self.audioOutput)
            }
            self.session.commitConfiguration()
            self.videoInput = nil
            self.audioInput = nil
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    /// Safety net: guarantee the hardware is released even if `stop()` was never
    /// reached (e.g. the hosting view was torn down without `onDisappear`).
    deinit {
        session.stopRunning()
    }

    // MARK: - Device switching

    func selectVideoDevice(id: String) {
        guard id != selectedVideoDeviceID else { return }
        selectedVideoDeviceID = id
        reconfigure()
    }

    func selectAudioDevice(id: String) {
        guard id != selectedAudioDeviceID else { return }
        selectedAudioDeviceID = id
        reconfigure()
    }

    private func reconfigure() {
        let cameraGranted = cameraAccess == .authorized
        let micGranted = micAccess == .authorized
        let videoID = selectedVideoDeviceID
        let audioID = selectedAudioDeviceID
        sessionQueue.async { [weak self] in
            self?.reloadDevicesAndConfigure(
                cameraGranted: cameraGranted,
                micGranted: micGranted,
                requestedVideoID: videoID,
                requestedAudioID: audioID
            )
        }
    }

    // MARK: - Access (opt-in)

    /// Requests camera and microphone access independently and republishes the
    /// resulting authorization states. This is the ONLY place the system
    /// permission prompts are triggered — never at launch.
    @discardableResult
    func requestAccess() async -> (camera: Bool, mic: Bool) {
        let camera = await Self.requestAccess(for: .video)
        let mic = await Self.requestAccess(for: .audio)
        cameraAccess = CameraPreviewAccess.from(AVCaptureDevice.authorizationStatus(for: .video))
        micAccess = CameraPreviewAccess.from(AVCaptureDevice.authorizationStatus(for: .audio))
        return (camera, mic)
    }

    private static func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: mediaType)
        default:
            return false
        }
    }

    // MARK: - System Settings affordances

    func openCameraSettings() {
        NSWorkspace.shared.open(Links.cameraPreferences)
    }

    func openMicrophoneSettings() {
        NSWorkspace.shared.open(Links.microphonePreferences)
    }

    // MARK: - Session configuration (session queue)

    nonisolated private func reloadDevicesAndConfigure(
        cameraGranted: Bool,
        micGranted: Bool,
        requestedVideoID: String?,
        requestedAudioID: String?
    ) {
        let discoveredVideo = cameraGranted ? Self.discoverVideoDevices() : []
        let discoveredAudio = micGranted ? Self.discoverAudioDevices() : []

        let chosenVideo = discoveredVideo.first { $0.uniqueID == requestedVideoID }
            ?? discoveredVideo.first
        let chosenAudio = discoveredAudio.first { $0.uniqueID == requestedAudioID }
            ?? discoveredAudio.first

        configureSession(video: chosenVideo, audio: chosenAudio)
        if !session.isRunning {
            session.startRunning()
        }

        let videoOptions = discoveredVideo.map {
            CameraDeviceOption(id: $0.uniqueID, name: $0.localizedName)
        }
        let audioOptions = discoveredAudio.map {
            CameraDeviceOption(id: $0.uniqueID, name: $0.localizedName)
        }
        let chosenVideoID = chosenVideo?.uniqueID
        let chosenAudioID = chosenAudio?.uniqueID
        let running = session.isRunning

        Task { @MainActor in
            self.videoDevices = videoOptions
            self.audioDevices = audioOptions
            self.selectedVideoDeviceID = chosenVideoID
            self.selectedAudioDeviceID = chosenAudioID
            self.hasNoCamera = cameraGranted && videoOptions.isEmpty
            self.isRunning = running
        }
    }

    /// Rebuilds the managed inputs/outputs inside a single begin/commit so the
    /// session never observes a half-configured graph. Removing the video input
    /// releases the camera; a fresh input is added for the chosen device.
    nonisolated private func configureSession(
        video: AVCaptureDevice?,
        audio: AVCaptureDevice?
    ) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if let videoInput {
            session.removeInput(videoInput)
            self.videoInput = nil
        }
        if let audioInput {
            session.removeInput(audioInput)
            self.audioInput = nil
        }

        if let video {
            do {
                let input = try AVCaptureDeviceInput(device: video)
                if session.canAddInput(input) {
                    session.addInput(input)
                    videoInput = input
                }
            } catch {
                MeetingBarLogger.camera.error(
                    "Camera input add failed: \(String(describing: error), privacy: .public)"
                )
            }
        }

        if let audio {
            do {
                let input = try AVCaptureDeviceInput(device: audio)
                if session.canAddInput(input) {
                    session.addInput(input)
                    audioInput = input
                }
            } catch {
                MeetingBarLogger.camera.error(
                    "Microphone input add failed: \(String(describing: error), privacy: .public)"
                )
            }
        }

        // Audio level metering: attach the data output only when a mic input is
        // present. Its sample-buffer delivery is what keeps the channel's
        // averagePowerLevel updated; the buffers themselves are never stored.
        if audioInput != nil {
            if !session.outputs.contains(audioOutput), session.canAddOutput(audioOutput) {
                session.addOutput(audioOutput)
                audioOutput.setSampleBufferDelegate(self, queue: audioSampleQueue)
            }
        } else if session.outputs.contains(audioOutput) {
            audioOutput.setSampleBufferDelegate(nil, queue: nil)
            session.removeOutput(audioOutput)
        }
    }

    nonisolated private static func discoverVideoDevices() -> [AVCaptureDevice] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14.0, *) {
            types.append(.external)
            types.append(.continuityCamera)
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified
        )
        var devices = discovery.devices
        // Macs without a built-in camera surface their attached webcam as the
        // default device; include it so external-only setups still get a preview.
        if let fallback = AVCaptureDevice.default(for: .video),
            !devices.contains(where: { $0.uniqueID == fallback.uniqueID }) {
            devices.insert(fallback, at: 0)
        }
        return devices
    }

    nonisolated private static func discoverAudioDevices() -> [AVCaptureDevice] {
        var devices: [AVCaptureDevice] = []
        if #available(macOS 14.0, *) {
            devices = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone],
                mediaType: .audio,
                position: .unspecified
            ).devices
        }
        if let fallback = AVCaptureDevice.default(for: .audio),
            !devices.contains(where: { $0.uniqueID == fallback.uniqueID }) {
            devices.insert(fallback, at: 0)
        }
        return devices
    }

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Read the channel's average power (dBFS) directly off the connection and
        // normalize to 0…1 with the pure MicLevel helper. The buffer is not read
        // or retained.
        let decibels = connection.audioChannels.first?.averagePowerLevel ?? -160
        let level = MicLevel.normalized(decibels: decibels)
        Task { @MainActor in
            self.micLevel = level
        }
    }
}
