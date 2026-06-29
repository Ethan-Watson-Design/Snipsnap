//
//  CaptureBar.swift
//  Snipsnap
//

import AppKit
import AVFoundation
import ScreenCaptureKit
import UniformTypeIdentifiers

// MARK: - CaptureMode

enum CaptureMode: Equatable {
    case screenshotRegion
    case screenshotWindow
    case screenshotFullScreen
    case recordFullScreen
    case recordWindow
    case recordRegion

    var isRecording: Bool {
        self == .recordFullScreen || self == .recordWindow || self == .recordRegion
    }
}

// MARK: - CaptureBarModeButton

private final class CaptureBarModeButton: NSControl {
    let mode: CaptureMode

    var isActiveMode: Bool = false {
        didSet { updateLook() }
    }

    private let highlightLayer = CALayer()
    private let iconView = NSImageView()
    private let labelField = NSTextField(labelWithString: "")

    init(mode: CaptureMode, sfSymbol: String, label: String) {
        self.mode = mode
        super.init(frame: .zero)
        wantsLayer = true
        highlightLayer.cornerRadius = 8
        layer?.addSublayer(highlightLayer)

        let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        iconView.image = NSImage(systemSymbolName: sfSymbol, accessibilityDescription: label)?
            .withSymbolConfiguration(cfg)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .labelColor

        labelField.stringValue = label
        labelField.font = NSFont.systemFont(ofSize: 9.5, weight: .regular)
        labelField.alignment = .center
        labelField.textColor = .labelColor
        labelField.isBezeled = false
        labelField.isEditable = false
        labelField.drawsBackground = false
        labelField.isSelectable = false

        addSubview(iconView)
        addSubview(labelField)
        updateLook()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func layout() {
        super.layout()
        highlightLayer.frame = bounds.insetBy(dx: 4, dy: 6)

        let padTop: CGFloat = 8
        let iconSide: CGFloat = 18
        let gap: CGFloat = 4
        let labelH: CGFloat = 12

        iconView.frame = NSRect(
            x: (bounds.width - iconSide) / 2,
            y: bounds.height - padTop - iconSide,
            width: iconSide,
            height: iconSide
        )
        labelField.frame = NSRect(
            x: 4,
            y: iconView.frame.minY - gap - labelH,
            width: bounds.width - 8,
            height: labelH
        )
    }

    override func mouseUp(with event: NSEvent) {
        guard let window, event.window == window else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        _ = target?.perform(action, with: self)
    }

    private func updateLook() {
        highlightLayer.backgroundColor = isActiveMode
            ? NSColor.black.withAlphaComponent(0.18).cgColor
            : .clear
    }
}

// MARK: - CaptureBarMediaButton

/// macOS screenshot-style control: icon + chevron, opens a popup menu on click.
private final class CaptureBarMediaButton: NSControl {
    var isMediaActive = false {
        didSet { updateHighlight() }
    }

    private let activeSymbol: String
    private let inactiveSymbol: String
    private let highlightLayer = CALayer()
    private let chevronView = NSImageView()
    private let iconView = NSImageView()
    private var isHovered = false

    init(baseSymbol: String, activeSymbol: String, inactiveSymbol: String, accessibilityLabel: String) {
        self.activeSymbol = activeSymbol
        self.inactiveSymbol = inactiveSymbol
        super.init(frame: .zero)
        wantsLayer = true
        toolTip = accessibilityLabel

        highlightLayer.cornerRadius = 8
        layer?.addSublayer(highlightLayer)

        chevronView.imageScaling = .scaleProportionallyDown
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(chevronView)
        addSubview(iconView)

        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateHighlight()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateHighlight()
    }

    override func layout() {
        super.layout()
        let padTop: CGFloat = 8
        let chevronSize = NSSize(width: 8, height: 5)
        let iconSide: CGFloat = 18
        let gap: CGFloat = 3

        chevronView.frame = NSRect(
            x: (bounds.width - chevronSize.width) / 2,
            y: bounds.height - padTop - chevronSize.height,
            width: chevronSize.width,
            height: chevronSize.height
        )
        iconView.frame = NSRect(
            x: (bounds.width - iconSide) / 2,
            y: chevronView.frame.minY - gap - iconSide,
            width: iconSide,
            height: iconSide
        )

        let highlightPad: CGFloat = 3
        let contentRect = iconView.frame.union(chevronView.frame)
        highlightLayer.frame = contentRect
            .insetBy(dx: -highlightPad, dy: -highlightPad)
            .intersection(bounds.insetBy(dx: 1, dy: 1))
    }

    override func mouseUp(with event: NSEvent) {
        guard let window, event.window == window else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        _ = target?.perform(action, with: self)
    }

    private func updateAppearance() {
        let symbol = isMediaActive ? activeSymbol : inactiveSymbol
        let cfg = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        iconView.contentTintColor = isMediaActive ? .systemBlue : .labelColor

        let chevronCfg = NSImage.SymbolConfiguration(pointSize: 6, weight: .bold)
        chevronView.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil)?
            .withSymbolConfiguration(chevronCfg)
        chevronView.contentTintColor = .secondaryLabelColor
        updateHighlight()
    }

