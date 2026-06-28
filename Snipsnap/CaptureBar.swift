//
//  CaptureBar.swift
//  Snipsnap
//

import AppKit

// MARK: - CaptureMode

enum CaptureMode: Equatable {
    case screenshotRegion
    case screenshotWindow
    case screenshotFullScreen
    case recordFullScreen
    case recordRegion

    var isRecording: Bool {
        self == .recordFullScreen || self == .recordRegion
    }
}

// MARK: - CaptureBarModeButton

private final class CaptureBarModeButton: NSButton {
    let mode: CaptureMode

    var isActiveMode: Bool = false {
        didSet { updateLook() }
    }

    init(mode: CaptureMode, sfSymbol: String, label: String) {
        self.mode = mode
        super.init(frame: .zero)
        let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        image = NSImage(systemSymbolName: sfSymbol, accessibilityDescription: label)?
                    .withSymbolConfiguration(cfg)
        title = label
        imagePosition = .imageAbove
        font = NSFont.systemFont(ofSize: 9.5, weight: .regular)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 6
        imageScaling = .scaleProportionallyDown
        alignment = .center
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateLook() {
        layer?.backgroundColor = isActiveMode
            ? NSColor.white.withAlphaComponent(0.22).cgColor
            : .clear
    }
}

// MARK: - CaptureBar

final class CaptureBar: NSPanel {

    private static var instance: CaptureBar?

    /// Read-only access to the active bar (nil until first `show()` call).
    static var shared: CaptureBar? { instance }

    private var selectedMode: CaptureMode = .screenshotRegion {
        didSet { refreshSelection() }
    }

    private var modeButtons: [(CaptureMode, CaptureBarModeButton)] = []
    private weak var captureButton: NSButton?
    private weak var cameraButton: NSButton?
    private weak var cameraVerticalButton: NSButton?
    private weak var micButton: NSButton?
    private weak var mediaSeparator: NSBox?
    private var localMonitor: Any?

    /// Tracks which camera preview style is active (.none means camera is off).
    private var activeCameraStyle: CameraPreviewStyle? = nil

    /// Legacy computed property — true if either camera mode is on.
    var cameraEnabled: Bool { activeCameraStyle != nil }
    var micEnabled = false

    // MARK: - Entry Points

    static func show() {
        DispatchQueue.main.async {
            if instance == nil {
                instance = CaptureBar()
            }
            instance?.selectedMode = .screenshotRegion
            instance?.repositionOnScreen()
            instance?.makeKeyAndOrderFront(nil)
        }
    }

    static func dismiss() {
        DispatchQueue.main.async {
            instance?.orderOut(nil)
        }
    }

    // MARK: - Init

    private init() {
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

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            if event.keyCode == 53 {
                CaptureBar.dismiss()
                return nil
            }
            return event
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeKey: Bool { true }

    // MARK: - Build UI

    private func buildUI() {
        let barH:       CGFloat = 64
        let btnW:       CGFloat = 58
        let btnH:       CGFloat = 48
        let hPad:       CGFloat = 12
        let captureW:   CGFloat = 82
        let captureH:   CGFloat = 30
        let sepPad:     CGFloat = 6
        let sepW:       CGFloat = 1
        let toggleSize: CGFloat = 36
        let toggleGap:  CGFloat = 4

        typealias BSpec = (CaptureMode, String, String)
        let groups: [[BSpec]] = [
            [
                (.screenshotRegion,     "rectangle.dashed",   "Region"),
                (.screenshotWindow,     "macwindow",          "Window"),
                (.screenshotFullScreen, "rectangle.fill",     "Full Screen"),
            ],
            [
                (.recordFullScreen,     "record.circle",      "Full Screen"),
                (.recordRegion,         "record.circle.fill", "Region"),
            ],
        ]

        let allButtonCount = groups.reduce(0) { $0 + $1.count }
        let separatorCount = groups.count
        // Media slot: separator + camera-bubble + gap + camera-vertical + gap + mic
        let mediaSlotW = (sepW + sepPad * 2)
                       + toggleSize + toggleGap
                       + toggleSize + toggleGap
                       + toggleSize
        let totalW = hPad
                   + CGFloat(allButtonCount) * btnW
                   + CGFloat(separatorCount) * (sepW + sepPad * 2)
                   + mediaSlotW
                   + captureW
                   + hPad

        let vfx = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: totalW, height: barH))
        vfx.material = .menu
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = 12
        vfx.layer?.masksToBounds = true
        contentView = vfx
        setContentSize(NSSize(width: totalW, height: barH))

