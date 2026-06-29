//
//  RecordingBackgroundPreviewWindow.swift
//  Snipsnap
//

import AppKit
@preconcurrency import AVFoundation
import CoreImage
import ScreenCaptureKit

/// Toggleable recording preview: small thumbnail bottom-left, click to expand full stage.
final class RecordingBackgroundPreviewWindow: NSPanel {

    private static var shared: RecordingBackgroundPreviewWindow?

    static var isVisible: Bool { shared?.isVisible ?? false }
    static var isExpanded: Bool { shared?.displayMode == .expanded }

    struct Configuration: Equatable {
        var captureMode: CaptureMode
        var windowID: CGWindowID?
        var background: RecordingBackgroundStyle
        var cameraDeviceID: String?
        var cameraStyle: CameraPreviewStyle
    }

    private enum DisplayMode {
        case thumbnail
        case expanded
    }

    static func showThumbnail(configuration: Configuration) {
        let present = {
            guard CaptureBar.isPresented else {
                hide()
                return
            }
            if let existing = shared, existing.configuration == configuration {
                existing.applyLayout()
                existing.orderFrontRegardless()
                existing.startRefreshing()
                return
            }
            shared?.stopRefreshing()
            shared?.orderOut(nil)
            shared = RecordingBackgroundPreviewWindow(configuration: configuration, displayMode: .thumbnail)
            shared?.orderFrontRegardless()
            shared?.startRefreshing()
        }
        if Thread.isMainThread {
            present()
        } else {
            DispatchQueue.main.async {
                present()
            }
        }
    }

    static func hide() {
        let dismiss = {
            shared?.stopRefreshing()
            shared?.orderOut(nil)
            shared = nil
        }
        if Thread.isMainThread {
            dismiss()
        } else {
            DispatchQueue.main.async {
                dismiss()
            }
        }
    }

    /// Stops the preview capture stream so RecordingEngine can own window capture during recording.
    static func transitionToRecording() {
        DispatchQueue.main.async {
            shared?.enterRecordingMode()
        }
    }

    static func updateFrame(_ image: CGImage) {
        DispatchQueue.main.async {
            guard let window = shared else { return }
            window.stageView?.update(image: image, screenSize: window.frame.size)
        }
    }

    private let configuration: Configuration
    private var displayMode: DisplayMode
    private let contentCapture = RecordingPreviewContentCapture()
    private let cameraCapture = CameraPreviewCapture()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let renderQueue = DispatchQueue(label: "com.snipsnap.recordingBackgroundPreview", qos: .userInitiated)
    private lazy var sourceOverFilter = CIFilter(name: "CISourceOverCompositing")
    private lazy var blendWithMaskFilter = CIFilter(name: "CIBlendWithMask")
    private var refreshTimer: Timer?
    private weak var stageView: RecordingBackgroundStageView?
    private var isInRecordingMode = false

    private let thumbnailWidth: CGFloat = 180
    private let thumbnailInset: CGFloat = 20

    private init(configuration: Configuration, displayMode: DisplayMode) {
        self.configuration = configuration
        self.displayMode = displayMode

        let frame = Self.frame(for: displayMode, thumbnailWidth: thumbnailWidth, inset: thumbnailInset)
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false

        let view = RecordingBackgroundStageView(
            frame: NSRect(origin: .zero, size: frame.size),
            isThumbnail: displayMode == .thumbnail
        )
        view.onClick = { [weak self] in self?.toggleDisplayMode() }
        contentView = view
        stageView = view

        Task { await contentCapture.start(configuration: configuration) }
        if let cameraID = configuration.cameraDeviceID {
            Task { await cameraCapture.start(deviceID: cameraID) }
        }
    }