    private func updateHighlight() {
        if isMediaActive {
            highlightLayer.backgroundColor = NSColor.black.withAlphaComponent(0.16).cgColor
        } else if isHovered {
            highlightLayer.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
        } else {
            highlightLayer.backgroundColor = .clear
        }
    }
}

// MARK: - CaptureBarWindowPicker

private final class CaptureBarWindowPickerCell: NSButtonCell {
    private let padding = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)

    private func padded(_ rect: NSRect) -> NSRect {
        NSRect(
            x: rect.origin.x + padding.left,
            y: rect.origin.y + padding.bottom,
            width: rect.width - padding.left - padding.right,
            height: rect.height - padding.top - padding.bottom
        )
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        super.titleRect(forBounds: padded(rect))
    }

    override func imageRect(forBounds rect: NSRect) -> NSRect {
        super.imageRect(forBounds: padded(rect))
    }
}

/// Full-width picker shown above the capture bar when recording a window.
private final class CaptureBarWindowPicker: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let pickerCell = CaptureBarWindowPickerCell(textCell: "")
        pickerCell.isBordered = false
        cell = pickerCell
        title = "Select a window…"
        imagePosition = .imageRight
        image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Choose window")
        font = NSFont.systemFont(ofSize: 13, weight: .medium)
        alignment = .left
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        contentTintColor = .labelColor
        lineBreakMode = .byTruncatingTail
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - CaptureMediaDevices

private enum CaptureMediaDevices {
    static func videoDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    static func audioInputDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    static func defaultVideoDeviceID() -> String? {
        let preferred = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
        return preferred?.uniqueID ?? videoDevices().first?.uniqueID
    }

    static func localizedName(for device: AVCaptureDevice) -> String {
        device.localizedName
    }
}

// MARK: - CaptureBar

final class CaptureBar: NSPanel {

    private static var instance: CaptureBar?

    /// True while the capture bar is intentionally on screen (set before async preview work).
    private(set) static var isPresented = false

    /// Read-only access to the active bar (nil until first `show()` call).
    static var shared: CaptureBar? { instance }

    private var selectedMode: CaptureMode = .screenshotRegion {
        didSet { refreshSelection() }
    }

    private var modeButtons: [(CaptureMode, CaptureBarModeButton)] = []
    private weak var captureButton: NSButton?
    private weak var cameraButton: CaptureBarMediaButton?
    private weak var backgroundButton: CaptureBarMediaButton?
    private weak var systemAudioButton: CaptureBarMediaButton?
    private weak var micButton: CaptureBarMediaButton?
    private weak var optionsMediaSeparator: NSBox?
    private var escapeGlobalMonitor: Any?
    private var escapeLocalMonitor: Any?

    private let barHeight: CGFloat = 64
    private let pickerRowHeight: CGFloat = 44
    private let pickerGap: CGFloat = 6
    private let barWidth: CGFloat
    private weak var barEffectView: NSVisualEffectView?
    private weak var optionsRow: NSVisualEffectView?
    private weak var windowPickerButton: CaptureBarWindowPicker?

    private var recordableWindows: [SCWindow] = []
    private var selectedRecordWindowID: CGWindowID?
    private var selectedRegionRect: CGRect?
    private var recordableWindowsLoadGeneration = 0

    private var showsWindowPicker: Bool {
        selectedMode == .recordWindow || selectedMode == .screenshotWindow
    }

    private var showsOptionsRow: Bool {
        selectedMode.isRecording || selectedMode == .screenshotWindow
    }

    private var showsRecordingMediaControls: Bool {
        selectedMode.isRecording
    }

    private var isRegionMode: Bool {
        selectedMode == .screenshotRegion || selectedMode == .recordRegion
    }

    /// Selected camera device ID; nil means camera is off.
    private var selectedCameraID: String? = CaptureMediaDevices.defaultVideoDeviceID()
    private var cameraStyle: CameraPreviewStyle = .square
    private var cameraBackground: CameraBackgroundStyle = .none
    private var recordingBackground: RecordingBackgroundStyle = .none
    /// Selected mic device ID; nil means mic is off.
    private var selectedMicID: String? = nil
    private var systemAudioEnabled = false

    /// Legacy computed property — true when a camera device is selected.
    var cameraEnabled: Bool { selectedCameraID != nil }
    var micEnabled: Bool { selectedMicID != nil }

    // MARK: - Entry Points

    static func show() {
        DispatchQueue.main.async {
            if instance == nil {
                instance = CaptureBar()
            }
            isPresented = true
            instance?.selectedMode = .screenshotRegion
            instance?.repositionOnScreen()
            instance?.startEscapeMonitor()
            instance?.makeKeyAndOrderFront(nil)
        }
    }

    static func dismiss() {
        RegionSelector.hide()
        dismissForRecording(hideCameraOverlay: true)
    }

