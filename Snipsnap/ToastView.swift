//
//  ToastView.swift
//  Snipsnap
//
//  Created by Ethan Watson on 6/27/26.
//

import AppKit

final class ToastWindow: NSWindow {

    private static var current: ToastWindow?

    private let onTap: () -> Void
    private var dismissTimer: Timer?

    // MARK: - Entry point

    static func show(image: NSImage, onTap: @escaping () -> Void) {
        DispatchQueue.main.async {
            current?.cancelAndClose()
            let window = ToastWindow(image: image, onTap: onTap)
            current = window
            window.presentAnimated()
        }
    }

    static func show(message: String) {
        DispatchQueue.main.async {
            current?.cancelAndClose()
            let window = ToastWindow(message: message)
            current = window
            window.presentAnimated()
        }
    }

    // MARK: - Init

    private init(image: NSImage, onTap: @escaping () -> Void) {
        self.onTap = onTap

        let contentSize = ToastWindow.layoutSize(for: image)

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        // Prevent AppKit from sending an extra ObjC release on close.
        // Without this, ARC + AppKit double-free the window → EXC_BAD_ACCESS.
        isReleasedWhenClosed = false

        let contentView = buildContentView(image: image, size: contentSize)
        self.contentView = contentView

        positionBottomRight(contentSize: contentSize)

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleTap))
        contentView.addGestureRecognizer(click)
    }

    private init(message: String) {
        self.onTap = {}

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isReleasedWhenClosed = false

        let (contentView, contentSize) = ToastWindow.makeMessageContent(message: message)
        self.contentView = contentView

        positionBottomCenter(contentSize: contentSize)
    }

    // MARK: - Layout helpers

    private static func layoutSize(for image: NSImage) -> NSSize {
        let maxW: CGFloat = 240
        let maxH: CGFloat = 140
        let padding = DesignTokens.Spacing.md

        let imgSize = image.size
        let scale = min(maxW / imgSize.width, maxH / imgSize.height, 1.0)
        let thumbW = max(imgSize.width * scale, 60)
        let thumbH = imgSize.height * scale

        let totalW = thumbW + padding * 2
        let totalH = thumbH + padding * 2
        return NSSize(width: totalW, height: totalH)
    }

    private static let messageFont = NSFont.snipsnap(.body)
    private static let messagePadding = NSEdgeInsets(
        top: 10,
        left: DesignTokens.Spacing.lg,
        bottom: 10,
        right: DesignTokens.Spacing.lg
    )

    private static func messageLabel(for message: String) -> NSTextField {
        let label = NSTextField(labelWithString: message)
        label.font = messageFont
        label.textColor = DesignTokens.Color.textPrimary.ns
        label.alignment = .center
        label.lineBreakMode = .byClipping
        label.cell?.wraps = false
        label.cell?.truncatesLastVisibleLine = false
        return label
    }

    private static func makeMessageContent(message: String) -> (view: NSView, size: NSSize) {
        let padding = messagePadding
        let label = messageLabel(for: message)
        label.sizeToFit()

        let textW = ceil(label.frame.width)
        let textH = ceil(label.frame.height)
        let size = NSSize(
            width: textW + padding.left + padding.right,
            height: textH + padding.top + padding.bottom
        )

        let vfx = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        vfx.material = .hudWindow
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = DesignTokens.Radius.lg
        vfx.layer?.masksToBounds = true

        label.frame = NSRect(x: padding.left, y: padding.bottom, width: textW, height: textH)
        vfx.addSubview(label)
        return (vfx, size)
    }

    private func buildContentView(image: NSImage, size: NSSize) -> NSView {
        let padding = DesignTokens.Spacing.md

        // Frosted glass background
        let vfx = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        vfx.material = .hudWindow
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = DesignTokens.Radius.lg
        vfx.layer?.masksToBounds = true

        // Thumbnail
        let thumbW = size.width - padding * 2
        let thumbH = size.height - padding * 2
        let thumbFrame = NSRect(x: padding, y: padding, width: thumbW, height: thumbH)
        let imageView = NSImageView(frame: thumbFrame)
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = DesignTokens.Radius.sm
        imageView.layer?.masksToBounds = true

        vfx.addSubview(imageView)
        return vfx
    }

    private func positionBottomRight(contentSize: NSSize) {
        guard let screen = NSScreen.main else { return }
        let margin: CGFloat = 20
        let visibleRect = screen.visibleFrame
        let origin = NSPoint(
            x: visibleRect.maxX - contentSize.width - margin,
            y: visibleRect.minY + margin
        )
        setFrame(NSRect(origin: origin, size: contentSize), display: false)
    }

    private func positionBottomCenter(contentSize: NSSize) {
        guard let screen = NSScreen.main else { return }
        let margin: CGFloat = 20
        let visibleRect = screen.visibleFrame
        let origin = NSPoint(
            x: visibleRect.midX - contentSize.width / 2,
            y: visibleRect.minY + margin
        )
        setFrame(NSRect(origin: origin, size: contentSize), display: false)
    }

    // MARK: - Animation

    private func presentAnimated() {
        alphaValue = 0
        let offscreen = frame.offsetBy(dx: 0, dy: -20)
        setFrame(offscreen, display: false)
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(frame.offsetBy(dx: 0, dy: 20), display: true)
        }

        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.dismissAnimated()
            }
        }
    }

    private func dismissAnimated() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.close()
                ToastWindow.current = nil
            }
        })
    }

    private func cancelAndClose() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        close()
        ToastWindow.current = nil
    }

    // MARK: - Interaction

    @objc private func handleTap() {
        onTap()
        dismissAnimated()
    }
}
