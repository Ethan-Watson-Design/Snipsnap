//
//  ToastView.swift
//  Snipsnap
//
//  Created by Ethan Watson on 6/27/26.
//

import AppKit

final class ToastWindow: NSPanel {

    private static var current: ToastWindow?
    static var currentAssociatedCaptureID: UUID? { current?.associatedCaptureID }
    static var currentToast: ToastWindow? { current }

    let associatedCaptureID: UUID?
    private let onTap: () -> Void
    private var dismissTimer: Timer?
    private var dismissalDuration: TimeInterval = 4.0
    private weak var backgroundView: NSVisualEffectView?
    private weak var toastContainerView: NSView?
    private weak var thumbnailView: NSImageView?
    private weak var chipButton: NSButton?
    private weak var messageLabel: NSTextField?
    private weak var messageActionButton: NSButton?
    private var messageActionTrampoline: ToastActionTrampoline?
    private var chipAction: (() -> Void)?
    private var anchorScreenRect: NSRect?

    // MARK: - Entry point

    static func show(image: NSImage, associatedCaptureID: UUID?, onTap: @escaping () -> Void) {
        DispatchQueue.main.async {
            current?.cancelAndClose()
            let window = ToastWindow(image: image, associatedCaptureID: associatedCaptureID, onTap: onTap)
            current = window
            window.presentAnimated()
        }
    }

    static func show(message: String, associatedCaptureID: UUID? = nil) {
        DispatchQueue.main.async {
            current?.cancelAndClose()
            let window = ToastWindow(message: message, associatedCaptureID: associatedCaptureID)
            current = window
            window.presentAnimated()
        }
    }

    static func show(
        message: String,
        associatedCaptureID: UUID?,
        actionTitle: String,
        anchorScreenRect: NSRect? = nil,
        hostWindow: NSWindow? = nil,
        onAction: @escaping () -> Void,
        onPresented: (() -> Void)? = nil
    ) {
        DispatchQueue.main.async {
            current?.cancelAndClose()
            let window = ToastWindow(
                message: message,
                associatedCaptureID: associatedCaptureID,
                actionTitle: actionTitle,
                anchorScreenRect: anchorScreenRect,
                onAction: onAction
            )
            current = window
            if associatedCaptureID != nil {
                window.prepareForPendingFolderSuggestion()
            }
            window.presentAnimated(hostWindow: hostWindow)
            onPresented?()
        }
    }

    func prepareForPendingFolderSuggestion() {
        dismissalDuration = 8.0
        restartDismissTimer()
    }

    static func isCurrentToast(for captureID: UUID) -> Bool {
        current?.associatedCaptureID == captureID
    }

    // MARK: - Init

    private func configurePanel(level: NSWindow.Level) {
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        worksWhenModal = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        self.level = level
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }

    private init(image: NSImage, associatedCaptureID: UUID?, onTap: @escaping () -> Void) {
        self.associatedCaptureID = associatedCaptureID
        self.onTap = onTap

        let contentSize = ToastWindow.layoutSize(for: image)

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel(level: .floating)

        let contentView = buildContentView(image: image, size: contentSize)
        self.contentView = contentView

        positionBottomRight(contentSize: contentSize)
    }

    private init(message: String, associatedCaptureID: UUID?) {
        self.associatedCaptureID = associatedCaptureID
        self.onTap = {}

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel(level: .floating)

        let (contentView, background, contentSize, label) = ToastWindow.makeMessageContent(message: message)
        self.contentView = contentView
        toastContainerView = contentView
        backgroundView = background
        messageLabel = label

        positionBottomCenter(contentSize: contentSize)
    }

    private init(
        message: String,
        associatedCaptureID: UUID?,
        actionTitle: String,
        anchorScreenRect: NSRect?,
        onAction: @escaping () -> Void
    ) {
        self.associatedCaptureID = associatedCaptureID
        self.anchorScreenRect = anchorScreenRect
        self.onTap = {}

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel(level: anchorScreenRect == nil ? .floating : .popUpMenu)

        let (contentView, contentSize, label, actionButton, background) = makeMessageContent(
            message: message,
            actionTitle: actionTitle,
            onAction: onAction
        )
        self.contentView = contentView
        toastContainerView = contentView
        backgroundView = background
        messageLabel = label
        self.messageActionButton = actionButton

        positionForAnchor(contentSize: contentSize)
    }

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

