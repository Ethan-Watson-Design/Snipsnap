//
//  SettingsWindow.swift
//  Snipsnap
//

import AppKit
import Foundation
import SwiftUI

enum AppSettings {
    private static let destinationFolderKey = "destinationFolderPath"

    static let spotlightDimOpacityNotches: [CGFloat] = [0, 0.05, 0.15, 0.30, 0.60]
    static let spotlightBlurRadiusNotches: [CGFloat] = [0, 1, 2, 5, 10]
    static let spotlightDimOpacityDefault: CGFloat = 0.30
    static let spotlightBlurRadiusDefault: CGFloat = 5

    static func snapSpotlightDimOpacity(_ value: CGFloat) -> CGFloat {
        spotlightDimOpacityNotches.min(by: { abs($0 - value) < abs($1 - value) }) ?? spotlightDimOpacityDefault
    }

    static func snapSpotlightBlurRadius(_ value: CGFloat) -> CGFloat {
        spotlightBlurRadiusNotches.min(by: { abs($0 - value) < abs($1 - value) }) ?? spotlightBlurRadiusDefault
    }

    static func spotlightDimOpacityIndex(for value: CGFloat) -> Int {
        let snapped = snapSpotlightDimOpacity(value)
        return spotlightDimOpacityNotches.firstIndex(of: snapped) ?? 3
    }

    static func spotlightBlurRadiusIndex(for value: CGFloat) -> Int {
        let snapped = snapSpotlightBlurRadius(value)
        return spotlightBlurRadiusNotches.firstIndex(of: snapped) ?? 3
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

// MARK: - Settings panes

private enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general
    case kitchenSink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .kitchenSink: return "Kitchen Sink"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .kitchenSink: return "square.grid.2x2"
        }
    }
}

private struct SettingsRootView: View {
    @State private var selection: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                ForEach(SettingsPane.allCases) { pane in
                    Button {
                        selection = pane
                    } label: {
                        Label(pane.title, systemImage: pane.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.vertical, DesignTokens.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                                    .fill(DesignTokens.Color.listSelectionFill.swiftUI.opacity(selection == pane ? 1 : 0))
                            )
                            .foregroundStyle(DesignTokens.Color.textPrimary.swiftUI)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(DesignTokens.Spacing.md)
            .background(DesignTokens.Color.background.swiftUI)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            Group {
                switch selection ?? .general {
                case .general:
                    GeneralSettingsView()
                case .kitchenSink:
                    KitchenSinkView()
                }
            }
            .background(DesignTokens.Color.background.swiftUI)
        }
        .background(DesignTokens.Color.background.swiftUI)
        .frame(minWidth: 720, minHeight: 480)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @State private var destinationPath = AppSettings.destinationFolderDisplayPath

    private let shortcuts: [(String, [String])] = [
        ("Snap Area", ["⌘", "⇧", "3"]),
        ("Record Screen", ["⌘", "⇧", "4"]),
        ("Clip Voice", ["⌘", "⇧", "5"]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                saveLocationSection
                shortcutsSection
            }
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DesignTokens.Color.background.swiftUI)
    }

    private var saveLocationSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            sectionHeader("Save Location")
            Divider()
            HStack(spacing: DesignTokens.Spacing.md) {
                Text("Save to")
                    .font(.snipsnap(.body))
                    .foregroundStyle(DesignTokens.Color.textPrimary.swiftUI)
                Text(destinationPath)
                    .font(.snipsnap(.body))
                    .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Button("Change…") {
                    chooseDestinationFolder()
                }
            }
            .padding(.vertical, DesignTokens.Spacing.sm)
        }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            sectionHeader("Shortcuts")
            Divider()

            ForEach(shortcuts, id: \.0) { label, keys in
                HStack {
                    Text(label)
                        .font(.snipsnap(.body))
                        .foregroundStyle(DesignTokens.Color.textPrimary.swiftUI)
                    Spacer()
                    HStack(spacing: 3) {
                        ForEach(keys, id: \.self) { key in
                            Text(key)
                                .font(DesignTokens.Typography.monoSwiftUI(size: DesignTokens.Typography.label.size))
                                .foregroundStyle(DesignTokens.Color.textPrimary.swiftUI)
                                .frame(width: 24, height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                        .fill(DesignTokens.Color.surface.swiftUI)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                        .stroke(DesignTokens.Color.border.swiftUI, lineWidth: 0.5)
                                )
                        }
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.sm)
                Divider()
            }

            Button("Open Accessibility Settings for Snipsnap…") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            }
            .buttonStyle(.plain)
            .font(.snipsnap(.caption))
            .foregroundStyle(Color(nsColor: .linkColor))
            .frame(maxWidth: .infinity)

            Text("Custom shortcuts coming soon")
                .font(.snipsnap(.caption))
                .foregroundStyle(DesignTokens.Color.textTertiary.swiftUI)
                .frame(maxWidth: .infinity)
                .padding(.top, DesignTokens.Spacing.xs)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.snipsnap(.caption))
            .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
    }

    private func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose where Snipsnap saves recordings."
        panel.directoryURL = AppSettings.destinationFolderURL

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            AppSettings.destinationFolderURL = url
            DispatchQueue.main.async {
                destinationPath = AppSettings.destinationFolderDisplayPath
            }
        }
    }
}

// MARK: - Window

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
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        title = "Snipsnap Settings"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 640, height: 420)

        let hosting = NSHostingView(rootView: SettingsRootView())
        hosting.frame = NSRect(x: 0, y: 0, width: 780, height: 560)
        contentView = hosting
    }
}
