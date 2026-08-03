//
//  LibraryIntroWindow.swift
//  Grabbit
//
//  First-open welcome for Capture Library (“Show All…”). Also launchable
//  from Settings in DEBUG builds.
//

import AppKit
import SwiftUI

struct LibraryIntroView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: DesignTokens.Spacing.xl)

            VStack(spacing: DesignTokens.Spacing.lg) {
                RabbitIcon(width: 64)
                    .foregroundStyle(DesignTokens.Color.textPrimary.swiftUI)

                VStack(spacing: DesignTokens.Spacing.sm) {
                    Text("Welcome to your Capture Library")
                        .font(.grabbit(.panelTitle))
                        .foregroundStyle(DesignTokens.Color.textPrimary.swiftUI)
                        .multilineTextAlignment(.center)

                    Text("Every screenshot and recording lives here — browse, tag, and organize without leaving Grabbit.")
                        .font(.grabbit(.body))
                        .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.xxl)

            Spacer(minLength: DesignTokens.Spacing.xl)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                introPoint(
                    systemImage: "sidebar.left",
                    title: "Browse captures",
                    detail: "Pick anything from the sidebar to preview screenshots and recordings."
                )
                introPoint(
                    systemImage: "tag",
                    title: "Tag projects & flows",
                    detail: "Group related work so finding “that checkout bug” stays one click away."
                )
                introPoint(
                    systemImage: "sparkles",
                    title: "Auto-Tag when you’re ready",
                    detail: "Let Grabbit suggest a name and project — accept, edit, or skip."
                )
            }
            .padding(.horizontal, DesignTokens.Spacing.xxl)
            .frame(maxWidth: 440, alignment: .leading)

            Spacer(minLength: DesignTokens.Spacing.xl)

            Button("Get Started") {
                onContinue()
            }
            .buttonStyle(.grabbitProminent)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, DesignTokens.Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Color.background.swiftUI)
    }

    private func introPoint(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(title)
                    .font(.grabbit(.bodyEmphasized))
                    .foregroundStyle(DesignTokens.Color.textPrimary.swiftUI)
                Text(detail)
                    .font(.grabbit(.caption))
                    .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

final class LibraryIntroWindow: NSWindow {

    static var current: LibraryIntroWindow?

    /// Shows the intro. Marks it seen when the user continues (unless `markSeen` is false).
    static func show(markSeenOnContinue: Bool = true) {
        DispatchQueue.main.async {
            if current == nil {
                current = LibraryIntroWindow(markSeenOnContinue: markSeenOnContinue)
            } else {
                current?.markSeenOnContinue = markSeenOnContinue
            }
            current?.center()
            current?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var markSeenOnContinue: Bool

    private init(markSeenOnContinue: Bool) {
        self.markSeenOnContinue = markSeenOnContinue
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "Welcome"
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        backgroundColor = DesignTokens.Color.background.ns
        level = .floating

        let root = LibraryIntroView { [weak self] in
            self?.continueAndClose()
        }
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 520, height: 520)
        contentView = hosting
    }

    private func continueAndClose() {
        if markSeenOnContinue {
            AppSettings.hasSeenLibraryIntro = true
        }
        orderOut(nil)
    }

    override func close() {
        // Closing via traffic light still counts as having seen the intro
        // when this was the first-open presentation.
        if markSeenOnContinue {
            AppSettings.hasSeenLibraryIntro = true
        }
        super.close()
    }
}
