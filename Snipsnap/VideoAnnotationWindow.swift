//
//  VideoAnnotationWindow.swift
//  Snipsnap
//
//  Created by Ethan Watson on 6/28/26.
//

import AppKit
import AVFoundation
import AVKit

final class VideoAnnotationWindow: NSWindow {

    private static var current: VideoAnnotationWindow?

    private let player: AVPlayer
    private let videoURL: URL
    private let canvas: AnnotationCanvasView

    private var pill: ToolbarPillView!
    private var playPauseButton: NSButton!
    private var timeControlObservation: NSKeyValueObservation?

    private let videoAreaHeight: CGFloat = 492
    private let toolbarHeight: CGFloat = 68

    // MARK: - Entry Point

    static func show(url: URL, thumbnail: NSImage) {
        DispatchQueue.main.async {
            current = VideoAnnotationWindow(url: url)
            current?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Init

    private init(url: URL) {
        self.videoURL = url
        self.player = AVPlayer(url: url)
        self.canvas = AnnotationCanvasView(frame: .zero)

        let windowSize = NSSize(width: 900, height: videoAreaHeight + toolbarHeight)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: screen.midX - windowSize.width / 2,
            y: screen.midY - windowSize.height / 2
        )

        super.init(
            contentRect: NSRect(origin: origin, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        title = "Recording"
        isReleasedWhenClosed = false

        buildLayout(windowSize: windowSize)
        wire()
    }

    // MARK: - Layout

    private func buildLayout(windowSize: NSSize) {
        pill = ToolbarPillView(frame: CGRect(x: 0, y: 0, width: 100, height: 48))

        let root = NSView(frame: NSRect(origin: .zero, size: windowSize))

        let videoRect = NSRect(x: 0, y: toolbarHeight, width: windowSize.width, height: videoAreaHeight)

        // Video player — no built-in controls so the canvas overlay owns all input
        let playerView = AVPlayerView(frame: videoRect)
        playerView.player = player
        playerView.controlsStyle = .none
        playerView.wantsLayer = true
        playerView.layer?.backgroundColor = NSColor.black.cgColor
        root.addSubview(playerView)

        // Annotation canvas — transparent overlay, same frame, added after player (higher z-order)
        canvas.frame = videoRect
        root.addSubview(canvas)

        // Separator
        let sep = NSView(frame: NSRect(x: 0, y: toolbarHeight - 1, width: windowSize.width, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        root.addSubview(sep)

        // Toolbar background
        let tbBg = NSView(frame: NSRect(x: 0, y: 0, width: windowSize.width, height: toolbarHeight))
        tbBg.wantsLayer = true
        tbBg.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.addSubview(tbBg)

        // Play / Pause button (left)
        let ppBtn = NSButton(frame: CGRect(x: 14, y: (toolbarHeight - 36) / 2, width: 36, height: 36))
        ppBtn.bezelStyle = .regularSquare
        ppBtn.isBordered = false
        ppBtn.imageScaling = .scaleProportionallyDown
        ppBtn.target = self
        ppBtn.action = #selector(togglePlayPause)
        root.addSubview(ppBtn)
        self.playPauseButton = ppBtn
        updatePlayPauseButton(playing: false)

        // Reveal in Finder button (right)
        let revealBtn = NSButton(frame: CGRect(
            x: windowSize.width - 144, y: (toolbarHeight - 30) / 2,
            width: 132, height: 30
        ))
        revealBtn.bezelStyle = .rounded
        revealBtn.title = "Reveal in Finder"
        revealBtn.target = self
        revealBtn.action = #selector(revealInFinder)
        root.addSubview(revealBtn)

        // Pill — centered between the two flanking buttons, 10 pt from bottom edge
        let pillX = max(62, (windowSize.width - pill.frame.width) / 2)
        pill.frame.origin = CGPoint(x: pillX, y: (toolbarHeight - 48) / 2)
        root.addSubview(pill)

        contentView = root
        makeFirstResponder(canvas)
    }

    // MARK: - Wire

    private func wire() {
        pill.selectedTool = .marker
        pill.selectedColorIndex = 0

        // Auto-pause when the user starts a stroke
        canvas.onWillDraw = { [weak self] in
            guard let self, self.player.timeControlStatus == .playing else { return }
            self.player.pause()
        }

        canvas.onToolChanged = { [weak self] tool in
            self?.pill.selectedTool = tool
        }

        canvas.onEscapeAction = { [weak self] in
            self?.close()
        }

        pill.onToolSelected = { [weak self] tool in
            guard let self else { return }
            canvas.selectedTool = tool
            pill.selectedTool = tool
        }

        pill.onColorSelected = { [weak self] idx in
            guard let self else { return }
            canvas.selectedColor = NSColor.annotationPalette[idx]
            pill.selectedColorIndex = idx
        }

        // Copy: flatten current video frame with annotations and put on clipboard
        pill.onCopy = { [weak self] in
            self?.copyFrameWithAnnotations()
        }

        // Keep play/pause button icon in sync with actual player state
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.updatePlayPauseButton(playing: player.timeControlStatus == .playing)
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
    }

    // MARK: - Playback

    @objc private func togglePlayPause() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    @objc private func playerItemDidEnd() {
        player.seek(to: .zero)
    }

    private func updatePlayPauseButton(playing: Bool) {
        let symbol = playing ? "pause.fill" : "play.fill"
        let cfg = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        playPauseButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: playing ? "Pause" : "Play")?
            .withSymbolConfiguration(cfg)
    }

    // MARK: - Copy Frame + Annotations

    private func copyFrameWithAnnotations() {
        player.pause()

        let currentTime = player.currentTime()
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: currentTime)]) { [weak self] _, cgImage, _, _, _ in
            DispatchQueue.main.async {
                guard let self, let cgImage else { return }
                let frame = NSImage(cgImage: cgImage, size: .zero)
                let flat = self.canvas.flattenedImage(background: frame)
                guard let tiff = flat.tiffRepresentation else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setData(tiff, forType: .tiff)
            }
        }
    }

    // MARK: - Reveal in Finder

    @objc private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([videoURL])
    }
}
