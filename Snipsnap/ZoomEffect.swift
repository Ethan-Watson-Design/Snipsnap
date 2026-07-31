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
    }

    /// Zoom is always defined relative to the original unzoomed frame:
    /// a fixed focal point (selection center) and a target scale that makes
    /// the selection fill the view. Progress only eases scale + recenter —
    /// the focal point never moves, so there is no per-frame drift.
    struct ZoomTransform: Equatable {
        var scale: CGFloat
        /// Selection center in output/view coordinates (from the unzoomed frame).
        var focalPoint: CGPoint
        /// 0 = zoom in place about the focal point; 1 = focal point centered in the view.
        var panProgress: CGFloat

        static func identity(viewSize: CGSize) -> ZoomTransform {
            ZoomTransform(
                scale: 1,
                focalPoint: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2),
                panProgress: 0
            )
        }
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

    /// - Parameter mediaSize: Natural video size. When provided, canvas zoom rects are mapped
    ///   through the aspect-fit content frame (letterboxing) into `outputSize`.
    /// - Parameter settleTransitions: When true, skip entry/exit easing and hold the full zoom
    ///   for whatever region is active at `time` (used for paused editing preview).
    static func transform(
        at time: Double,
        from annotations: [PlacedAnnotation],
        outputSize: CGSize,
        canvasSize: CGSize,
        mediaSize: CGSize? = nil,
        settleTransitions: Bool = false
    ) -> ZoomTransform {
        let identity = ZoomTransform.identity(viewSize: outputSize)

        let zoomAnnotations = annotations.filter {
            if case .zoom = $0.content { return true }
            return false
        }
        guard let placed = activeAnnotation(at: time, from: zoomAnnotations),
              case let .zoom(rect) = placed.content else {
            return identity
        }

        let weight: CGFloat
        if settleTransitions {
            weight = 1
        } else {
            weight = progress(at: time, for: placed)
            guard weight > 0 else { return identity }
        }

        guard let targetRect = selectionRect(
            zoomRect: rect,
            outputSize: outputSize,
            canvasSize: canvasSize,
            mediaSize: mediaSize
        ) else { return identity }

        return transform(to: targetRect, progress: weight, outputSize: outputSize)
    }

    /// Builds a zoom that always aims at the fixed selection on the unzoomed frame.
    /// Uses aspect-fill (`max`) so the settled frame is strictly inside the selection
    /// (fit/`min` would letterbox and reveal pixels outside the dashed border).
    private static func transform(
        to targetRect: CGRect,
        progress: CGFloat,
        outputSize: CGSize
    ) -> ZoomTransform {
        let t = max(0, min(1, progress))
        let focal = CGPoint(x: targetRect.midX, y: targetRect.midY)
        let targetScale = max(
            outputSize.width / max(targetRect.width, 0.5),
            outputSize.height / max(targetRect.height, 0.5)
        )
        guard targetScale.isFinite, targetScale > 0 else {
            return ZoomTransform.identity(viewSize: outputSize)
        }

        return ZoomTransform(
            scale: 1 + (targetScale - 1) * t,
            focalPoint: focal,
            panProgress: t
        )
    }

    /// Layer transform for a layer with anchor point (0.5, 0.5) and position at view center.
    /// Maps `p → scale*(p - focal) + focal + (viewCenter - focal)*panProgress`.
    static func layerTransform(_ zoom: ZoomTransform, viewSize: CGSize) -> CATransform3D {
        let s = zoom.scale
        let pan = max(0, min(1, zoom.panProgress))
        let focal = zoom.focalPoint
        let viewCenter = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)

        if abs(s - 1) < 0.001, pan < 0.001 {
            return CATransform3DIdentity
        }
        guard s.isFinite, s > 0 else { return CATransform3DIdentity }

        // With center anchor: p' = viewCenter + M*(p - viewCenter).
        // We need M(x) = s*x + (tx, ty), i.e. scale first, then translate — so build
        // the matrix's translation row directly rather than composing with
        // CATransform3DConcat, whose argument order applies the *first* transform
        // first (translate-then-scale here), which re-scales the pan offset by `s`
        // on every frame. That error is proportional to (viewCenter - focal) and to
        // (s - 1)², i.e. it compounds with zoom level and with how far the selection
        // is from center — exactly the runaway drift/edge-overshoot this fixes.
        let tx = (s + pan - 1) * (viewCenter.x - focal.x)
        let ty = (s + pan - 1) * (viewCenter.y - focal.y)
        var transform = CATransform3DMakeScale(s, s, 1)
        transform.m41 = tx
        transform.m42 = ty
        return transform
    }

    static func applyZoom(
        to image: CIImage,
        zoomRect: CGRect,
        progress: CGFloat,
        outputSize: CGSize,
        canvasSize: CGSize,
        mediaSize: CGSize? = nil
    ) -> CIImage {
        guard let targetRect = selectionRect(
            zoomRect: zoomRect,
            outputSize: outputSize,
            canvasSize: canvasSize,
            mediaSize: mediaSize
        ) else { return image }
        let zoom = transform(to: targetRect, progress: progress, outputSize: outputSize)
        return applyZoom(to: image, zoom: zoom, outputSize: outputSize)
    }

    static func applyZoom(
        to image: CIImage,
        zoom: ZoomTransform,
        outputSize: CGSize
    ) -> CIImage {
        let s = zoom.scale
        let pan = max(0, min(1, zoom.panProgress))
        if abs(s - 1) < 0.001, pan < 0.001 { return image }
        guard s.isFinite, s > 0 else { return image }

        let focal = zoom.focalPoint
        let viewCenter = CGPoint(x: outputSize.width / 2, y: outputSize.height / 2)
        let tx = (1 - s) * focal.x + (viewCenter.x - focal.x) * pan
        let ty = (1 - s) * focal.y + (viewCenter.y - focal.y) * pan
        // p' = s*p + (1-s)*focal + (viewCenter-focal)*pan
        let affine = CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: tx, ty: ty)
        let transformed = image.transformed(by: affine)
        return transformed.cropped(to: CGRect(origin: .zero, size: outputSize))
    }

    static func aspectFitRect(for mediaSize: CGSize, in canvasSize: CGSize) -> CGRect {
        guard mediaSize.width > 0, mediaSize.height > 0,
              canvasSize.width > 0, canvasSize.height > 0 else {
            return CGRect(origin: .zero, size: canvasSize)
        }
        let widthRatio = canvasSize.width / mediaSize.width
        let heightRatio = canvasSize.height / mediaSize.height
        let scale = min(widthRatio, heightRatio)
        let size = CGSize(width: mediaSize.width * scale, height: mediaSize.height * scale)
        return CGRect(
            x: (canvasSize.width - size.width) / 2,
            y: (canvasSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Maps a canvas-space zoom selection into a fixed rect in `outputSize` coordinates.
    /// Exposed (not private) so the live preview can align its dashed border to the exact
    /// same rect the zoom targets — both must use identical math or they'll disagree once
    /// `mediaSize` introduces letterboxing between the editor window and the real recording.
    static func selectionRect(
        zoomRect: CGRect,
        outputSize: CGSize,
        canvasSize: CGSize,
        mediaSize: CGSize?
    ) -> CGRect? {
        guard canvasSize.width > 0, canvasSize.height > 0,
              zoomRect.width > 0, zoomRect.height > 0,
              outputSize.width > 0, outputSize.height > 0 else {
            return nil
        }

        if let mediaSize, mediaSize.width > 0, mediaSize.height > 0 {
            let contentFrame = aspectFitRect(for: mediaSize, in: canvasSize)
            guard contentFrame.width > 0, contentFrame.height > 0 else { return nil }
            let clamped = zoomRect.intersection(contentFrame)
            guard clamped.width > 1, clamped.height > 1 else { return nil }
            let nx = (clamped.minX - contentFrame.minX) / contentFrame.width
            let ny = (clamped.minY - contentFrame.minY) / contentFrame.height
            let nw = clamped.width / contentFrame.width
            let nh = clamped.height / contentFrame.height
            return CGRect(
                x: nx * outputSize.width,
                y: ny * outputSize.height,
                width: nw * outputSize.width,
                height: nh * outputSize.height
            )
        }

        let scaleX = outputSize.width / canvasSize.width
        let scaleY = outputSize.height / canvasSize.height
        let clamped = zoomRect.intersection(CGRect(origin: .zero, size: canvasSize))
        guard clamped.width > 1, clamped.height > 1 else { return nil }
        return CGRect(
            x: clamped.origin.x * scaleX,
            y: clamped.origin.y * scaleY,
            width: clamped.width * scaleX,
            height: clamped.height * scaleY
        )
    }
}
