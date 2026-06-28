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

// MARK: - CameraPreviewStyle

enum CameraPreviewStyle: Equatable {
    /// Classic circular bubble anchored to a corner.
    case bubble
    /// Tall vertical strip (TikTok/Bōrumi style) — 1/5 screen width, full height, far right.
    case vertical
}

// MARK: - CameraPreviewWindow

final class CameraPreviewWindow: NSPanel {

    // MARK: Shared state

    private static var shared: CameraPreviewWindow?

    static var isVisible: Bool {
        shared?.isVisible ?? false
    }

    static func show(style: CameraPreviewStyle = .bubble) {
        DispatchQueue.main.async {
            // If the same style is already up, just make sure it's visible.
            if let existing = shared, existing.currentStyle == style {
                existing.startSession()
                existing.orderFrontRegardless()
                return
            }
            // Style changed or first launch — tear down previous and rebuild.
            shared?.stopSession()
            shared?.orderOut(nil)
            shared = CameraPreviewWindow(style: style)
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

    // MARK: Constants (bubble)

    private let bubbleSize:    CGFloat = 120
    private let edgeInset:     CGFloat = 24
    private let borderWidth:   CGFloat = 1.5
    private let shadowBlur:    CGFloat = 12
    private let shadowOpacity: Float   = 0.4
    private let shadowOffset           = CGSize(width: 0, height: -3)

    // MARK: AV

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: Style

    private let currentStyle: CameraPreviewStyle

    // MARK: Init

    init(style: CameraPreviewStyle = .bubble) {
        self.currentStyle = style

        let initialFrame: NSRect
        switch style {
        case .bubble:
            let origin = CameraPreviewWindow.bubbleOrigin(size: 120, inset: 24)
            initialFrame = NSRect(origin: origin, size: CGSize(width: 120, height: 120))
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
        hasShadow = true
    }

    // MARK: - Content view

    private func buildContentView() {
        switch currentStyle {
        case .bubble:
            buildBubbleContent()
        case .vertical:
            buildVerticalContent()
        }
    }

    private func buildBubbleContent() {
        let container = CameraBubbleView(
            frame: NSRect(origin: .zero, size: CGSize(width: bubbleSize, height: bubbleSize)),
            borderWidth: borderWidth,
            shadowBlur: shadowBlur,
            shadowOpacity: shadowOpacity,
            shadowOffset: shadowOffset
        )
        contentView = container

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        container.attach(previewLayer: preview)
        self.previewLayer = preview
    }

    private func buildVerticalContent() {
        // The layer manages its own shadow; the system window shadow would apply to the
        // full panel rectangle and create an ugly translucent halo.
        hasShadow = false
        let frame = CameraPreviewWindow.verticalFrame()
        let container = CameraVerticalView(
            frame: NSRect(origin: .zero, size: frame.size)
        )
        contentView = container

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        container.attach(previewLayer: preview)
        self.previewLayer = preview
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

        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .front
            ),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)
        session.commitConfiguration()
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

    private static func bubbleOrigin(size: CGFloat, inset: CGFloat) -> CGPoint {
        guard let screen = NSScreen.main else { return .zero }
        let vis = screen.visibleFrame
        return CGPoint(x: vis.maxX - size - inset, y: vis.minY + inset)
    }

    private static func verticalFrame() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let vis = screen.visibleFrame
        let margin: CGFloat = 20
        let w = (vis.width / 4).rounded()
        let h = vis.height - margin * 2   // top + bottom margin
        return NSRect(x: vis.maxX - w - margin, y: vis.minY + margin, width: w, height: h)
    }
}

// MARK: - CameraBubbleView

/// Clips the camera feed to a circle with a subtle ring border and drop shadow.
private final class CameraBubbleView: NSView {

    private let borderWidth: CGFloat
    private let shadowBlur: CGFloat
    private let shadowOpacity: Float
    private let shadowOffset: CGSize

    private var captureLayer: AVCaptureVideoPreviewLayer?