    private static func makeToastChrome(size: NSSize) -> (container: NSView, background: NSVisualEffectView) {
        let cornerRadius = DesignTokens.Radius.lg
        let bounds = NSRect(origin: .zero, size: size)

        let container = NSView(frame: bounds)
        container.wantsLayer = true

        let vfx = NSVisualEffectView(frame: bounds)
        vfx.material = .hudWindow
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = cornerRadius
        vfx.layer?.cornerCurve = .continuous
        vfx.layer?.masksToBounds = true

        container.addSubview(vfx)
        applyToastShadow(to: container)
        return (container, vfx)
    }

    private static func applyToastShadow(to container: NSView) {
        guard let layer = container.layer else { return }
        DesignTokens.Elevation.panel.apply(
            to: layer,
            roundedPathIn: container.bounds,
            cornerRadius: DesignTokens.Radius.lg
        )
    }

    private func resizeToastChrome(to size: NSSize) {
        toastContainerView?.setFrameSize(size)
        backgroundView?.setFrameSize(size)
        if let container = toastContainerView {
            ToastWindow.applyToastShadow(to: container)
        }
    }

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

    private static func makeMessageContent(message: String) -> (view: NSView, background: NSVisualEffectView, size: NSSize, label: NSTextField) {
        let padding = ToastWindow.messagePadding
        let label = ToastWindow.messageLabel(for: message)
        label.sizeToFit()

        let textW = ceil(label.frame.width)
        let textH = ceil(label.frame.height)
        let size = NSSize(
            width: textW + padding.left + padding.right,
            height: textH + padding.top + padding.bottom
        )

        let (container, vfx) = ToastWindow.makeToastChrome(size: size)

        label.frame = NSRect(x: padding.left, y: padding.bottom, width: textW, height: textH)
        vfx.addSubview(label)
        return (container, vfx, size, label)
    }

    private func makeMessageContent(
        message: String,
        actionTitle: String,
        onAction: @escaping () -> Void
    ) -> (view: NSView, size: NSSize, label: NSTextField, actionButton: NSButton, background: NSVisualEffectView) {
        let padding = ToastWindow.messagePadding
        let label = ToastWindow.messageLabel(for: message)
        label.sizeToFit()

        let actionButton = NSButton(title: actionTitle, target: nil, action: nil)
        actionButton.isBordered = false
        actionButton.bezelStyle = .inline
        actionButton.font = NSFont.snipsnap(.body)
        actionButton.alignment = .center
        actionButton.contentTintColor = DesignTokens.Color.accent.ns
        actionButton.setButtonType(.momentaryChange)
        actionButton.action = #selector(ToastActionTrampoline.handleTap)
        let trampoline = ToastActionTrampoline { [weak self] in
            onAction()
            self?.dismissAnimated()
        }
        messageActionTrampoline = trampoline
        actionButton.target = trampoline
        actionButton.sizeToFit()

        let spacing: CGFloat = 6
        let textW = ceil(label.frame.width)
        let textH = ceil(label.frame.height)
        let actionW = ceil(actionButton.frame.width)
        let actionH = ceil(actionButton.frame.height)
        let contentW = max(textW, actionW) + padding.left + padding.right
        let contentH = textH + actionH + spacing + padding.top + padding.bottom
        let size = NSSize(width: contentW, height: contentH)

        let (container, vfx) = ToastWindow.makeToastChrome(size: size)

        label.frame = NSRect(
            x: (size.width - textW) / 2,
            y: padding.bottom + actionH + spacing,
            width: textW,
            height: textH
        )
        actionButton.frame = NSRect(
            x: (size.width - actionW) / 2,
            y: padding.bottom,
            width: actionW,
            height: actionH
        )

        vfx.addSubview(label)
        vfx.addSubview(actionButton)
        return (container, size, label, actionButton, vfx)
    }