    private static func frame(for mode: DisplayMode, thumbnailWidth: CGFloat, inset: CGFloat) -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let vis = screen.visibleFrame
        switch mode {
        case .thumbnail:
            let height = thumbnailWidth * 9 / 16
            return NSRect(
                x: vis.minX + inset,
                y: vis.minY + inset,
                width: thumbnailWidth,
                height: height
            )
        case .expanded:
            return vis
        }
    }

    private func applyLayout() {
        let frame = Self.frame(for: displayMode, thumbnailWidth: thumbnailWidth, inset: thumbnailInset)
        stageView?.isThumbnail = displayMode == .thumbnail
        setFrame(frame, display: true)
    }

    private func toggleDisplayMode() {
        displayMode = displayMode == .thumbnail ? .expanded : .thumbnail
        applyLayout()
    }

    private func startRefreshing() {
        guard refreshTimer == nil else { return }
        refreshFrame()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshFrame()
            }
        }
    }

    private func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        Task {
            await contentCapture.stop()
            await cameraCapture.stop()
        }
    }

    private func enterRecordingMode() {
        isInRecordingMode = true
        refreshTimer?.invalidate()
        refreshTimer = nil
        Task {
            await contentCapture.stop()
            await cameraCapture.stop()
        }
        if displayMode == .expanded {
            displayMode = .thumbnail
            applyLayout()
        }
    }

    private func refreshFrame() {
        guard !isInRecordingMode else { return }

        let background = configuration.background
        let cameraStyle = configuration.cameraStyle
        let hasCamera = configuration.cameraDeviceID != nil
        let screenSize = frame.size
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let canvasSize = RecordingBackgroundRenderer.canvasSize(for: scale)
        let contentImage = contentCapture.latestCIImage()
        let isRecordWindow: Bool
        switch configuration.captureMode {
        case .recordWindow: isRecordWindow = true
        default: isRecordWindow = false
        }
        let backgroundIsNone: Bool
        switch background {
        case .none: backgroundIsNone = true
        default: backgroundIsNone = false
        }
        let cameraIsVertical: Bool
        switch cameraStyle {
        case .vertical: cameraIsVertical = true
        case .square: cameraIsVertical = false
        }

        let cameraImage = hasCamera ? cameraCapture.latestCIImage() : nil
        let extent = CGRect(origin: .zero, size: canvasSize)
        var composited: CIImage

        if let contentImage {
            let useCompositeLayout = isRecordWindow && (!backgroundIsNone || hasCamera)
            if useCompositeLayout {
                let layoutCamera: CameraPreviewStyle? = hasCamera && cameraIsVertical ? .vertical : nil
                composited = RecordingBackgroundRenderer.composite(
                    windowImage: contentImage,
                    background: background,
                    canvasSize: canvasSize,
                    cameraStyle: layoutCamera,
                    scale: scale
                )
            } else {
                composited = fitImage(contentImage, into: extent)
            }
        } else {
            composited = RecordingBackgroundRenderer.backgroundImage(for: background, extent: extent)
        }

        if hasCamera, let cameraImage {
            composited = compositeCamera(cameraImage, onto: composited, style: cameraStyle, scale: scale)
                ?? composited
        }

        renderQueue.async { [weak self] in
            guard let self else { return }
            guard let cgImage = self.ciContext.createCGImage(composited, from: composited.extent) else { return }
            DispatchQueue.main.async {
                self.stageView?.update(image: cgImage, screenSize: screenSize)
            }
        }
    }

    private func fitImage(_ image: CIImage, into extent: CGRect) -> CIImage {
        let scale = min(extent.width / image.extent.width, extent.height / image.extent.height)
        let scaledW = image.extent.width * scale
        let scaledH = image.extent.height * scale
        let tx = extent.midX - scaledW / 2 - image.extent.minX * scale
        let ty = extent.midY - scaledH / 2 - image.extent.minY * scale
        return image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: tx / scale, y: ty / scale))
            .cropped(to: extent)
    }

    private func compositeCamera(
        _ cameraFrame: CIImage,
        onto screen: CIImage,
        style: CameraPreviewStyle,
        scale: CGFloat
    ) -> CIImage? {
        let screenW = screen.extent.width
        let screenH = screen.extent.height
        let camW = cameraFrame.extent.width
        let camH = cameraFrame.extent.height
        let mirrorTx = CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -camW, y: 0)
        let ciCamera = cameraFrame.transformed(by: mirrorTx)

        let margin: CGFloat
        switch style {
        case .square:
            let side = 100.0 * scale
            margin = 20.0 * scale
            let camScale = side / min(camW, camH)
            let scaledW = camW * camScale
            let scaledH = camH * camScale
            let cropRect = CGRect(x: (scaledW - side) / 2, y: (scaledH - side) / 2, width: side, height: side)
            let croppedCam = ciCamera
                .transformed(by: CGAffineTransform(scaleX: camScale, y: camScale))
                .cropped(to: cropRect)
            let tx = screenW - side - margin - croppedCam.extent.minX
            let ty = margin - croppedCam.extent.minY
            let positioned = croppedCam.transformed(by: CGAffineTransform(translationX: tx, y: ty))
            return sourceOver(positioned, over: screen)

        case .vertical:
            let strip = VerticalCameraStripLayout.metrics(screenWidth: screenW, screenHeight: screenH, scale: scale)
            let stripW = strip.width
            let stripH = strip.height
            let camScale = max(stripW / camW, stripH / camH)
            let scaledW = camW * camScale
            let scaledH = camH * camScale
            let cropRect = CGRect(x: (scaledW - stripW) / 2, y: (scaledH - stripH) / 2, width: stripW, height: stripH)
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
            return VerticalCameraStripLayout.compositeWithRoundedMask(positioned, mask: mask, over: screen)
        }
    }

    private func sourceOver(_ foreground: CIImage, over background: CIImage) -> CIImage? {
        guard let filter = sourceOverFilter else { return nil }
        filter.setValue(foreground, forKey: kCIInputImageKey)
        filter.setValue(background, forKey: kCIInputBackgroundImageKey)
        return filter.outputImage
    }
}