        var x = hPad
        let btnY = (barH - btnH) / 2

        for group in groups {
            for spec in group {
                let btn = CaptureBarModeButton(mode: spec.0, sfSymbol: spec.1, label: spec.2)
                btn.frame = CGRect(x: x, y: btnY, width: btnW, height: btnH)
                btn.target = self
                btn.action = #selector(modeTapped(_:))
                vfx.addSubview(btn)
                modeButtons.append((spec.0, btn))
                x += btnW
            }
            x += sepPad
            let sep = NSBox(frame: CGRect(x: x, y: 12, width: sepW, height: barH - 24))
            sep.boxType = .separator
            vfx.addSubview(sep)
            x += sepW + sepPad
        }

        // Media section separator
        let mediaSep = NSBox(frame: CGRect(x: x + sepPad, y: 12, width: sepW, height: barH - 24))
        mediaSep.boxType = .separator
        vfx.addSubview(mediaSep)
        mediaSeparator = mediaSep
        x += sepPad + sepW + sepPad

        // Bubble camera toggle
        let camBtn = makeToggleButton(sfSymbol: "video.circle", accessibilityLabel: "Camera")
        camBtn.frame = CGRect(x: x, y: (barH - toggleSize) / 2, width: toggleSize, height: toggleSize)
        camBtn.target = self
        camBtn.action = #selector(cameraBubbleToggled)
        vfx.addSubview(camBtn)
        cameraButton = camBtn
        x += toggleSize + toggleGap

        // Vertical camera toggle
        let camVBtn = makeToggleButton(sfSymbol: "rectangle.portrait", accessibilityLabel: "Vertical Camera")
        camVBtn.frame = CGRect(x: x, y: (barH - toggleSize) / 2, width: toggleSize, height: toggleSize)
        camVBtn.target = self
        camVBtn.action = #selector(cameraVerticalToggled)
        vfx.addSubview(camVBtn)
        cameraVerticalButton = camVBtn
        x += toggleSize + toggleGap

        // Mic toggle
        let micBtn = makeToggleButton(sfSymbol: "mic.circle", accessibilityLabel: "Mic")
        micBtn.frame = CGRect(x: x, y: (barH - toggleSize) / 2, width: toggleSize, height: toggleSize)
        micBtn.target = self
        micBtn.action = #selector(micToggled)
        vfx.addSubview(micBtn)
        micButton = micBtn
        x += toggleSize

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

        refreshSelection()
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

    // MARK: - Actions

    @objc private func modeTapped(_ sender: NSButton) {
        guard let btn = sender as? CaptureBarModeButton else { return }
        selectedMode = btn.mode
    }

    @objc private func captureTapped() {
        let mode  = selectedMode
        let micOn = micEnabled

        CaptureBar.dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // CameraPreviewWindow stays visible and is captured naturally by SCK,
            // so RecordingEngine never needs its own camera session.
            CaptureBar.execute(mode: mode, cameraEnabled: false, micEnabled: micOn)
        }
    }

    // MARK: - Capture Execution