    init(
        frame: NSRect,
        borderWidth: CGFloat,
        shadowBlur: CGFloat,
        shadowOpacity: Float,
        shadowOffset: CGSize
    ) {
        self.borderWidth   = borderWidth
        self.shadowBlur    = shadowBlur
        self.shadowOpacity = shadowOpacity
        self.shadowOffset  = shadowOffset
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func makeBackingLayer() -> CALayer {
        let root = CALayer()
        root.masksToBounds = false
        return root
    }

    override func layout() {
        super.layout()
        guard let root = layer else { return }
        root.frame = bounds
        applyDropShadow(to: root)
        layoutCaptureLayer()
        layoutBorderRing(on: root)
    }

    func attach(previewLayer: AVCaptureVideoPreviewLayer) {
        captureLayer = previewLayer
        wantsLayer = true
        needsLayout = true
    }

    private func layoutCaptureLayer() {
        guard let root = layer, let capture = captureLayer else { return }
        capture.frame = root.bounds
        if capture.superlayer == nil { root.addSublayer(capture) }

        let mask = CAShapeLayer()
        mask.path = CGPath(ellipseIn: root.bounds, transform: nil)
        capture.mask = mask
    }

    private func applyDropShadow(to layer: CALayer) {
        layer.shadowColor   = NSColor.black.cgColor
        layer.shadowOpacity = shadowOpacity
        layer.shadowRadius  = shadowBlur / 2
        layer.shadowOffset  = shadowOffset
    }

    private func layoutBorderRing(on root: CALayer) {
        let ringTag = "cameraRing"
        let ring: CAShapeLayer
        if let existing = root.sublayers?.first(where: { $0.name == ringTag }) as? CAShapeLayer {
            ring = existing
        } else {
            ring = CAShapeLayer()
            ring.name      = ringTag
            ring.fillColor = CGColor.clear
            root.addSublayer(ring)
        }
        let inset  = borderWidth / 2
        let rect   = root.bounds.insetBy(dx: inset, dy: inset)
        ring.path        = CGPath(ellipseIn: rect, transform: nil)
        ring.strokeColor = NSColor.white.withAlphaComponent(0.20).cgColor
        ring.lineWidth   = borderWidth
        ring.frame       = root.bounds
    }
}

// MARK: - CameraVerticalView

/// A tall vertical strip that clips the camera feed to a rounded rectangle,
/// matching the TikTok / Bōrumi presenter-cam aesthetic.
private final class CameraVerticalView: NSView {

    private let clipCornerRadius: CGFloat = 24
    private var captureLayer: AVCaptureVideoPreviewLayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func makeBackingLayer() -> CALayer {
        let root = CALayer()
        root.masksToBounds = false
        root.backgroundColor = CGColor.clear
        return root
    }

    override func layout() {
        super.layout()
        guard let root = layer else { return }
        root.frame = bounds
        root.backgroundColor = CGColor.clear
        applyDropShadow(to: root)
        layoutCaptureLayer()
    }

    func attach(previewLayer: AVCaptureVideoPreviewLayer) {
        captureLayer = previewLayer
        wantsLayer = true
        needsLayout = true
    }

    private func layoutCaptureLayer() {
        guard let root = layer, let capture = captureLayer else { return }
        capture.frame = root.bounds
        if capture.superlayer == nil { root.addSublayer(capture) }

        // Rounded-rect clip mask — video fills the full height of the strip.
        let mask = CAShapeLayer()
        mask.path = CGPath(
            roundedRect: root.bounds,
            cornerWidth: clipCornerRadius,
            cornerHeight: clipCornerRadius,
            transform: nil
        )
        capture.mask = mask
    }

    private func applyDropShadow(to layer: CALayer) {
        layer.shadowColor   = NSColor.black.cgColor
        layer.shadowOpacity = 0.55
        layer.shadowRadius  = 22
        layer.shadowOffset  = CGSize(width: -4, height: 0)
    }
}
