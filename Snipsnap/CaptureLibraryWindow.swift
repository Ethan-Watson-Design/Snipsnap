//
//  CaptureLibraryWindow.swift
//  Snipsnap
//

import SwiftUI
@preconcurrency import AppKit
import AVKit

enum AppDockPresentation {
    static var isLibraryPresented: Bool {
        guard let window = CaptureLibraryWindow.current else { return false }
        return window.isVisible || window.isMiniaturized
    }

    static func presentLibraryWindow() {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
    }

    static func hideFromDockIfNeeded() {
        guard isLibraryPresented == false else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}

final class CaptureLibraryWindow: NSWindow, NSWindowDelegate {
    static var current: CaptureLibraryWindow?

    private nonisolated(unsafe) var historyObserver: NSObjectProtocol?

    static func show() {
        DispatchQueue.main.async {
            if current == nil {
                current = CaptureLibraryWindow()
            }
            AppDockPresentation.presentLibraryWindow()
            current?.reloadContent()
            current?.center()
            current?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "Snipsnap"
        minSize = NSSize(width: 640, height: 420)
        isReleasedWhenClosed = false
        delegate = self

        historyObserver = NotificationCenter.default.addObserver(
            forName: .captureHistoryDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reloadContent()
            }
        }

        reloadContent()
    }

    deinit {
        if let historyObserver {
            NotificationCenter.default.removeObserver(historyObserver)
        }
    }

    func reloadContent() {
        let view = CaptureLibraryView(
            entries: CaptureHistory.shared.entries,
            onOpen: { entry in
                CaptureLibraryWindow.open(entry)
            }
        )
        contentView = NSHostingView(rootView: view)
    }

    static func open(_ entry: CaptureEntry) {
        switch entry.item {
        case .screenshot(let image):
            AnnotationWindow.show(image: image)
        case .recording(let url, let thumbnail):
            VideoAnnotationWindow.show(url: url, thumbnail: thumbnail)
        }
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            AppDockPresentation.hideFromDockIfNeeded()
        }
    }
}

// MARK: - SwiftUI

private struct CaptureLibraryView: View {
    let entries: [CaptureEntry]
    let onOpen: (CaptureEntry) -> Void

    @State private var selection: UUID?

    var body: some View {
        NavigationSplitView {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No Captures Yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Screenshots and recordings will appear here.")
                    )
                } else {
                    List(entries, selection: $selection) { entry in
                        CaptureSidebarRow(entry: entry)
                            .tag(entry.id)
                            .contextMenu {
                                Button("Show in Finder") {
                                    showInFinder(entry)
                                }
                                Button("Move to Trash", role: .destructive) {
                                    moveToTrash(entry)
                                }
                            }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            if let entry = entries.first(where: { $0.id == selection }) {
                CapturePreviewPane(entry: entry, onOpen: onOpen)
            } else {
                ContentUnavailableView(
                    "Select a Capture",
                    systemImage: "sidebar.left",
                    description: Text("Choose a screenshot or recording from the sidebar.")
                )
            }
        }
        .onAppear {
            if selection == nil {
                selection = entries.first?.id
            }
        }
        .onChange(of: entries.count) { _, _ in
            if let selection, entries.contains(where: { $0.id == selection }) {
                return
            }
            selection = entries.first?.id
        }
    }

    private func showInFinder(_ entry: CaptureEntry) {
        guard let url = CaptureHistory.shared.fileURL(for: entry.id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func moveToTrash(_ entry: CaptureEntry) {
        CaptureHistory.shared.remove(id: entry.id)
    }
}

private struct CaptureSidebarRow: View {
    let entry: CaptureEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: entry.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.system(size: 13, weight: .medium))
                Text(entry.createdAt.compactRelativeLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct CapturePreviewPane: View {
    let entry: CaptureEntry
    let onOpen: (CaptureEntry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            previewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.headline)
                    Text(entry.createdAt.compactRelativeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Open") {
                    onOpen(entry)
                }
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch entry.item {
        case .screenshot(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(24)

        case .recording(let url, _):
            VideoPreviewRepresentable(url: url)
                .padding(24)
        }
    }
}

private struct VideoPreviewRepresentable: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        context.coordinator.bind(url: url, to: view)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        context.coordinator.bind(url: url, to: nsView)
    }

    final class Coordinator {
        private var currentURL: URL?

        func bind(url: URL, to view: AVPlayerView) {
            guard currentURL != url else { return }
            currentURL = url
            view.player = AVPlayer(url: url)
        }
    }
}
