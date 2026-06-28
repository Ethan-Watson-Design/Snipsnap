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

// MARK: - CaptureBarMediaButton

/// macOS screenshot-style control: icon + chevron, opens a popup menu on click.
private final class CaptureBarMediaButton: NSButton {
    var isMediaActive = false {
        didSet { updateAppearance() }
    }

    private let baseSymbol: String
    private let activeSymbol: String
    private let inactiveSymbol: String

    init(baseSymbol: String, activeSymbol: String, inactiveSymbol: String, accessibilityLabel: String) {
        self.baseSymbol = baseSymbol
        self.activeSymbol = activeSymbol
        self.inactiveSymbol = inactiveSymbol
        super.init(frame: .zero)
        title = ""
        imagePosition = .imageOnly
        isBordered = false
        imageScaling = .scaleProportionallyDown
        wantsLayer = true
        layer?.cornerRadius = 8
        toolTip = accessibilityLabel
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateAppearance() {
        let symbol = isMediaActive ? activeSymbol : inactiveSymbol
        let cfg = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        image = compositeIcon(main: symbol, cfg: cfg)
        contentTintColor = isMediaActive ? .systemBlue : .labelColor
    }

    /// Stacks the media icon above a small chevron, matching the native screenshot toolbar.
    private func compositeIcon(main: String, cfg: NSImage.SymbolConfiguration) -> NSImage? {
        guard let mainImg = NSImage(systemSymbolName: main, accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg),
              let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)) else {
            return NSImage(systemSymbolName: baseSymbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg)
        }

        let w: CGFloat = 28
        let h: CGFloat = 30
        let composite = NSImage(size: NSSize(width: w, height: h))
        composite.lockFocus()
        mainImg.draw(in: NSRect(x: 2, y: 8, width: 24, height: 20),
                     from: .zero, operation: .sourceOver, fraction: 1)
        chevron.draw(in: NSRect(x: 9, y: 1, width: 10, height: 6),
                     from: .zero, operation: .sourceOver, fraction: 0.55)
        composite.unlockFocus()
        return composite
    }
}

// MARK: - CaptureBarWindowPicker

/// Full-width picker shown above the capture bar when recording a window.
private final class CaptureBarWindowPicker: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
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
        contentInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        lineBreakMode = .byTruncatingTail
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - CaptureMediaDevices

private enum CaptureMediaDevices {
    static func videoDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    static func audioInputDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
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
    private weak var mediaSeparator: NSBox?
    private var localMonitor: Any?

    private let barHeight: CGFloat = 64
    private let pickerRowHeight: CGFloat = 44
    private let pickerGap: CGFloat = 6
    private let barWidth: CGFloat
    private weak var barEffectView: NSVisualEffectView?
    private weak var windowPickerRow: NSVisualEffectView?
    private weak var windowPickerButton: CaptureBarWindowPicker?

