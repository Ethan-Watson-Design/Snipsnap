//
//  AnnotationWindow.swift
//  Snipsnap
//
//  Created by Ethan Watson on 6/27/26.
//

import AppKit

// MARK: - AnnotationCanvasView

final class AnnotationCanvasView: NSView {

    // Raw point storage — no mutable reference types shared between draw and event handlers.
    private var strokes: [[CGPoint]] = []
    private var currentStroke: [CGPoint] = []

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setStrokeColor(NSColor.red.cgColor)
        ctx.setLineWidth(3)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for points in strokes {
            stroke(points, in: ctx)
        }
        stroke(currentStroke, in: ctx)
    }

    private func stroke(_ points: [CGPoint], in ctx: CGContext) {
        guard !points.isEmpty else { return }
        ctx.beginPath()
        ctx.move(to: points[0])
        if points.count == 1 {
            // Render single-click as a tiny segment so it has visible length.
            ctx.addLine(to: CGPoint(x: points[0].x + 0.5, y: points[0].y))
        } else {
            for pt in points.dropFirst() {
                ctx.addLine(to: pt)
            }
        }
        ctx.strokePath()
    }

    // MARK: Mouse events

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        currentStroke = [convert(event.locationInWindow, from: nil)]
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentStroke.append(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentStroke.append(convert(event.locationInWindow, from: nil))
        if !currentStroke.isEmpty {
            strokes.append(currentStroke)
        }
        currentStroke = []
        needsDisplay = true
    }

    // MARK: Undo

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "z" {
            undoLastStroke()
        } else {
            super.keyDown(with: event)
        }
    }

    func undoLastStroke() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
        needsDisplay = true
    }

    // MARK: Flatten

    func flattenedImage(background: NSImage) -> NSImage {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return background }

        let result = NSImage(size: size)
        result.lockFocus()
        defer { result.unlockFocus() }

        background.draw(in: NSRect(origin: .zero, size: size),
                        from: NSRect(origin: .zero, size: background.size),
                        operation: .sourceOver,
                        fraction: 1.0)

        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setStrokeColor(NSColor.red.cgColor)
            ctx.setLineWidth(3)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for points in strokes { stroke(points, in: ctx) }
        }

        return result
    }
}

// MARK: - AnnotationWindow

final class AnnotationWindow: NSWindow {

    private static var current: AnnotationWindow?

    private let screenshot: NSImage
    private let canvas: AnnotationCanvasView
    private let toolbarHeight: CGFloat = 48

    // MARK: Entry point

    static func show(image: NSImage) {
        DispatchQueue.main.async {
            current = AnnotationWindow(image: image)
            current?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: Init

    private init(image: NSImage) {
        self.screenshot = image

        let imageSize = AnnotationWindow.fittedSize(for: image)
        self.canvas = AnnotationCanvasView(frame: NSRect(origin: .zero, size: imageSize))

        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: screenRect.midX - imageSize.width / 2,
            y: screenRect.midY - imageSize.height / 2
        )

        // Create the window sized to just the image; toolbar height is added via setContentSize below.
        super.init(
            contentRect: NSRect(origin: origin, size: imageSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "Annotate"
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false

        buildContentHierarchy(imageSize: imageSize)
    }

    // MARK: Layout

    private static func fittedSize(for image: NSImage) -> NSSize {
        let maxW: CGFloat = 1200
        let maxH: CGFloat = 800
        let s = image.size
        let scale = min(maxW / s.width, maxH / s.height, 1.0)
        return NSSize(width: (s.width * scale).rounded(), height: (s.height * scale).rounded())
    }

    private func buildContentHierarchy(imageSize: NSSize) {
        let totalContentHeight = imageSize.height + toolbarHeight

        // Grow the window content area to accommodate the toolbar without touching the title bar.
        setContentSize(NSSize(width: imageSize.width, height: totalContentHeight))

        let root = NSView(frame: NSRect(origin: .zero,
                                        size: NSSize(width: imageSize.width, height: totalContentHeight)))

        // Screenshot sits above the toolbar.
        let imageView = NSImageView(frame: NSRect(x: 0,
                                                  y: toolbarHeight,
                                                  width: imageSize.width,
                                                  height: imageSize.height))
        imageView.image = screenshot
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        root.addSubview(imageView)

        // Canvas overlays the image exactly.
        canvas.frame = imageView.frame
        root.addSubview(canvas)

        // Toolbar at the bottom.
        root.addSubview(buildToolbar(width: imageSize.width))

        contentView = root
        makeFirstResponder(canvas)
    }

    private func buildToolbar(width: CGFloat) -> NSView {
        let toolbar = NSView(frame: NSRect(x: 0, y: 0, width: width, height: toolbarHeight))
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let separator = NSBox(frame: NSRect(x: 0, y: toolbarHeight - 1, width: width, height: 1))
        separator.boxType = .separator
        toolbar.addSubview(separator)

        let copyButton = NSButton(title: "Copy", target: self, action: #selector(copyAnnotatedImage))
        copyButton.bezelStyle = .rounded
        copyButton.sizeToFit()
        let sz = copyButton.frame.size
        copyButton.frame = NSRect(x: (width - sz.width) / 2,
                                  y: (toolbarHeight - sz.height) / 2,
                                  width: sz.width,
                                  height: sz.height)
        toolbar.addSubview(copyButton)

        return toolbar
    }

    // MARK: Actions

    @objc private func copyAnnotatedImage() {
        let flat = canvas.flattenedImage(background: screenshot)
        guard let tiffData = flat.tiffRepresentation else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(tiffData, forType: .tiff)
    }
}
