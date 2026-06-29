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

    /// Width reserved on the right for a vertical camera strip (strip + inset).
    static func verticalStripReservedWidth(in canvasSize: CGSize, scale: CGFloat = 1) -> CGFloat {
        let strip = VerticalCameraStripLayout.metrics(
            screenWidth: canvasSize.width,
            screenHeight: canvasSize.height,
            scale: scale
        )
        return strip.width + strip.margin
    }

    static func windowFrame(
        inCanvas windowSize: CGSize,
        canvasSize: CGSize,
        cameraStyle: CameraPreviewStyle? = nil,
        scale: CGFloat = 1
    ) -> CGRect {
        let margin = canvasSize.width * marginFraction
        var contentWidth = canvasSize.width - margin * 2
        let maxH = canvasSize.height - margin * 2
        guard windowSize.width > 0, windowSize.height > 0, contentWidth > 0 else { return .zero }

        if cameraStyle == .vertical {
            contentWidth -= verticalStripReservedWidth(in: canvasSize, scale: scale)
        }
        guard contentWidth > 0 else { return .zero }

        let windowAspect = windowSize.width / windowSize.height
        var drawW = contentWidth
        var drawH = drawW / windowAspect
        if drawH > maxH {
            drawH = maxH
            drawW = drawH * windowAspect
        }

        let x: CGFloat
        if cameraStyle == .vertical {
            x = margin + (contentWidth - drawW) / 2
        } else {
            x = (canvasSize.width - drawW) / 2
        }
        return CGRect(
            x: x,
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
                colors: [
                    CIColor(red: 0.98, green: 0.72, blue: 0.45),
                    CIColor(red: 0.92, green: 0.38, blue: 0.55)
                ],
                extent: extent
            )
        case .cool:
            return linearGradient(
                colors: [
                    CIColor(red: 0.35, green: 0.75, blue: 0.98),
                    CIColor(red: 0.18, green: 0.42, blue: 0.92)
                ],
                extent: extent
            )
        case .midnight:
            return linearGradient(
                colors: [
                    CIColor(red: 0.12, green: 0.14, blue: 0.22),
                    CIColor(red: 0.04, green: 0.05, blue: 0.10)
                ],
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
        cameraStyle: CameraPreviewStyle? = nil,
        scale: CGFloat = 1
    ) -> CIImage {
        let extent = CGRect(origin: .zero, size: canvasSize)
        let backgroundImage = backgroundImage(for: background, extent: extent)
        let drawRect = windowFrame(
            inCanvas: windowImage.extent.size,
            canvasSize: canvasSize,
            cameraStyle: cameraStyle,
            scale: scale
        )
        guard drawRect.width > 0, drawRect.height > 0 else { return backgroundImage }

        let scaleX = drawRect.width / windowImage.extent.width
        let scaleY = drawRect.height / windowImage.extent.height
        let scaledWindow = windowImage
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(translationX: drawRect.minX, y: drawRect.minY))

        guard let compositeFilter = CIFilter(name: "CISourceOverCompositing") else { return backgroundImage }
        compositeFilter.setValue(scaledWindow, forKey: kCIInputImageKey)
        compositeFilter.setValue(backgroundImage, forKey: kCIInputBackgroundImageKey)
        return compositeFilter.outputImage?.cropped(to: extent) ?? backgroundImage
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
