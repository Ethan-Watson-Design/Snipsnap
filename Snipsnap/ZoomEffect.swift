//
//  ZoomEffect.swift
//  Snipsnap
//

import AppKit
import CoreImage

enum ZoomEffect {

    struct Configuration {
        static let entryDuration: Double = 0.55
        static let exitDuration: Double = 0.45
        static let regionPaddingFraction: CGFloat = 0.12
        static let maxScale: CGFloat = 2.75
    }

    /// Uniform scale with a focal point in view coordinates.
    struct ZoomTransform: Equatable {
        var scale: CGFloat
        var center: CGPoint
    }

    static func activeAnnotation(at time: Double, from zoomAnnotations: [PlacedAnnotation]) -> PlacedAnnotation? {
        var active: PlacedAnnotation?
        for placed in zoomAnnotations where placed.isVisible(at: time) {
            active = placed
        }
        return active
    }

    static func easeInOutCubic(_ t: CGFloat) -> CGFloat {
        let c = max(0, min(1, t))
        if c < 0.5 {
            return 4 * c * c * c
        }
        let f = 2 * c - 2
        return 1 + f * f * f / 2
    }

    static func progress(at time: Double, for placed: PlacedAnnotation) -> CGFloat {
        let elapsed = time - placed.startTime

        let entryProgress: CGFloat = elapsed < Configuration.entryDuration
            ? easeInOutCubic(CGFloat(elapsed / Configuration.entryDuration))
            : 1.0

        var exitProgress: CGFloat = 1.0
        if let duration = placed.visibleDuration {
            let remaining = (placed.startTime + duration) - time
            if remaining < Configuration.exitDuration {
                exitProgress = easeInOutCubic(CGFloat(max(0, remaining) / Configuration.exitDuration))
            }
        }

        return min(entryProgress, exitProgress)
    }

    static func transform(
        at time: Double,
        from annotations: [PlacedAnnotation],
        outputSize: CGSize,
        canvasSize: CGSize
    ) -> ZoomTransform {
        let viewCenter = CGPoint(x: outputSize.width / 2, y: outputSize.height / 2)
        let identity = ZoomTransform(scale: 1, center: viewCenter)

        var weighted: [(transform: ZoomTransform, weight: CGFloat)] = []
        for placed in annotations {
            guard case let .zoom(rect) = placed.content else { continue }
            let progress = progress(at: time, for: placed)
            guard progress > 0 else { continue }
            let target = targetTransform(
                zoomRect: rect,
                outputSize: outputSize,
                canvasSize: canvasSize
            )
            weighted.append((
                transform: interpolate(from: identity, to: target, progress: progress),
                weight: progress
            ))
        }

        guard !weighted.isEmpty else { return identity }
        if weighted.count == 1 { return weighted[0].transform }

        var totalWeight: CGFloat = 0
        var scale: CGFloat = 0
        var centerX: CGFloat = 0
        var centerY: CGFloat = 0
        for item in weighted {
            totalWeight += item.weight
            scale += item.transform.scale * item.weight
            centerX += item.transform.center.x * item.weight
            centerY += item.transform.center.y * item.weight
        }
        guard totalWeight > 0 else { return identity }
        return ZoomTransform(
            scale: scale / totalWeight,
            center: CGPoint(x: centerX / totalWeight, y: centerY / totalWeight)
        )
    }

    static func layerTransform(_ zoom: ZoomTransform, viewSize: CGSize) -> CATransform3D {
        guard abs(zoom.scale - 1) > 0.001 else { return CATransform3DIdentity }

        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, viewSize.width / 2, viewSize.height / 2, 0)
        transform = CATransform3DScale(transform, zoom.scale, zoom.scale, 1)
        transform = CATransform3DTranslate(transform, -zoom.center.x, -zoom.center.y, 0)
        return transform
    }

    static func applyZoom(
        to image: CIImage,
        zoomRect: CGRect,
        progress: CGFloat,
        outputSize: CGSize,
        canvasSize: CGSize
    ) -> CIImage {
        let viewCenter = CGPoint(x: outputSize.width / 2, y: outputSize.height / 2)
        let identity = ZoomTransform(scale: 1, center: viewCenter)
        let target = targetTransform(
            zoomRect: zoomRect,
            outputSize: outputSize,
            canvasSize: canvasSize
        )
        let zoom = interpolate(from: identity, to: target, progress: progress)
        return applyZoom(to: image, zoom: zoom, outputSize: outputSize)
    }

    static func applyZoom(
        to image: CIImage,
        zoom: ZoomTransform,
        outputSize: CGSize
    ) -> CIImage {
        guard abs(zoom.scale - 1) > 0.001 else { return image }

        let visibleWidth = outputSize.width / zoom.scale
        let visibleHeight = outputSize.height / zoom.scale
        let cropRect = CGRect(
            x: zoom.center.x - visibleWidth / 2,
            y: zoom.center.y - visibleHeight / 2,
            width: visibleWidth,
            height: visibleHeight
        )
        guard cropRect.width > 0, cropRect.height > 0 else { return image }

        let cropped = image.cropped(to: cropRect)
        let translated = cropped.transformed(
            by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y)
        )
        let scale = min(outputSize.width / cropRect.width, outputSize.height / cropRect.height)

        guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return image }
        filter.setValue(translated, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        return filter.outputImage ?? image
    }

    // MARK: - Private

    private static func targetTransform(
        zoomRect: CGRect,
        outputSize: CGSize,
        canvasSize: CGSize
    ) -> ZoomTransform {
        let viewCenter = CGPoint(x: outputSize.width / 2, y: outputSize.height / 2)
        guard canvasSize.width > 0, canvasSize.height > 0,
              zoomRect.width > 0, zoomRect.height > 0 else {
            return ZoomTransform(scale: 1, center: viewCenter)
        }

        let scaleX = outputSize.width / canvasSize.width
        let scaleY = outputSize.height / canvasSize.height
        let padded = zoomRect.insetBy(
            dx: -zoomRect.width * Configuration.regionPaddingFraction,
            dy: -zoomRect.height * Configuration.regionPaddingFraction
        )
        let clamped = padded.intersection(CGRect(origin: .zero, size: canvasSize))
        guard clamped.width > 0, clamped.height > 0 else {
            return ZoomTransform(scale: 1, center: viewCenter)
        }

        let zoomPixelRect = CGRect(
            x: clamped.origin.x * scaleX,
            y: clamped.origin.y * scaleY,
            width: clamped.width * scaleX,
            height: clamped.height * scaleY
        )

        let fitScale = min(
            outputSize.width / zoomPixelRect.width,
            outputSize.height / zoomPixelRect.height
        )
        let targetScale = min(fitScale, Configuration.maxScale)
        let regionCenter = CGPoint(x: zoomPixelRect.midX, y: zoomPixelRect.midY)

        return ZoomTransform(scale: targetScale, center: regionCenter)
    }

    private static func interpolate(
        from start: ZoomTransform,
        to end: ZoomTransform,
        progress: CGFloat
    ) -> ZoomTransform {
        let t = max(0, min(1, progress))
        return ZoomTransform(
            scale: start.scale + (end.scale - start.scale) * t,
            center: CGPoint(
                x: start.center.x + (end.center.x - start.center.x) * t,
                y: start.center.y + (end.center.y - start.center.y) * t
            )
        )
    }
}
