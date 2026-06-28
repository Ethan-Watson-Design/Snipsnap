//
//  SnipsnapApp.swift
//  Snipsnap
//
//  Created by Ethan Watson on 6/27/26.
//

import SwiftUI
import AppKit
import AVFoundation

final class CaptureHistory {
    static let shared = CaptureHistory()
    private init() {}

    var recents: [NSImage] = []

    func add(_ image: NSImage) {
        recents.insert(image, at: 0)
        if recents.count > 3 { recents = Array(recents.prefix(3)) }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var globalMonitor: Any?
    private var isRecording = false
    private var isStartingRecording = false
    private var recordingMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.aperture", accessibilityDescription: "Snipsnap")
        }

        rebuildMenu()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.requestAccessibilityPermissionIfNeeded()
        }

        // Front-load screen capture permission + SCK warm-up so neither appears mid-recording.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            RecordingEngine.shared.prewarm()
        }

        RecordingEngine.shared.onRecordingStopped = { [weak self] url in
            guard let self else { return }
            self.isRecording = false
            self.isStartingRecording = false
            self.statusItem.button?.image = NSImage(systemSymbolName: "camera.aperture",
                                                    accessibilityDescription: "Snipsnap")
            self.recordingMenuItem?.title = "Start Recording"
            self.recordingMenuItem?.isEnabled = true

            guard let url else { return }
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.generateCGImagesAsynchronously(
                forTimes: [NSValue(time: .zero)]
            ) { _, cgImage, _, _, _ in
                DispatchQueue.main.async {
                    guard let cgImage else { return }
                    let thumbnail = NSImage(cgImage: cgImage, size: .zero)
                    ToastWindow.show(image: thumbnail) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
        }

        let trusted = AXIsProcessTrusted()
        print("[Snipsnap] Accessibility trusted: \(trusted)")

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            print("[Snipsnap] keyDown keyCode=\(event.keyCode) modifiers=\(modifiers)")
            if event.keyCode == 19 && modifiers == [.command, .shift] {
                print("[Snipsnap] ⌘⇧2 triggered")
                self?.takeScreenshot()
            }
            if event.keyCode == 21 && modifiers == [.command, .shift] {
                print("[Snipsnap] ⌘⇧4 triggered")
                self?.toggleRecording()
            }
        }
        print("[Snipsnap] Global monitor registered: \(globalMonitor != nil)")
    }

    private func requestAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else { return }

        let appPath = Bundle.main.bundlePath
        print("[Snipsnap] Grant accessibility at: \(appPath)")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appPath, forType: .string)

        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = """
            Snipsnap needs Accessibility access for global shortcuts (⌘⇧2).

            The app path has been copied to your clipboard.

            In System Settings → Privacy & Security → Accessibility:
            1. Click the + button
            2. Press ⌘⇧G in the file picker
            3. Paste the path and press Return
            4. Select Snipsnap.app and click Open
            5. Toggle Snipsnap on
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }

        pollForAccessibilityGrant()
    }

    private func pollForAccessibilityGrant() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            if AXIsProcessTrusted() {
                print("[Snipsnap] Accessibility granted — re-registering monitor")
                if let old = self.globalMonitor {
                    NSEvent.removeMonitor(old)
                }
                self.globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    print("[Snipsnap] keyDown keyCode=\(event.keyCode) modifiers=\(modifiers)")
                    if event.keyCode == 19 && modifiers == [.command, .shift] {
                        print("[Snipsnap] ⌘⇧2 triggered")
                        self?.takeScreenshot()
                    }
                    if event.keyCode == 21 && modifiers == [.command, .shift] {
                        print("[Snipsnap] ⌘⇧4 triggered")
                        self?.toggleRecording()
                    }
                }
                print("[Snipsnap] Monitor re-registered: \(self.globalMonitor != nil)")
            } else {
                self.pollForAccessibilityGrant()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }

    func rebuildMenu() {
        let menu = NSMenu()

        let recents = CaptureHistory.shared.recents
        if recents.isEmpty {
            let emptyItem = NSMenuItem(title: "No recent captures", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for (index, image) in recents.enumerated() {
                let item = NSMenuItem(
                    title: "Capture \(index + 1)",
                    action: #selector(openHistoryItem(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                item.image = thumbnail(for: image, size: NSSize(width: 40, height: 40))
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let screenshotItem = NSMenuItem(title: "Take Screenshot", action: #selector(takeScreenshot), keyEquivalent: "")
        screenshotItem.target = self
        menu.addItem(screenshotItem)

        let recItem: NSMenuItem
        if isRecording {
            recItem = NSMenuItem(title: "Recording…", action: nil, keyEquivalent: "")
            recItem.isEnabled = false
        } else {
            recItem = NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: "")
            recItem.target = self
        }
        recordingMenuItem = recItem
        menu.addItem(recItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Snipsnap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func thumbnail(for image: NSImage, size: NSSize) -> NSImage {
        let srcSize = image.size
        guard srcSize.width > 0, srcSize.height > 0 else { return image }

        let widthRatio = size.width / srcSize.width
        let heightRatio = size.height / srcSize.height
        let scale = min(widthRatio, heightRatio)
        let drawSize = NSSize(width: srcSize.width * scale, height: srcSize.height * scale)

        let thumb = NSImage(size: size)
        thumb.lockFocus()
        let origin = NSPoint(
            x: (size.width - drawSize.width) / 2,
            y: (size.height - drawSize.height) / 2
        )
        image.draw(in: NSRect(origin: origin, size: drawSize),
                   from: NSRect(origin: .zero, size: srcSize),
                   operation: .copy,
                   fraction: 1.0)
        thumb.unlockFocus()
        return thumb
    }

    @objc private func openHistoryItem(_ sender: NSMenuItem) {
        let image = CaptureHistory.shared.recents[sender.tag]
        AnnotationWindow.show(image: image)
    }

    @objc func toggleRecording() {
        guard !isRecording, !isStartingRecording else { return }
        isStartingRecording = true
        RecordingEngine.shared.startRecording { [weak self] error in
            guard let self else { return }
            self.isStartingRecording = false
            if let error {
                let alert = NSAlert()
                alert.messageText = "Recording Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.runModal()
                return
            }
            self.isRecording = true
            self.statusItem.button?.image = NSImage(systemSymbolName: "record.circle.fill",
                                                    accessibilityDescription: "Recording")
            self.recordingMenuItem?.title = "Recording…"
            self.recordingMenuItem?.isEnabled = false
        }
    }

    @objc func takeScreenshot() {
        DispatchQueue.main.async {
            RegionSelector.show { rect in
                guard let rect else { return }
                ScreenshotEngine.captureRegion(rect) { image in
                    guard let image else { return }
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([image])
                    CaptureHistory.shared.add(image)
                    self.rebuildMenu()
                    ToastWindow.show(image: image) {
                        AnnotationWindow.show(image: image)
                    }
                }
            }
        }
    }
}

@main
struct SnipsnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
