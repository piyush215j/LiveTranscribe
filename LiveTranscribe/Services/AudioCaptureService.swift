// AudioCaptureService.swift
// LiveTranscribe
//
// Captures system audio in real time using ScreenCaptureKit (macOS 13+).
// Outputs 16 kHz mono Int16 PCM chunks via a Combine publisher.

import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import Combine

// MARK: - Error types

enum AudioCaptureError: LocalizedError {
    case permissionDenied
    case noDisplayFound
    case alreadyCapturing
    case streamFailed(Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is required for system audio capture. " +
                   "Enable it in System Preferences → Privacy & Security → Screen Recording."
        case .noDisplayFound:
            return "No display found. Please ensure your Mac has at least one connected display."
        case .alreadyCapturing:
            return "Audio capture is already running."
        case .streamFailed(let err):
            return "Stream failed: \(err.localizedDescription)"
        }
    }
}

// MARK: - AudioCaptureService

/// Captures system-wide audio via ScreenCaptureKit and publishes PCM chunks.
@MainActor
final class AudioCaptureService: NSObject, ObservableObject {

    // MARK: Published state

    @Published private(set) var isCapturing = false
    @Published private(set) var permissionGranted = false
    @Published private(set) var audioLevel: Float = 0.0
    @Published private(set) var errorMessage: String?

    // Downstream subscribers (e.g. WhisperService) receive raw PCM data here
    let audioDataPublisher = PassthroughSubject<Data, Never>()

    // MARK: Private

    private var stream: SCStream?
    private var streamOutput: AudioStreamOutput?

    // MARK: - Permission

    /// Checks if screen-recording permission is actually usable.
    /// Uses SCShareableContent.excludingDesktopWindows as the real probe —
    /// CGPreflightScreenCaptureAccess() is unreliable for ad-hoc signed binaries.
    func checkPermission() async -> Bool {
        do {
            // This is the authoritative check: if SCKit can enumerate content,
            // we have permission. This matches what startCapture() will call.
            _ = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
            permissionGranted = true
            errorMessage = nil
            return true
        } catch {
            permissionGranted = false
            // Don't overwrite errorMessage here — let the caller decide messaging
            return false
        }
    }

    /// Triggers the macOS Screen Recording permission prompt if not yet granted,
    /// then re-checks. Returns true if permission was granted.
    func requestPermission() async -> Bool {
        // CGRequestScreenCaptureAccess shows the system alert (if not yet decided)
        // For ad-hoc apps this may do nothing, so we follow up with the real check.
        CGRequestScreenCaptureAccess()
        // Small delay to let the TCC daemon process the decision
        try? await Task.sleep(nanoseconds: 500_000_000)
        return await checkPermission()
    }

    // MARK: - Start / Stop

    func startCapture() async throws {
        guard !isCapturing else { throw AudioCaptureError.alreadyCapturing }

        // 1. Enumerate shareable content (triggers permission prompt on first use)
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
        } catch {
            throw AudioCaptureError.permissionDenied
        }

        guard let display = content.displays.first else {
            throw AudioCaptureError.noDisplayFound
        }

        // 2. Stream configuration — audio-only, 16 kHz mono
        let config = SCStreamConfiguration()
        config.capturesAudio   = true
        config.sampleRate      = 16_000
        config.channelCount    = 1
        // Minimise video overhead (still required by SCStream API)
        config.width           = 2
        config.height          = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor     = false

        // 3. Capture everything on the display (all system audio)
        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )

        // 4. Create stream and attach output handler
        let newStream = SCStream(filter: filter, configuration: config, delegate: nil)

        let output = AudioStreamOutput()
        output.onAudioData = { [weak self] data in
            self?.audioDataPublisher.send(data)
        }
        output.onLevelUpdate = { [weak self] level in
            Task { @MainActor [weak self] in
                self?.audioLevel = level
            }
        }

        try newStream.addStreamOutput(
            output,
            type: .audio,
            sampleHandlerQueue: DispatchQueue.global(qos: .userInteractive)
        )
        try await newStream.startCapture()

        stream       = newStream
        streamOutput = output
        isCapturing  = true
        errorMessage = nil
    }

    func stopCapture() async {
        guard isCapturing, let stream = stream else { return }
        do {
            try await stream.stopCapture()
        } catch {
            print("[AudioCapture] stopCapture error: \(error)")
        }
        self.stream       = nil
        self.streamOutput = nil
        isCapturing       = false
        audioLevel        = 0
    }
}

// MARK: - Private stream output handler

/// Receives CMSampleBuffer callbacks from SCStream on a background queue.
private final class AudioStreamOutput: NSObject, SCStreamOutput {

    /// Called with raw PCM Int16 data ready for the Whisper bridge
    var onAudioData: ((Data) -> Void)?
    /// Called with RMS level for the VU meter
    var onLevelUpdate: ((Float) -> Void)?

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else { return }
        guard let data = extractPCMInt16(from: sampleBuffer) else { return }

        onAudioData?(data)

        // Compute RMS for the level meter
        let rms = computeRMS(from: data)
        onLevelUpdate?(rms)
    }

    // MARK: - PCM extraction

    /// Extracts Float32 samples from the CMSampleBuffer and converts to Int16.
    private func extractPCMInt16(from sampleBuffer: CMSampleBuffer) -> Data? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        guard length > 0 else { return nil }

        let sampleCount = length / MemoryLayout<Float32>.size
        guard sampleCount > 0 else { return nil }

        var floatSamples = [Float32](repeating: 0, count: sampleCount)
        let status = floatSamples.withUnsafeMutableBytes { ptr in
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
        }
        guard status == noErr else { return nil }

        var int16Samples = [Int16](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let clamped = max(-1.0, min(1.0, floatSamples[i]))
            int16Samples[i] = Int16(clamped * 32_767.0)
        }

        return int16Samples.withUnsafeBytes { Data($0) }
    }

    /// Compute RMS amplitude of an Int16 PCM buffer (returns 0…1 float)
    private func computeRMS(from data: Data) -> Float {
        let count = data.count / MemoryLayout<Int16>.size
        guard count > 0 else { return 0 }
        var sum: Float = 0
        data.withUnsafeBytes { ptr in
            let int16Ptr = ptr.bindMemory(to: Int16.self)
            for sample in int16Ptr.prefix(count) {
                let f = Float(sample) / 32_767.0
                sum += f * f
            }
        }
        return sqrt(sum / Float(count))
    }
}
