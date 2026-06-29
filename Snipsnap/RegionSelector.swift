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
    private static weak var activeView: RegionSelectorView?

    /// Drag to select, release to confirm (menu shortcut flow).
    static func show(completion: @escaping (CGRect?) -> Void) {
        present(mode: .oneShot, level: .screenSaver, initialRect: nil) { view in
            view.completion = { rect in
                Self.overlayWindow?.close()
                Self.overlayWindow = nil
                Self.activeView = nil
                completion(rect)
            }
        }
    }

    /// Stays open while the capture bar is visible; selection can be moved and resized.
    static func showInteractive(
        initialRect: CGRect? = nil,
        onChange: @escaping (CGRect?) -> Void
    ) {
        // Above normal app windows, below the capture bar (.popUpMenu).
        present(mode: .interactive, level: .statusBar, initialRect: initialRect) { view in
            view.onSelectionChange = onChange
            view.onSelectionChange?(view.currentScreenRect)
        }
    }

    static func hide() {
        overlayWindow?.close()
        overlayWindow = nil
        activeView = nil
    }

    private static func present(
        mode: RegionSelectorView.Mode,
        level: NSWindow.Level,
        initialRect: CGRect?,
        configure: (RegionSelectorView) -> Void
    ) {
        hide()

        let screenRect = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        let window = RegionSelectorWindow(contentRect: screenRect, level: level)
        let view = RegionSelectorView(frame: NSRect(origin: .zero, size: screenRect.size))
        view.mode = mode
        if let initialRect {
            view.setSelection(fromScreenRect: initialRect)
        }
        configure(view)

        window.contentView = view
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        overlayWindow = window
        activeView = view
    }
}

// MARK: - Window

