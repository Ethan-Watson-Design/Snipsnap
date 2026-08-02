//
//  RecordingTimelinePreviewView.swift
//  Grabbit
//
//  Library recording preview with the same play/timeline chrome as annotation.
//

import AppKit
import AVFoundation
import SwiftUI

/// Video surface + annotation-style timeline row (play/pause, scrubber, time).
final class RecordingTimelinePreviewView: NSView {

    private var player: AVPlayer?
    private let playerLayer = AVPlayerLayer()
    private let videoHost = NSView(frame: .zero)
    private let timelineBg = NSView(frame: .zero)
    private let rowSep = NSView(frame: .zero)
    private let playPauseButton = NSButton(frame: .zero)
    private let timeline = VideoTimelineView(frame: .zero)
    private let timeLabel = NSTextField(labelWithString: "0:00 / 0:00")

    private var timeControlObservation: NSKeyValueObservation?
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private var isScrubbing = false
    private var videoDuration: Double = 0
    private var boundURL: URL?

    private let timelineRowHeight: CGFloat = 44
    private let timelineHorizontalInset: CGFloat = 12
    private let playButtonWidth: CGFloat = 32
    private let timeLabelWidth: CGFloat = 98

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = DesignTokens.Color.background.ns.cgColor

        videoHost.wantsLayer = true
        videoHost.layer?.backgroundColor = DesignTokens.Color.background.ns.cgColor
        videoHost.layer?.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = DesignTokens.Color.background.ns.cgColor
        addSubview(videoHost)

        timelineBg.wantsLayer = true
        addSubview(timelineBg)

        rowSep.wantsLayer = true
        addSubview(rowSep)

        playPauseButton.bezelStyle = .regularSquare
        playPauseButton.isBordered = false
        playPauseButton.imageScaling = .scaleProportionallyDown
        playPauseButton.target = self
        playPauseButton.action = #selector(togglePlayPause)
        addSubview(playPauseButton)
        updatePlayPauseButton(playing: false)

        addSubview(timeline)

        timeLabel.alignment = .right
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = .secondaryLabelColor
        addSubview(timeLabel)

        timeline.onSeek = { [weak self] time in
            self?.seekTo(time)
        }
        timeline.onScrubBegan = { [weak self] in
            self?.isScrubbing = true
        }
        timeline.onScrubEnded = { [weak self] in
            self?.isScrubbing = false
        }

        updateChromeAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        tearDownPlayer()
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateChromeAppearance()
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let videoHeight = max(1, bounds.height - timelineRowHeight)

        videoHost.frame = NSRect(x: 0, y: timelineRowHeight, width: width, height: videoHeight)
        playerLayer.frame = videoHost.bounds

        timelineBg.frame = NSRect(x: 0, y: 0, width: width, height: timelineRowHeight)
        rowSep.frame = NSRect(x: 0, y: timelineRowHeight, width: width, height: 1)

        let timelineMidY = timelineRowHeight / 2
        let timelineX = timelineHorizontalInset + playButtonWidth + 8
        let trailingInset = timelineHorizontalInset
        let timelineWidth = width - timelineX - timeLabelWidth - 8 - trailingInset

