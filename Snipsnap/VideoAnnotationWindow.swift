//
//  VideoAnnotationWindow.swift
//  Snipsnap
//
//  Created by Ethan Watson on 6/28/26.
//

import AppKit
import AVFoundation
import AVKit

// MARK: - Duration Toast (anchored to selected annotation)

final class AnnotationDurationToastView: NSView {

    var onStartTimeChanged: ((Double) -> Void)?
    var onDurationChanged: ((Double?) -> Void)?

    private let startLabel = NSTextField(labelWithString: "Beginning")
    private let startSlider = NSSlider()
    private let endLabel = NSTextField(labelWithString: "Forever")
    private let endSlider = NSSlider()
    private var recordingDuration: Double = 60

    private static let toastWidth: CGFloat = 168
    private static let toastHeight: CGFloat = 80

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        let vfx = NSVisualEffectView(frame: bounds)
        vfx.autoresizingMask = [.width, .height]
        vfx.material = .popover
        vfx.blendingMode = .withinWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = 10
        vfx.layer?.masksToBounds = true
        addSubview(vfx)

        let labelWidth = Self.toastWidth - 20

        startLabel.frame = CGRect(x: 10, y: 56, width: labelWidth, height: 16)
        startLabel.font = .systemFont(ofSize: 11, weight: .medium)
        startLabel.textColor = .labelColor
        startLabel.alignment = .center
        addSubview(startLabel)

        startSlider.frame = CGRect(x: 10, y: 38, width: labelWidth, height: 16)
        startSlider.minValue = 1
        startSlider.maxValue = 61
        startSlider.doubleValue = startSlider.minValue
        startSlider.sliderType = .linear
        startSlider.isContinuous = true
        startSlider.target = self
        startSlider.action = #selector(startSliderMoved(_:))
        addSubview(startSlider)

        endLabel.frame = CGRect(x: 10, y: 28, width: labelWidth, height: 16)
        endLabel.font = .systemFont(ofSize: 11, weight: .medium)
        endLabel.textColor = .labelColor
        endLabel.alignment = .center
        addSubview(endLabel)

        endSlider.frame = CGRect(x: 10, y: 10, width: labelWidth, height: 16)
        endSlider.minValue = 1
        endSlider.maxValue = 61
        endSlider.doubleValue = endSlider.maxValue
        endSlider.sliderType = .linear
        endSlider.isContinuous = true
        endSlider.target = self
        endSlider.action = #selector(endSliderMoved(_:))
        addSubview(endSlider)
    }

    func configure(recordingDuration: Double, startTime: Double, visibleDuration: Double?) {
        self.recordingDuration = max(1, floor(recordingDuration))
        let maxVal = Self.sliderMax(for: self.recordingDuration)
        for slider in [startSlider, endSlider] {
            slider.maxValue = maxVal
            slider.minValue = 1
        }
        startSlider.doubleValue = Self.startSliderValue(for: startTime, recordingDuration: self.recordingDuration)
        endSlider.doubleValue = Self.endSliderValue(for: visibleDuration, recordingDuration: self.recordingDuration)
        updateLabels()
    }

    @objc private func startSliderMoved(_ sender: NSSlider) {
        let start = Self.startTime(fromSlider: sender.doubleValue, recordingDuration: recordingDuration)
        updateLabels()
        onStartTimeChanged?(start)
    }

    @objc private func endSliderMoved(_ sender: NSSlider) {
        let duration = Self.duration(fromEndSlider: sender.doubleValue, recordingDuration: recordingDuration)
        updateLabels()
        onDurationChanged?(duration)
    }

    private func updateLabels() {
        let start = Self.startTime(fromSlider: startSlider.doubleValue, recordingDuration: recordingDuration)
        startLabel.stringValue = start <= 0.5 ? "Beginning" : "\(Int(start.rounded()))s"

        if let seconds = Self.duration(fromEndSlider: endSlider.doubleValue, recordingDuration: recordingDuration) {
            endLabel.stringValue = "\(Int(seconds.rounded()))s"
        } else {
            endLabel.stringValue = "Forever"
        }
    }

    private static func sliderMax(for recordingDuration: Double) -> Double {
        max(2, floor(recordingDuration) + 1)
    }

    /// Min slider position = beginning of video; higher values map 1s … recording length.
    private static func startTime(fromSlider value: Double, recordingDuration: Double) -> Double {
        if value <= 1.5 { return 0 }
        return max(1, min(value.rounded() - 1, floor(recordingDuration)))
    }

    private static func startSliderValue(for startTime: Double, recordingDuration: Double) -> Double {
        if startTime <= 0.5 { return 1 }
        return min(max(2, startTime.rounded() + 1), sliderMax(for: recordingDuration))
    }

    /// Max slider position = forever; lower values map 1s … recording length.
    private static func duration(fromEndSlider value: Double, recordingDuration: Double) -> Double? {
        let maxVal = sliderMax(for: recordingDuration)
        if value >= maxVal - 0.5 { return nil }
        return max(1, min(value.rounded(), floor(recordingDuration)))
    }

    private static func endSliderValue(for duration: Double?, recordingDuration: Double) -> Double {
        let maxVal = sliderMax(for: recordingDuration)
        guard let duration else { return maxVal }
        return min(max(1, duration.rounded()), floor(recordingDuration))
    }

    static func preferredSize() -> NSSize {
        NSSize(width: toastWidth, height: toastHeight)
    }
}