    /// Hides the capture bar when starting a recording. Keeps the camera overlay visible
    /// so ScreenCaptureKit can include it in full-screen recordings.
    static func dismissForRecording(hideCameraOverlay: Bool = false) {
        let dismiss = {
            isPresented = false
            guard let bar = instance else { return }
            bar.stopEscapeMonitor()
            RecordingBackgroundPreviewWindow.hide()
            if hideCameraOverlay {
                CameraPreviewWindow.hide()
            }
            bar.orderOut(nil)
        }
        if Thread.isMainThread {
            dismiss()
        } else {
            DispatchQueue.main.async {
                dismiss()
            }
        }
    }

    /// Restores default media settings after a recording ends.
    static func resetActiveCamera() {
        DispatchQueue.main.async {
            guard let bar = instance else { return }
            bar.selectedCameraID = CaptureMediaDevices.defaultVideoDeviceID()
            bar.cameraStyle = .square
            bar.cameraBackground = .none
            bar.recordingBackground = .none
            bar.selectedMicID = nil
            bar.systemAudioEnabled = false
            bar.updateMediaButtonAppearances()
            RecordingBackgroundPreviewWindow.hide()
            CameraPreviewWindow.hide()
            if isPresented, bar.selectedMode.isRecording {
                bar.applyRecordingPreview()
            }
        }
    }

    override func orderOut(_ sender: Any?) {
        CaptureBar.isPresented = false
        RecordingBackgroundPreviewWindow.hide()
        super.orderOut(sender)
    }

    // MARK: - Init

    private init() {
        let layout = CaptureBar.computeBarLayout()
        barWidth = layout.totalWidth

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level.popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeKey: Bool { true }

    // MARK: - Build UI

    private struct BarLayout {
        let totalWidth: CGFloat
        let horizontalPad: CGFloat
    }

    private static func computeBarLayout() -> BarLayout {
        let hPad: CGFloat = 12
        let btnW: CGFloat = 58
        let sepPad: CGFloat = 6
        let sepW: CGFloat = 1
        let captureW: CGFloat = 82

        let allButtonCount = 6
        let separatorCount = 2
        let totalW = hPad
                   + CGFloat(allButtonCount) * btnW
                   + CGFloat(separatorCount) * (sepW + sepPad * 2)
                   + captureW
                   + hPad
        return BarLayout(totalWidth: totalW, horizontalPad: hPad)
    }

    private static let mediaToggleW: CGFloat = 32
    private static let mediaToggleGap: CGFloat = 4
    private static let mediaControlCount = 4

    private static var mediaControlsWidth: CGFloat {
        let count = CGFloat(mediaControlCount)
        return count * mediaToggleW + (count - 1) * mediaToggleGap
    }

    private func buildUI() {
        let barH = barHeight
        let btnW:       CGFloat = 58
        let btnH:       CGFloat = 48
        let hPad = Self.computeBarLayout().horizontalPad
        let captureW:   CGFloat = 82
        let captureH:   CGFloat = 30
        let sepPad:     CGFloat = 6
        let sepW:       CGFloat = 1
        let toggleW:    CGFloat = Self.mediaToggleW
        let toggleGap:  CGFloat = Self.mediaToggleGap
        let totalW = barWidth

        typealias BSpec = (CaptureMode, String, String)
        let groups: [[BSpec]] = [
            [
                (.screenshotRegion,     "rectangle.dashed",   "Region"),
                (.screenshotWindow,     "macwindow",          "Window"),
                (.screenshotFullScreen, "rectangle.fill",     "Full Screen"),
            ],
            [
                (.recordFullScreen,     "display",            "Full Screen"),
                (.recordWindow,         "macwindow",          "Window"),
                (.recordRegion,         "record.circle.fill", "Region"),
            ],
        ]

        let root = NSView(frame: NSRect(x: 0, y: 0, width: totalW, height: barH))
        contentView = root

        let vfx = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: totalW, height: barH))
        vfx.material = .menu
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = 12
        vfx.layer?.masksToBounds = true
        root.addSubview(vfx)
        barEffectView = vfx

        let optionsRowView = NSVisualEffectView(frame: NSRect(
            x: 0,
            y: barH + pickerGap,
            width: totalW,
            height: pickerRowHeight
        ))
        optionsRowView.material = .menu
        optionsRowView.blendingMode = .behindWindow
        optionsRowView.state = .active
        optionsRowView.wantsLayer = true
        optionsRowView.layer?.cornerRadius = 10
        optionsRowView.layer?.masksToBounds = true
        optionsRowView.isHidden = true
        root.addSubview(optionsRowView)
        optionsRow = optionsRowView

        let pickerH: CGFloat = 32
        let pickerBtn = CaptureBarWindowPicker(frame: CGRect(
            x: hPad,
            y: (pickerRowHeight - pickerH) / 2,
            width: totalW - hPad * 2,
            height: pickerH
        ))
        pickerBtn.target = self
        pickerBtn.action = #selector(windowPickerClicked(_:))
        optionsRowView.addSubview(pickerBtn)
        windowPickerButton = pickerBtn

        let mediaBtnY: CGFloat = (pickerRowHeight - 36) / 2
        var mediaX = totalW - hPad - Self.mediaControlsWidth