    private static func execute(mode: CaptureMode, cameraEnabled: Bool = false, micEnabled: Bool = false) {
        switch mode {

        case .screenshotRegion, .screenshotWindow:
            RegionSelector.show { rect in
                guard let rect else { return }
                ScreenshotEngine.captureRegion(rect) { img in
                    guard let img else { return }
                    finishScreenshot(img)
                }
            }

        case .screenshotFullScreen:
            guard let rect = NSScreen.main?.frame else { return }
            ScreenshotEngine.captureRegion(rect) { img in
                guard let img else { return }
                finishScreenshot(img)
            }

        case .recordFullScreen, .recordRegion:
            RecordingEngine.shared.startRecording(cameraEnabled: cameraEnabled, micEnabled: micEnabled)
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

    // MARK: - Toggle Button Factory

    private func makeToggleButton(sfSymbol: String, accessibilityLabel: String) -> NSButton {
        let btn = NSButton()
        let cfg = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        btn.image = NSImage(systemSymbolName: sfSymbol, accessibilityDescription: accessibilityLabel)?
                        .withSymbolConfiguration(cfg)
        btn.title = ""
        btn.imagePosition = .imageOnly
        btn.isBordered = false
        btn.imageScaling = .scaleProportionallyDown
        btn.contentTintColor = .labelColor
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 8
        return btn
    }

    // MARK: - Toggle Actions

    @objc private func cameraBubbleToggled() {
        if activeCameraStyle == .bubble {
            activeCameraStyle = nil
            CameraPreviewWindow.hide()
        } else {
            activeCameraStyle = .bubble
            CameraPreviewWindow.show(style: .bubble)
        }
        updateCameraButtonAppearances()
    }

    @objc private func cameraVerticalToggled() {
        if activeCameraStyle == .vertical {
            activeCameraStyle = nil
            CameraPreviewWindow.hide()
        } else {
            activeCameraStyle = .vertical
            CameraPreviewWindow.show(style: .vertical)
        }
        updateCameraButtonAppearances()
    }

    @objc private func micToggled() {
        micEnabled.toggle()
        updateMicButtonAppearance()
    }

    private func updateCameraButtonAppearances() {
        let cfg = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)

        let bubbleActive = activeCameraStyle == .bubble
        let bubbleSymbol = bubbleActive ? "video.circle.fill" : "video.circle"
        cameraButton?.image = NSImage(systemSymbolName: bubbleSymbol, accessibilityDescription: "Camera")?
                                  .withSymbolConfiguration(cfg)
        cameraButton?.contentTintColor = bubbleActive ? .systemBlue : .labelColor

        let vertActive = activeCameraStyle == .vertical
        let vertSymbol = vertActive ? "rectangle.portrait.fill" : "rectangle.portrait"
        cameraVerticalButton?.image = NSImage(systemSymbolName: vertSymbol, accessibilityDescription: "Vertical Camera")?
                                          .withSymbolConfiguration(cfg)
        cameraVerticalButton?.contentTintColor = vertActive ? .systemBlue : .labelColor
    }

    private func updateMicButtonAppearance() {
        let symbol = micEnabled ? "mic.circle.fill" : "mic.circle"
        let cfg = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        micButton?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Mic")?
                               .withSymbolConfiguration(cfg)
        micButton?.contentTintColor = micEnabled ? .systemBlue : .labelColor
    }

    // MARK: - Refresh

    private func refreshSelection() {
        for (mode, btn) in modeButtons {
            btn.isActiveMode = (mode == selectedMode)
        }
        captureButton?.title = selectedMode.isRecording ? "Record" : "Capture"

        let showMedia = selectedMode.isRecording
        mediaSeparator?.isHidden      = !showMedia
        cameraButton?.isHidden        = !showMedia
        cameraVerticalButton?.isHidden = !showMedia
        micButton?.isHidden           = !showMedia

        // Hide camera preview when switching away from recording modes.
        if !showMedia, activeCameraStyle != nil {
            activeCameraStyle = nil
            CameraPreviewWindow.hide()
            updateCameraButtonAppearances()
        }
    }
}