final class VideoAnnotationWindow: NSWindow {

    private static var current: VideoAnnotationWindow?

    private let player: AVPlayer
    private let videoURL: URL
    private let canvas: AnnotationCanvasView

    private var pill: ToolbarPillView!
    private var playPauseButton: NSButton!
    private var scrubber: NSSlider!
    private var timeLabel: NSTextField!
    private var durationToast: AnnotationDurationToastView!
    private var saveButton: NSButton!
    private var isSaving = false
    private var timeControlObservation: NSKeyValueObservation?
    private var timeObserverToken: Any?
    private var undoRedoKeyMonitor: Any?
    private var videoDuration: Double = 0

    private let videoAreaHeight: CGFloat = 492
    private let toolbarHeight: CGFloat = 64
    private let toolbarHorizontalInset: CGFloat = 12
    private let controlsRowHeight: CGFloat = 40

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
        player.play()
    }

    // MARK: - Layout

    private func buildLayout(windowSize: NSSize) {
        pill = ToolbarPillView(
            frame: CGRect(x: 0, y: 0, width: 100, height: 40),
            showsCopyButton: false
        )

        let root = NSView(frame: NSRect(origin: .zero, size: windowSize))

        let videoRect = NSRect(x: 0, y: toolbarHeight, width: windowSize.width, height: videoAreaHeight)

        // Video player — no overlay controls so the annotation canvas owns the full surface
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

        let rowSep = NSView(frame: NSRect(x: 0, y: controlsRowHeight, width: windowSize.width, height: 1))
        rowSep.wantsLayer = true
        rowSep.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        root.addSubview(rowSep)

        // ── Scrubber row ────────────────────────────────────────────────────
        let scrubRowY = controlsRowHeight
        let timeLabelWidth: CGFloat = 98

        let scrub = NSSlider(value: 0, minValue: 0, maxValue: 1, target: self, action: #selector(scrubberMoved(_:)))
        scrub.frame = CGRect(
            x: toolbarHorizontalInset,
            y: scrubRowY + 4,
            width: windowSize.width - timeLabelWidth - toolbarHorizontalInset * 2,
            height: 16
        )
        scrub.sliderType = .linear
        scrub.isContinuous = true
        scrub.autoresizingMask = [.width]
        root.addSubview(scrub)
        self.scrubber = scrub

        let tLabel = NSTextField(labelWithString: "0:00 / 0:00")
        tLabel.frame = CGRect(
            x: windowSize.width - timeLabelWidth - toolbarHorizontalInset,
            y: scrubRowY + 3,
            width: timeLabelWidth,
            height: 18
        )
        tLabel.alignment = .right
        tLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        tLabel.textColor = .secondaryLabelColor
        tLabel.autoresizingMask = [.minXMargin]
        root.addSubview(tLabel)
        self.timeLabel = tLabel

        // Duration toast — floats over the video near the selected annotation
        let toast = AnnotationDurationToastView(frame: .zero)
        toast.isHidden = true
        root.addSubview(toast)
        self.durationToast = toast

        // ── Controls row ────────────────────────────────────────────────────
        let controlsMidY = controlsRowHeight / 2
        let playButtonWidth: CGFloat = 32

        // Play / Pause button (left)
        let ppBtn = NSButton(frame: CGRect(
            x: toolbarHorizontalInset,
            y: controlsMidY - 16,
            width: playButtonWidth,
            height: 32
        ))
        ppBtn.bezelStyle = .regularSquare
        ppBtn.isBordered = false
        ppBtn.imageScaling = .scaleProportionallyDown
        ppBtn.target = self
        ppBtn.action = #selector(togglePlayPause)
        root.addSubview(ppBtn)
        self.playPauseButton = ppBtn
        updatePlayPauseButton(playing: false)

        // Save and show in Finder (right)
        let saveBtn = NSButton(frame: CGRect(
            x: windowSize.width - 220 - toolbarHorizontalInset,
            y: controlsMidY - 15,
            width: 206,
            height: 30
        ))
        saveBtn.bezelStyle = .rounded
        saveBtn.title = "Save and show in Finder"
        saveBtn.target = self
        saveBtn.action = #selector(saveAndShowInFinder)
        root.addSubview(saveBtn)
        self.saveButton = saveBtn

        // Tool strip — flush after play button
        let pillX = toolbarHorizontalInset + playButtonWidth + 8
        pill.frame.origin = CGPoint(x: pillX, y: 0)
        root.addSubview(pill)

        contentView = root
        makeFirstResponder(canvas)
    }

    // MARK: - Wire

    private func wire() {
        canvas.videoMode = true
        pill.selectedTool = .marker
        pill.selectedColorIndex = 0

        canvas.onSelectionChanged = { [weak self] index in
            self?.updateDurationToast(for: index)
        }

        canvas.onSelectionGeometryChanged = { [weak self] in
            self?.positionDurationToast()
        }

        durationToast.onStartTimeChanged = { [weak self] startTime in
            guard let self, let index = canvas.selectedIndex else { return }
            canvas.setStartTime(for: index, seconds: startTime, recordingDuration: videoDuration)
            self.updateDurationToast(for: index)
        }

        durationToast.onDurationChanged = { [weak self] duration in
            guard let self, let index = canvas.selectedIndex else { return }
            if let duration {
                canvas.setVisibleDuration(for: index, seconds: duration, recordingDuration: videoDuration)
            } else {
                canvas.setForever(for: index, forever: true)
            }
            self.updateDurationToast(for: index)
        }

        // Auto-pause when the user starts a stroke
        canvas.onWillDraw = { [weak self] in
            guard let self, self.player.timeControlStatus == .playing else { return }
            self.player.pause()
        }

        canvas.onToolChanged = { [weak self] tool in
            self?.pill.selectedTool = tool
            self?.updateDurationToast(for: self?.canvas.selectedIndex)
        }

        canvas.onEscapeAction = { [weak self] in
            self?.close()
        }

        pill.onToolSelected = { [weak self] tool in
            guard let self else { return }
            canvas.selectedTool = tool
            pill.selectedTool = tool
            updateDurationToast(for: canvas.selectedIndex)
        }

        pill.onColorSelected = { [weak self] idx in
            guard let self else { return }
            let color = NSColor.annotationPalette[idx]
            canvas.selectedColor = color
            pill.selectedColorIndex = idx
            canvas.updateEmojiPickerColor(color)
        }

        pill.onArrowTipStyleSelected = { [weak self] style in
            guard let self else { return }
            canvas.selectedArrowTipStyle = style
            pill.selectedArrowTipStyle = style
        }

        // Keep play/pause button icon in sync with actual player state
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.updatePlayPauseButton(playing: player.timeControlStatus == .playing)
            }
        }

        // Drive scrubber + time label from playback position
        let interval = CMTime(value: 1, timescale: 10)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                let current = CMTimeGetSeconds(time)
                let total = CMTimeGetSeconds(self.player.currentItem?.duration ?? .zero)
                guard total.isFinite, total > 0 else { return }
                self.videoDuration = total
                self.canvas.playbackTime = current
                self.canvas.needsDisplay = true
                self.scrubber.doubleValue = current / total
                self.timeLabel.stringValue = "\(Self.formatTime(current)) / \(Self.formatTime(total))"
            }
        }

        Task { [weak self] in
            guard let self, let asset = self.player.currentItem?.asset else { return }
            guard let duration = try? await asset.load(.duration) else { return }
            let total = CMTimeGetSeconds(duration)
            await MainActor.run {
                guard total.isFinite, total > 0 else { return }
                self.videoDuration = total
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )

        undoRedoKeyMonitor = canvas.installUndoRedoKeyMonitor(for: self)
    }

    // MARK: - Playback

    @objc private func togglePlayPause() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    @objc private func scrubberMoved(_ sender: NSSlider) {
        guard let item = player.currentItem else { return }
        let total = CMTimeGetSeconds(item.duration)
        guard total.isFinite, total > 0 else { return }
        let target = CMTimeMakeWithSeconds(sender.doubleValue * total, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        canvas.playbackTime = CMTimeGetSeconds(target)
        canvas.needsDisplay = true
    }

    // MARK: - Annotation Duration

    private func updateDurationToast(for index: Int?) {
        let show = index != nil && canvas.selectedTool == .select
        durationToast.isHidden = !show

        guard show, let index, canvas.annotations.indices.contains(index) else { return }
        let placed = canvas.annotations[index]
        durationToast.configure(
            recordingDuration: videoDuration,
            startTime: placed.startTime,
            visibleDuration: placed.visibleDuration
        )
        positionDurationToast()
    }

    private func positionDurationToast() {
        guard !durationToast.isHidden,
              let box = canvas.selectionBoundingBox(),
              let root = contentView else { return }

        let toastSize = AnnotationDurationToastView.preferredSize()
        let anchor = canvas.convert(box, to: root)
        let gap: CGFloat = 8
        let videoTop = toolbarHeight + videoAreaHeight
        let videoBottom = toolbarHeight

        let aboveY = anchor.maxY + gap
        let belowY = anchor.minY - gap - toastSize.height
        let placeAbove = aboveY + toastSize.height <= videoTop

        var originX = anchor.midX - toastSize.width / 2
        originX = max(8, min(originX, root.bounds.width - toastSize.width - 8))

        let originY = placeAbove ? aboveY : belowY
        let clampedY = max(videoBottom + 8, min(originY, videoTop - toastSize.height - 8))

        durationToast.frame = CGRect(
            x: originX,
            y: clampedY,
            width: toastSize.width,
            height: toastSize.height
        )
    }

    @objc private func playerItemDidEnd() {
        player.seek(to: .zero)
        scrubber.doubleValue = 0
    }

    private static func formatTime(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    override func close() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let undoRedoKeyMonitor {
            NSEvent.removeMonitor(undoRedoKeyMonitor)
            self.undoRedoKeyMonitor = nil
        }
        super.close()
    }

    private func updatePlayPauseButton(playing: Bool) {
        let symbol = playing ? "pause.fill" : "play.fill"
        let cfg = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        playPauseButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: playing ? "Pause" : "Play")?
            .withSymbolConfiguration(cfg)
    }

    // MARK: - Save

    @objc private func saveAndShowInFinder() {
        guard !isSaving else { return }
        player.pause()
        isSaving = true
        saveButton.isEnabled = false
        saveButton.title = "Saving…"

        AnnotatedVideoExporter.export(sourceURL: videoURL, canvas: canvas) { [weak self] result in
            guard let self else { return }
            self.isSaving = false
            self.saveButton.isEnabled = true
            self.saveButton.title = "Save and show in Finder"

            switch result {
            case .success(let url):
                NSWorkspace.shared.activateFileViewerSelecting([url])
            case .failure(let error):
                let alert = NSAlert()
                alert.messageText = "Could Not Save Video"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
}
