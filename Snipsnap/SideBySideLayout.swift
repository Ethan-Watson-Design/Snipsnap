//
//  SideBySideLayout.swift
//  Snipsnap
//

import AppKit

enum SideBySideImageOrder: Equatable {
    case currentLeft
    case previousLeft

    mutating func swap() {
        self = self == .currentLeft ? .previousLeft : .currentLeft
    }
}

struct SideBySideSettings {
    var isEnabled = false
    var previousImage: NSImage?
    var previousCaptureID: UUID?
    var order: SideBySideImageOrder = .currentLeft
}

struct SideBySideComposition {
    let stageSize: NSSize
    let leftFrame: NSRect
    let rightFrame: NSRect
    let leftImage: NSImage
    let rightImage: NSImage

    var canvasFrame: NSRect {
        NSRect(origin: .zero, size: stageSize)
    }
}

enum SideBySideLayout {
    static let gapFraction: CGFloat = 0.03
    static let annotationMarginFraction: CGFloat = 0.08

    static func compose(
        current: NSImage,
        previous: NSImage,
        order: SideBySideImageOrder,
        background: RecordingBackgroundStyle
    ) -> SideBySideComposition {
        let left = order == .currentLeft ? current : previous
        let right = order == .currentLeft ? previous : current
        if background == .none {
            return composePlain(left: left, right: right)
        }
        return composeWithBackground(left: left, right: right)
    }

    static func renderStage(
        _ composition: SideBySideComposition,
        background: RecordingBackgroundStyle
    ) -> NSImage {
        let size = composition.stageSize
        guard size.width > 0, size.height > 0 else { return NSImage() }

        let width = max(1, Int(size.width))
        let height = max(1, Int(size.height))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphicsContext = NSGraphicsContext(bitmapImageRep: rep) else {
            return NSImage()
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        if background != .none {
            if let bg = backgroundImage(for: background, size: size) {
                bg.draw(
                    in: NSRect(origin: .zero, size: size),
                    from: NSRect(origin: .zero, size: bg.size),
                    operation: .sourceOver,
                    fraction: 1
                )
            }
        }

        composition.leftImage.draw(
            in: composition.leftFrame,
            from: NSRect(origin: .zero, size: composition.leftImage.size),
            operation: .sourceOver,
            fraction: 1
        )
        composition.rightImage.draw(
            in: composition.rightFrame,
            from: NSRect(origin: .zero, size: composition.rightImage.size),
            operation: .sourceOver,
            fraction: 1
        )

        let result = NSImage(size: size)
        result.addRepresentation(rep)
        return result
    }

    // MARK: - Private layout

    private static func composePlain(left: NSImage, right: NSImage) -> SideBySideComposition {
        let leftSize = left.size
        let rightSize = right.size
        guard leftSize.width > 0, leftSize.height > 0,
              rightSize.width > 0, rightSize.height > 0 else {
            let fallback = AnnotationViewBackground.fittedStageSize(leftSize)
            return SideBySideComposition(
                stageSize: fallback,
                leftFrame: NSRect(origin: .zero, size: fallback),
                rightFrame: .zero,
                leftImage: left,
                rightImage: right
            )
        }

        let targetHeight = max(leftSize.height, rightSize.height)
        let leftWidth = leftSize.width * (targetHeight / leftSize.height)
        let rightWidth = rightSize.width * (targetHeight / rightSize.height)
        let gap = targetHeight * gapFraction
        let margin = targetHeight * annotationMarginFraction

        let contentWidth = leftWidth + gap + rightWidth
        let contentHeight = targetHeight
        let naturalStage = NSSize(
            width: contentWidth + margin * 2,
            height: contentHeight + margin * 2
        )
        let stage = AnnotationViewBackground.fittedStageSize(naturalStage)
        let scale = stage.width / naturalStage.width

        let leftFrame = NSRect(
            x: (margin * scale).rounded(),
            y: (margin * scale).rounded(),
            width: (leftWidth * scale).rounded(),
            height: (contentHeight * scale).rounded()
        )
        let rightFrame = NSRect(
            x: ((margin + leftWidth + gap) * scale).rounded(),
            y: (margin * scale).rounded(),
            width: (rightWidth * scale).rounded(),
            height: (contentHeight * scale).rounded()
        )

        return SideBySideComposition(
            stageSize: stage,
            leftFrame: leftFrame,
            rightFrame: rightFrame,
            leftImage: left,
            rightImage: right
        )
    }

    private static func composeWithBackground(left: NSImage, right: NSImage) -> SideBySideComposition {
        let slotWidth = RecordingBackgroundRenderer.canvasWidth
        let slotHeight = RecordingBackgroundRenderer.canvasHeight
        let gap = slotWidth * gapFraction
        let margin = slotHeight * annotationMarginFraction
        let naturalStage = NSSize(
            width: slotWidth * 2 + gap + margin * 2,
            height: slotHeight + margin * 2
        )
        let stage = AnnotationViewBackground.fittedStageSize(naturalStage)
        let scale = stage.width / naturalStage.width

        let leftSlot = CGRect(
            x: margin,
            y: margin,
            width: slotWidth,
            height: slotHeight
        )
        let rightSlot = CGRect(
            x: margin + slotWidth + gap,
            y: margin,
            width: slotWidth,
            height: slotHeight
        )

        let leftContent = RecordingBackgroundRenderer.windowFrame(
            inCanvas: left.size,
            canvasSize: leftSlot.size
        )
        let rightContent = RecordingBackgroundRenderer.windowFrame(
            inCanvas: right.size,
            canvasSize: rightSlot.size
        )

        let leftFrame = NSRect(
            x: ((leftSlot.minX + leftContent.minX) * scale).rounded(),
            y: ((leftSlot.minY + leftContent.minY) * scale).rounded(),
            width: (leftContent.width * scale).rounded(),
            height: (leftContent.height * scale).rounded()
        )
        let rightFrame = NSRect(
            x: ((rightSlot.minX + rightContent.minX) * scale).rounded(),
            y: ((rightSlot.minY + rightContent.minY) * scale).rounded(),
            width: (rightContent.width * scale).rounded(),
            height: (rightContent.height * scale).rounded()
        )

        return SideBySideComposition(
            stageSize: stage,
            leftFrame: leftFrame,
            rightFrame: rightFrame,
            leftImage: left,
            rightImage: right
        )
    }

    private static func backgroundImage(
        for style: RecordingBackgroundStyle,
        size: NSSize
    ) -> NSImage? {
        guard style != .none else { return nil }
        let extent = CGRect(origin: .zero, size: size)
        let ciImage = RecordingBackgroundRenderer.backgroundImage(for: style, extent: extent)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(size.width)),
            pixelsHigh: max(1, Int(size.height)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        defer {
            NSGraphicsContext.restoreGraphicsState()
        }

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: extent) else { return nil }
        NSImage(cgImage: cgImage, size: size).draw(
            in: extent,
            from: extent,
            operation: .copy,
            fraction: 1
        )
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}