        // Camera popup
        let camBtn = CaptureBarMediaButton(
            baseSymbol: "video",
            activeSymbol: "video.fill",
            inactiveSymbol: "video",
            accessibilityLabel: "Camera"
        )
        camBtn.frame = CGRect(x: mediaX, y: mediaBtnY, width: toggleW, height: 36)
        camBtn.target = self
        camBtn.action = #selector(cameraMenuClicked(_:))
        optionsRowView.addSubview(camBtn)
        cameraButton = camBtn
        mediaX += toggleW + toggleGap

        // Recording background popup
        let bgBtn = CaptureBarMediaButton(
            baseSymbol: "photo.on.rectangle.angled",
            activeSymbol: "photo.on.rectangle.angled",
            inactiveSymbol: "photo.on.rectangle",
            accessibilityLabel: "Background"
        )
        bgBtn.frame = CGRect(x: mediaX, y: mediaBtnY, width: toggleW, height: 36)
        bgBtn.target = self
        bgBtn.action = #selector(backgroundMenuClicked(_:))
        optionsRowView.addSubview(bgBtn)
        backgroundButton = bgBtn
        mediaX += toggleW + toggleGap

        // System audio popup
        let audioBtn = CaptureBarMediaButton(
            baseSymbol: "speaker.wave.2",
            activeSymbol: "speaker.wave.2.fill",
            inactiveSymbol: "speaker.wave.2",
            accessibilityLabel: "System Audio"
        )
        audioBtn.frame = CGRect(x: mediaX, y: mediaBtnY, width: toggleW, height: 36)
        audioBtn.target = self
        audioBtn.action = #selector(systemAudioMenuClicked(_:))
        optionsRowView.addSubview(audioBtn)
        systemAudioButton = audioBtn
        mediaX += toggleW + toggleGap

        // Microphone popup
        let micBtn = CaptureBarMediaButton(
            baseSymbol: "mic",
            activeSymbol: "mic.fill",
            inactiveSymbol: "mic",
            accessibilityLabel: "Microphone"
        )
        micBtn.frame = CGRect(x: mediaX, y: mediaBtnY, width: toggleW, height: 36)
        micBtn.target = self
        micBtn.action = #selector(micMenuClicked(_:))
        optionsRowView.addSubview(micBtn)
        micButton = micBtn

        let optionsMediaSep = NSBox(frame: .zero)
        optionsMediaSep.boxType = NSBox.BoxType.separator
        optionsRowView.addSubview(optionsMediaSep)
        optionsMediaSeparator = optionsMediaSep

        setContentSize(NSSize(width: totalW, height: barH))

        var x = hPad
        let modeBtnY: CGFloat = 8

        for group in groups {
            for spec in group {
                let btn = CaptureBarModeButton(mode: spec.0, sfSymbol: spec.1, label: spec.2)
                btn.frame = CGRect(x: x, y: modeBtnY, width: btnW, height: btnH)
                btn.target = self
                btn.action = #selector(modeTapped(_:))
                vfx.addSubview(btn)
                modeButtons.append((spec.0, btn))
                x += btnW
            }
            x += sepPad
            let sep = NSBox(frame: CGRect(x: x, y: 12, width: sepW, height: barH - 24))
            sep.boxType = NSBox.BoxType.separator
            vfx.addSubview(sep)
            x += sepW + sepPad
        }

        let capBtn = NSButton(frame: CGRect(
            x: x,
            y: (barH - captureH) / 2,
            width: captureW,
            height: captureH
        ))
        capBtn.title = "Capture"
        capBtn.isBordered = false
        capBtn.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        capBtn.wantsLayer = true
        capBtn.layer?.backgroundColor = NSColor.systemBlue.cgColor
        capBtn.layer?.cornerRadius = captureH / 2
        capBtn.contentTintColor = NSColor.white
        capBtn.target = self
        capBtn.action = #selector(captureTapped)
        vfx.addSubview(capBtn)
        captureButton = capBtn

