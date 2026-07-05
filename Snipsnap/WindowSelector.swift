//
//  WindowSelector.swift
//  Snipsnap
//

import AppKit
import ApplicationServices
import ScreenCaptureKit

// MARK: - Entry point

final class WindowSelector {
    private static var overlayWindow: WindowSelectorWindow?

    static func fetchRecordableWindows() async -> [SCWindow] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            return filterRecordableWindows(content.windows)
        } catch {
            return []
        }
    }

    static func displayName(for window: SCWindow) -> String {
        let app = window.owningApplication?.applicationName ?? "Window"
        let title = window.title ?? ""
        if title.isEmpty { return app }
        return "\(app) — \(title)"
    }

    /// Brings the owning app (and window, when accessibility allows) to the front.
    static func activateWindow(_ windowID: CGWindowID) async {
        let windows = await fetchRecordableWindows()
        guard let window = windows.first(where: { $0.windowID == windowID }),
              let pid = window.owningApplication?.processID else { return }

        await MainActor.run {
            _ = NSRunningApplication(processIdentifier: pid_t(pid))?.activate()
        }

        try? await Task.sleep(nanoseconds: 80_000_000)
        await MainActor.run {
            raiseWindow(pid: pid_t(pid), title: window.title)
        }
    }

    private static func raiseWindow(pid: pid_t, title: String?) {
        let appRef = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement],
              !windows.isEmpty else { return }

        let target: AXUIElement?
        if let title, !title.isEmpty {
            target = windows.first { win in
                var titleValue: CFTypeRef?
                guard AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleValue) == .success else {
                    return false
                }
                return (titleValue as? String) == title
            } ?? windows.first
        } else {
            target = windows.first
        }

        if let target {
            AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        }
    }

    static func defaultWindowID(from windows: [SCWindow]) -> CGWindowID? {
        guard !windows.isEmpty else { return nil }
        let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let frontBundle {
            let frontAppWindows = windows.filter { $0.owningApplication?.bundleIdentifier == frontBundle }
            if let top = frontAppWindows.max(by: { $0.windowLayer < $1.windowLayer }) {
                return top.windowID
            }
        }
        return windows.max(by: { $0.windowLayer < $1.windowLayer })?.windowID
    }

    private static func filterRecordableWindows(_ windows: [SCWindow]) -> [SCWindow] {
        windows
            .filter { window in
                guard window.isOnScreen else { return false }
                guard window.frame.width > 40, window.frame.height > 40 else { return false }
                guard let app = window.owningApplication, !app.applicationName.isEmpty else { return false }
                if app.bundleIdentifier == Bundle.main.bundleIdentifier { return false }
                return true
            }
            .sorted { lhs, rhs in
                let lName = displayName(for: lhs)
                let rName = displayName(for: rhs)
                if lName != rName { return lName.localizedCaseInsensitiveCompare(rName) == .orderedAscending }
                return lhs.windowLayer > rhs.windowLayer
            }
    }

    static func show(completion: @escaping (CGWindowID?) -> Void) {
        Task {
            let windows = await fetchRecordableWindows()
            guard !windows.isEmpty else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            DispatchQueue.main.async {
                let screenRect = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
                let window = WindowSelectorWindow(contentRect: screenRect)
                let view = WindowSelectorView(frame: NSRect(origin: .zero, size: screenRect.size))
                view.windows = windows
                view.completion = { id in
                    Self.overlayWindow?.close()
                    Self.overlayWindow = nil
                    completion(id)
                }

                window.contentView = view
                window.makeFirstResponder(view)
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                Self.overlayWindow = window
            }
        }
    }
}

// MARK: - Window

private final class WindowSelectorWindow: NSWindow {
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
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - View

private final class WindowSelectorView: NSView {
    var windows: [SCWindow] = []
    var completion: ((CGWindowID?) -> Void)?

    private var hoveredWindowID: CGWindowID?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        for window in windows {
            let rect = screenRect(for: window)
            guard rect.width > 1, rect.height > 1 else { continue }

            let isHovered = window.windowID == hoveredWindowID
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)

            if isHovered {
                NSColor.systemBlue.withAlphaComponent(0.18).setFill()
                path.fill()
                NSColor.systemBlue.setStroke()
                path.lineWidth = 3
                path.stroke()

                let titleText = window.title ?? ""
                let title = titleText.isEmpty
                    ? (window.owningApplication?.applicationName ?? "Window")
                    : titleText
                drawLabel(title, near: rect)
            } else {
                NSColor.white.withAlphaComponent(0.12).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }

        drawInstruction()
    }

    private func drawInstruction() {
        let text = "Click a window to record  ·  Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.snipsnap(.title),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: bounds.height - size.height - 28
        )
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }

    private func drawLabel(_ text: String, near rect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.snipsnap(.label),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = NSPoint(
            x: rect.minX,
            y: min(rect.maxY + 6, bounds.height - size.height - 8)
        )
        let bg = NSRect(x: origin.x - 6, y: origin.y - 2, width: size.width + 12, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: bg, xRadius: DesignTokens.Radius.sm, yRadius: DesignTokens.Radius.sm).fill()
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }

    private func screenRect(for window: SCWindow) -> NSRect {
        guard let overlay = self.window else { return .zero }
        let frame = window.frame
        let origin = overlay.frame.origin
        return NSRect(
            x: frame.origin.x - origin.x,
            y: frame.origin.y - origin.y,
            width: frame.width,
            height: frame.height
        )
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        updateHover(at: event.locationInWindow)
    }

    override func mouseDown(with event: NSEvent) {
        let point = event.locationInWindow
        if let hit = topmostWindow(at: point) {
            completion?(hit.windowID)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            completion?(nil)
            return
        }
        super.keyDown(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    private func updateHover(at point: NSPoint) {
        let next = topmostWindow(at: point)?.windowID
        guard next != hoveredWindowID else { return }
        hoveredWindowID = next
        needsDisplay = true
    }

    private func topmostWindow(at point: NSPoint) -> SCWindow? {
        guard let overlay = window else { return nil }
        let screenPoint = NSPoint(
            x: point.x + overlay.frame.origin.x,
            y: point.y + overlay.frame.origin.y
        )
        return windows
            .filter { $0.frame.contains(screenPoint) }
            .sorted { $0.windowLayer > $1.windowLayer }
            .first
    }
}