    private var recordableWindows: [SCWindow] = []
    private var selectedRecordWindowID: CGWindowID?

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
            if bar.selectedMode.isRecording {
                bar.applyCameraPreview()
            } else {
                CameraPreviewWindow.hide()
            }
        }
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

    private struct BarLayout {
        let totalWidth: CGFloat
        let horizontalPad: CGFloat
    }

    private static func computeBarLayout() -> BarLayout {
        let hPad: CGFloat = 12
        let btnW: CGFloat = 58
        let sepPad: CGFloat = 6
        let sepW: CGFloat = 1
        let toggleSize: CGFloat = 36
        let toggleGap: CGFloat = 4
        let captureW: CGFloat = 82

        let allButtonCount = 6
        let separatorCount = 2
        let mediaSlotW = (sepW + sepPad * 2)
                       + toggleSize + toggleGap
                       + toggleSize + toggleGap
                       + toggleSize + toggleGap
                       + toggleSize
        let totalW = hPad
                   + CGFloat(allButtonCount) * btnW
                   + CGFloat(separatorCount) * (sepW + sepPad * 2)
                   + mediaSlotW
                   + captureW
                   + hPad
        return BarLayout(totalWidth: totalW, horizontalPad: hPad)
    }

    private func buildUI() {
        let barH = barHeight
        let btnW:       CGFloat = 58
        let btnH:       CGFloat = 48
        let hPad = computeBarLayout().horizontalPad
        let captureW:   CGFloat = 82
        let captureH:   CGFloat = 30
        let sepPad:     CGFloat = 6
        let sepW:       CGFloat = 1
        let toggleSize: CGFloat = 36
        let toggleGap:  CGFloat = 4
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

        let pickerRow = NSVisualEffectView(frame: NSRect(
            x: 0,
            y: barH + pickerGap,
            width: totalW,
            height: pickerRowHeight
        ))
        pickerRow.material = .menu
        pickerRow.blendingMode = .behindWindow
        pickerRow.state = .active
        pickerRow.wantsLayer = true
        pickerRow.layer?.cornerRadius = 10
        pickerRow.layer?.masksToBounds = true
        pickerRow.isHidden = true
        root.addSubview(pickerRow)
        windowPickerRow = pickerRow

        let pickerH: CGFloat = 32
        let pickerBtn = CaptureBarWindowPicker(frame: CGRect(
            x: hPad,
            y: (pickerRowHeight - pickerH) / 2,
            width: totalW - hPad * 2,
            height: pickerH
        ))
        pickerBtn.target = self
        pickerBtn.action = #selector(windowPickerClicked(_:))
        pickerRow.addSubview(pickerBtn)
        windowPickerButton = pickerBtn

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

        // Camera popup
        let camBtn = CaptureBarMediaButton(
            baseSymbol: "video",
            activeSymbol: "video.fill",
            inactiveSymbol: "video.slash.fill",
            accessibilityLabel: "Camera"
        )
        camBtn.frame = CGRect(x: x, y: (barH - toggleSize) / 2, width: toggleSize, height: toggleSize)
        camBtn.target = self
        camBtn.action = #selector(cameraMenuClicked(_:))
        vfx.addSubview(camBtn)
        cameraButton = camBtn
        x += toggleSize + toggleGap

        // Recording background popup
        let bgBtn = CaptureBarMediaButton(
            baseSymbol: "photo.on.rectangle.angled",
            activeSymbol: "photo.on.rectangle.angled",
            inactiveSymbol: "photo.on.rectangle",
            accessibilityLabel: "Background"
        )
        bgBtn.frame = CGRect(x: x, y: (barH - toggleSize) / 2, width: toggleSize, height: toggleSize)
        bgBtn.target = self
        bgBtn.action = #selector(backgroundMenuClicked(_:))
        vfx.addSubview(bgBtn)
        backgroundButton = bgBtn
        x += toggleSize + toggleGap

        // System audio popup
        let audioBtn = CaptureBarMediaButton(
            baseSymbol: "speaker.wave.2",
            activeSymbol: "speaker.wave.2.fill",
            inactiveSymbol: "speaker.slash.fill",
            accessibilityLabel: "System Audio"
        )
        audioBtn.frame = CGRect(x: x, y: (barH - toggleSize) / 2, width: toggleSize, height: toggleSize)
        audioBtn.target = self
        audioBtn.action = #selector(systemAudioMenuClicked(_:))
        vfx.addSubview(audioBtn)
        systemAudioButton = audioBtn
        x += toggleSize + toggleGap

        // Microphone popup
        let micBtn = CaptureBarMediaButton(
            baseSymbol: "mic",
            activeSymbol: "mic.fill",
            inactiveSymbol: "mic.slash.fill",
            accessibilityLabel: "Microphone"
        )
        micBtn.frame = CGRect(x: x, y: (barH - toggleSize) / 2, width: toggleSize, height: toggleSize)
        micBtn.target = self
        micBtn.action = #selector(micMenuClicked(_:))
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

        updateMediaButtonAppearances()
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
        let mode = selectedMode
        let micOn = micEnabled
        let micID = selectedMicID
        let sysAudio = systemAudioEnabled
        let recBackground = recordingBackground
        let camID = selectedCameraID
        let camStyle = cameraStyle

        switch mode {
        case .recordWindow:
            guard let windowID = selectedRecordWindowID else { return }
            CaptureBar.dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                CaptureBar.execute(
                    mode: mode,
                    captureTarget: .window(windowID),
                    recordingBackground: recBackground,
                    cameraDeviceID: camID,
                    cameraStyle: camStyle,
                    micEnabled: micOn,
                    systemAudioEnabled: sysAudio,
                    micDeviceID: micID
                )
            }

        case .recordRegion:
            CaptureBar.dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                RegionSelector.show { rect in
                    guard let rect else { return }
                    CaptureBar.execute(
                        mode: mode,
                        captureTarget: .region(rect),
                        recordingBackground: recBackground,
                        cameraDeviceID: camID,
                        cameraStyle: camStyle,
                        micEnabled: micOn,
                        systemAudioEnabled: sysAudio,
                        micDeviceID: micID
                    )
                }
            }

        default:
            CaptureBar.dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let target: RecordingCaptureTarget
                switch mode {
                case .recordFullScreen: target = .fullScreen
                default: return
                }
                CaptureBar.execute(
                    mode: mode,
                    captureTarget: target,
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

    // MARK: - Capture Execution

    private static func execute(
        mode: CaptureMode,
        captureTarget: RecordingCaptureTarget = .fullScreen,
        recordingBackground: RecordingBackgroundStyle = .none,
        cameraDeviceID: String? = nil,
        cameraStyle: CameraPreviewStyle = .square,
        micEnabled: Bool = false,
        systemAudioEnabled: Bool = false,
        micDeviceID: String? = nil
    ) {
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

        case .recordFullScreen, .recordWindow, .recordRegion:
            let engineCamera = captureTarget != .fullScreen ? cameraDeviceID : nil
            if engineCamera != nil {
                CameraPreviewWindow.hide()
            }
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

    @objc private func cameraMenuClicked(_ sender: NSButton) {
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

            for style in [CameraBackgroundStyle.none, .blur, .warm, .cool, .midnight] {
                let item = NSMenuItem(title: style.menuTitle, action: #selector(selectCameraBackground(_:)), keyEquivalent: "")
                item.target = self
                item.tag = cameraBackgroundTag(for: style)
                item.state = cameraBackground == style ? .on : .off
                menu.addItem(item)
            }

            let customCamBg = NSMenuItem(title: "Custom Image…", action: #selector(selectCustomCameraBackground(_:)), keyEquivalent: "")
            customCamBg.target = self
            if case .custom = cameraBackground { customCamBg.state = .on }
            menu.addItem(customCamBg)
        }

        popMenu(menu, from: sender)
    }

    @objc private func backgroundMenuClicked(_ sender: NSButton) {
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

    @objc private func systemAudioMenuClicked(_ sender: NSButton) {
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

    @objc private func micMenuClicked(_ sender: NSButton) {
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
        applyCameraPreview()
    }

    @objc private func selectCameraStyle(_ sender: NSMenuItem) {
        guard selectedCameraID != nil else { return }
        cameraStyle = sender.tag == 1 ? .vertical : .square
        applyCameraPreview()
    }

    @objc private func selectCameraBackground(_ sender: NSMenuItem) {
        guard selectedCameraID != nil else { return }
        cameraBackground = cameraBackgroundStyle(for: sender.tag)
        applyCameraPreview()
    }

    @objc private func selectCustomCameraBackground(_ sender: NSMenuItem) {
        guard selectedCameraID != nil else { return }
        pickImage { [weak self] path in
            guard let self, let path else { return }
            self.cameraBackground = .custom(path: path)
            self.applyCameraPreview()
        }
    }

    @objc private func selectRecordingBackground(_ sender: NSMenuItem) {
        recordingBackground = recordingBackgroundStyle(for: sender.tag)
        updateMediaButtonAppearances()
    }

    @objc private func selectCustomRecordingBackground(_ sender: NSMenuItem) {
        pickImage { [weak self] path in
            guard let self, let path else { return }
            self.recordingBackground = .custom(path: path)
            self.updateMediaButtonAppearances()
        }
    }

    private func cameraBackgroundTag(for style: CameraBackgroundStyle) -> Int {
        switch style {
        case .none: return 0
        case .blur: return 1
        case .warm: return 2
        case .cool: return 3
        case .midnight: return 4
        case .custom: return 5
        }
    }

    private func cameraBackgroundStyle(for tag: Int) -> CameraBackgroundStyle {
        switch tag {
        case 1: return .blur
        case 2: return .warm
        case 3: return .cool
        case 4: return .midnight
        default: return .none
        }
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

    private func popMenu(_ menu: NSMenu, from button: NSButton) {
        let loc = NSPoint(x: button.bounds.midX, y: button.bounds.maxY + 2)
        menu.popUp(positioning: nil, at: loc, in: button)
    }

    private func popMenuAbove(_ menu: NSMenu, from button: NSButton) {
        menu.font = NSFont.systemFont(ofSize: 13)
        let loc = NSPoint(x: button.bounds.midX, y: button.bounds.maxY)
        menu.popUp(positioning: menu.items.last, at: loc, in: button)
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
                self.captureButton?.isEnabled = self.selectedRecordWindowID != nil
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
                self.popMenuAbove(menu, from: sender)
            }
        }
    }

    @objc private func selectRecordWindow(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        selectedRecordWindowID = CGWindowID(number.uint32Value)
        updateWindowPickerTitle()
    }

    private func loadRecordableWindows() {
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
                self.captureButton?.isEnabled = self.selectedRecordWindowID != nil
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
        let show = selectedMode == .recordWindow
        windowPickerRow?.isHidden = !show

        let totalH = show ? (barHeight + pickerGap + pickerRowHeight) : barHeight
        setContentSize(NSSize(width: barWidth, height: totalH))
        contentView?.setFrameSize(NSSize(width: barWidth, height: totalH))

        if show {
            loadRecordableWindows()
        } else {
            captureButton?.isEnabled = true
        }
    }

    // MARK: - Camera Preview

    private func applyCameraPreview() {
        guard selectedMode.isRecording else {
            CameraPreviewWindow.hide()
            return
        }
        if let deviceID = selectedCameraID {
            CameraPreviewWindow.show(style: cameraStyle, deviceID: deviceID, background: cameraBackground)
        } else {
            CameraPreviewWindow.hide()
        }
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

        let showMedia = selectedMode.isRecording
        mediaSeparator?.isHidden      = !showMedia
        cameraButton?.isHidden        = !showMedia
        backgroundButton?.isHidden    = !showMedia
        systemAudioButton?.isHidden   = !showMedia
        micButton?.isHidden           = !showMedia

        if showMedia {
            applyCameraPreview()
        } else {
            CameraPreviewWindow.hide()
        }

        updateWindowPickerVisibility()
    }
}
