//
//  CameraPreviewWindow.swift
//  Snipsnap
//
//  Created by Ethan Watson on 6/28/26.
//
//  NOTE: Add NSCameraUsageDescription to Info.plist before shipping.
//  e.g. <key>NSCameraUsageDescription</key>
//       <string>Snipsnap uses your camera to show a picture-in-picture bubble during recordings.</string>

import AppKit
import AVFoundation
import CoreImage
import Vision

// MARK: - CameraBackgroundStyle

enum CameraBackgroundStyle: Equatable {
    case none
    case blur
    case warm
    case cool
    case midnight
    case custom(path: String)

    var menuTitle: String {
        switch self {
        case .none:     return "None"
        case .blur:     return "Blur"
        case .warm:     return "Warm"
        case .cool:     return "Cool"
        case .midnight: return "Midnight"
        case .custom:   return "Custom Image"
        }
    }
}

// MARK: - CameraBackgroundProcessor

/// Applies virtual backgrounds to camera frames using person segmentation.
final class CameraBackgroundProcessor {

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let segmentationRequest = VNGeneratePersonSegmentationRequest()
    private let processingQueue = DispatchQueue(label: "com.snipsnap.cameraBackground", qos: .userInitiated)
    private var customBackground: CIImage?
    private var customBackgroundPath: String?

    init() {
        segmentationRequest.qualityLevel = .balanced
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    func process(
        pixelBuffer: CVPixelBuffer,
        background: CameraBackgroundStyle,
        mirror: Bool = true,
        completion: @escaping (CGImage?) -> Void
    ) {
        processingQueue.async { [weak self] in
            guard let self else { return }
            let image = self.render(
                pixelBuffer: pixelBuffer,
                background: background,
                mirror: mirror
            )
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    private func render(
        pixelBuffer: CVPixelBuffer,
        background: CameraBackgroundStyle,
        mirror: Bool
    ) -> CGImage? {
        var input = CIImage(cvPixelBuffer: pixelBuffer)
        if mirror {
            input = input.transformed(by: CGAffineTransform(scaleX: -1, y: 1)
                .translatedBy(x: -input.extent.width, y: 0))
        }

        guard background != .none else {
            return ciContext.createCGImage(input, from: input.extent)
        }

        guard let mask = personMask(for: pixelBuffer, extent: input.extent) else {
            return ciContext.createCGImage(input, from: input.extent)
        }

        let bgImage = backgroundImage(for: background, extent: input.extent, source: input)
        let composited = composite(foreground: input, background: bgImage, mask: mask)
        return ciContext.createCGImage(composited, from: composited.extent)
    }

    private func personMask(for pixelBuffer: CVPixelBuffer, extent: CGRect) -> CIImage? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([segmentationRequest])
        } catch {
            return nil
        }
        guard let observation = segmentationRequest.results?.first else { return nil }
        let mask = CIImage(cvPixelBuffer: observation.pixelBuffer)
        let scaleX = extent.width / mask.extent.width
        let scaleY = extent.height / mask.extent.height
        return mask
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: extent)
    }

    private func backgroundImage(for style: CameraBackgroundStyle, extent: CGRect, source: CIImage) -> CIImage {
        switch style {
        case .none:
            return source
        case .blur:
            return source
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 18])
                .cropped(to: extent)
        case .warm:
            return gradient(
                colors: [
                    CIColor(red: 0.98, green: 0.72, blue: 0.45),
                    CIColor(red: 0.92, green: 0.38, blue: 0.55)
                ],
                extent: extent
            )
        case .cool:
            return gradient(
                colors: [
                    CIColor(red: 0.35, green: 0.75, blue: 0.98),
                    CIColor(red: 0.18, green: 0.42, blue: 0.92)
                ],
                extent: extent
            )
        case .midnight:
            return gradient(
                colors: [
                    CIColor(red: 0.12, green: 0.14, blue: 0.22),
                    CIColor(red: 0.04, green: 0.05, blue: 0.10)
                ],
                extent: extent
            )
        case .custom(let path):
            if customBackgroundPath != path {
                customBackgroundPath = path
                customBackground = CIImage(contentsOf: URL(fileURLWithPath: path))
            }
            guard let custom = customBackground else {
                return CIImage(color: .black).cropped(to: extent)
            }
            return custom
                .transformed(by: fitTransform(image: custom.extent, into: extent))
                .cropped(to: extent)
        }
    }

    private func gradient(colors: [CIColor], extent: CGRect) -> CIImage {
        guard let filter = CIFilter(name: "CILinearGradient") else {
            return CIImage(color: colors.first ?? .black).cropped(to: extent)
        }
        filter.setValue(CIVector(x: extent.minX, y: extent.minY), forKey: "inputPoint0")
        filter.setValue(CIVector(x: extent.maxX, y: extent.maxY), forKey: "inputPoint1")
        filter.setValue(colors[0], forKey: "inputColor0")
        filter.setValue(colors[1], forKey: "inputColor1")
        return filter.outputImage?.cropped(to: extent)
            ?? CIImage(color: colors[0]).cropped(to: extent)
    }

    private func fitTransform(image: CGRect, into target: CGRect) -> CGAffineTransform {
        let scale = max(target.width / image.width, target.height / image.height)
        let scaledW = image.width * scale
        let scaledH = image.height * scale
        let tx = target.midX - scaledW / 2 - image.minX * scale
        let ty = target.midY - scaledH / 2 - image.minY * scale
        return CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: tx / scale, y: ty / scale)
    }

    private func composite(foreground: CIImage, background: CIImage, mask: CIImage) -> CIImage {
        guard let blend = CIFilter(name: "CIBlendWithMask") else { return foreground }
        blend.setValue(foreground, forKey: kCIInputImageKey)
        blend.setValue(background, forKey: kCIInputBackgroundImageKey)
        blend.setValue(mask, forKey: kCIInputMaskImageKey)
        return blend.outputImage ?? foreground
    }
}

