//
//  ZoomablePlayerView.swift
//  Snipsnap
//

import AppKit
import AVFoundation
import QuartzCore

final class ZoomablePlayerView: NSView {

    let player: AVPlayer
    private let playerLayer = AVPlayerLayer()
    private var updateTimer: Timer?

    var zoomAnnotationsProvider: () -> [PlacedAnnotation] = { [] }
    var playbackTime: Double = 0
    var canvasSize: CGSize = .zero
    var isPlaybackActive: Bool = false
    var isScrubbing: Bool = false

    init(player: AVPlayer, frame: NSRect) {
        self.player = player
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor

        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        stopContinuousUpdates()
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateZoomPreview()
        CATransaction.commit()
    }

    func updateZoomPreview() {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            playerLayer.transform = CATransform3DIdentity
            return
        }

        let shouldAnimate = isPlaybackActive || isScrubbing
        guard shouldAnimate else {
            playerLayer.transform = CATransform3DIdentity
            return
        }

        let zoom = ZoomEffect.transform(
            at: playbackTime,
            from: zoomAnnotationsProvider(),
            outputSize: bounds.size,
            canvasSize: canvasSize
        )
        playerLayer.transform = ZoomEffect.layerTransform(zoom, viewSize: bounds.size)
    }
}
