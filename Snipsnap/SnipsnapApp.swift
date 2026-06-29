//
//  SnipsnapApp.swift
//  Snipsnap
//
//  Created by Ethan Watson on 6/27/26.
//

import SwiftUI
import AppKit
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var globalMonitor: Any?
    private var recordingEscapeGlobalMonitor: Any?
    private var recordingEscapeLocalMonitor: Any?
    private var recordingElapsedSeconds = 0
    private var recordingTimerSource: DispatchSourceTimer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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

        RecordingEngine.shared.onRecordingStarted = { [weak self] in
            guard let self else { return }
            self.startRecordingStatus()
            self.startRecordingEscapeMonitor()
            self.rebuildMenu()
        }

        RecordingEngine.shared.onRecordingStopped = { [weak self] url in
            guard let self else { return }
            self.stopRecordingEscapeMonitor()
            self.stopRecordingStatus()
            RecordingEngine.shared.onCompositedPreviewFrame = nil
            CameraPreviewWindow.hide()
            RecordingBackgroundPreviewWindow.hide()
            CaptureBar.resetActiveCamera()
            self.rebuildMenu()

            guard let url else { return }
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.generateCGImagesAsynchronously(
                forTimes: [NSValue(time: .zero)]
            ) { _, cgImage, _, _, _ in
                DispatchQueue.main.async {
                    guard let cgImage else { return }
                    let thumb = NSImage(cgImage: cgImage, size: .zero)
                    CaptureHistory.shared.add(.recording(url: url, thumbnail: thumb))
                    self.rebuildMenu()
                    ToastWindow.show(image: thumb) {
                        VideoAnnotationWindow.show(url: url, thumbnail: thumb)
                    }
                }
            }
        }

        RecordingEngine.shared.onRecordingFailed = { [weak self] error in
            guard let self else { return }
            self.stopRecordingEscapeMonitor()
            self.stopRecordingStatus()
            RecordingEngine.shared.onCompositedPreviewFrame = nil
            CameraPreviewWindow.hide()
            RecordingBackgroundPreviewWindow.hide()
            CaptureBar.resetActiveCamera()
            self.rebuildMenu()
            let alert = NSAlert()
            alert.messageText = "Recording Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.runModal()
        }

        let trusted = AXIsProcessTrusted()
        print("[Snipsnap] Accessibility trusted: \(trusted)")

        registerGlobalHotkeys()
        print("[Snipsnap] Global monitor registered: \(globalMonitor != nil)")
    }

    private func registerGlobalHotkeys() {
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
            if event.keyCode == 22 && modifiers == [.command] {
                print("[Snipsnap] ⌘6 triggered")
                CaptureBar.show()
            }
        }
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
                self.registerGlobalHotkeys()
                print("[Snipsnap] Monitor re-registered: \(self.globalMonitor != nil)")
            } else {
                self.pollForAccessibilityGrant()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopRecordingEscapeMonitor()
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AppDockPresentation.isLibraryPresented {
            CaptureLibraryWindow.current?.makeKeyAndOrderFront(nil)
        } else {
            CaptureLibraryWindow.show()
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let showAllItem = NSMenuItem(title: "Show All…", action: #selector(showCaptureLibrary), keyEquivalent: "")
        showAllItem.target = self
        menu.addItem(showAllItem)
        return menu
    }

    private func startRecordingEscapeMonitor() {
        stopRecordingEscapeMonitor()
        recordingEscapeGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            self?.stopRecording()
        }
        recordingEscapeLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard RecordingEngine.shared.isRecording, event.keyCode == 53 else { return event }
            self?.stopRecording()
            return nil
        }
    }

    private func stopRecordingEscapeMonitor() {
        if let monitor = recordingEscapeGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            recordingEscapeGlobalMonitor = nil
        }
        if let monitor = recordingEscapeLocalMonitor {
            NSEvent.removeMonitor(monitor)
            recordingEscapeLocalMonitor = nil
        }
    }

    func rebuildMenu() {
        let menu = NSMenu()

        let captureBarItem = NSMenuItem(title: "Open Capture Bar", action: #selector(showCaptureBar), keyEquivalent: "6")
        captureBarItem.keyEquivalentModifierMask = [.command]
        captureBarItem.target = self
        menu.addItem(captureBarItem)

        menu.addItem(.separator())

        let screenshotItem = NSMenuItem(title: "Take Screenshot", action: #selector(takeScreenshot), keyEquivalent: "")
        screenshotItem.target = self
        menu.addItem(screenshotItem)

        let recItem: NSMenuItem
        if RecordingEngine.shared.isRecording {
            recItem = NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "")
            recItem.target = self
            let stopCfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
            recItem.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(stopCfg)
        } else if RecordingEngine.shared.isStartingRecording {
            recItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        } else {
            recItem = NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: "")
            recItem.target = self
        }
        menu.addItem(recItem)

        menu.addItem(.separator())

        let menuEntries = CaptureHistory.shared.menuEntries
        if menuEntries.isEmpty {
            let emptyItem = NSMenuItem(title: "No recent captures", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for (index, entry) in menuEntries.enumerated() {
                let label = entry.displayName
                let item = NSMenuItem(
                    title: label,
                    action: #selector(openHistoryItem(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                item.image = entry.thumbnail.thumbnail(size: NSSize(width: 40, height: 40))
                menu.addItem(item)
            }
        }

        let showAllItem = NSMenuItem(title: "Show All…", action: #selector(showCaptureLibrary), keyEquivalent: "")
        showAllItem.target = self
        menu.addItem(showAllItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem(title: "Quit Snipsnap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func formattedRecordingTime(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func startRecordingStatus() {
        recordingElapsedSeconds = 0
        statusItem.length = NSStatusItem.variableLength
        updateRecordingStatusDisplay()

        let src = DispatchSource.makeTimerSource(queue: .main)
        src.schedule(deadline: .now() + 1, repeating: 1)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            self.recordingElapsedSeconds += 1
            self.updateRecordingStatusDisplay()
        }
        src.resume()
        recordingTimerSource = src
    }

    private func stopRecordingStatus() {
        recordingTimerSource?.cancel()
        recordingTimerSource = nil
        recordingElapsedSeconds = 0
        statusItem.length = NSStatusItem.squareLength
        if let button = statusItem.button {
            button.title = ""
            button.image = NSImage(systemSymbolName: "camera.aperture", accessibilityDescription: "Snipsnap")
        }
    }

    private func updateRecordingStatusDisplay() {
        guard let button = statusItem.button else { return }
        let time = formattedRecordingTime(recordingElapsedSeconds)
        button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
        button.imagePosition = .imageLeading
        button.title = " \(time)"
        button.toolTip = "Recording — \(time). Click to stop."
    }

    @objc private func openHistoryItem(_ sender: NSMenuItem) {
        let menuEntries = CaptureHistory.shared.menuEntries
        guard menuEntries.indices.contains(sender.tag) else { return }
        CaptureLibraryWindow.open(menuEntries[sender.tag])
    }

    @objc private func showCaptureLibrary() {
        CaptureLibraryWindow.show()
    }

    @objc func showCaptureBar() {
        CaptureBar.show()
    }

    @objc func toggleRecording() {
        RecordingEngine.shared.startRecording()
        rebuildMenu()  // immediately reflect "Starting…" state
    }

    @objc func stopRecording() {
        RecordingEngine.shared.stopRecording()
    }

    @objc func openSettings() {
        SettingsWindow.show()
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
                    CaptureHistory.shared.add(.screenshot(image))
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

extension NSImage {
    func thumbnail(size: NSSize) -> NSImage {
        let srcSize = self.size
        guard srcSize.width > 0, srcSize.height > 0 else { return self }

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
        draw(in: NSRect(origin: origin, size: drawSize),
             from: NSRect(origin: .zero, size: srcSize),
             operation: .copy,
             fraction: 1.0)
        thumb.unlockFocus()
        return thumb
    }
}