// MARK: - Content capture (window or display)

private final class RecordingPreviewContentCapture: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private var latestFrame: CVPixelBuffer?
    private let frameQueue = DispatchQueue(label: "com.snipsnap.recordingPreviewContentCapture.frames")

    func start(configuration: RecordingBackgroundPreviewWindow.Configuration) async {
        await stop()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let scale = Int(NSScreen.main?.backingScaleFactor ?? 2)

            let filter: SCContentFilter
            let width: Int
            let height: Int

            switch configuration.captureMode {
            case .recordWindow:
                guard let windowID = configuration.windowID,
                      let window = content.windows.first(where: { $0.windowID == windowID }) else { return }
                filter = SCContentFilter(desktopIndependentWindow: window)
                width = Int(window.frame.width) * scale
                height = Int(window.frame.height) * scale

            case .recordFullScreen:
                let mainID = CGMainDisplayID()
                guard let display = content.displays.first(where: { $0.displayID == mainID })
                                 ?? content.displays.first else { return }
                filter = SCContentFilter(display: display, excludingWindows: [])
                width = display.width * scale
                height = display.height * scale

            default:
                return
            }

            let config = SCStreamConfiguration()
            config.width = width
            config.height = height
            config.minimumFrameInterval = CMTime(value: 1, timescale: 15)
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = true

            let captureStream = SCStream(filter: filter, configuration: config, delegate: nil)
            try captureStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
            try await captureStream.startCapture()
            stream = captureStream
        } catch {
            print("[RecordingBackgroundPreview] Content capture failed: \(error)")
        }
    }

    func stop() async {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        frameQueue.sync { latestFrame = nil }
    }

    func latestCIImage() -> CIImage? {
        frameQueue.sync {
            guard let latestFrame else { return nil }
            return CIImage(cvPixelBuffer: latestFrame)
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        frameQueue.sync { latestFrame = pixelBuffer }
    }
}

// MARK: - Camera capture for preview

private final class CameraPreviewCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var session: AVCaptureSession?
    private var latestFrame: CVPixelBuffer?
    private let frameQueue = DispatchQueue(label: "com.snipsnap.cameraPreviewCapture.frames")

    func start(deviceID: String) async {
        await stop()
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .medium

        guard let device = AVCaptureDevice(uniqueID: deviceID)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else { return }

        captureSession.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: .global(qos: .userInitiated))
        guard captureSession.canAddOutput(output) else { return }
        captureSession.addOutput(output)

        session = captureSession
        let sessionToStart = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            sessionToStart.startRunning()
        }
    }

    func stop() async {
        session?.stopRunning()
        session = nil
        frameQueue.sync { latestFrame = nil }
    }

    func latestCIImage() -> CIImage? {
        frameQueue.sync {
            guard let latestFrame else { return nil }
            return CIImage(cvPixelBuffer: latestFrame)
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameQueue.sync { latestFrame = pixelBuffer }
    }
}

// MARK: - Stage view

private final class RecordingBackgroundStageView: NSView {
    var onClick: (() -> Void)?
    var isThumbnail: Bool {
        didSet { needsLayout = true }
    }

    private let imageLayer = CALayer()
    private var contentSize = CGSize.zero

    init(frame: NSRect, isThumbnail: Bool) {
        self.isThumbnail = isThumbnail
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        imageLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(imageLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        guard let root = layer else { return }
        if isThumbnail {
            root.cornerRadius = 10
            root.masksToBounds = true
            root.borderWidth = 2
            root.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
            root.shadowColor = NSColor.black.cgColor
            root.shadowOpacity = 0.45
            root.shadowRadius = 10
            root.shadowOffset = CGSize(width: 0, height: -2)
        } else {
            root.cornerRadius = 0
            root.masksToBounds = true
            root.borderWidth = 0
            root.shadowOpacity = 0
        }
        imageLayer.frame = aspectFitFrame(for: contentSize, in: bounds)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    func update(image: CGImage, screenSize: NSSize) {
        imageLayer.contents = image
        contentSize = CGSize(width: image.width, height: image.height)
        needsLayout = true
    }

    private func aspectFitFrame(for contentSize: CGSize, in bounds: CGRect) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0 else { return bounds }
        let widthRatio = bounds.width / contentSize.width
        let heightRatio = bounds.height / contentSize.height
        let scale = min(widthRatio, heightRatio)
        let size = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
