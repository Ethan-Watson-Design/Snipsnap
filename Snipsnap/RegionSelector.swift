//
//  RegionSelector.swift
//  Snipsnap
//
//  Created by Ethan Watson on 6/27/26.
//

import AppKit

// MARK: - Entry point

final class RegionSelector {
    private static var overlayWindow: RegionSelectorWindow?

    static func show(completion: @escaping (CGRect?) -> Void) {
        // Union of all display frames gives the full virtual desktop rect.
        let screenRect = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }

        let window = RegionSelectorWindow(contentRect: screenRect)
        let view = RegionSelectorView(frame: NSRect(origin: .zero, size: screenRect.size))
        view.completion = { rect in
            Self.overlayWindow?.close()
            Self.overlayWindow = nil
            completion(rect)
        }

        window.contentView = view
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // Retain until dismissed.
        Self.overlayWindow = window
    }
}

// MARK: - Window

private final class RegionSelectorWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Prevent AppKit from sending an extra ObjC release on close.
        // Without this, ARC + AppKit double-free the window → EXC_BAD_ACCESS.
        isReleasedWhenClosed = false
    }

    // Required so the window can receive keyboard events.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - View

private final class RegionSelectorView: NSView {
    var completion: ((CGRect?) -> Void)?

    private var startPoint: NSPoint?
    private var selectionRect: NSRect?

    override var acceptsFirstResponder: Bool { true }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        if let sel = selectionRect, sel.size.width > 1, sel.size.height > 1 {
            // Punch a clear hole in the dark tint using the even-odd fill rule:
            // outer rect covers everything, inner rect is the selection cutout.
            let tintPath = NSBezierPath(rect: bounds)
            tintPath.append(NSBezierPath(rect: sel))
            tintPath.windingRule = .evenOdd

            NSColor.black.withAlphaComponent(0.35).setFill()
            tintPath.fill()

            // White selection border
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: sel.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1.5
            border.stroke()

            // Thin corner handles (purely visual, 8 pt long each)
            drawCornerHandles(for: sel, in: ctx)

            // Size label
            drawSizeLabel(for: sel)
        } else {
            // No active selection — just the full dark tint.
            NSColor.black.withAlphaComponent(0.35).setFill()
            NSBezierPath(rect: bounds).fill()
        }
    }

    private func drawCornerHandles(for rect: NSRect, in ctx: CGContext) {
        let len: CGFloat = 10
        let lw: CGFloat = 2.5
        NSColor.white.setStroke()

        let corners: [(NSPoint, NSPoint, NSPoint)] = [
            // (corner, along-x neighbour end, along-y neighbour end)
            (rect.origin,
             NSPoint(x: rect.minX + len, y: rect.minY),
             NSPoint(x: rect.minX, y: rect.minY + len)),
            (NSPoint(x: rect.maxX, y: rect.minY),
             NSPoint(x: rect.maxX - len, y: rect.minY),
             NSPoint(x: rect.maxX, y: rect.minY + len)),
            (NSPoint(x: rect.minX, y: rect.maxY),
             NSPoint(x: rect.minX + len, y: rect.maxY),
             NSPoint(x: rect.minX, y: rect.maxY - len)),
            (NSPoint(x: rect.maxX, y: rect.maxY),
             NSPoint(x: rect.maxX - len, y: rect.maxY),
             NSPoint(x: rect.maxX, y: rect.maxY - len)),
        ]

        for (corner, xEnd, yEnd) in corners {
            let p = NSBezierPath()
            p.lineWidth = lw
            p.lineCapStyle = .square
            p.move(to: xEnd)
            p.line(to: corner)
            p.line(to: yEnd)
            p.stroke()
        }
    }

    private func drawSizeLabel(for rect: NSRect) {
        guard let window else { return }

        // Convert to screen pixels for the display label.
        let screenRect = window.convertToScreen(convert(rect, to: nil))
        // Use the backing scale factor of the screen under the cursor for pixel counts.
        let scale = window.backingScaleFactor
        let pw = Int(screenRect.width * scale)
        let ph = Int(screenRect.height * scale)
        let label = "\(pw) × \(ph)"

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let size = str.size()
        let padding: CGFloat = 6
        let boxSize = NSSize(width: size.width + padding * 2, height: size.height + padding)

        // Position label below the selection, or above if near the bottom edge.
        var origin = NSPoint(x: rect.midX - boxSize.width / 2, y: rect.minY - boxSize.height - 6)
        if origin.y < 4 { origin.y = rect.maxY + 6 }
        origin.x = max(4, min(origin.x, bounds.maxX - boxSize.width - 4))

        let boxRect = NSRect(origin: origin, size: boxSize)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: boxRect, xRadius: 4, yRadius: 4).fill()
        str.draw(at: NSPoint(x: boxRect.minX + padding, y: boxRect.minY + padding / 2))
    }

    // MARK: Mouse events

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        selectionRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        selectionRect = rectBetween(start, current)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let sel = selectionRect,
              sel.width > 2, sel.height > 2,
              let window else {
            DispatchQueue.main.async { self.completion?(nil) }
            return
        }
        let screenRect = window.convertToScreen(convert(sel, to: nil))
        DispatchQueue.main.async { self.completion?(screenRect) }
    }

    // MARK: Keyboard events

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            DispatchQueue.main.async { self.completion?(nil) }
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: Cursor

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: Helpers

    private func rectBetween(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }
}
