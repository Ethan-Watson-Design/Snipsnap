//
//  SettingsWindow.swift
//  Snipsnap
//

import AppKit

final class SettingsWindow: NSWindow {

    static var current: SettingsWindow?

    static func show() {
        if current == nil {
            current = SettingsWindow()
        }
        current?.center()
        current?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "Snipsnap Settings"
        isReleasedWhenClosed = false

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 220))
        self.contentView = contentView

        buildContent(in: contentView)
    }

    private func buildContent(in parent: NSView) {
        let width: CGFloat = 380
        let height: CGFloat = 220
        let sideMargin: CGFloat = 20
        let rowHeight: CGFloat = 44

        // "Shortcuts" section header
        let header = NSTextField(labelWithString: "SHORTCUTS")
        header.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.frame = NSRect(x: sideMargin, y: height - 32, width: width - sideMargin * 2, height: 16)
        parent.addSubview(header)

        // Separator below header
        let topSep = separator(y: height - 36, width: width)
        parent.addSubview(topSep)

        let shortcuts: [(String, [String])] = [
            ("Region Screenshot", ["⌘", "⇧", "2"]),
            ("Start Recording",   ["⌘", "⇧", "4"]),
            ("Clip Voice",        ["⌘", "⇧", "5"]),
        ]

        var rowTop = height - 36

        for (label, keys) in shortcuts {
            let rowY = rowTop - rowHeight

            // Left label
            let left = NSTextField(labelWithString: label)
            left.font = NSFont.systemFont(ofSize: 13)
            left.textColor = .labelColor
            left.frame = NSRect(x: sideMargin, y: rowY + (rowHeight - 16) / 2, width: 200, height: 16)
            parent.addSubview(left)

            // Key badge row (right-aligned)
            let badgeRowWidth = CGFloat(keys.count) * 24 + CGFloat(keys.count - 1) * 3
            var badgeX = width - sideMargin - badgeRowWidth
            let badgeCenterY = rowY + (rowHeight - 22) / 2

            for key in keys {
                let badge = keyBadge(label: key, origin: NSPoint(x: badgeX, y: badgeCenterY))
                parent.addSubview(badge)
                badgeX += 24 + 3
            }

            // Bottom separator
            let sep = separator(y: rowY, width: width)
            parent.addSubview(sep)

            rowTop = rowY
        }

        // Footer note
        let note = NSTextField(labelWithString: "Custom shortcuts coming soon")
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        note.alignment = .center
        note.frame = NSRect(x: sideMargin, y: 12, width: width - sideMargin * 2, height: 14)
        parent.addSubview(note)
    }

    private func separator(y: CGFloat, width: CGFloat) -> NSView {
        let line = NSView(frame: NSRect(x: 0, y: y, width: width, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        return line
    }

    private func keyBadge(label: String, origin: NSPoint) -> NSView {
        let container = NSView(frame: NSRect(origin: origin, size: NSSize(width: 24, height: 22)))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlColor.cgColor
        container.layer?.cornerRadius = 5
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.separatorColor.cgColor

        let text = NSTextField(labelWithString: label)
        text.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        text.textColor = .labelColor
        text.alignment = .center
        text.frame = NSRect(x: 0, y: 3, width: 24, height: 16)
        container.addSubview(text)

        return container
    }
}
