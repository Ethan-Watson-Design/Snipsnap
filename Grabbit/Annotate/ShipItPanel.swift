//
//  ShipItPanel.swift
//  Grabbit
//

import AppKit
import UniformTypeIdentifiers

// MARK: - Side-by-side choice

struct ShipItSideBySideChoice: Equatable {
    let id: UUID
    let thumbnail: NSImage
    let title: String
}

// MARK: - Background swatch

final class BackgroundStyleSwatch: NSControl {
    enum Kind {
        case preset(RecordingBackgroundStyle)
        case custom
    }

    let kind: Kind
    var isStyleSelected = false { didSet { needsDisplay = true } }
    var customPreview: NSImage? { didSet { needsDisplay = true } }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseUp(with event: NSEvent) {
        guard let window, event.window == window else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        _ = target?.perform(action, with: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let path = CGPath(roundedRect: rect, cornerWidth: 5, cornerHeight: 5, transform: nil)
        ctx.addPath(path)
        ctx.clip()

        switch kind {
        case .preset(let style):
            switch style {
            case .none:
                NSColor.quaternaryLabelColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: DesignTokens.Radius.sm, yRadius: DesignTokens.Radius.sm).fill()
                DesignTokens.Color.border.ns.setStroke()
                let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: DesignTokens.Radius.sm, yRadius: DesignTokens.Radius.sm)
                border.lineWidth = 1
                border.setLineDash([3, 2], count: 2, phase: 0)
                border.stroke()
            case .warm:
                drawGradient(in: rect, colors: DesignTokens.Color.RecordingGradient.warm.ns)
            case .cool:
                drawGradient(in: rect, colors: DesignTokens.Color.RecordingGradient.cool.ns)
            case .midnight:
                drawGradient(in: rect, colors: DesignTokens.Color.RecordingGradient.midnight.ns)
            case .custom:
                break
            }
        case .custom:
            if let customPreview {
                customPreview.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            } else {
                NSColor.quaternaryLabelColor.setFill()
                NSBezierPath(rect: rect).fill()
                let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
                if let icon = NSImage(systemSymbolName: "photo.badge.plus", accessibilityDescription: "Custom")?
                    .withSymbolConfiguration(cfg) {
                    let iconSize = NSSize(width: 14, height: 14)
                    let origin = NSPoint(
                        x: rect.midX - iconSize.width / 2,
                        y: rect.midY - iconSize.height / 2
                    )
                    icon.draw(in: NSRect(origin: origin, size: iconSize))
                }
            }
        }

        ctx.resetClip()
        if isStyleSelected {
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(2)
            ctx.addPath(CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerWidth: 6, cornerHeight: 6, transform: nil))
            ctx.strokePath()
        } else {
            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.setLineWidth(0.5)
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    private func drawGradient(in rect: NSRect, colors: [NSColor]) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors.map(\.cgColor) as CFArray,
            locations: [0, 1]
        ) else { return }
        NSGraphicsContext.current?.cgContext.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: CGPoint(x: rect.maxX, y: rect.maxY),
            options: []
        )
    }
}

// MARK: - Ship It panel

/// Right-edge overlay for presentation settings (background, side-by-side).
/// Hidden until presented; overlays content without resizing the stage.
final class ShipItPanelView: NSView {

    static let panelWidth: CGFloat = 252
    static let edgeInset: CGFloat = DesignTokens.Spacing.lg

    private static var contentWidth: CGFloat { panelWidth - contentPadding * 2 }
    private static let contentPadding = DesignTokens.Spacing.md

    static let presetStyles: [RecordingBackgroundStyle] = [.none, .warm, .cool, .midnight]

    var isPresented = false {
        didSet {
            guard oldValue != isPresented else { return }
            refreshPresentation()
            onPresentationChanged?()
        }
    }

    var selectedBackground: RecordingBackgroundStyle = .none {
        didSet { refreshBackgroundSwatches() }
    }

    var showsSideBySide = false {
        didSet { sideBySideSection.isHidden = !showsSideBySide }
    }

    var sideBySideSettings = SideBySideSettings() {
        didSet { refreshSideBySideUI() }
    }