        playPauseButton.frame = CGRect(
            x: timelineHorizontalInset,
            y: timelineMidY - 16,
            width: playButtonWidth,
            height: 32
        )
        timeline.frame = CGRect(
            x: timelineX,
            y: (timelineRowHeight - 28) / 2,
            width: max(40, timelineWidth),
            height: 28
        )
        timeLabel.frame = CGRect(
            x: width - trailingInset - timeLabelWidth,
            y: (timelineRowHeight - 18) / 2,
            width: timeLabelWidth,
            height: 18
        )
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods.isEmpty || mods == .shift {
                togglePlayPause()
                return
            }
        }
        super.keyDown(with: event)
    }

    func bind(url: URL) {
        let standardized = url.standardizedFileURL
        guard boundURL != standardized else { return }
        boundURL = standardized

        tearDownPlayer()

        if FileManager.default.isUbiquitousItem(at: standardized) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: standardized)
        }

        let player = AVPlayer(url: standardized)
        self.player = player
        playerLayer.player = player

        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.updatePlayPauseButton(playing: player.timeControlStatus == .playing)
            }
        }

        installPlaybackTimeObserver()
        loadDuration(from: player)

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.seekTo(0)
        }

        updatePlaybackTime(0, total: 0)
        updatePlayPauseButton(playing: false)
    }

    // MARK: - Private

    private func tearDownPlayer() {
        if let token = timeObserverToken, let player {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
        timeControlObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        playerLayer.player = nil
        player = nil
        videoDuration = 0
        timeline.videoDuration = 0
        timeline.currentTime = 0
        timeline.clearSelection()
    }

    private func installPlaybackTimeObserver() {
        guard let player, timeObserverToken == nil else { return }
        let interval = CMTime(value: 1, timescale: 10)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing else { return }
                let current = CMTimeGetSeconds(time)
                let total = CMTimeGetSeconds(self.player?.currentItem?.duration ?? .zero)
                guard total.isFinite, total > 0 else { return }
                self.videoDuration = total
                self.timeline.videoDuration = total
                self.updatePlaybackTime(current, total: total)
            }
        }
    }

    private func loadDuration(from player: AVPlayer) {
        Task { [weak self] in
            guard let asset = player.currentItem?.asset else { return }
            guard let duration = try? await asset.load(.duration) else { return }
            let total = CMTimeGetSeconds(duration)
            await MainActor.run {
                guard let self, total.isFinite, total > 0 else { return }
                self.videoDuration = total
                self.timeline.videoDuration = total
                self.updatePlaybackTime(
                    CMTimeGetSeconds(player.currentTime()),
                    total: total
                )
            }
        }
    }

    @objc private func togglePlayPause() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    private func seekTo(_ seconds: Double) {
        guard let player, let item = player.currentItem else { return }
        let total = videoDuration > 0 ? videoDuration : CMTimeGetSeconds(item.duration)
        guard total.isFinite, total > 0 else { return }
        let clamped = max(0, min(seconds, total))
        let target = CMTimeMakeWithSeconds(clamped, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        updatePlaybackTime(clamped, total: total)
    }

    private func updatePlaybackTime(_ current: Double, total: Double) {
        timeline.currentTime = current
        let displayTotal = total > 0 ? total : videoDuration
        timeLabel.stringValue = "\(Self.formatTime(current)) / \(Self.formatTime(displayTotal))"
    }

    private func updatePlayPauseButton(playing: Bool) {
        let symbol = playing ? "pause.fill" : "play.fill"
        let cfg = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
            .applying(.init(hierarchicalColor: .labelColor))
        playPauseButton.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: playing ? "Pause" : "Play"
        )?.withSymbolConfiguration(cfg)
        playPauseButton.contentTintColor = .labelColor
    }

    private func updateChromeAppearance() {
        let fill = DesignTokens.Color.background.ns.cgColor
        layer?.backgroundColor = fill
        videoHost.layer?.backgroundColor = fill
        playerLayer.backgroundColor = fill
        // Same fill as the preview — no distinct chrome bar behind the controls.
        timelineBg.layer?.backgroundColor = fill
        rowSep.layer?.backgroundColor = NSColor.clear.cgColor
        timeLabel.textColor = .secondaryLabelColor
        playPauseButton.contentTintColor = .labelColor
        timeline.needsDisplay = true
    }

    private static func formatTime(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct RecordingTimelinePreviewRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> RecordingTimelinePreviewView {
        let view = RecordingTimelinePreviewView(frame: .zero)
        view.bind(url: url)
        return view
    }

    func updateNSView(_ nsView: RecordingTimelinePreviewView, context: Context) {
        nsView.bind(url: url)
    }
}
