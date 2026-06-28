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