// MARK: - CameraPreviewStyle

enum CameraPreviewStyle: Equatable {
    /// Small rounded square anchored to the bottom-right corner.
    case square
    /// Tall vertical strip (TikTok/Bōrumi style) — 1/4 screen width, full height, far right.
    case vertical
}

// MARK: - CameraPreviewWindow

final class CameraPreviewWindow: NSPanel {

    // MARK: Shared state

    private static var shared: CameraPreviewWindow?

    static var isVisible: Bool {
        shared?.isVisible ?? false
    }

    static func show(
        style: CameraPreviewStyle = .square,
        deviceID: String? = nil,
        background: CameraBackgroundStyle = .none
    ) {
        DispatchQueue.main.async {
            if let existing = shared,
               existing.currentStyle == style,
               existing.deviceID == deviceID,
               existing.backgroundStyle == background {
                existing.startSession()
                existing.orderFrontRegardless()
                return
            }
            shared?.stopSession()
            shared?.orderOut(nil)
            shared = CameraPreviewWindow(style: style, deviceID: deviceID, background: background)
            shared?.startSession()
            shared?.orderFrontRegardless()
        }
    }

    static func hide() {
        DispatchQueue.main.async {
            shared?.stopSession()
            shared?.orderOut(nil)
        }
    }

    // MARK: Constants

    private let squareSize:    CGFloat = 100
    private let edgeInset:     CGFloat = 24
    private let borderWidth:   CGFloat = 1.5
    private let squareCorner:  CGFloat = 12

    // MARK: AV

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let outputQueue = DispatchQueue(label: "com.snipsnap.cameraPreview", qos: .userInitiated)
    private let backgroundProcessor = CameraBackgroundProcessor()
    private weak var previewView: CameraPreviewDisplayView?

    // MARK: Style

    private let currentStyle: CameraPreviewStyle
    private let deviceID: String?
    private let backgroundStyle: CameraBackgroundStyle

    // MARK: Init

    init(
        style: CameraPreviewStyle = .square,
        deviceID: String? = nil,
        background: CameraBackgroundStyle = .none
    ) {
        self.currentStyle = style
        self.deviceID = deviceID
        self.backgroundStyle = background

        let initialFrame: NSRect
        switch style {
        case .square:
            let origin = CameraPreviewWindow.squareOrigin(size: 100, inset: 24)
            initialFrame = NSRect(origin: origin, size: CGSize(width: 100, height: 100))
        case .vertical:
            initialFrame = CameraPreviewWindow.verticalFrame()
        }

        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configure()
        buildContentView()
        configureCapture()
    }

    // MARK: - Window configuration

    private func configure() {
        level = .floating
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
    }

    // MARK: - Content view

    private func buildContentView() {
        switch currentStyle {
        case .square:
            buildSquareContent()
        case .vertical:
            buildVerticalContent()
        }
    }

    private func buildSquareContent() {
        let container = CameraSquareView(
            frame: NSRect(origin: .zero, size: CGSize(width: squareSize, height: squareSize)),
            cornerRadius: squareCorner,
            borderWidth: borderWidth
        )
        let display = CameraPreviewDisplayView(frame: container.bounds)
        display.autoresizingMask = [.width, .height]
        container.addSubview(display)
        contentView = container
        previewView = display
    }

