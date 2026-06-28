//
//  RecordingIndicatorWindow.swift
//  Snipsnap
//
//  A small floating pill that appears at the bottom of the screen while a
//  recording is in progress. It shows the elapsed time and a stop button so
//  the user always has an obvious way to end the recording.
//

import AppKit

// MARK: - RecordingIndicatorWindow

final class RecordingIndicatorWindow: NSPanel {

    // MARK: Shared state

    private static var shared: RecordingIndicatorWindow?

    static func show() {
        DispatchQueue.main.async {
            if shared == nil {
                shared = RecordingIndicatorWindow()
            }
            shared?.startTimer()
            shared?.repositionOnScreen()
            shared?.orderFrontRegardless()
        }
    }

    static func hide() {
        DispatchQueue.main.async {
            shared?.stopTimer()
            shared?.orderOut(nil)
        }
    }

    // MARK: Layout constants

    private let pillH:     CGFloat = 36
    private let pillW:     CGFloat = 168
    private let dotSize:   CGFloat = 10
    private let hPad:      CGFloat = 12
    private let gap:       CGFloat = 7

    // MARK: Subviews

    private weak var dotLayer: CALayer?
    private weak var timerLabel: NSTextField?

    // MARK: Timer

    private var displayLink: CVDisplayLink?
    private var startTime: Date = Date()
    private var elapsedSeconds: Int = 0

    // MARK: Init

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: pillW, height: pillH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        buildUI()
    }

    // MARK: - UI

    private func buildUI() {
        let vfx = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: pillW, height: pillH))
        vfx.material = .hudWindow
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = pillH / 2
        vfx.layer?.masksToBounds = true
        contentView = vfx

        var x: CGFloat = hPad

        // Red pulsing dot
        let dotView = NSView(frame: CGRect(x: x, y: (pillH - dotSize) / 2, width: dotSize, height: dotSize))
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = dotSize / 2
        dotView.layer?.backgroundColor = NSColor.systemRed.cgColor
        vfx.addSubview(dotView)
        dotLayer = dotView.layer
        startPulse(on: dotView.layer!)
        x += dotSize + gap

        // Elapsed time label
        let label = NSTextField(labelWithString: "00:00")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.sizeToFit()
        let labelW: CGFloat = 38
        label.frame = CGRect(x: x, y: (pillH - label.frame.height) / 2, width: labelW, height: label.frame.height)
        vfx.addSubview(label)
        timerLabel = label
        x += labelW + gap

        // Divider
        let divider = NSBox(frame: CGRect(x: x, y: 8, width: 1, height: pillH - 16))
        divider.boxType = .separator
        vfx.addSubview(divider)
        x += 1 + gap

        // Stop button (square icon)
        let stopBtn = NSButton()
        let stopCfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        stopBtn.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop Recording")?
                            .withSymbolConfiguration(stopCfg)
        stopBtn.contentTintColor = .systemRed
        stopBtn.title = ""
        stopBtn.imagePosition = .imageOnly
        stopBtn.isBordered = false
        stopBtn.imageScaling = .scaleProportionallyDown
        let stopW: CGFloat = pillW - x - hPad
        stopBtn.frame = CGRect(x: x, y: (pillH - 24) / 2, width: stopW, height: 24)
        stopBtn.target = self
        stopBtn.action = #selector(stopTapped)
        vfx.addSubview(stopBtn)
    }

    // MARK: - Pulse animation

    private func startPulse(on layer: CALayer) {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.25
        anim.duration = 0.8
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(anim, forKey: "pulse")
    }

    // MARK: - Timer

    private func startTimer() {
        startTime = Date()
        elapsedSeconds = 0
        updateLabel()

        // Use a repeating DispatchSource timer on the main queue for simple 1-second ticks
        let src = DispatchSource.makeTimerSource(queue: .main)
        src.schedule(deadline: .now() + 1, repeating: 1)
        src.setEventHandler { [weak self] in self?.tick() }
        src.resume()
        timerSource = src
    }

    private func stopTimer() {
        timerSource?.cancel()
        timerSource = nil
    }

    private var timerSource: DispatchSourceTimer?

    @objc private func tick() {
        elapsedSeconds += 1
        updateLabel()
    }

    private func updateLabel() {
        let mins = elapsedSeconds / 60
        let secs = elapsedSeconds % 60
        timerLabel?.stringValue = String(format: "%02d:%02d", mins, secs)
    }

    // MARK: - Stop action

    @objc private func stopTapped() {
        (NSApp.delegate as? AppDelegate)?.stopRecording()
    }

    // MARK: - Position

    private func repositionOnScreen() {
        guard let screen = NSScreen.main else { return }
        let vis = screen.visibleFrame
        let x = (vis.midX - pillW / 2).rounded()
        // Sit just below the menu bar so it's visible next to the macOS camera/recording dots.
        let y = (vis.maxY - pillH - 6).rounded()
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
