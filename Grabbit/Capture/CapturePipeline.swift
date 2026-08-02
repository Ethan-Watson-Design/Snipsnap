//
//  CapturePipeline.swift
//  Grabbit
//

import AppKit
import Foundation

enum CapturePipeline {
    /// Shared post-screenshot path: clipboard → history → organize context → toast → annotate.
    static func finishScreenshot(
        _ image: NSImage,
        captureRect: CGRect?,
        earlySignals: EarlyCaptureSignals?
    ) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])

        let entry = CaptureHistory.shared.add(.screenshot(image))
        (NSApp.delegate as? AppDelegate)?.rebuildMenu()

        let early = earlySignals ?? CaptureClassifier.gatherEarlyCaptureSignals()
        let windowInfo = CaptureClassifier.completeWindowSignature(from: early, captureRect: captureRect)
        if let captureID = entry?.id {
            CaptureOrganizer.registerCaptureContext(captureID: captureID, windowInfo: windowInfo)
        }

        ToastWindow.show(image: image, associatedCaptureID: entry?.id) {
            AnnotationWindow.show(
                image: image,
                fileName: entry?.displayName,
                captureID: entry?.id,
                windowInfo: windowInfo
            )
        }
    }
}
