//
//  RecordingEngine.swift
//  Snipsnap
//
//  Created by Ethan Watson on 6/27/26.
//

// NOTE: When includeMic = true, add NSMicrophoneUsageDescription to Info.plist.
// NOTE: When cameraEnabled = true, NSCameraUsageDescription is also required.

import ScreenCaptureKit
@preconcurrency import AVFoundation
import AppKit
import CoreImage

class RecordingEngine: NSObject, SCStreamOutput, SCStreamDelegate,
                       AVCaptureAudioDataOutputSampleBufferDelegate,
                       AVCaptureVideoDataOutputSampleBufferDelegate {

    static let shared = RecordingEngine()

    var onRecordingStarted: (() -> Void)?
    var onRecordingStopped: ((URL?) -> Void)?
    var onRecordingFailed: ((Error) -> Void)?

    /// Whether a recording is currently active.
    private(set) var isRecording = false
    /// True from the moment startRecording() is called until the stream either starts or fails.
    private(set) var isStartingRecording = false

    private var includeMic: Bool = false
    private var cameraEnabled: Bool = false

    // MARK: - Private recording state

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    // Microphone
    private var audioCaptureSession: AVCaptureSession?

    // Camera compositing
    private var cameraSession: AVCaptureSession?
    private var cameraVideoOutput: AVCaptureVideoDataOutput?
    private let cameraQueue = DispatchQueue(label: "com.snipsnap.cameraCapture", qos: .userInitiated)
    private var latestCameraFrame: CVPixelBuffer?
    private let cameraLock = NSLock()
    private lazy var ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private var streamRunning = false
    private var outputURL: URL?
    private var sessionStarted = false
    private var recordingPixelScale: Int = 1

    // MARK: - Prewarm

    /// Triggers the SCK permission dialog before the user starts a recording.
    func prewarm() {
        Task {
            _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
    }

    // MARK: - Start Recording

    func startRecording(cameraEnabled: Bool = false, micEnabled: Bool = false) {
        assert(Thread.isMainThread)
        guard !isRecording, !isStartingRecording else { return }
        isStartingRecording = true
        self.cameraEnabled = cameraEnabled
        self.includeMic = micEnabled
        let backingScale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2
        recordingPixelScale = Int(backingScale)

        Task {
            do {
                // Fetch shareable content (also validates SCK permission).
                let availableContent: SCShareableContent
                do {
                    availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                } catch {
                    DispatchQueue.main.async {
                        self.isStartingRecording = false
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                        )
                        self.onRecordingFailed?(RecordingError.permissionDenied)
                    }
                    return
                }

                let mainID = CGMainDisplayID()
                guard let display = availableContent.displays.first(where: { $0.displayID == mainID })
                                 ?? availableContent.displays.first else {
                    DispatchQueue.main.async {
                        self.isStartingRecording = false
                        self.onRecordingFailed?(RecordingError.noDisplayFound)
                    }
                    return
                }

                let scale  = recordingPixelScale
                let pixelW = display.width  * scale
                let pixelH = display.height * scale

                // Stream configuration
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = pixelW
                config.height = pixelH
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = true

                // Output file
                let timestamp = Int(Date().timeIntervalSince1970)
                let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
                let url = desktopURL.appendingPathComponent("Snipsnap-recording-\(timestamp).mp4")
                self.outputURL = url

                // Asset writer + video input
                let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
                self.assetWriter = writer

                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: pixelW,
                    AVVideoHeightKey: pixelH
                ]
                let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                vInput.expectsMediaDataInRealTime = true
                self.videoInput = vInput
                writer.add(vInput)

                // Pixel buffer adaptor (provides a pool for composited frames)
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: vInput,
                    sourcePixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                        kCVPixelBufferWidthKey as String: pixelW,
                        kCVPixelBufferHeightKey as String: pixelH,
                        kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                    ]
                )
                self.pixelBufferAdaptor = adaptor

                // Microphone (optional)
                if includeMic {
                    let audioSettings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatMPEG4AAC,
                        AVNumberOfChannelsKey: 2,
                        AVSampleRateKey: 44100.0
                    ]
                    let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                    aInput.expectsMediaDataInRealTime = true
                    self.audioInput = aInput
                    writer.add(aInput)

                    let micSession = AVCaptureSession()
                    if let micDevice = AVCaptureDevice.default(for: .audio),
                       let micInput = try? AVCaptureDeviceInput(device: micDevice),
                       micSession.canAddInput(micInput) {
                        micSession.addInput(micInput)
                    }
                    let audioOut = AVCaptureAudioDataOutput()
                    audioOut.setSampleBufferDelegate(self, queue: .global(qos: .userInitiated))
                    if micSession.canAddOutput(audioOut) {
                        micSession.addOutput(audioOut)
                    }
                    self.audioCaptureSession = micSession
                    micSession.startRunning()
                }

                // Camera (optional)
                if cameraEnabled {
                    let camSession = AVCaptureSession()
                    camSession.sessionPreset = .medium

                    let camDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                              ?? AVCaptureDevice.default(for: .video)
                    if let camDevice,
                       let camInput = try? AVCaptureDeviceInput(device: camDevice),
                       camSession.canAddInput(camInput) {
                        camSession.addInput(camInput)
                    }

                    let videoOut = AVCaptureVideoDataOutput()
                    videoOut.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                    ]
                    videoOut.alwaysDiscardsLateVideoFrames = true
                    videoOut.setSampleBufferDelegate(self, queue: cameraQueue)
                    if camSession.canAddOutput(videoOut) {
                        camSession.addOutput(videoOut)
                    }

                    self.cameraSession = camSession
                    self.cameraVideoOutput = videoOut
                    // Start on the camera queue to avoid blocking the Task.
                    cameraQueue.async { [weak self] in
                        self?.cameraSession?.startRunning()
                    }
                }

                // Begin writing, then start the screen stream.
                writer.startWriting()

                let captureStream = SCStream(filter: filter, configuration: config, delegate: self)
                self.stream = captureStream
                try captureStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
                try await captureStream.startCapture()

                self.isRecording = true
                self.streamRunning = true
                DispatchQueue.main.async {
                    self.isStartingRecording = false
                    self.onRecordingStarted?()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isStartingRecording = false
                    self.onRecordingFailed?(error)
                }
            }
        }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard isRecording, type == .screen else { return }
        guard let vInput = videoInput, vInput.isReadyForMoreMediaData else { return }

        let pts = buffer.presentationTimeStamp

        if !sessionStarted {
            sessionStarted = true
            assetWriter?.startSession(atSourceTime: pts)
        }

        if cameraEnabled,
           let screenPB = CMSampleBufferGetImageBuffer(buffer),
           let composited = compositeCamera(onto: screenPB) {
            pixelBufferAdaptor?.append(composited, withPresentationTime: pts)
        } else {
            vInput.append(buffer)
        }
    }

    // MARK: - Camera compositing

    /// Renders the latest camera frame as a mirrored circle into the bottom-right corner of the screen buffer.
    /// Returns nil when no camera frame is available yet (caller appends the raw screen buffer instead).
    private func compositeCamera(onto screenBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        cameraLock.lock()
        let cameraFrame = latestCameraFrame
        cameraLock.unlock()
        guard let cameraFrame else { return nil }

        let screenW  = CVPixelBufferGetWidth(screenBuffer)
        let screenH  = CVPixelBufferGetHeight(screenBuffer)
        let scale    = CGFloat(recordingPixelScale)
        let diameter = 120.0 * scale   // 120 pt → pixels
        let margin   =  20.0 * scale   //  20 pt → pixels

        let camW = CGFloat(CVPixelBufferGetWidth(cameraFrame))
        let camH = CGFloat(CVPixelBufferGetHeight(cameraFrame))

        // Mirror the camera frame horizontally (selfie / FaceTime convention).
        let mirrorTx  = CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -camW, y: 0)
        let ciCamera  = CIImage(cvPixelBuffer: cameraFrame).transformed(by: mirrorTx)
        let ciScreen  = CIImage(cvPixelBuffer: screenBuffer)

        // Scale camera uniformly so its shorter side fills `diameter`, then center-crop.
        let camScale  = diameter / min(camW, camH)
        let scaledCam = ciCamera.transformed(by: CGAffineTransform(scaleX: camScale, y: camScale))
        let scaledW   = camW * camScale
        let scaledH   = camH * camScale
        let cropRect  = CGRect(x: (scaledW - diameter) / 2,
                               y: (scaledH - diameter) / 2,
                               width: diameter,
                               height: diameter)
        let croppedCam = scaledCam.cropped(to: cropRect)

        // Circular mask: white inside, black outside (near-hard 2 px transition).
        guard let gradFilter = CIFilter(name: "CIRadialGradient") else { return nil }
        gradFilter.setValue(CIVector(x: cropRect.midX, y: cropRect.midY), forKey: "inputCenter")
        gradFilter.setValue(NSNumber(value: Double(diameter / 2 - 1.5)), forKey: "inputRadius0")
        gradFilter.setValue(NSNumber(value: Double(diameter / 2 + 0.5)), forKey: "inputRadius1")
        gradFilter.setValue(CIColor.white, forKey: "inputColor0")
        gradFilter.setValue(CIColor.black, forKey: "inputColor1")
        guard let mask = gradFilter.outputImage?.cropped(to: cropRect) else { return nil }

        // Blend camera with mask → circle with transparent exterior.
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else { return nil }
        blendFilter.setValue(croppedCam,          forKey: kCIInputImageKey)
        blendFilter.setValue(CIImage(color: .clear), forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(mask,                forKey: kCIInputMaskImageKey)
        guard let maskedCam = blendFilter.outputImage else { return nil }

        // Translate to bottom-right corner (CIImage origin = bottom-left).
        let tx = CGFloat(screenW) - diameter - margin - maskedCam.extent.minX
        let ty = margin - maskedCam.extent.minY
        let positioned = maskedCam.transformed(by: CGAffineTransform(translationX: tx, y: ty))

        // Composite circle over screen.
        guard let compositeFilter = CIFilter(name: "CISourceOverCompositing") else { return nil }
        compositeFilter.setValue(positioned, forKey: kCIInputImageKey)
        compositeFilter.setValue(ciScreen,   forKey: kCIInputBackgroundImageKey)
        guard let composited = compositeFilter.outputImage else { return nil }

        // Obtain an output pixel buffer (prefer the adaptor pool to avoid allocs per frame).
        var outBuffer: CVPixelBuffer?
        if let pool = pixelBufferAdaptor?.pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outBuffer)
        }
        if outBuffer == nil {
            let attrs: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: screenW,
                kCVPixelBufferHeightKey: screenH,
                kCVPixelBufferIOSurfacePropertiesKey: [:]
            ]
            CVPixelBufferCreate(kCFAllocatorDefault, screenW, screenH,
                                kCVPixelFormatType_32BGRA, attrs as CFDictionary, &outBuffer)
        }
        guard let outBuffer else { return nil }

        ciContext.render(composited,
                         to: outBuffer,
                         bounds: CGRect(x: 0, y: 0, width: screenW, height: screenH),
                         colorSpace: CGColorSpaceCreateDeviceRGB())
        return outBuffer
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[RecordingEngine] Stream stopped with error: \(error)")
        streamRunning = false
        guard isRecording else { return }
        isRecording = false
        sessionStarted = false
        teardownCamera()
        audioCaptureSession?.stopRunning()
        audioCaptureSession = nil
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        let url = outputURL
        assetWriter?.finishWriting {
            print("[RecordingEngine] File finalized after stream error: \(url?.lastPathComponent ?? "nil")")
            DispatchQueue.main.async { self.onRecordingStopped?(url) }
        }
    }

    // MARK: - Stop Recording

    func stopRecording() {
        isRecording = false
        sessionStarted = false
        Task {
            if streamRunning {
                streamRunning = false
                try? await stream?.stopCapture()
            }
            teardownCamera()
            audioCaptureSession?.stopRunning()
            audioCaptureSession = nil
            videoInput?.markAsFinished()
            audioInput?.markAsFinished()
            let adaptor = pixelBufferAdaptor
            pixelBufferAdaptor = nil
            _ = adaptor  // release after inputs are marked finished
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

    private func teardownCamera() {
        cameraLock.lock()
        latestCameraFrame = nil
        cameraLock.unlock()
        cameraVideoOutput = nil
        cameraSession?.stopRunning()
        cameraSession = nil
    }

    // MARK: - AVCapture delegates (audio + video)

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output === cameraVideoOutput {
            // Store the latest camera frame for compositing.
            guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            cameraLock.lock()
            latestCameraFrame = pb
            cameraLock.unlock()
        } else {
            // Microphone audio → write to audio track.
            guard isRecording, sessionStarted,
                  audioInput?.isReadyForMoreMediaData == true else { return }
            audioInput?.append(sampleBuffer)
        }
    }
}

// MARK: - Errors

private enum RecordingError: LocalizedError {
    case noDisplayFound
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplayFound:
            return "No display found for screen recording."
        case .permissionDenied:
            return "Screen recording permission is required. Please grant access in System Settings → Privacy & Security → Screen Recording, then try again."
        }
    }
}
