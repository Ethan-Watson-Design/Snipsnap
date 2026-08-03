//
//  KitchenSinkWindow.swift
//  Grabbit
//
//  DEBUG-only modal window hosting the design-system gallery.
//

import AppKit
import SwiftUI

#if DEBUG
final class KitchenSinkWindow: NSWindow {

    static var current: KitchenSinkWindow?

    static func show() {
        DispatchQueue.main.async {
            if current == nil {
                current = KitchenSinkWindow()
            }
            current?.center()
            current?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        title = "Kitchen Sink"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 640, height: 480)
        backgroundColor = DesignTokens.Color.background.ns
        level = .floating

        let hosting = NSHostingView(rootView: KitchenSinkView())
        hosting.frame = NSRect(x: 0, y: 0, width: 780, height: 640)
        contentView = hosting
    }
}
#endif