        updateMediaButtonAppearances()
        refreshSelection()
    }

    // MARK: - Escape

    private func startEscapeMonitor() {
        stopEscapeMonitor()
        escapeGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return }
            CaptureBar.dismiss()
        }
        escapeLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible, event.keyCode == 53 else { return event }
            CaptureBar.dismiss()
            return nil
        }
    }

    private func stopEscapeMonitor() {
        if let monitor = escapeGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            escapeGlobalMonitor = nil
        }
        if let monitor = escapeLocalMonitor {
            NSEvent.removeMonitor(monitor)
            escapeLocalMonitor = nil
        }
    }

    override func cancelOperation(_ sender: Any?) {
        CaptureBar.dismiss()
    }

    // MARK: - Position

    private func repositionOnScreen() {
        guard let screen = NSScreen.main else { return }
        let vis = screen.visibleFrame
        let sz = frame.size
        let x = (vis.midX - sz.width / 2).rounded()
        let y = (vis.minY + 24).rounded()
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Resizes content while keeping the window's bottom edge fixed so the bar does not shift.
    private func setContentSizeKeepingBottomFixed(_ size: NSSize) {
        let bottomY = frame.minY
        var newFrame = frameRect(forContentRect: NSRect(origin: .zero, size: size))
        newFrame.origin.x = frame.origin.x
        newFrame.origin.y = bottomY
        setFrame(newFrame, display: true)
    }

    // MARK: - Actions

    @objc private func modeTapped(_ sender: NSControl) {
        guard let btn = sender as? CaptureBarModeButton else { return }
        selectedMode = btn.mode
    }

    @objc private func captureTapped() {
        let mode = selectedMode
        let micOn = micEnabled
        let micID = selectedMicID
        let sysAudio = systemAudioEnabled
        let recBackground = recordingBackground
        let camID = selectedCameraID
        let camStyle = cameraStyle

        switch mode {
        case .screenshotRegion:
            guard let rect = selectedRegionRect else { return }
            RegionSelector.hide()
            CaptureBar.dismiss()
            ScreenshotEngine.captureRegion(rect) { img in
                guard let img else { return }
                CaptureBar.finishScreenshot(img)
            }

        case .screenshotWindow:
            guard let windowID = selectedRecordWindowID else { return }
            RegionSelector.hide()
            CaptureBar.dismiss()
            Task {
                await WindowSelector.activateWindow(windowID)
                await MainActor.run {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        ScreenshotEngine.captureWindow(windowID) { img in
                            guard let img else { return }
                            CaptureBar.finishScreenshot(img)
                        }
                    }
                }
            }

        case .screenshotFullScreen:
            guard let rect = NSScreen.main?.frame else { return }
            RegionSelector.hide()
            CaptureBar.dismiss()
            ScreenshotEngine.captureRegion(rect) { img in
                guard let img else { return }
                CaptureBar.finishScreenshot(img)
            }

        case .recordWindow:
            guard let windowID = selectedRecordWindowID else { return }
            RegionSelector.hide()
            CaptureBar.dismissForRecording()
            Task {
                await WindowSelector.activateWindow(windowID)
                await MainActor.run {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        CaptureBar.wireRecordingPreviewForCapture()
                        CaptureBar.executeRecording(
                            captureTarget: .window(windowID),
                            recordingBackground: recBackground,
                            cameraDeviceID: camID,
                            cameraStyle: camStyle,
                            micEnabled: micOn,
                            systemAudioEnabled: sysAudio,
                            micDeviceID: micID
                        )
                    }
                }
            }

        case .recordRegion:
            guard let rect = selectedRegionRect else { return }
            RegionSelector.hide()
            CaptureBar.dismissForRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                CaptureBar.executeRecording(
                    captureTarget: .region(rect),
                    recordingBackground: recBackground,
                    cameraDeviceID: camID,
                    cameraStyle: camStyle,
                    micEnabled: micOn,
                    systemAudioEnabled: sysAudio,
                    micDeviceID: micID
                )
            }

        case .recordFullScreen:
            RegionSelector.hide()
            CaptureBar.dismissForRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                CaptureBar.wireRecordingPreviewForCapture()
                CaptureBar.executeRecording(
                    captureTarget: .fullScreen,
                    recordingBackground: recBackground,
                    cameraDeviceID: camID,
                    cameraStyle: camStyle,
                    micEnabled: micOn,
                    systemAudioEnabled: sysAudio,
                    micDeviceID: micID
                )
            }
        }
    }

    /// Hands live composited frames to the preview thumbnail while RecordingEngine owns capture.
    private static func wireRecordingPreviewForCapture() {
        guard RecordingBackgroundPreviewWindow.isVisible else { return }
        RecordingBackgroundPreviewWindow.transitionToRecording()
        RecordingEngine.shared.onCompositedPreviewFrame = { image in
            RecordingBackgroundPreviewWindow.updateFrame(image)
        }
    }

    // MARK: - Capture Execution

    private static func executeRecording(
        captureTarget: RecordingCaptureTarget,
        recordingBackground: RecordingBackgroundStyle = .none,
        cameraDeviceID: String? = nil,
        cameraStyle: CameraPreviewStyle = .square,
        micEnabled: Bool = false,
        systemAudioEnabled: Bool = false,
        micDeviceID: String? = nil
    ) {
        let engineCamera = captureTarget != .fullScreen ? cameraDeviceID : nil
        let usesOnScreenCamera = cameraDeviceID != nil && captureTarget == .fullScreen

        if engineCamera != nil {
            CameraPreviewWindow.hide()
        } else if let cameraDeviceID {
            let camBackground = instance?.cameraBackground ?? .none
            CameraPreviewWindow.show(
                style: cameraStyle,
                deviceID: cameraDeviceID,
                background: camBackground
            )
        }

        let start = {
            RecordingEngine.shared.startRecording(
                captureTarget: captureTarget,
                recordingBackground: recordingBackground,
                cameraDeviceID: engineCamera,
                cameraStyle: cameraStyle,
                micEnabled: micEnabled,
                systemAudioEnabled: systemAudioEnabled,
                micDeviceID: micDeviceID
            )
        }

        if usesOnScreenCamera {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                start()
            }
        } else {
            start()
        }
    }

    private static func finishScreenshot(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        CaptureHistory.shared.add(.screenshot(image))
        (NSApp.delegate as? AppDelegate)?.rebuildMenu()
        ToastWindow.show(image: image) {
            AnnotationWindow.show(image: image)
        }
    }

    // MARK: - Media Popup Menus

    @objc private func cameraMenuClicked(_ sender: NSControl) {
        let menu = NSMenu()

        let noneItem = NSMenuItem(title: "None", action: #selector(selectCamera(_:)), keyEquivalent: "")
        noneItem.target = self
        noneItem.representedObject = nil as String?
        noneItem.state = selectedCameraID == nil ? .on : .off
        menu.addItem(noneItem)

        let devices = CaptureMediaDevices.videoDevices()
        if !devices.isEmpty {
            menu.addItem(.separator())

            for device in devices {
                let item = NSMenuItem(
                    title: CaptureMediaDevices.localizedName(for: device),
                    action: #selector(selectCamera(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = device.uniqueID
                item.state = selectedCameraID == device.uniqueID ? .on : .off
                menu.addItem(item)
            }

            menu.addItem(.separator())

            let squareItem = NSMenuItem(title: "Square", action: #selector(selectCameraStyle(_:)), keyEquivalent: "")
            squareItem.target = self
            squareItem.tag = 0
            squareItem.state = cameraStyle == .square ? .on : .off
            menu.addItem(squareItem)

            let verticalItem = NSMenuItem(title: "Vertical Strip", action: #selector(selectCameraStyle(_:)), keyEquivalent: "")
            verticalItem.target = self
            verticalItem.tag = 1
            verticalItem.state = cameraStyle == .vertical ? .on : .off
            menu.addItem(verticalItem)

            menu.addItem(.separator())

            for style in [CameraBackgroundStyle.none, .blur] {
                let item = NSMenuItem(title: style.menuTitle, action: #selector(selectCameraBackground(_:)), keyEquivalent: "")
                item.target = self
                item.tag = cameraBackgroundTag(for: style)
                item.state = cameraBackground == style ? .on : .off
                menu.addItem(item)
            }
        }

        popMenu(menu, from: sender)
    }

    @objc private func backgroundMenuClicked(_ sender: NSControl) {
        let menu = NSMenu()

        for style in [RecordingBackgroundStyle.none, .warm, .cool, .midnight] {
            let item = NSMenuItem(title: style.menuTitle, action: #selector(selectRecordingBackground(_:)), keyEquivalent: "")
            item.target = self
            item.tag = recordingBackgroundTag(for: style)
            item.state = recordingBackground == style ? .on : .off
            menu.addItem(item)
        }

        let customRecBg = NSMenuItem(title: "Custom Image…", action: #selector(selectCustomRecordingBackground(_:)), keyEquivalent: "")
        customRecBg.target = self
        if case .custom = recordingBackground { customRecBg.state = .on }
        menu.addItem(customRecBg)

        popMenu(menu, from: sender)
    }

    @objc private func systemAudioMenuClicked(_ sender: NSControl) {
        let menu = NSMenu()

        let noneItem = NSMenuItem(title: "None", action: #selector(selectSystemAudio(_:)), keyEquivalent: "")
        noneItem.target = self
        noneItem.tag = 0
        noneItem.state = !systemAudioEnabled ? .on : .off
        menu.addItem(noneItem)

        let onItem = NSMenuItem(title: "System Audio", action: #selector(selectSystemAudio(_:)), keyEquivalent: "")
        onItem.target = self
        onItem.tag = 1
        onItem.state = systemAudioEnabled ? .on : .off
        menu.addItem(onItem)

        popMenu(menu, from: sender)
    }

    @objc private func micMenuClicked(_ sender: NSControl) {
        let menu = NSMenu()

        let noneItem = NSMenuItem(title: "None", action: #selector(selectMic(_:)), keyEquivalent: "")
        noneItem.target = self
        noneItem.representedObject = nil as String?
        noneItem.state = selectedMicID == nil ? .on : .off
        menu.addItem(noneItem)

        let devices = CaptureMediaDevices.audioInputDevices()
        if !devices.isEmpty {
            menu.addItem(.separator())
            for device in devices {
                let item = NSMenuItem(
                    title: CaptureMediaDevices.localizedName(for: device),
                    action: #selector(selectMic(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = device.uniqueID
                item.state = selectedMicID == device.uniqueID ? .on : .off
                menu.addItem(item)
            }
        }

        popMenu(menu, from: sender)
    }

    @objc private func selectCamera(_ sender: NSMenuItem) {
        selectedCameraID = sender.representedObject as? String
        updateMediaButtonAppearances()
        applyRecordingPreview()
    }

    @objc private func selectCameraStyle(_ sender: NSMenuItem) {
        guard selectedCameraID != nil else { return }
        cameraStyle = sender.tag == 1 ? .vertical : .square
        applyRecordingPreview()
    }

    @objc private func selectCameraBackground(_ sender: NSMenuItem) {
        guard selectedCameraID != nil else { return }
        cameraBackground = cameraBackgroundStyle(for: sender.tag)
        applyRecordingPreview()
    }

    @objc private func selectRecordingBackground(_ sender: NSMenuItem) {
        recordingBackground = recordingBackgroundStyle(for: sender.tag)
        updateMediaButtonAppearances()
        applyRecordingPreview()
    }

    @objc private func selectCustomRecordingBackground(_ sender: NSMenuItem) {
        pickImage { [weak self] path in
            guard let self, let path else { return }
            self.recordingBackground = .custom(path: path)
            self.updateMediaButtonAppearances()
            self.applyRecordingPreview()
        }
    }

    private func cameraBackgroundTag(for style: CameraBackgroundStyle) -> Int {
        style == .blur ? 1 : 0
    }

    private func cameraBackgroundStyle(for tag: Int) -> CameraBackgroundStyle {
        tag == 1 ? .blur : .none
    }

    private func recordingBackgroundTag(for style: RecordingBackgroundStyle) -> Int {
        switch style {
        case .none: return 0
        case .warm: return 1
        case .cool: return 2
        case .midnight: return 3
        case .custom: return 4
        }
    }

    private func recordingBackgroundStyle(for tag: Int) -> RecordingBackgroundStyle {
        switch tag {
        case 1: return .warm
        case 2: return .cool
        case 3: return .midnight
        default: return .none
        }
    }

    private func pickImage(completion: @escaping (String?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            completion(response == .OK ? panel.url?.path : nil)
        }
    }

    @objc private func selectSystemAudio(_ sender: NSMenuItem) {
        systemAudioEnabled = sender.tag == 1
        updateMediaButtonAppearances()
    }

    @objc private func selectMic(_ sender: NSMenuItem) {
        selectedMicID = sender.representedObject as? String
        updateMediaButtonAppearances()
    }

    private func popMenu(_ menu: NSMenu, from button: NSView, above: Bool = false) {
        if above {
            menu.font = NSFont.systemFont(ofSize: 13)
        }
        let y = above ? button.bounds.maxY : button.bounds.maxY + 2
        let loc = NSPoint(x: button.bounds.midX, y: y)
        menu.popUp(positioning: above ? menu.items.last : nil, at: loc, in: button)
    }

    // MARK: - Window Picker

    @objc private func windowPickerClicked(_ sender: NSButton) {
        Task {
            let windows = await WindowSelector.fetchRecordableWindows()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.recordableWindows = windows
                if self.selectedRecordWindowID == nil
                    || !windows.contains(where: { $0.windowID == self.selectedRecordWindowID }) {
                    self.selectedRecordWindowID = WindowSelector.defaultWindowID(from: windows)
                }
                self.updateWindowPickerTitle()
                self.updateCaptureButtonState()
                guard !windows.isEmpty else { return }

                let menu = NSMenu()
                for window in windows {
                    let item = NSMenuItem(
                        title: WindowSelector.displayName(for: window),
                        action: #selector(self.selectRecordWindow(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.representedObject = NSNumber(value: window.windowID)
                    item.state = self.selectedRecordWindowID == window.windowID ? .on : .off
                    menu.addItem(item)
                }
                self.popMenu(menu, from: sender, above: true)
            }
        }
    }

    @objc private func selectRecordWindow(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        selectedRecordWindowID = CGWindowID(number.uint32Value)
        updateWindowPickerTitle()
        updateCaptureButtonState()
        applyRecordingPreview()
    }

    private func loadRecordableWindows() {
        recordableWindowsLoadGeneration += 1
        let generation = recordableWindowsLoadGeneration
        Task {
            let windows = await WindowSelector.fetchRecordableWindows()
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard generation == self.recordableWindowsLoadGeneration else { return }
                self.recordableWindows = windows
                if self.selectedRecordWindowID == nil
                    || !windows.contains(where: { $0.windowID == self.selectedRecordWindowID }) {
                    self.selectedRecordWindowID = WindowSelector.defaultWindowID(from: windows)
                }
                self.updateWindowPickerTitle()
                self.updateCaptureButtonState()
                self.applyRecordingPreview()
            }
        }
    }

    private func updateWindowPickerTitle() {
        if let id = selectedRecordWindowID,
           let window = recordableWindows.first(where: { $0.windowID == id }) {
            windowPickerButton?.title = WindowSelector.displayName(for: window)
        } else if recordableWindows.isEmpty {
            windowPickerButton?.title = "Loading windows…"
        } else {
            windowPickerButton?.title = "Select a window…"
        }
    }

    private func updateWindowPickerVisibility() {
        optionsRow?.isHidden = !showsOptionsRow

        windowPickerButton?.isHidden = !showsWindowPicker
        let showMediaSeparator = showsWindowPicker && showsRecordingMediaControls
        optionsMediaSeparator?.isHidden = !showMediaSeparator

        for button in [cameraButton, backgroundButton, systemAudioButton, micButton].compactMap({ $0 }) {
            button.isHidden = !showsRecordingMediaControls
        }

        layoutOptionsRow()

        let totalH = showsOptionsRow ? (barHeight + pickerGap + pickerRowHeight) : barHeight
        let newSize = NSSize(width: barWidth, height: totalH)
        if contentView?.frame.size != newSize {
            setContentSizeKeepingBottomFixed(newSize)
        }

        if showsWindowPicker {
            loadRecordableWindows()
        } else {
            updateCaptureButtonState()
        }
    }

    private func updateCaptureButtonState() {
        switch selectedMode {
        case .screenshotRegion, .recordRegion:
            captureButton?.isEnabled = selectedRegionRect != nil
        case .screenshotWindow, .recordWindow:
            captureButton?.isEnabled = selectedRecordWindowID != nil
        default:
            captureButton?.isEnabled = true
        }
    }

    private func applyRegionSelector() {
        if isRegionMode {
            RegionSelector.showInteractive(initialRect: selectedRegionRect) { [weak self] rect in
                guard let self else { return }
                self.selectedRegionRect = rect
                self.updateCaptureButtonState()
            }
        } else {
            RegionSelector.hide()
            selectedRegionRect = nil
            updateCaptureButtonState()
        }
    }

    private func layoutOptionsRow() {
        guard let optionsRow else { return }
        let hPad = Self.computeBarLayout().horizontalPad
        let totalW = barWidth
        let pickerH: CGFloat = 32
        let toggleW = Self.mediaToggleW
        let toggleGap = Self.mediaToggleGap
        let mediaW = Self.mediaControlsWidth
        let sepPad: CGFloat = 8
        let sepW: CGFloat = 1
        let mediaBtnY: CGFloat = (pickerRowHeight - 36) / 2
        var mediaX: CGFloat

        let showWindowPicker = showsWindowPicker
        let showMediaControls = showsRecordingMediaControls

        if showWindowPicker && showMediaControls {
            let sepX = totalW - hPad - mediaW - sepPad - sepW
            let sepH: CGFloat = pickerRowHeight - 16
            optionsMediaSeparator?.frame = CGRect(x: sepX, y: 8, width: sepW, height: sepH)

            let pickerMaxX = sepX - sepPad
            windowPickerButton?.frame = CGRect(
                x: hPad,
                y: (pickerRowHeight - pickerH) / 2,
                width: max(120, pickerMaxX - hPad),
                height: pickerH
            )

            mediaX = totalW - hPad - mediaW
        } else if showWindowPicker {
            windowPickerButton?.frame = CGRect(
                x: hPad,
                y: (pickerRowHeight - pickerH) / 2,
                width: totalW - hPad * 2,
                height: pickerH
            )
            optionsMediaSeparator?.frame = .zero
            mediaX = totalW
        } else {
            windowPickerButton?.frame = .zero
            mediaX = (totalW - mediaW) / 2
        }

        for button in [cameraButton, backgroundButton, systemAudioButton, micButton].compactMap({ $0 }) {
            button.frame = CGRect(x: mediaX, y: mediaBtnY, width: toggleW, height: 36)
            mediaX += toggleW + toggleGap
        }

        optionsRow.frame = NSRect(
            x: 0,
            y: barHeight + pickerGap,
            width: totalW,
            height: pickerRowHeight
        )
    }

    // MARK: - Recording Preview

    private func applyRecordingPreview() {
        guard CaptureBar.isPresented, isVisible else {
            RecordingBackgroundPreviewWindow.hide()
            return
        }

        guard selectedMode.isRecording else {
            RecordingBackgroundPreviewWindow.hide()
            return
        }

        switch selectedMode {
        case .recordWindow:
            guard selectedRecordWindowID != nil else {
                RecordingBackgroundPreviewWindow.hide()
                return
            }
        case .recordFullScreen:
            break
        case .recordRegion:
            RecordingBackgroundPreviewWindow.hide()
            return
        default:
            RecordingBackgroundPreviewWindow.hide()
            return
        }

        let config = RecordingBackgroundPreviewWindow.Configuration(
            captureMode: selectedMode,
            windowID: selectedRecordWindowID,
            background: recordingBackground,
            cameraDeviceID: selectedCameraID,
            cameraStyle: cameraStyle
        )
        RecordingBackgroundPreviewWindow.showThumbnail(configuration: config)
    }

    private func updateMediaButtonAppearances() {
        cameraButton?.isMediaActive = selectedCameraID != nil
        backgroundButton?.isMediaActive = recordingBackground != .none
        systemAudioButton?.isMediaActive = systemAudioEnabled
        micButton?.isMediaActive = selectedMicID != nil
    }

    // MARK: - Refresh

    private func refreshSelection() {
        for (mode, btn) in modeButtons {
            btn.isActiveMode = (mode == selectedMode)
        }
        captureButton?.title = selectedMode.isRecording ? "Record" : "Capture"

        if selectedMode.isRecording {
            applyRecordingPreview()
        } else {
            CameraPreviewWindow.hide()
            RecordingBackgroundPreviewWindow.hide()
        }

        updateWindowPickerVisibility()
        applyRegionSelector()
    }
}