    var sideBySideChoices: [ShipItSideBySideChoice] = [] {
        didSet { refreshSideBySideUI() }
    }

    var onBackgroundChanged: ((RecordingBackgroundStyle) -> Void)?
    var onSideBySideChanged: ((SideBySideSettings) -> Void)?
    var onPresentationChanged: (() -> Void)?

    var currentWidth: CGFloat {
        isPresented ? Self.panelWidth : 0
    }

    private let contentPanel = NSView()
    private let scrollView = NSScrollView()
    private let documentContainer = FlippedClipView()
    private let stackView = NSStackView()
    private let sideBySideSection = NSView()
    private let sideBySideEnableSwitch = NSSwitch()
    private let sideBySideSwapButton = NSButton()
    private let sideBySideTilesContainer = NSView()
    private var backgroundSwatches: [BackgroundStyleSwatch] = []
    private var sideBySideTileButtons: [UUID: NSButton] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    func layoutOverlay(in containerBounds: NSRect) {
        guard isPresented else {
            isHidden = true
            return
        }
        isHidden = false
        let inset = Self.edgeInset
        let panelHeight = max(0, containerBounds.height - inset * 2)
        frame = NSRect(
            x: containerBounds.width - Self.panelWidth - inset,
            y: inset,
            width: Self.panelWidth,
            height: panelHeight
        )
        contentPanel.frame = NSRect(origin: .zero, size: frame.size)
        let padding = Self.contentPadding
        scrollView.frame = NSRect(
            x: padding,
            y: padding,
            width: max(0, frame.width - padding * 2),
            height: max(0, frame.height - padding * 2)
        )
        applyPanelShadow()
    }

    private func applyPanelShadow() {
        guard let layer = contentPanel.layer else { return }
        DesignTokens.Elevation.panel.apply(
            to: layer,
            roundedPathIn: contentPanel.bounds,
            cornerRadius: DesignTokens.Radius.lg
        )
    }

    func dismiss() {
        isPresented = false
    }

    // MARK: - Build

    private func build() {
        wantsLayer = true
        isHidden = true

        contentPanel.wantsLayer = true
        contentPanel.layer?.backgroundColor = NSColor.white.cgColor
        contentPanel.layer?.cornerRadius = DesignTokens.Radius.lg
        contentPanel.layer?.cornerCurve = .continuous
        contentPanel.layer?.masksToBounds = false
        addSubview(contentPanel)

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        contentPanel.addSubview(scrollView)

        documentContainer.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentContainer

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false
        documentContainer.addSubview(stackView)

        stackView.addArrangedSubview(makeHeaderRow())
        stackView.addArrangedSubview(makeSectionLabel("Background"))
        stackView.addArrangedSubview(makeBackgroundSwatchRow())
        stackView.addArrangedSubview(makeSideBySideSection())

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: documentContainer.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: documentContainer.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: documentContainer.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: documentContainer.bottomAnchor),
            documentContainer.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        applyPanelShadow()