    private func buildContentView(image: NSImage, size: NSSize) -> NSView {
        let padding = DesignTokens.Spacing.md
        let (container, vfx) = ToastWindow.makeToastChrome(size: size)

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
        backgroundView = vfx
        thumbnailView = imageView
        toastContainerView = container
        return container
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
        setFrame(NSRect(origin: anchoredOrigin(for: contentSize), size: contentSize), display: false)
    }

    private func positionForAnchor(contentSize: NSSize) {
        positionBottomCenter(contentSize: contentSize)
    }

    private func anchoredOrigin(for contentSize: NSSize) -> NSPoint {
        if let titleBarAnchor = anchorScreenRect {
            let margin: CGFloat = 6
            return NSPoint(
                x: titleBarAnchor.midX - contentSize.width / 2,
                y: titleBarAnchor.minY - contentSize.height - margin
            )
        }
        return screenBottomCenterOrigin(for: contentSize)
    }

    private func screenBottomCenterOrigin(for contentSize: NSSize) -> NSPoint {
        let margin: CGFloat = 16
        let visibleRect = NSScreen.main?.visibleFrame ?? .zero
        return NSPoint(
            x: visibleRect.midX - contentSize.width / 2,
            y: visibleRect.minY + margin
        )
    }

    // MARK: - Animation

