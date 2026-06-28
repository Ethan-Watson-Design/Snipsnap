//
//  RecordingEngine.swift
//  Snipsnap
//
//  Created by Ethan Watson on 6/27/26.
//

import ScreenCaptureKit
import AVFoundation
import AppKit

class RecordingEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    static let shared = RecordingEngine()

    var onRecordingStopped: ((URL?) -> Void)?

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var isRecording = false
    private var streamRunning = false
    private var outputURL: URL?
    private var sessionStarted = false

    /// Call at launch so the permission dialog and SCK first-fetch happen before the user
    /// triggers a recording. Without this, both appear mid-recording and look like a picker.
    func prewarm() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        Task {
            _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
    }

    func startRecording(completion: @escaping (Error?) -> Void) {
        guard CGPreflightScreenCaptureAccess() else {
            DispatchQueue.main.async {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                )
                completion(RecordingError.permissionDenied)
            }
            return
        }
        Task {
            do {
                let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

                let mainID = CGMainDisplayID()
                guard let display = availableContent.displays.first(where: { $0.displayID == mainID })
                                 ?? availableContent.displays.first else {
                    DispatchQueue.main.async { completion(RecordingError.noDisplayFound) }
                    return
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])

                let config = SCStreamConfiguration()
                config.width = display.width
                config.height = display.height
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                config.pixelFormat = kCVPixelFormatType_32BGRA

                let timestamp = Int(Date().timeIntervalSince1970)
                let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
                let url = desktopURL.appendingPathComponent("Snipsnap-recording-\(timestamp).mp4")
                self.outputURL = url

                let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
                self.assetWriter = writer

                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: display.width,
                    AVVideoHeightKey: display.height
                ]
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                input.expectsMediaDataInRealTime = true
                self.videoInput = input

                writer.add(input)
                writer.startWriting()

                let captureStream = SCStream(filter: filter, configuration: config, delegate: self)
                self.stream = captureStream
                try captureStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
                try await captureStream.startCapture()

                self.isRecording = true
                self.streamRunning = true
                DispatchQueue.main.async { completion(nil) }
            } catch {
                DispatchQueue.main.async { completion(error) }
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard isRecording, type == .screen else { return }
        guard videoInput?.isReadyForMoreMediaData == true else { return }

        if !sessionStarted {
            sessionStarted = true
            assetWriter?.startSession(atSourceTime: buffer.presentationTimeStamp)
        }

        videoInput?.append(buffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[RecordingEngine] Stream stopped with error: \(error)")
        streamRunning = false
        guard isRecording else { return }
        isRecording = false
        sessionStarted = false
        videoInput?.markAsFinished()
        let url = outputURL
        assetWriter?.finishWriting {
            print("[RecordingEngine] File finalized after stream error: \(url?.lastPathComponent ?? "nil")")
            DispatchQueue.main.async { self.onRecordingStopped?(url) }
        }
    }

    func stopRecording() {
        isRecording = false
        sessionStarted = false
        Task {
            if streamRunning {
                streamRunning = false
                try? await stream?.stopCapture()
            }
            videoInput?.markAsFinished()
            let url = outputURL
            guard assetWriter?.status == .writing else {
                DispatchQueue.main.async { self.onRecordingStopped?(url) }
                return
            }
            assetWriter?.finishWriting {
                DispatchQueue.main.async { self.onRecordingStopped?(url) }
            }
        }
    }
}

private enum RecordingError: LocalizedError {
    case noDisplayFound
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplayFound: return "No display found for screen recording."
        case .permissionDenied: return "Screen recording permission is required. Please grant access in System Settings → Privacy & Security → Screen Recording, then try again."
        }
    }
}
