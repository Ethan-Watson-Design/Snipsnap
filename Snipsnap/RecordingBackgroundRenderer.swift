//
//  RecordingBackgroundRenderer.swift
//  Snipsnap
//

import CoreImage
import AppKit

enum RecordingBackgroundRenderer {
    static let canvasWidth: CGFloat = 1920
    static let canvasHeight: CGFloat = 1080
    static let marginFraction: CGFloat = 0.06

    static func canvasSize(for scale: CGFloat = 1) -> CGSize {
        CGSize(width: canvasWidth * scale, height: canvasHeight * scale)
    }

    static func windowFrame(
        inCanvas windowSize: CGSize,
        canvasSize: CGSize
    ) -> CGRect {
        let margin = canvasSize.width * marginFraction
        let contentWidth = canvasSize.width - margin * 2
        let maxH = canvasSize.height - margin * 2
        guard windowSize.width > 0, windowSize.height > 0, contentWidth > 0 else { return .zero }

        let windowAspect = windowSize.width / windowSize.height
        var drawW = contentWidth
        var drawH = drawW / windowAspect
        if drawH > maxH {
            drawH = maxH
            drawW = drawH * windowAspect
        }

        return CGRect(
            x: (canvasSize.width - drawW) / 2,
            y: (canvasSize.height - drawH) / 2,
            width: drawW,
            height: drawH
        )
    }

    private static var customImageCache: (path: String, image: CIImage)?

    static func backgroundImage(for style: RecordingBackgroundStyle, extent: CGRect) -> CIImage {
        switch style {
        case .none:
            return CIImage(color: .black).cropped(to: extent)
        case .warm:
            return linearGradient(
                colors: DesignTokens.Color.RecordingGradient.warm.ci,
                extent: extent
            )
        case .cool:
            return linearGradient(
                colors: DesignTokens.Color.RecordingGradient.cool.ci,
                extent: extent
            )
        case .midnight:
            return linearGradient(
                colors: DesignTokens.Color.RecordingGradient.midnight.ci,
                extent: extent
            )
        case .custom(let path):
            let rawImage: CIImage
            if let cached = customImageCache, cached.path == path {
                rawImage = cached.image
            } else if let loaded = CIImage(contentsOf: URL(fileURLWithPath: path)) {
                customImageCache = (path: path, image: loaded)
                rawImage = loaded
            } else {
                return CIImage(color: .black).cropped(to: extent)
            }
            let image = rawImage
            let scale = max(extent.width / image.extent.width, extent.height / image.extent.height)
            let scaledW = image.extent.width * scale
            let scaledH = image.extent.height * scale
            let tx = extent.midX - scaledW / 2 - image.extent.minX * scale
            let ty = extent.midY - scaledH / 2 - image.extent.minY * scale
            return image
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: tx / scale, y: ty / scale))
                .cropped(to: extent)
        }
    }

    static func composite(
        windowImage: CIImage,
        background: RecordingBackgroundStyle,
        canvasSize: CGSize,
        scale: CGFloat = 1
    ) -> CIImage {
        let extent = CGRect(origin: .zero, size: canvasSize)
        let backgroundImage = backgroundImage(for: background, extent: extent)
        let drawRect = windowFrame(
            inCanvas: windowImage.extent.size,
            canvasSize: canvasSize
        )
        guard drawRect.width > 0, drawRect.height > 0 else { return backgroundImage }

        let fitScale = min(
            drawRect.width / windowImage.extent.width,
            drawRect.height / windowImage.extent.height
        )
        let scaledW = windowImage.extent.width * fitScale
        let scaledH = windowImage.extent.height * fitScale
        let tx = drawRect.minX + (drawRect.width - scaledW) / 2
        let ty = drawRect.minY + (drawRect.height - scaledH) / 2
        let scaledWindow = windowImage
            .transformed(by: CGAffineTransform(scaleX: fitScale, y: fitScale))
            .transformed(by: CGAffineTransform(translationX: tx, y: ty))

        guard let compositeFilter = CIFilter(name: "CISourceOverCompositing") else { return backgroundImage }
        compositeFilter.setValue(scaledWindow, forKey: kCIInputImageKey)
        compositeFilter.setValue(backgroundImage, forKey: kCIInputBackgroundImageKey)
        return compositeFilter.outputImage?.cropped(to: extent) ?? backgroundImage
    }

    /// Shared GPU-backed context for background compositing and spotlight effects.
    static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static func backgroundPreviewImage(
        for style: RecordingBackgroundStyle,
        scale: CGFloat = 1
    ) -> NSImage? {
        guard style != .none else { return nil }
        let size = Self.canvasSize(for: scale)
        let extent = CGRect(origin: .zero, size: size)
        let image = backgroundImage(for: style, extent: extent)
        return nsImage(from: image, logicalSize: Self.canvasSize(for: 1))
    }

    /// Full-image effect used outside a spotlight cutout (blur or desaturate).
    static func spotlightSuppressionImage(
        from background: NSImage,
        technique: SpotlightTechnique
    ) -> NSImage? {
        guard technique != .dim else { return nil }
        guard let cgImage = background.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let input = CIImage(cgImage: cgImage)
        let extent = input.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        let output: CIImage?
        switch technique {
        case .dim:
            output = nil
        case .blur:
            guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
            filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
            filter.setValue(15.0, forKey: kCIInputRadiusKey)
            output = filter.outputImage?.cropped(to: extent)
        case .desaturate:
            guard let filter = CIFilter(name: "CIColorControls") else { return nil }
            filter.setValue(input, forKey: kCIInputImageKey)
            filter.setValue(0.0, forKey: kCIInputSaturationKey)
            output = filter.outputImage?.cropped(to: extent)
        }

        guard let output,
              let resultCG = ciContext.createCGImage(output, from: extent) else { return nil }
        return NSImage(cgImage: resultCG, size: background.size)
    }

    /// Places `content` centered on the preset canvas, like window capture compositing.
    static func compositeContent(
        _ content: NSImage,
        background style: RecordingBackgroundStyle,
        scale: CGFloat = 1
    ) -> NSImage? {
        guard style != .none else { return content }
        guard let tiff = content.tiffRepresentation,
              let ciImage = CIImage(data: tiff) else { return nil }
        let outputCanvasSize = Self.canvasSize(for: scale)
        let output = composite(
            windowImage: ciImage,
            background: style,
            canvasSize: outputCanvasSize,
            scale: scale
        )
        return nsImage(from: output, logicalSize: Self.canvasSize(for: 1))
    }

    private static func nsImage(from image: CIImage, logicalSize: CGSize) -> NSImage? {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0,
              let cgImage = ciContext.createCGImage(image, from: extent) else { return nil }
        return NSImage(cgImage: cgImage, size: logicalSize)
    }

    private static func linearGradient(colors: [CIColor], extent: CGRect) -> CIImage {
        guard let filter = CIFilter(name: "CILinearGradient") else {
            return CIImage(color: colors.first ?? .black).cropped(to: extent)
        }
        filter.setValue(CIVector(x: extent.minX, y: extent.minY), forKey: "inputPoint0")
        filter.setValue(CIVector(x: extent.maxX, y: extent.maxY), forKey: "inputPoint1")
        filter.setValue(colors[0], forKey: "inputColor0")
        filter.setValue(colors[1], forKey: "inputColor1")
        return filter.outputImage?.cropped(to: extent)
            ?? CIImage(color: colors[0]).cropped(to: extent)
    }
}