    private func presentAnimated(hostWindow: NSWindow? = nil) {
        let targetFrame = frame
        alphaValue = 0
        let slidesFromAbove = anchorScreenRect != nil
        let offscreen = targetFrame.offsetBy(dx: 0, dy: slidesFromAbove ? 12 : -20)
        setFrame(offscreen, display: false)
        orderFrontRegardless()
        if let hostWindow {
            order(.above, relativeTo: hostWindow.windowNumber)
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(targetFrame, display: true)
        }

        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissalDuration = 4.0
        restartDismissTimer()
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

    override func mouseUp(with event: NSEvent) {
        guard let contentView else { return }
        let locationInContent = contentView.convert(event.locationInWindow, from: nil)
        if let chipButton, chipButton.frame.contains(locationInContent) {
            return
        }
        if let messageActionButton, messageActionButton.frame.contains(locationInContent) {
            return
        }
        handleTap()
    }

    func attachFolderSuggestion(_ destination: CaptureDestination, onConfirm: @escaping () -> Void) {
        chipAction = onConfirm
        let destinationCopy = destination
        DispatchQueue.main.async { [weak self] in
            self?.applyFolderSuggestionLayout(destination: destinationCopy)
        }
    }

    private func applyFolderSuggestionLayout(destination: CaptureDestination) {
        guard let contentView = backgroundView else { return }

        let chipLabel = folderChipLabel(for: destination)
        let button = chipButton ?? makeFolderChipButton()
        setChipTitle(chipLabel, on: button)

        let chipFont = NSFont.snipsnap(.caption)
        let chipVerticalGap: CGFloat = 8
        let chipHorizontalPadding: CGFloat = 10
        let chipHeight: CGFloat = 24
        let measuredTextWidth = ceil(
            (chipLabel as NSString).size(withAttributes: [.font: chipFont]).width
        )
        let measuredChipWidth = measuredTextWidth + chipHorizontalPadding * 2

        if let imageView = thumbnailView {
            let contentPadding = DesignTokens.Spacing.md
            let maxChipWidth = max(120, imageView.frame.width)
            let chipWidth = min(maxChipWidth, measuredChipWidth)
            let newHeight = imageView.frame.height + contentPadding * 2 + chipVerticalGap + chipHeight

            button.frame = NSRect(
                x: contentPadding,
                y: contentPadding,
                width: chipWidth,
                height: chipHeight
            )
            imageView.frame = NSRect(
                x: contentPadding,
                y: contentPadding + chipHeight + chipVerticalGap,
                width: imageView.frame.width,
                height: imageView.frame.height
            )
            resizeToastChrome(to: NSSize(width: frame.width, height: newHeight))

            if button.superview == nil {
                contentView.addSubview(button)
            }

            repositionKeepingBottomRight(contentSize: NSSize(width: frame.width, height: newHeight))
        } else if let label = messageLabel {
            applyMessageToastFolderChip(
                destination: destination,
                button: button,
                label: label,
                chipWidth: measuredChipWidth,
                chipHeight: chipHeight
            )
        } else {
            return
        }

        dismissalDuration = 8.0
        restartDismissTimer()
    }

    /// Re-lays out a message toast as: folder chip (top) → status label → action button (bottom).
    private func applyMessageToastFolderChip(
        destination: CaptureDestination,
        button: NSButton,
        label: NSTextField,
        chipWidth: CGFloat,
        chipHeight: CGFloat
    ) {
        guard let contentView = backgroundView else { return }

        let padding = ToastWindow.messagePadding
        let rowGap: CGFloat = 6
        let chipGap: CGFloat = 8
        let labelSize = label.frame.size
        let actionSize = messageActionButton?.frame.size ?? .zero
        let contentWidth = max(
            labelSize.width,
            actionSize.width,
            chipWidth
        ) + padding.left + padding.right
        let fittedChipWidth = min(contentWidth - padding.left - padding.right, chipWidth)
        let newHeight = padding.top
            + chipHeight
            + chipGap
            + labelSize.height
            + rowGap
            + actionSize.height
            + padding.bottom

        var y = padding.bottom
        if let action = messageActionButton {
            action.frame = NSRect(
                x: (contentWidth - actionSize.width) / 2,
                y: y,
                width: actionSize.width,
                height: actionSize.height
            )
            y += actionSize.height + rowGap
        }

        label.frame = NSRect(
            x: (contentWidth - labelSize.width) / 2,
            y: y,
            width: labelSize.width,
            height: labelSize.height
        )
        y += labelSize.height + chipGap

        button.frame = NSRect(
            x: (contentWidth - fittedChipWidth) / 2,
            y: y,
            width: fittedChipWidth,
            height: chipHeight
        )
        setChipTitle(folderChipLabel(for: destination), on: button)

        resizeToastChrome(to: NSSize(width: contentWidth, height: newHeight))
        if button.superview == nil {
            contentView.addSubview(button)
        }

        repositionKeepingBottomCenter(contentSize: NSSize(width: contentWidth, height: newHeight))
    }

    private func repositionKeepingBottomRight(contentSize: NSSize) {
        guard let screen = NSScreen.main else { return }
        let margin: CGFloat = 20
        let visibleRect = screen.visibleFrame
        let origin = NSPoint(
            x: visibleRect.maxX - contentSize.width - margin,
            y: visibleRect.minY + margin
        )
        setFrame(NSRect(origin: origin, size: contentSize), display: true)
    }

    private func repositionKeepingBottomCenter(contentSize: NSSize) {
        setFrame(NSRect(origin: anchoredOrigin(for: contentSize), size: contentSize), display: true)
    }

    private func restartDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        dismissTimer = Timer.scheduledTimer(withTimeInterval: dismissalDuration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.dismissAnimated()
            }
        }
    }

    private func makeFolderChipButton() -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(handleChipTap))
        button.isBordered = false
        button.bezelStyle = .inline
        button.font = NSFont.snipsnap(.caption)
        button.alignment = .center
        button.imagePosition = .noImage
        button.setButtonType(.momentaryChange)
        button.wantsLayer = true
        button.layer?.cornerRadius = DesignTokens.Radius.md
        button.layer?.backgroundColor = DesignTokens.Color.panelHoverFill.cg
        button.lineBreakMode = .byTruncatingTail
        chipButton = button
        return button
    }

    private func setChipTitle(_ title: String, on button: NSButton) {
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.snipsnap(.caption),
                .foregroundColor: DesignTokens.Color.textPrimary.ns,
            ]
        )
    }

    private func folderChipLabel(for destination: CaptureDestination) -> String {
        if let subfolder = destination.subfolder, !subfolder.isEmpty {
            return "→ \(destination.productFolder) / \(subfolder)"
        }
        return "→ \(destination.productFolder)"
    }

    @objc private func handleChipTap() {
        chipAction?()
        dismissAnimated()
    }

    @objc private func handleTap() {
        onTap()
        dismissAnimated()
    }
}

private final class ToastActionTrampoline: NSObject {
    let onTap: () -> Void

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init()
    }

    @objc func handleTap() {
        onTap()
    }
}
