//
//  RecordingEngine.swift
//  Snipsnap
//
//  Created by Ethan Watson on 6/27/26.
//

// NOTE: When cameraEnabled = true, NSCameraUsageDescription is also required.

import ScreenCaptureKit
@preconcurrency import AVFoundation
import AppKit
import CoreImage

// MARK: - RecordingCaptureTarget

enum RecordingCaptureTarget: Equatable {
    case fullScreen
    case window(CGWindowID)
    case region(CGRect)
}

// MARK: - RecordingBackgroundStyle

enum RecordingBackgroundStyle: Equatable {
    case none
    case warm
    case cool
    case midnight
    case custom(path: String)

    var menuTitle: String {
        switch self {
        case .none:     return "None"
        case .warm:     return "Warm"
        case .cool:     return "Cool"
        case .midnight: return "Midnight"
        case .custom:   return "Custom Image"
        }
    }
}

class RecordingEngine: NSObject, SCStreamOutput, SCStreamDelegate,
                       AVCaptureAudioDataOutputSampleBufferDelegate,
                       AVCaptureVideoDataOutputSampleBufferDelegate {

    static let shared = RecordingEngine()

    var onRecordingStarted: (() -> Void)?
    var onRecordingStopped: ((URL?) -> Void)?
    var onRecordingFailed: ((Error) -> Void)?
    /// Called with composited frames when recording a window with a background.
    var onCompositedPreviewFrame: ((CGImage) -> Void)?

    /// Whether a recording is currently active.
    private(set) var isRecording = false
    /// True from the moment startRecording() is called until the stream either starts or fails.
    private(set) var isStartingRecording = false

    private var includeMic: Bool = false
    private var includeSystemAudio: Bool = false
    private var micDeviceID: String?
    private var captureTarget: RecordingCaptureTarget = .fullScreen
    private var recordingBackground: RecordingBackgroundStyle = .none
    private var usesBackgroundComposite = false
    private var cameraDeviceID: String?
    private var cameraStyle: CameraPreviewStyle = .square
    private var cameraEnabled: Bool { cameraDeviceID != nil }

    // MARK: - Private recording state

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var micAudioInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    // Microphone
    private var audioCaptureSession: AVCaptureSession?
    private var micAnchorPTS: CMTime?
    private var sessionAnchorTime: CMTime = .invalid

    // Camera compositing
    private var cameraSession: AVCaptureSession?
    private var cameraVideoOutput: AVCaptureVideoDataOutput?
    private let cameraQueue = DispatchQueue(label: "com.snipsnap.cameraCapture", qos: .userInitiated)
    private var latestCameraFrame: CVPixelBuffer?
    private let cameraLock = NSLock()
    private lazy var ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private lazy var blendWithMaskFilter = CIFilter(name: "CIBlendWithMask")
    private lazy var sourceOverFilter = CIFilter(name: "CISourceOverCompositing")
    private var cachedMask: (key: String, image: CIImage)?

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

    func startRecording(
        captureTarget: RecordingCaptureTarget = .fullScreen,
        recordingBackground: RecordingBackgroundStyle = .none,
        cameraDeviceID: String? = nil,
        cameraStyle: CameraPreviewStyle = .square,
        micEnabled: Bool = false,
        systemAudioEnabled: Bool = false,
        micDeviceID: String? = nil
    ) {
        assert(Thread.isMainThread)
        guard !isRecording, !isStartingRecording else { return }
        isStartingRecording = true
        self.captureTarget = captureTarget
        self.recordingBackground = recordingBackground
        self.cameraDeviceID = cameraDeviceID
        self.cameraStyle = cameraStyle
        self.includeMic = micEnabled
        self.includeSystemAudio = systemAudioEnabled
        self.micDeviceID = micDeviceID
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

                let scale = recordingPixelScale

                let filter: SCContentFilter
                let streamW: Int
                let streamH: Int
                let outputW: Int
                let outputH: Int

                switch captureTarget {
                case .fullScreen:
                    let mainID = CGMainDisplayID()
                    guard let display = availableContent.displays.first(where: { $0.displayID == mainID })
                                     ?? availableContent.displays.first else {
                        DispatchQueue.main.async {
                            self.isStartingRecording = false
                            self.onRecordingFailed?(RecordingError.noDisplayFound)
                        }
                        return
                    }
                    filter = SCContentFilter(display: display, excludingWindows: [])
                    streamW = display.width * scale
                    streamH = display.height * scale
                    outputW = streamW
                    outputH = streamH
                    usesBackgroundComposite = false

                case .window(let windowID):
                    guard let window = availableContent.windows.first(where: { $0.windowID == windowID }) else {
                        DispatchQueue.main.async {
                            self.isStartingRecording = false
                            self.onRecordingFailed?(RecordingError.windowNotFound)
                        }
                        return
                    }
                    filter = SCContentFilter(desktopIndependentWindow: window)
                    streamW = Int(window.frame.width) * scale
                    streamH = Int(window.frame.height) * scale
                    let needsCanvasLayout = recordingBackground != .none || cameraDeviceID != nil
                    if needsCanvasLayout {
                        outputW = 1920 * scale
                        outputH = 1080 * scale
                        usesBackgroundComposite = true
                    } else {
                        outputW = streamW
                        outputH = streamH
                        usesBackgroundComposite = false
                    }

                case .region(let rect):
                    guard let display = availableContent.displays.first(where: { display in
                        let displayFrame = CGRect(
                            x: display.frame.origin.x,
                            y: display.frame.origin.y,
                            width: CGFloat(display.width),
                            height: CGFloat(display.height)
                        )
                        return displayFrame.intersects(rect)
                    }) ?? availableContent.displays.first else {
                        DispatchQueue.main.async {
                            self.isStartingRecording = false
                            self.onRecordingFailed?(RecordingError.noDisplayFound)
                        }
                        return
                    }
                    filter = SCContentFilter(display: display, excludingWindows: [])
                    streamW = Int(rect.width) * scale
                    streamH = Int(rect.height) * scale
                    outputW = streamW
                    outputH = streamH
                    usesBackgroundComposite = false
                }

                let pixelW = outputW
                let pixelH = outputH

                // Stream configuration
                let config = SCStreamConfiguration()
                config.width = streamW
                config.height = streamH
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = true
                config.capturesAudio = includeSystemAudio
                config.sampleRate = 48_000
                config.channelCount = 2

                if case .region(let rect) = captureTarget {
                    let display = availableContent.displays.first(where: { display in
                        let displayFrame = CGRect(
                            x: display.frame.origin.x,
                            y: display.frame.origin.y,
                            width: CGFloat(display.width),
                            height: CGFloat(display.height)
                        )
                        return displayFrame.intersects(rect)
                    }) ?? availableContent.displays.first!
                    let displayOriginX = display.frame.origin.x
                    let displayOriginY = display.frame.origin.y
                    let displayHeight = CGFloat(display.height)
                    config.sourceRect = CGRect(
                        x: rect.origin.x - displayOriginX,
                        y: displayHeight - (rect.origin.y - displayOriginY) - rect.height,
                        width: rect.width,
                        height: rect.height
                    )
                    config.scalesToFit = false
                }

                // Output file
                try AppSettings.ensureDestinationFolderExists()
                let folderURL = AppSettings.destinationFolderURL
                let url = CaptureNaming.uniqueURL(
                    in: folderURL,
                    preferredFilename: CaptureNaming.recordingFilename()
                )
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

                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: 2,
                    AVSampleRateKey: 48_000,
                    AVEncoderBitRateKey: 128_000
                ]

                // System audio (ScreenCaptureKit — shares timeline with video).
                if includeSystemAudio {
                    let sysInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                    sysInput.expectsMediaDataInRealTime = true
                    self.systemAudioInput = sysInput
                    writer.add(sysInput)
                }

                // Microphone (optional — AVCapture clock is retimestamped to the screen stream).
                if includeMic {
                    let micGranted = await Self.requestMicrophoneAccess()
                    if micGranted {
                        let micInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                        micInput.expectsMediaDataInRealTime = true
                        self.micAudioInput = micInput
                        writer.add(micInput)

                        let micSession = AVCaptureSession()
                        let micDevice = micDeviceID.flatMap { AVCaptureDevice(uniqueID: $0) }
                            ?? AVCaptureDevice.default(for: .audio)
                        if let micDevice,
                           let deviceInput = try? AVCaptureDeviceInput(device: micDevice),
                           micSession.canAddInput(deviceInput) {
                            micSession.addInput(deviceInput)
                        }
                        let audioOut = AVCaptureAudioDataOutput()
                        audioOut.setSampleBufferDelegate(self, queue: .global(qos: .userInitiated))
                        if micSession.canAddOutput(audioOut) {
                            micSession.addOutput(audioOut)
                        }
                        self.audioCaptureSession = micSession
                        micSession.startRunning()
                    } else {
                        DispatchQueue.main.async {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                            )
                        }
                    }
                }

                // Camera compositing for window/region captures (full-screen uses the floating preview overlay).
                if cameraEnabled {
                    let camGranted = await Self.requestCameraAccess()
                    if !camGranted {
                        DispatchQueue.main.async {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
                            )
                        }
                    }
                    if camGranted {
                        let camSession = AVCaptureSession()
                        camSession.sessionPreset = .medium

                        let camDevice = cameraDeviceID.flatMap { AVCaptureDevice(uniqueID: $0) }
                            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
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
                        cameraQueue.async {
                            camSession.startRunning()
                        }
                    }
                }

                // Begin writing, then start the screen stream.
                writer.startWriting()

                let captureStream = SCStream(filter: filter, configuration: config, delegate: self)
                self.stream = captureStream
                let mediaQueue = DispatchQueue.global(qos: .userInitiated)
                try captureStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: mediaQueue)
                if includeSystemAudio {
                    try captureStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: mediaQueue)
                }
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
        guard isRecording else { return }

        switch type {
        case .screen:
            guard let vInput = videoInput, vInput.isReadyForMoreMediaData else { return }
            let pts = buffer.presentationTimeStamp
            beginSessionIfNeeded(at: pts)

            guard let screenPB = CMSampleBufferGetImageBuffer(buffer) else { return }

            if cameraEnabled || usesBackgroundComposite {
                var working = screenPB
                if usesBackgroundComposite, let composited = compositeOntoRecordingBackground(screenPB) {
                    working = composited
                }
                if cameraEnabled, let withCamera = compositeCamera(onto: working) {
                    if let callback = onCompositedPreviewFrame {
                        publishPreviewFrame(withCamera, callback: callback)
                    }
                    pixelBufferAdaptor?.append(withCamera, withPresentationTime: pts)
                } else if usesBackgroundComposite, working !== screenPB {
                    if let callback = onCompositedPreviewFrame {
                        publishPreviewFrame(working, callback: callback)
                    }
                    pixelBufferAdaptor?.append(working, withPresentationTime: pts)
                } else {
                    if let callback = onCompositedPreviewFrame {
                        publishPreviewFrame(screenPB, callback: callback)
                    }
                    vInput.append(buffer)
                }
            } else {
                if let callback = onCompositedPreviewFrame {
                    publishPreviewFrame(screenPB, callback: callback)
                }
                vInput.append(buffer)
            }

        case .audio:
            guard let sysInput = systemAudioInput, sysInput.isReadyForMoreMediaData else { return }
            let pts = buffer.presentationTimeStamp
            beginSessionIfNeeded(at: pts)
            sysInput.append(buffer)

        default:
            break
        }
    }

    private func beginSessionIfNeeded(at pts: CMTime) {
        guard !sessionStarted else { return }
        sessionStarted = true
        sessionAnchorTime = pts
        assetWriter?.startSession(atSourceTime: pts)
    }

    // MARK: - Recording background compositing

    /// Places a window capture onto a gradient or image background (Borumi-style).
    private func compositeOntoRecordingBackground(_ windowBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let scale = CGFloat(recordingPixelScale)
        let canvasSize = RecordingBackgroundRenderer.canvasSize(for: scale)
        let windowImage = CIImage(cvPixelBuffer: windowBuffer)
        let layoutCamera: CameraPreviewStyle? = cameraEnabled && cameraStyle == .vertical ? .vertical : nil
        let composited = RecordingBackgroundRenderer.composite(
            windowImage: windowImage,
            background: recordingBackground,
            canvasSize: canvasSize,
            cameraStyle: layoutCamera,
            scale: scale
        )
        return renderToPixelBuffer(composited, width: Int(canvasSize.width), height: Int(canvasSize.height))
    }

    private func publishPreviewFrame(_ pixelBuffer: CVPixelBuffer, callback: @escaping (CGImage) -> Void) {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return }
        DispatchQueue.main.async {
            callback(cgImage)
        }
    }

    private func renderToPixelBuffer(_ image: CIImage, width: Int, height: Int) -> CVPixelBuffer? {
        var outBuffer: CVPixelBuffer?
        if let pool = pixelBufferAdaptor?.pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outBuffer)
        }
        if outBuffer == nil {
            let attrs: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [:]
            ]
            CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                kCVPixelFormatType_32BGRA, attrs as CFDictionary, &outBuffer)
        }
        guard let outBuffer else { return nil }
        ciContext.render(
            image,
            to: outBuffer,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return outBuffer
    }

    // MARK: - Camera compositing (legacy — camera overlay is captured via SCK)

    /// Renders the latest camera frame into the screen buffer using the selected layout.
    private func compositeCamera(onto screenBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        cameraLock.lock()
        let cameraFrame = latestCameraFrame
        cameraLock.unlock()
        guard let cameraFrame else { return nil }

        let screenW = CGFloat(CVPixelBufferGetWidth(screenBuffer))
        let screenH = CGFloat(CVPixelBufferGetHeight(screenBuffer))
        let scale   = CGFloat(recordingPixelScale)

        let camW = CGFloat(CVPixelBufferGetWidth(cameraFrame))
        let camH = CGFloat(CVPixelBufferGetHeight(cameraFrame))

        let mirrorTx  = CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -camW, y: 0)
        let ciCamera  = CIImage(cvPixelBuffer: cameraFrame).transformed(by: mirrorTx)
        let ciScreen  = CIImage(cvPixelBuffer: screenBuffer)

        let margin: CGFloat

        switch cameraStyle {
        case .square:
            let side = 100.0 * scale
            margin = 20.0 * scale
            let camScale = side / min(camW, camH)
            let scaledW = camW * camScale
            let scaledH = camH * camScale
            let cropRect = CGRect(
                x: (scaledW - side) / 2,
                y: (scaledH - side) / 2,
                width: side,
                height: side
            )
            let croppedCam = ciCamera
                .transformed(by: CGAffineTransform(scaleX: camScale, y: camScale))
                .cropped(to: cropRect)
            let tx = screenW - side - margin - croppedCam.extent.minX
            let ty = margin - croppedCam.extent.minY
            let positioned = croppedCam.transformed(by: CGAffineTransform(translationX: tx, y: ty))
            let mask = roundedRectMask(rect: CGRect(x: 0, y: 0, width: side, height: side),
                                       cornerRadius: 12 * scale,
                                       translatedTo: CGPoint(x: tx, y: ty))
            return compositeMaskedCamera(positioned, mask: mask, over: ciScreen,
                                         screenBuffer: screenBuffer, width: Int(screenW), height: Int(screenH))

        case .vertical:
            let strip = VerticalCameraStripLayout.metrics(screenWidth: screenW, screenHeight: screenH, scale: scale)
            let stripW = strip.width
            let stripH = strip.height
            let camScale = max(stripW / camW, stripH / camH)
            let scaledW = camW * camScale
            let scaledH = camH * camScale
            let cropRect = CGRect(
                x: (scaledW - stripW) / 2,
                y: (scaledH - stripH) / 2,
                width: stripW,
                height: stripH
            )
            let croppedCam = ciCamera
                .transformed(by: CGAffineTransform(scaleX: camScale, y: camScale))
                .cropped(to: cropRect)
            let tx = strip.originX - croppedCam.extent.minX
            let ty = strip.originY - croppedCam.extent.minY
            let positioned = croppedCam.transformed(by: CGAffineTransform(translationX: tx, y: ty))
            let mask = VerticalCameraStripLayout.roundedRectMask(
                rect: CGRect(origin: .zero, size: CGSize(width: stripW, height: stripH)),
                cornerRadius: strip.cornerRadius,
                translatedTo: CGPoint(x: tx, y: ty)
            )
            return compositeMaskedCamera(positioned, mask: mask, over: ciScreen,
                                         screenBuffer: screenBuffer, width: Int(screenW), height: Int(screenH))
        }
    }

    private func roundedRectMask(rect: CGRect, cornerRadius: CGFloat, translatedTo origin: CGPoint) -> CIImage {
        let cacheKey = "\(rect)-\(cornerRadius)-\(origin)"
        if let cached = cachedMask, cached.key == cacheKey { return cached.image }

        let extent = rect.offsetBy(dx: origin.x, dy: origin.y)
        let w = Int(extent.width.rounded())
        let h = Int(extent.height.rounded())
        guard w > 0, h > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.linearGray),
              let ctx = CGContext(
                data: nil,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else {
            return CIImage(color: .white).cropped(to: extent)
        }

        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(gray: 1, alpha: 1)
        let path = CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: rect.width, height: rect.height),
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        ctx.addPath(path)
        ctx.fillPath()

        guard let cgImage = ctx.makeImage() else {
            return CIImage(color: .white).cropped(to: extent)
        }
        let result = CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
        cachedMask = (key: cacheKey, image: result)
        return result
    }

    private func compositeMaskedCamera(
        _ camera: CIImage,
        mask: CIImage,
        over screen: CIImage,
        screenBuffer: CVPixelBuffer,
        width: Int,
        height: Int
    ) -> CVPixelBuffer? {
        guard let blendFilter = blendWithMaskFilter else { return nil }
        blendFilter.setValue(camera, forKey: kCIInputImageKey)
        blendFilter.setValue(CIImage(color: .clear), forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)
        guard let maskedCam = blendFilter.outputImage else { return nil }

        guard let compositeFilter = sourceOverFilter else { return nil }
        compositeFilter.setValue(maskedCam, forKey: kCIInputImageKey)
        compositeFilter.setValue(screen, forKey: kCIInputBackgroundImageKey)
        guard let composited = compositeFilter.outputImage else { return nil }

        return renderToPixelBuffer(composited, width: width, height: height)
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
        micAnchorPTS = nil
        sessionAnchorTime = .invalid
        videoInput?.markAsFinished()
        micAudioInput?.markAsFinished()
        systemAudioInput?.markAsFinished()
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
            micAnchorPTS = nil
            sessionAnchorTime = .invalid
            videoInput?.markAsFinished()
            micAudioInput?.markAsFinished()
            systemAudioInput?.markAsFinished()
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
            // Microphone audio — retimestamp to align with the screen-capture timeline.
            guard isRecording, sessionStarted,
                  let micInput = micAudioInput, micInput.isReadyForMoreMediaData,
                  let aligned = alignMicBufferToSession(sampleBuffer) else { return }
            micInput.append(aligned)
        }
    }

    // MARK: - Mic timestamp alignment

    /// Maps AVCapture audio timestamps onto the ScreenCaptureKit session timeline.
    private func alignMicBufferToSession(_ buffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard sessionAnchorTime.isValid else { return nil }

        let micPTS = CMSampleBufferGetPresentationTimeStamp(buffer)
        if micAnchorPTS == nil {
            micAnchorPTS = micPTS
        }
        guard let anchor = micAnchorPTS else { return nil }

        let relative = CMTimeSubtract(micPTS, anchor)
        let alignedPTS = CMTimeAdd(sessionAnchorTime, relative)

        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(buffer),
            presentationTimeStamp: alignedPTS,
            decodeTimeStamp: .invalid
        )
        var out: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: buffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &out
        )
        return status == noErr ? out : nil
    }

    private static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    private static func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
}

// MARK: - Errors

private enum RecordingError: LocalizedError {
    case noDisplayFound
    case permissionDenied
    case windowNotFound

    var errorDescription: String? {
        switch self {
        case .noDisplayFound:
            return "No display found for screen recording."
        case .permissionDenied:
            return "Screen recording permission is required. Please grant access in System Settings → Privacy & Security → Screen Recording, then try again."
        case .windowNotFound:
            return "The selected window could not be found. It may have been closed."
        }
    }
}
