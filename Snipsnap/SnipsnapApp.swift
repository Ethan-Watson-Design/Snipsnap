//
//  SnipsnapApp.swift
//  Snipsnap
//
//  Created by Ethan Watson on 6/27/26.
//

import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var globalMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.aperture", accessibilityDescription: "Snipsnap")
        }

        let menu = NSMenu()

        let screenshotItem = NSMenuItem(title: "Take Screenshot", action: #selector(takeScreenshot), keyEquivalent: "")
        screenshotItem.target = self
        menu.addItem(screenshotItem)

        menu.addItem(NSMenuItem(title: "Start Recording", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Snipsnap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.requestAccessibilityPermissionIfNeeded()
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

    @objc func takeScreenshot() {
        DispatchQueue.main.async {
            RegionSelector.show { rect in
                guard let rect else { return }
                ScreenshotEngine.captureRegion(rect) { image in
                    guard let image else { return }
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([image])
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