        refreshBackgroundSwatches()
        refreshSideBySideUI()
    }

    private func preferredWidthConstraint(for view: NSView) -> NSLayoutConstraint {
        let constraint = view.widthAnchor.constraint(equalToConstant: Self.contentWidth)
        // Scrollbars can shrink the clip width; keep this as a preference to avoid conflicts.
        constraint.priority = .defaultHigh
        return constraint
    }

    private func makeHeaderRow() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "More")
        label.font = NSFont.grabbit(.title)
        label.textColor = DesignTokens.Color.textPrimary.ns
        label.translatesAutoresizingMaskIntoConstraints = false

        let closeBtn = NSButton(frame: .zero)
        closeBtn.bezelStyle = .regularSquare
        closeBtn.isBordered = false
        closeBtn.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Close")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        closeBtn.imageScaling = .scaleProportionallyDown
        closeBtn.target = self
        closeBtn.action = #selector(dismissTapped)
        closeBtn.toolTip = "Close"
        closeBtn.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(label)
        row.addSubview(closeBtn)
        let preferredWidth = preferredWidthConstraint(for: row)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            closeBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            closeBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 22),
            preferredWidth,
        ])
        return row
    }

    private func makeSectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.grabbit(.caption)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeBackgroundSwatchRow() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let swatchSize: CGFloat = 28
        let gap: CGFloat = 6
        var x: CGFloat = 0

        for style in Self.presetStyles {
            let swatch = BackgroundStyleSwatch(kind: .preset(style))
            swatch.frame = CGRect(x: x, y: 0, width: swatchSize, height: swatchSize)
            swatch.target = self
            swatch.action = #selector(backgroundSwatchTapped(_:))
            row.addSubview(swatch)
            backgroundSwatches.append(swatch)
            x += swatchSize + gap
        }

        let customSwatch = BackgroundStyleSwatch(kind: .custom)
        customSwatch.frame = CGRect(x: x, y: 0, width: swatchSize, height: swatchSize)
        customSwatch.target = self
        customSwatch.action = #selector(customBackgroundSwatchTapped(_:))
        row.addSubview(customSwatch)
        backgroundSwatches.append(customSwatch)

        row.heightAnchor.constraint(equalToConstant: swatchSize).isActive = true
        row.widthAnchor.constraint(equalToConstant: x + swatchSize).isActive = true
        return row
    }

    private func makeSideBySideSection() -> NSView {
        sideBySideSection.translatesAutoresizingMaskIntoConstraints = false

        let titleRow = NSView()
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        let title = makeSectionLabel("Side by Side")
        title.translatesAutoresizingMaskIntoConstraints = false

        sideBySideEnableSwitch.target = self
        sideBySideEnableSwitch.action = #selector(sideBySideEnableToggled)
        sideBySideEnableSwitch.translatesAutoresizingMaskIntoConstraints = false

        titleRow.addSubview(title)
        titleRow.addSubview(sideBySideEnableSwitch)
        let preferredTitleWidth = preferredWidthConstraint(for: titleRow)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: titleRow.leadingAnchor),
            title.centerYAnchor.constraint(equalTo: titleRow.centerYAnchor),
            sideBySideEnableSwitch.trailingAnchor.constraint(equalTo: titleRow.trailingAnchor),
            sideBySideEnableSwitch.centerYAnchor.constraint(equalTo: titleRow.centerYAnchor),
            titleRow.heightAnchor.constraint(equalToConstant: 22),
            preferredTitleWidth,
        ])

        sideBySideTilesContainer.translatesAutoresizingMaskIntoConstraints = false
        sideBySideTilesContainer.heightAnchor.constraint(equalToConstant: 128).isActive = true
        preferredWidthConstraint(for: sideBySideTilesContainer).isActive = true

        sideBySideSwapButton.title = "Swap Order"
        sideBySideSwapButton.bezelStyle = .rounded
        sideBySideSwapButton.controlSize = .small
        sideBySideSwapButton.target = self
        sideBySideSwapButton.action = #selector(sideBySideSwapTapped)

        let sectionStack = NSStackView(views: [titleRow, sideBySideTilesContainer, sideBySideSwapButton])
        sectionStack.orientation = .vertical
        sectionStack.alignment = .leading
        sectionStack.spacing = 8
        sectionStack.translatesAutoresizingMaskIntoConstraints = false

        sideBySideSection.addSubview(sectionStack)
        NSLayoutConstraint.activate([
            sectionStack.topAnchor.constraint(equalTo: sideBySideSection.topAnchor),
            sectionStack.leadingAnchor.constraint(equalTo: sideBySideSection.leadingAnchor),
            sectionStack.trailingAnchor.constraint(equalTo: sideBySideSection.trailingAnchor),
            sectionStack.bottomAnchor.constraint(equalTo: sideBySideSection.bottomAnchor),
        ])

        sideBySideSection.isHidden = !showsSideBySide
        return sideBySideSection
    }

    // MARK: - Layout

    private func refreshPresentation() {
        isHidden = !isPresented
    }

    // MARK: - Refresh

    private func refreshBackgroundSwatches() {
        for swatch in backgroundSwatches {
            switch swatch.kind {
            case .preset(let style):
                swatch.isStyleSelected = selectedBackground == style
            case .custom:
                swatch.isStyleSelected = {
                    if case .custom = selectedBackground { return true }
                    return false
                }()
                if case .custom(let path) = selectedBackground {
                    swatch.customPreview = NSImage(contentsOfFile: path)
                } else {
                    swatch.customPreview = nil
                }
            }
            swatch.needsDisplay = true
        }
    }

    private func refreshSideBySideUI() {
        sideBySideEnableSwitch.state = sideBySideSettings.isEnabled ? .on : .off
        sideBySideSwapButton.isEnabled = sideBySideSettings.isEnabled && sideBySideSettings.previousImage != nil

        sideBySideTilesContainer.subviews.forEach { $0.removeFromSuperview() }
        sideBySideTileButtons.removeAll()

        let tileSize: CGFloat = 60
        let gap: CGFloat = 6
        let columns = 3
        var x: CGFloat = 0
        var y: CGFloat = 68

        if sideBySideChoices.isEmpty {
            let label = NSTextField(labelWithString: "No previous screenshots")
            label.font = NSFont.grabbit(.caption)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 0, y: 24, width: Self.contentWidth, height: 16)
            sideBySideTilesContainer.addSubview(label)
            return
        }

        for (index, choice) in sideBySideChoices.enumerated() {
            if index > 0, index % columns == 0 {
                x = 0
                y -= tileSize + gap
            }

            let btn = NSButton(frame: NSRect(x: x, y: y, width: tileSize, height: tileSize))
            btn.bezelStyle = .regularSquare
            btn.isBordered = false
            btn.image = choice.thumbnail
            btn.imageScaling = .scaleProportionallyUpOrDown
            btn.imagePosition = .imageOnly
            btn.toolTip = choice.title
            btn.tag = index
            btn.target = self
            btn.action = #selector(sideBySideChoiceTapped(_:))
            btn.wantsLayer = true
            btn.layer?.cornerRadius = DesignTokens.Radius.md
            btn.layer?.masksToBounds = true
            let selected = sideBySideSettings.previousCaptureID == choice.id
            btn.layer?.borderWidth = selected ? 2.5 : 1
            btn.layer?.borderColor = selected
                ? NSColor.controlAccentColor.cgColor
                : NSColor.separatorColor.cgColor
            sideBySideTilesContainer.addSubview(btn)
            sideBySideTileButtons[choice.id] = btn
            x += tileSize + gap
        }
    }

    // MARK: - Actions

    @objc private func dismissTapped() {
        dismiss()
    }

    @objc private func backgroundSwatchTapped(_ sender: BackgroundStyleSwatch) {
        guard case .preset(let style) = sender.kind else { return }
        selectedBackground = style
        onBackgroundChanged?(style)
    }

    @objc private func customBackgroundSwatchTapped(_ sender: BackgroundStyleSwatch) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.image]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.begin { [weak self] response in
            guard let self, response == .OK, let path = openPanel.url?.path else { return }
            let style = RecordingBackgroundStyle.custom(path: path)
            self.selectedBackground = style
            self.onBackgroundChanged?(style)
        }
    }

    @objc private func sideBySideEnableToggled() {
        var settings = sideBySideSettings
        settings.isEnabled = sideBySideEnableSwitch.state == .on
        if settings.isEnabled, settings.previousImage == nil, let first = sideBySideChoices.first {
            settings.previousCaptureID = first.id
            settings.previousImage = first.thumbnail
        }
        sideBySideSettings = settings
        onSideBySideChanged?(settings)
    }

    @objc private func sideBySideSwapTapped() {
        var settings = sideBySideSettings
        settings.order.swap()
        sideBySideSettings = settings
        onSideBySideChanged?(settings)
    }

    @objc private func sideBySideChoiceTapped(_ sender: NSButton) {
        guard sideBySideChoices.indices.contains(sender.tag) else { return }
        let choice = sideBySideChoices[sender.tag]
        var settings = sideBySideSettings
        settings.previousCaptureID = choice.id
        settings.previousImage = choice.thumbnail
        settings.isEnabled = true
        sideBySideSettings = settings
        sideBySideEnableSwitch.state = .on
        onSideBySideChanged?(settings)
    }
}

private final class FlippedClipView: NSView {
    override var isFlipped: Bool { true }
}