    private func buildVerticalContent() {
        let frame = CameraPreviewWindow.verticalFrame()
        let container = CameraVerticalView(
            frame: NSRect(origin: .zero, size: frame.size)
        )
        let display = CameraPreviewDisplayView(frame: container.bounds)
        display.autoresizingMask = [.width, .height]
        container.addSubview(display)
        contentView = container
        previewView = display
    }

    // MARK: - Capture setup

    private func configureCapture() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async { self?.configureSession() }
            }
        default:
            break
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .medium

        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }

        guard
            let device = resolvedVideoDevice(),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()
    }

    private func resolvedVideoDevice() -> AVCaptureDevice? {
        if let id = deviceID, let device = AVCaptureDevice(uniqueID: id) {
            return device
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
    }

    // MARK: - Session lifecycle

    private func startSession() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    private func stopSession() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
        }
    }

    // MARK: - Positioning helpers

    private static func squareOrigin(size: CGFloat, inset: CGFloat) -> CGPoint {
        guard let screen = NSScreen.main else { return .zero }
        let vis = screen.visibleFrame
        return CGPoint(x: vis.maxX - size - inset, y: vis.minY + inset)
    }

    private static func verticalFrame() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let vis = screen.visibleFrame
        let margin: CGFloat = 20
        let w = (vis.width / 4).rounded()
        let h = vis.height - margin * 2
        return NSRect(x: vis.maxX - w - margin, y: vis.minY + margin, width: w, height: h)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraPreviewWindow: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if backgroundStyle == .none {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                .transformed(by: CGAffineTransform(scaleX: -1, y: 1)
                    .translatedBy(x: -CGFloat(CVPixelBufferGetWidth(pixelBuffer)), y: 0))
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
            DispatchQueue.main.async { [weak self] in
                self?.previewView?.update(image: cgImage)
            }
            return
        }

        backgroundProcessor.process(
            pixelBuffer: pixelBuffer,
            background: backgroundStyle,
            mirror: true
        ) { [weak self] cgImage in
            guard let cgImage else { return }
            self?.previewView?.update(image: cgImage)
        }
    }
}

// MARK: - CameraPreviewDisplayView

private final class CameraPreviewDisplayView: NSView {
    private let imageLayer = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspectFill
        layer?.addSublayer(imageLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        imageLayer.frame = bounds
    }

    func update(image: CGImage) {
        imageLayer.contents = image
    }
}

// MARK: - CameraSquareView

/// Small rounded square with a subtle ring border and drop shadow.
private final class CameraSquareView: NSView {

    private let cornerRadius: CGFloat
    private let borderWidth: CGFloat

    init(frame: NSRect, cornerRadius: CGFloat, borderWidth: CGFloat) {
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        guard let root = layer else { return }
        root.frame = bounds
        root.cornerRadius = cornerRadius
        root.masksToBounds = true
        root.shadowColor = NSColor.black.cgColor
        root.shadowOpacity = 0.4
        root.shadowRadius = 8
        root.shadowOffset = CGSize(width: 0, height: -2)
        layoutBorderRing(on: root)
    }

    private func layoutBorderRing(on root: CALayer) {
        let ringTag = "cameraSquareRing"
        let ring: CAShapeLayer
        if let existing = root.sublayers?.first(where: { $0.name == ringTag }) as? CAShapeLayer {
            ring = existing
        } else {
            ring = CAShapeLayer()
            ring.name = ringTag
            ring.fillColor = CGColor.clear
            root.addSublayer(ring)
        }
        let inset = borderWidth / 2
        let rect = root.bounds.insetBy(dx: inset, dy: inset)
        ring.path = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        ring.strokeColor = NSColor.white.withAlphaComponent(0.20).cgColor
        ring.lineWidth = borderWidth
        ring.frame = root.bounds
    }
}

// MARK: - CameraVerticalView

/// A tall vertical strip that clips the camera feed to a rounded rectangle.
private final class CameraVerticalView: NSView {

    private let clipCornerRadius: CGFloat = 24

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        guard let root = layer else { return }
        root.frame = bounds
        root.cornerRadius = clipCornerRadius
        root.masksToBounds = true
        root.shadowColor = NSColor.black.cgColor
        root.shadowOpacity = 0.55
        root.shadowRadius = 22
        root.shadowOffset = CGSize(width: -4, height: 0)
    }
}
