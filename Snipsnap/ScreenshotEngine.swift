//
//  ScreenshotEngine.swift
//  Snipsnap
//
//  Created by Ethan Watson on 6/27/26.
//

import AppKit
import ScreenCaptureKit

class ScreenshotEngine {
    static func captureWindow(_ windowID: CGWindowID, completion: @escaping (NSImage?) -> Void) {
        Task {
            do {
                let availableContent = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )
                guard let window = availableContent.windows.first(where: { $0.windowID == windowID }) else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }

                let filter = SCContentFilter(desktopIndependentWindow: window)
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                let config = SCStreamConfiguration()
                config.width = Int(window.frame.width * scale)
                config.height = Int(window.frame.height * scale)
                config.scalesToFit = false

                let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let nsImage = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: window.frame.width, height: window.frame.height)
                )
                DispatchQueue.main.async { completion(nsImage) }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    static func captureRegion(_ rect: CGRect, completion: @escaping (NSImage?) -> Void) {
        Task {
            do {
                let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

                guard let display = availableContent.displays.first(where: { display in
                    let displayFrame = CGRect(x: display.frame.origin.x,
                                             y: display.frame.origin.y,
                                             width: CGFloat(display.width),
                                             height: CGFloat(display.height))
                    return displayFrame.intersects(rect)
                }) ?? availableContent.displays.first else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])

                let scale = NSScreen.main?.backingScaleFactor ?? 2
                let config = SCStreamConfiguration()
                config.width = Int(rect.width * scale)
                config.height = Int(rect.height * scale)
                let displayOriginX = display.frame.origin.x
                let displayOriginY = display.frame.origin.y
                let displayHeight = CGFloat(display.height)

                let localRect = CGRect(
                    x: rect.origin.x - displayOriginX,
                    y: displayHeight - (rect.origin.y - displayOriginY) - rect.height,
                    width: rect.width,
                    height: rect.height
                )

                config.sourceRect = localRect
                config.scalesToFit = false

                let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let nsImage = NSImage(cgImage: cgImage, size: rect.size)
                DispatchQueue.main.async { completion(nsImage) }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
}
