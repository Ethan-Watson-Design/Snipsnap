//
//  SettingsWindow.swift
//  Snipsnap
//

import AppKit
import Foundation

enum AppSettings {
    private static let destinationFolderKey = "destinationFolderPath"

    static let spotlightDimOpacityNotches: [CGFloat] = [0, 0.05, 0.15, 0.30, 0.60]
    static let spotlightBlurRadiusNotches: [CGFloat] = [0, 1, 2, 5, 10]
    static let spotlightSoftnessNotches: [CGFloat] = [0, 2, 4, 8, 16]
    static let spotlightDimOpacityDefault: CGFloat = 0.30
    static let spotlightBlurRadiusDefault: CGFloat = 5
    static let spotlightSoftnessDefault: CGFloat = 0

    static func snapSpotlightDimOpacity(_ value: CGFloat) -> CGFloat {
        spotlightDimOpacityNotches.min(by: { abs($0 - value) < abs($1 - value) }) ?? spotlightDimOpacityDefault
    }

    static func snapSpotlightBlurRadius(_ value: CGFloat) -> CGFloat {
        spotlightBlurRadiusNotches.min(by: { abs($0 - value) < abs($1 - value) }) ?? spotlightBlurRadiusDefault
    }

    static func snapSpotlightSoftness(_ value: CGFloat) -> CGFloat {
        spotlightSoftnessNotches.min(by: { abs($0 - value) < abs($1 - value) }) ?? spotlightSoftnessDefault
    }

    static func spotlightDimOpacityIndex(for value: CGFloat) -> Int {
        let snapped = snapSpotlightDimOpacity(value)
        return spotlightDimOpacityNotches.firstIndex(of: snapped) ?? 3
    }

    static func spotlightBlurRadiusIndex(for value: CGFloat) -> Int {
        let snapped = snapSpotlightBlurRadius(value)
        return spotlightBlurRadiusNotches.firstIndex(of: snapped) ?? 3
    }

    static func spotlightSoftnessIndex(for value: CGFloat) -> Int {
        let snapped = snapSpotlightSoftness(value)
        return spotlightSoftnessNotches.firstIndex(of: snapped) ?? 0
    }

    static var destinationFolderURL: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: destinationFolderKey) {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                    return URL(fileURLWithPath: path, isDirectory: true)
                }
            }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        }
        set {
            UserDefaults.standard.set(newValue.path, forKey: destinationFolderKey)
        }
    }

    static var destinationFolderDisplayPath: String {
        let path = destinationFolderURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    static func ensureDestinationFolderExists() throws {
        try FileManager.default.createDirectory(
            at: destinationFolderURL,
            withIntermediateDirectories: true
        )
    }

}

final class SettingsWindow: NSWindow {

    static var current: SettingsWindow?

    private var destinationPathLabel: NSTextField!