private final class RegionSelectorWindow: NSWindow {
    init(contentRect: NSRect, level: NSWindow.Level) {
        super.init(
            contentRect: contentRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        self.level = level
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - View

private final class RegionSelectorView: NSView {
    enum Mode {
        case oneShot
        case interactive
    }

    var mode: Mode = .oneShot
    var completion: ((CGRect?) -> Void)?
    var onSelectionChange: ((CGRect?) -> Void)?

    private var startPoint: NSPoint?
    private var selectionRect: NSRect?
    private var dragMode: DragMode = .none

    private enum DragMode {
        case none
        case creating
        case moving(origin: NSRect, start: NSPoint)
        case resizing(handle: ResizeHandle, anchor: NSRect)

        var isActive: Bool {
            if case .none = self { return false }
            return true
        }
    }

    private enum ResizeHandle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        var cursor: NSCursor {
            switch self {
            case .topLeft, .bottomRight: return .crosshair
            case .topRight, .bottomLeft: return .crosshair
            case .top, .bottom: return .resizeUpDown
            case .left, .right: return .resizeLeftRight
            }
        }
    }

    var currentScreenRect: CGRect? {
        guard let sel = selectionRect, sel.width > 2, sel.height > 2, let window else { return nil }
        return window.convertToScreen(convert(sel, to: nil))
    }

    override var acceptsFirstResponder: Bool { true }

    func setSelection(fromScreenRect screenRect: CGRect) {
        guard let window else { return }
        let local = convert(window.convertFromScreen(screenRect), from: nil)
        selectionRect = clamped(local)
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard NSGraphicsContext.current != nil else { return }

        if let sel = selectionRect, sel.size.width > 1, sel.size.height > 1 {
            let tintPath = NSBezierPath(rect: bounds)
            tintPath.append(NSBezierPath(rect: sel))
            tintPath.windingRule = .evenOdd

            NSColor.black.withAlphaComponent(0.35).setFill()
            tintPath.fill()

            let accent = NSColor.regionSelectionAccent
            accent.setStroke()
            let border = NSBezierPath(rect: sel)
            border.lineWidth = 1.5
            border.stroke()

            drawCornerHandles(for: sel, accent: accent)
            drawSizeLabel(for: sel)
            drawInstruction(hasSelection: true)
        } else {
            NSColor.black.withAlphaComponent(0.35).setFill()
            NSBezierPath(rect: bounds).fill()
            drawInstruction(hasSelection: false)
        }
    }

    private func drawInstruction(hasSelection: Bool) {
        let text: String
        if hasSelection {
            text = mode == .oneShot
                ? "Release to capture  ·  Esc to cancel"
                : "Drag corners or edges to resize  ·  Drag inside to move  ·  Esc to clear"
        } else {
            text = "Drag to select a region  ·  Esc to cancel"
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = instructionOrigin(for: size)
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }

    /// Bottom-center of the main screen visible area, aligned with the capture bar.
    private func instructionOrigin(for textSize: NSSize) -> NSPoint {
        guard let window, let screen = NSScreen.main else {
            return NSPoint(x: (bounds.width - textSize.width) / 2, y: 24)
        }
        let vis = screen.visibleFrame
        let screenPoint = NSPoint(x: vis.midX - textSize.width / 2, y: vis.minY + 24)
        let windowPoint = window.convertFromScreen(NSRect(origin: screenPoint, size: .zero)).origin
        return convert(windowPoint, from: nil)
    }

    private func drawCornerHandles(for rect: NSRect, accent: NSColor) {
        let radius: CGFloat = 5

        for point in cornerPoints(in: rect) {
            let handleRect = NSRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            NSColor.white.setFill()
            NSBezierPath(ovalIn: handleRect).fill()
            accent.setStroke()
            let outline = NSBezierPath(ovalIn: handleRect.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1.5
            outline.stroke()
        }
    }

    private func cornerPoints(in rect: NSRect) -> [NSPoint] {
        [
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.maxY),
            NSPoint(x: rect.minX, y: rect.maxY),
        ]
    }

    private func drawSizeLabel(for rect: NSRect) {
        guard let window else { return }

        let screenRect = window.convertToScreen(convert(rect, to: nil))
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
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point

        if let sel = selectionRect, sel.width > 2, sel.height > 2 {
            if let handle = hitTestHandle(at: point, in: sel) {
                dragMode = .resizing(handle: handle, anchor: sel)
                return
            }
            if interiorRect(of: sel).contains(point) {
                dragMode = .moving(origin: sel, start: point)
                return
            }
        }

        dragMode = .creating
        selectionRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)

        switch dragMode {
        case .none:
            break

        case .creating:
            guard let start = startPoint else { return }
            selectionRect = clamped(rectBetween(start, current))
            needsDisplay = true

        case .moving(let origin, let start):
            let dx = current.x - start.x
            let dy = current.y - start.y
            var moved = origin.offsetBy(dx: dx, dy: dy)
            moved = clampedToBounds(moved)
            selectionRect = moved
            needsDisplay = true
            if mode == .interactive { notifySelectionChange() }

        case .resizing(let handle, let anchor):
            selectionRect = clamped(resizedRect(anchor: anchor, handle: handle, to: current))
            needsDisplay = true
            if mode == .interactive { notifySelectionChange() }
        }
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = dragMode.isActive

        defer {
            dragMode = .none
            startPoint = nil
        }

        switch mode {
        case .oneShot:
            resetCursorRects()
            if wasDragging,
               let sel = selectionRect,
               sel.width > 2, sel.height > 2 {
                confirmOneShotSelection()
            }

        case .interactive:
            notifySelectionChange()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            switch mode {
            case .oneShot:
                DispatchQueue.main.async { self.completion?(nil) }
            case .interactive:
                selectionRect = nil
                needsDisplay = true
                notifySelectionChange()
            }
            return
        }

        super.keyDown(with: event)
    }

    private func confirmOneShotSelection() {
        guard let sel = selectionRect,
              sel.width > 2, sel.height > 2,
              let window else {
            DispatchQueue.main.async { self.completion?(nil) }
            return
        }
        let screenRect = window.convertToScreen(convert(sel, to: nil))
        DispatchQueue.main.async { self.completion?(screenRect) }
    }

    override func resetCursorRects() {
        if let sel = selectionRect, sel.width > 2, sel.height > 2 {
            addEdgeCursorRects(for: sel)
            addCornerCursorRects(for: sel)
            addInteriorCursorRect(for: sel)
        } else {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    private func addInteriorCursorRect(for sel: NSRect) {
        let inset = cornerHitRadius + 2
        let interior = sel.insetBy(dx: inset, dy: inset)
        guard interior.width > 0, interior.height > 0 else { return }
        addCursorRect(interior, cursor: .arrow)
    }

    private func addCornerCursorRects(for sel: NSRect) {
        let hit = cornerHitRadius
        for (point, handle) in cornerHitTargets(in: sel) {
            let rect = NSRect(x: point.x - hit, y: point.y - hit, width: hit * 2, height: hit * 2)
            addCursorRect(rect, cursor: handle.cursor)
        }
    }

    private func addEdgeCursorRects(for sel: NSRect) {
        let t = edgeHitThickness
        let inset = cornerHitRadius

        let bottom = NSRect(x: sel.minX + inset, y: sel.minY - t / 2, width: sel.width - inset * 2, height: t)
        let top = NSRect(x: sel.minX + inset, y: sel.maxY - t / 2, width: sel.width - inset * 2, height: t)
        let left = NSRect(x: sel.minX - t / 2, y: sel.minY + inset, width: t, height: sel.height - inset * 2)
        let right = NSRect(x: sel.maxX - t / 2, y: sel.minY + inset, width: t, height: sel.height - inset * 2)

        if bottom.width > 0 { addCursorRect(bottom, cursor: ResizeHandle.bottom.cursor) }
        if top.width > 0 { addCursorRect(top, cursor: ResizeHandle.top.cursor) }
        if left.height > 0 { addCursorRect(left, cursor: ResizeHandle.left.cursor) }
        if right.height > 0 { addCursorRect(right, cursor: ResizeHandle.right.cursor) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let sel = selectionRect, sel.width > 2, sel.height > 2 {
            if let handle = hitTestHandle(at: point, in: sel) {
                handle.cursor.set()
                return
            }
            if interiorRect(of: sel).contains(point) {
                NSCursor.arrow.set()
                return
            }
        }
        NSCursor.crosshair.set()
    }

    // MARK: Helpers

    private func notifySelectionChange() {
        onSelectionChange?(currentScreenRect)
        resetCursorRects()
    }

    private func rectBetween(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }

    private func clamped(_ rect: NSRect) -> NSRect {
        var r = rect
        let minSize: CGFloat = 20
        r.size.width = max(r.size.width, minSize)
        r.size.height = max(r.size.height, minSize)
        return clampedToBounds(r)
    }

    private func clampedToBounds(_ rect: NSRect) -> NSRect {
        var r = rect
        if r.minX < bounds.minX {
            r.origin.x = bounds.minX
        }
        if r.minY < bounds.minY {
            r.origin.y = bounds.minY
        }
        if r.maxX > bounds.maxX {
            r.origin.x = bounds.maxX - r.width
        }
        if r.maxY > bounds.maxY {
            r.origin.y = bounds.maxY - r.height
        }
        return r
    }

    private let cornerHitRadius: CGFloat = 10
    private let edgeHitThickness: CGFloat = 6

    private func cornerHitTargets(in rect: NSRect) -> [(NSPoint, ResizeHandle)] {
        [
            (NSPoint(x: rect.minX, y: rect.minY), .bottomLeft),
            (NSPoint(x: rect.maxX, y: rect.minY), .bottomRight),
            (NSPoint(x: rect.maxX, y: rect.maxY), .topRight),
            (NSPoint(x: rect.minX, y: rect.maxY), .topLeft),
        ]
    }

    private func interiorRect(of rect: NSRect) -> NSRect {
        rect.insetBy(dx: cornerHitRadius + 2, dy: cornerHitRadius + 2)
    }

    private func hitTestHandle(at point: NSPoint, in rect: NSRect) -> ResizeHandle? {
        for (p, handle) in cornerHitTargets(in: rect) {
            if hypot(point.x - p.x, point.y - p.y) <= cornerHitRadius {
                return handle
            }
        }

        let t = edgeHitThickness / 2
        let inset = cornerHitRadius

        if point.y >= rect.minY - t, point.y <= rect.minY + t,
           point.x >= rect.minX + inset, point.x <= rect.maxX - inset {
            return .bottom
        }
        if point.y >= rect.maxY - t, point.y <= rect.maxY + t,
           point.x >= rect.minX + inset, point.x <= rect.maxX - inset {
            return .top
        }
        if point.x >= rect.minX - t, point.x <= rect.minX + t,
           point.y >= rect.minY + inset, point.y <= rect.maxY - inset {
            return .left
        }
        if point.x >= rect.maxX - t, point.x <= rect.maxX + t,
           point.y >= rect.minY + inset, point.y <= rect.maxY - inset {
            return .right
        }

        return nil
    }

    private func resizedRect(anchor: NSRect, handle: ResizeHandle, to point: NSPoint) -> NSRect {
        let minSize: CGFloat = 20
        var minX = anchor.minX
        var minY = anchor.minY
        var maxX = anchor.maxX
        var maxY = anchor.maxY

        switch handle {
        case .topLeft:
            minX = min(point.x, maxX - minSize)
            maxY = max(point.y, minY + minSize)
        case .top:
            maxY = max(point.y, minY + minSize)
        case .topRight:
            maxX = max(point.x, minX + minSize)
            maxY = max(point.y, minY + minSize)
        case .right:
            maxX = max(point.x, minX + minSize)
        case .bottomRight:
            maxX = max(point.x, minX + minSize)
            minY = min(point.y, maxY - minSize)
        case .bottom:
            minY = min(point.y, maxY - minSize)
        case .bottomLeft:
            minX = min(point.x, maxX - minSize)
            minY = min(point.y, maxY - minSize)
        case .left:
            minX = min(point.x, maxX - minSize)
        }

        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
