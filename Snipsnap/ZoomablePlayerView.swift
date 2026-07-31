//
//  ZoomablePlayerView.swift
//  Snipsnap
//

import AppKit
import AVFoundation
import QuartzCore

final class ZoomablePlayerView: NSView {

    let player: AVPlayer
    /// Shared transform parent: video + fixed dashed border stay locked to the recording.
    private let zoomContainer = CALayer()
    private let playerLayer = AVPlayerLayer()
    private let selectionBorderLayer = CAShapeLayer()
    private var updateTimer: Timer?

    var zoomAnnotationsProvider: () -> [PlacedAnnotation] = { [] }
    /// When true, paused preview skips settled zoom so the region can be edited on the raw frame.
    var prefersRawVideoForZoomEditing: () -> Bool = { false }
    var playbackTime: Double = 0
    var canvasSize: CGSize = .zero
    /// Real recording pixel size (orientation-corrected). The editor window is an arbitrary
    /// fixed size, so when its aspect ratio doesn't exactly match the recording, the video
    /// letterboxes inside it. Zoom must target the recording's actual content — not the raw
    /// canvas — or the crop drifts away from the fixed dashed border as it scales up.
    var mediaSize: CGSize = .zero
    var isPlaybackActive: Bool = false
    var isScrubbing: Bool = false

    init(player: AVPlayer, frame: NSRect) {
        self.player = player
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor

        zoomContainer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.addSublayer(zoomContainer)

        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        zoomContainer.addSublayer(playerLayer)

        selectionBorderLayer.fillColor = nil
        selectionBorderLayer.strokeColor = NSColor.systemBlue.cgColor
        selectionBorderLayer.lineWidth = 2
        selectionBorderLayer.lineDashPattern = [6, 3]
        selectionBorderLayer.opacity = 0
        selectionBorderLayer.isHidden = true
        zoomContainer.addSublayer(selectionBorderLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        stopContinuousUpdates()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        zoomContainer.bounds = CGRect(origin: .zero, size: bounds.size)
        zoomContainer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        playerLayer.frame = zoomContainer.bounds
        selectionBorderLayer.frame = zoomContainer.bounds
        updateZoomPreview()
        CATransaction.commit()
    }

    func setContinuousUpdatesEnabled(_ enabled: Bool) {
        if enabled {
            startContinuousUpdates()
        } else {
            stopContinuousUpdates()
        }
    }

    private func startContinuousUpdates() {
        guard updateTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.displayTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    private func stopContinuousUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func displayTick() {
        guard isPlaybackActive || isScrubbing else { return }
        let time = CMTimeGetSeconds(player.currentTime())
        guard time.isFinite else { return }
        playbackTime = time
        updateZoomPreview()
    }

    func updateZoomPreview() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard canvasSize.width > 0, canvasSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            zoomContainer.transform = CATransform3DIdentity
            hideSelectionBorder()
            return
        }

        let editingRaw = prefersRawVideoForZoomEditing()
        let annotations = zoomAnnotationsProvider()
        // Use the player bounds as the coordinate space so the zoom target matches
        // the dashed border path exactly (both in view points on the recording).
        let viewSize = bounds.size
        let effectiveMediaSize: CGSize? = (mediaSize.width > 0 && mediaSize.height > 0) ? mediaSize : nil

        let zoom = ZoomEffect.transform(
            at: playbackTime,
            from: annotations,
            outputSize: viewSize,
            canvasSize: canvasSize.width > 0 ? canvasSize : viewSize,
            mediaSize: effectiveMediaSize,
            settleTransitions: !(isPlaybackActive || isScrubbing || editingRaw)
        )

        if editingRaw {
            zoomContainer.transform = CATransform3DIdentity
            hideSelectionBorder()
            return
        }

        zoomContainer.transform = ZoomEffect.layerTransform(zoom, viewSize: viewSize)
        updateSelectionBorder(annotations: annotations, mediaSize: effectiveMediaSize)
    }

    /// Border path is the fixed recording selection; container transform grows it.
    /// Uses the exact same `ZoomEffect.selectionRect` mapping as the zoom target itself
    /// (including the `mediaSize` letterbox correction) so the border can never disagree
    /// with what's actually being zoomed into.
    private func updateSelectionBorder(annotations: [PlacedAnnotation], mediaSize: CGSize?) {
        guard isPlaybackActive || isScrubbing else {
            hideSelectionBorder()
            return
        }

        let zoomAnnotations = annotations.filter {
            if case .zoom = $0.content { return true }
            return false
        }
        guard let placed = ZoomEffect.activeAnnotation(at: playbackTime, from: zoomAnnotations),
              case let .zoom(rect) = placed.content else {
            hideSelectionBorder()
            return
        }

        let weight = ZoomEffect.progress(at: playbackTime, for: placed)
        let opacity = max(0, 1 - weight)
        guard weight > 0.001, weight < 0.999, opacity > 0.02 else {
            hideSelectionBorder()
            return
        }

        guard let viewRect = ZoomEffect.selectionRect(
            zoomRect: rect,
            outputSize: bounds.size,
            canvasSize: canvasSize.width > 0 ? canvasSize : bounds.size,
            mediaSize: mediaSize
        ) else {
            hideSelectionBorder()
            return
        }

        selectionBorderLayer.path = CGPath(rect: viewRect, transform: nil)
        selectionBorderLayer.opacity = Float(opacity)
        selectionBorderLayer.isHidden = false
    }

    private func hideSelectionBorder() {
        selectionBorderLayer.isHidden = true
        selectionBorderLayer.opacity = 0
        selectionBorderLayer.path = nil
    }
}