    static func show() {
        if current == nil {
            current = SettingsWindow()
        }
        current?.refreshDestinationPathLabel()
        current?.center()
        current?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "Snipsnap Settings"
        isReleasedWhenClosed = false

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 300))
        self.contentView = contentView

        buildContent(in: contentView)
    }

    private func buildContent(in parent: NSView) {
        let width: CGFloat = 380
        let height: CGFloat = 300
        let sideMargin: CGFloat = 20
        let rowHeight: CGFloat = 44

        // "Save Location" section
        let destHeader = NSTextField(labelWithString: "SAVE LOCATION")
        destHeader.font = NSFont.snipsnap(.caption)
        destHeader.textColor = DesignTokens.Color.textSecondary.ns
        destHeader.frame = NSRect(x: sideMargin, y: height - 32, width: width - sideMargin * 2, height: 16)
        parent.addSubview(destHeader)

        let destTopSep = separator(y: height - 36, width: width)
        parent.addSubview(destTopSep)

        let destRowY = height - 36 - rowHeight

        let destLabel = NSTextField(labelWithString: "Save to")
        destLabel.font = NSFont.snipsnap(.body)
        destLabel.textColor = DesignTokens.Color.textPrimary.ns
        destLabel.frame = NSRect(x: sideMargin, y: destRowY + (rowHeight - 16) / 2, width: 52, height: 16)
        parent.addSubview(destLabel)

        destinationPathLabel = NSTextField(labelWithString: AppSettings.destinationFolderDisplayPath)
        destinationPathLabel.font = NSFont.snipsnap(.body)
        destinationPathLabel.textColor = DesignTokens.Color.textSecondary.ns
        destinationPathLabel.lineBreakMode = .byTruncatingMiddle
        destinationPathLabel.frame = NSRect(
            x: sideMargin + 58,
            y: destRowY + (rowHeight - 16) / 2,
            width: width - sideMargin * 2 - 58 - 80,
            height: 16
        )
        parent.addSubview(destinationPathLabel)

        let changeButton = NSButton(title: "Change…", target: self, action: #selector(chooseDestinationFolder))
        changeButton.bezelStyle = .rounded
        changeButton.frame = NSRect(x: width - sideMargin - 72, y: destRowY + (rowHeight - 24) / 2, width: 72, height: 24)
        parent.addSubview(changeButton)

        let destBottomSep = separator(y: destRowY, width: width)
        parent.addSubview(destBottomSep)

        // "Shortcuts" section
        let shortcutsTop = destRowY - 36

        let header = NSTextField(labelWithString: "SHORTCUTS")
        header.font = NSFont.snipsnap(.caption)
        header.textColor = DesignTokens.Color.textSecondary.ns
        header.frame = NSRect(x: sideMargin, y: shortcutsTop + 4, width: width - sideMargin * 2, height: 16)
        parent.addSubview(header)

        let topSep = separator(y: shortcutsTop, width: width)
        parent.addSubview(topSep)

        let shortcuts: [(String, [String])] = [
            ("Snap Area",       ["⌘", "⇧", "3"]),
            ("Record Screen",   ["⌘", "⇧", "4"]),
            ("Clip Voice",        ["⌘", "⇧", "5"]),
        ]

        var rowTop = shortcutsTop

        for (label, keys) in shortcuts {
            let rowY = rowTop - rowHeight

            let left = NSTextField(labelWithString: label)
            left.font = NSFont.snipsnap(.body)
            left.textColor = DesignTokens.Color.textPrimary.ns
            left.frame = NSRect(x: sideMargin, y: rowY + (rowHeight - 16) / 2, width: 200, height: 16)
            parent.addSubview(left)

            let badgeRowWidth = CGFloat(keys.count) * 24 + CGFloat(keys.count - 1) * 3
            var badgeX = width - sideMargin - badgeRowWidth
            let badgeCenterY = rowY + (rowHeight - 22) / 2

            for key in keys {
                let badge = keyBadge(label: key, origin: NSPoint(x: badgeX, y: badgeCenterY))
                parent.addSubview(badge)
                badgeX += 24 + 3
            }

            let sep = separator(y: rowY, width: width)
            parent.addSubview(sep)

            rowTop = rowY
        }

        let accessibilityLink = NSButton(
            title: "Open Accessibility Settings for Snipsnap…",
            target: self,
            action: #selector(openAccessibilitySettings)
        )
        accessibilityLink.bezelStyle = .inline
        accessibilityLink.isBordered = false
        accessibilityLink.font = NSFont.snipsnap(.caption)
        accessibilityLink.contentTintColor = .linkColor
        accessibilityLink.sizeToFit()
        let linkSize = accessibilityLink.fittingSize
        accessibilityLink.frame = NSRect(
            x: (width - linkSize.width) / 2,
            y: rowTop - 28,
            width: linkSize.width,
            height: linkSize.height
        )
        parent.addSubview(accessibilityLink)

        let note = NSTextField(labelWithString: "Custom shortcuts coming soon")
        note.font = NSFont.snipsnap(.caption)
        note.textColor = DesignTokens.Color.textTertiary.ns
        note.alignment = .center
        note.frame = NSRect(x: sideMargin, y: 12, width: width - sideMargin * 2, height: 14)
        parent.addSubview(note)
    }

    private func refreshDestinationPathLabel() {
        destinationPathLabel?.stringValue = AppSettings.destinationFolderDisplayPath
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }

    @objc private func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose where Snipsnap saves recordings."
        panel.directoryURL = AppSettings.destinationFolderURL

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            AppSettings.destinationFolderURL = url
            DispatchQueue.main.async {
                self?.refreshDestinationPathLabel()
            }
        }
    }

    private func separator(y: CGFloat, width: CGFloat) -> NSView {
        let line = NSView(frame: NSRect(x: 0, y: y, width: width, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = DesignTokens.Color.border.cg
        return line
    }

    private func keyBadge(label: String, origin: NSPoint) -> NSView {
        let container = NSView(frame: NSRect(origin: origin, size: NSSize(width: 24, height: 22)))
        container.wantsLayer = true
        container.layer?.backgroundColor = DesignTokens.Color.surface.cg
        container.layer?.cornerRadius = DesignTokens.Radius.sm
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = DesignTokens.Color.border.cg

        let text = NSTextField(labelWithString: label)
        text.font = NSFont.monospacedSystemFont(ofSize: DesignTokens.Typography.label.size, weight: .regular)
        text.textColor = DesignTokens.Color.textPrimary.ns
        text.alignment = .center
        text.frame = NSRect(x: 0, y: 3, width: 24, height: 16)
        container.addSubview(text)

        return container
    }
}
