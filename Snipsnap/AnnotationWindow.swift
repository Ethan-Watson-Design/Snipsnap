//
//  AnnotationWindow.swift
//  Snipsnap
//
//  Created by Ethan Watson on 6/27/26.
//

import AppKit

// MARK: - Enums

enum StrokeTool {
    case marker, highlighter
}

enum AnnotationTool: CaseIterable, Hashable {
    case select, marker, highlighter, arrow, rect, text, number, emoji

    var sfSymbol: String {
        switch self {
        case .select:      return "cursorarrow"
        case .marker:      return "scribble"
        case .highlighter: return "highlighter"
        case .arrow:       return "arrow.up.right"
        case .rect:        return "rectangle"
        case .text:        return "textformat"
        case .number:      return "number.circle"
        case .emoji:       return "face.smiling"
        }
    }

    var displayName: String {
        switch self {
        case .select:      return "Select"
        case .marker:      return "Marker"
        case .highlighter: return "Highlighter"
        case .arrow:       return "Arrow"
        case .rect:        return "Rectangle"
        case .text:        return "Text"
        case .number:      return "Number"
        case .emoji:       return "Sticker"
        }
    }

    var shortcutKey: String {
        switch self {
        case .select:      return "S"
        case .marker:      return "M"
        case .highlighter: return "H"
        case .arrow:       return "A"
        case .rect:        return "R"
        case .text:        return "T"
        case .number:      return "N"
        case .emoji:       return "E"
        }
    }
}

enum ArrowTipStyle: Equatable, CaseIterable {
    case solid, dot

    var menuSymbol: String {
        switch self {
        case .solid: return "arrow.up.right"
        case .dot:   return "circle.fill"
        }
    }

    var menuSymbolPointSize: CGFloat {
        switch self {
        case .solid: return 14
        case .dot:   return 5
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .solid: return "Solid arrow"
        case .dot:   return "Dot arrow"
        }
    }
}

enum Annotation {
    case stroke(points: [CGPoint], color: NSColor, lineWidth: CGFloat, tool: StrokeTool)
    case arrow(from: CGPoint, to: CGPoint, color: NSColor, tipStyle: ArrowTipStyle)
    case rect(rect: CGRect, color: NSColor)
    case text(origin: CGPoint, text: String, color: NSColor, maxWidth: CGFloat?)
    case number(center: CGPoint, value: Int, color: NSColor)
    case emoji(center: CGPoint, emoji: String, size: CGFloat, color: NSColor)
}

struct PlacedAnnotation {
    var content: Annotation
    /// Video timeline position when the annotation appears.
    var startTime: Double = 0
    /// Seconds visible after `startTime`. `nil` = forever.
    var visibleDuration: Double? = nil

    func isVisible(at time: Double) -> Bool {
        guard time >= startTime else { return false }
        guard let duration = visibleDuration else { return true }
        return time <= startTime + duration
    }
}

// MARK: - Color Palette

extension NSColor {
    /// Selection outline for annotations in select mode (solid pink, Figma-style handles).
    static let annotationSelectionAccent = NSColor(hex24: 0xE8328C)
    /// Region capture overlay border and handles.
    static let regionSelectionAccent = NSColor(calibratedWhite: 0.78, alpha: 1)

    static let annotationPalette: [NSColor] = [
        NSColor(hex24: 0xE03D38), // Tomato     — readable on light + dark
        NSColor(hex24: 0xE07535), // Tangerine  — readable on light + dark
        NSColor(hex24: 0xC49000), // Gold       — darkened banana, readable on light
        NSColor(hex24: 0x3A9862), // Sage       — muted mid-green
        NSColor(hex24: 0x1B8FA6), // Peacock    — teal
        NSColor(hex24: 0x3B65D8), // Blueberry  — blue
        NSColor(hex24: 0x8050CC), // Grape      — purple
        NSColor(hex24: 0xC43D72), // Flamingo   — rose
    ]

    convenience init(hex24: UInt32) {
        self.init(
            calibratedRed:   CGFloat((hex24 >> 16) & 0xFF) / 255,
            green:           CGFloat((hex24 >>  8) & 0xFF) / 255,
            blue:            CGFloat( hex24         & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Perceived luminance via Rec. 601 coefficients.
    var isLight: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        (usingColorSpace(.sRGB) ?? self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.6
    }
}

// MARK: - Sticker Symbol Rendering

private enum StickerStyle {
    static let outlineWidth: CGFloat = 6
}

private func drawStickerSymbol(
    base: NSImage,
    in symRect: NSRect,
    pointSize: CGFloat,
    color: NSColor
) {
    let outline = StickerStyle.outlineWidth
    let outlineCfg = NSImage.SymbolConfiguration(pointSize: pointSize + outline * 2, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let outlineImg = base.withSymbolConfiguration(outlineCfg) {
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.setShadow(
                offset: .zero,
                blur: 3,
                color: NSColor.white.withAlphaComponent(0.75).cgColor
            )
            outlineImg.draw(in: symRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            ctx.restoreGState()
        }
        outlineImg.draw(in: symRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    let fillCfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    if let fillImg = base.withSymbolConfiguration(fillCfg) {
        fillImg.draw(in: symRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
}

private func stickerSymbolImage(symbolName: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
    guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { return nil }
    let pad = StickerStyle.outlineWidth + 3
    let canvas = pointSize + pad * 2
    let size = NSSize(width: canvas, height: canvas)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }
    let symRect = NSRect(x: pad, y: pad, width: pointSize, height: pointSize)
    drawStickerSymbol(base: base, in: symRect, pointSize: pointSize, color: color)
    return image
}

// MARK: - Path Helpers

func smoothPath(from points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    guard !points.isEmpty else { return path }

    if points.count == 1 {
        let p = points[0]
        path.addEllipse(in: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3))
        return path
    }

    if points.count == 2 {
        path.move(to: points[0])
        path.addLine(to: points[1])
        return path
    }

    // Midpoint quadratic Bézier: control = raw point, end = midpoint between this and next.
    path.move(to: points[0])
    for i in 0 ..< points.count - 1 {
        let mid = CGPoint(
            x: (points[i].x + points[i + 1].x) / 2,
            y: (points[i].y + points[i + 1].y) / 2
        )
        path.addQuadCurve(to: mid, control: points[i])
    }
    path.addLine(to: points[points.count - 1])
    return path
}

private struct ArrowLayout {
    let angle: CGFloat
    let headLen: CGFloat
    let headAngle: CGFloat
    let baseCenter: CGPoint
    let wingLeft: CGPoint
    let wingRight: CGPoint
}

private func arrowLayout(from start: CGPoint, to end: CGPoint) -> ArrowLayout? {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let len = hypot(dx, dy)
    guard len > 4 else { return nil }

    let angle = atan2(dy, dx)
    let headLen = min(16, len * 0.35)
    let headAngle: CGFloat = .pi / 6
    let cosA = cos(angle)
    let sinA = sin(angle)

    return ArrowLayout(
        angle: angle,
        headLen: headLen,
        headAngle: headAngle,
        baseCenter: CGPoint(
            x: end.x - headLen * cos(headAngle) * cosA,
            y: end.y - headLen * cos(headAngle) * sinA
        ),
        wingLeft: CGPoint(
            x: end.x - headLen * cos(angle - headAngle),
            y: end.y - headLen * sin(angle - headAngle)
        ),
        wingRight: CGPoint(
            x: end.x - headLen * cos(angle + headAngle),
            y: end.y - headLen * sin(angle + headAngle)
        )
    )
}

private struct ArrowPaths {
    var stroke: CGPath
    var fill: CGPath?
}

/// Radius of the dot drawn at the arrow tip (8px diameter).
private let arrowDotRadius: CGFloat = 4

private func arrowPaths(from start: CGPoint, to end: CGPoint, tipStyle: ArrowTipStyle, lineWidth: CGFloat) -> ArrowPaths? {
    guard let layout = arrowLayout(from: start, to: end) else { return nil }

    let stroke = CGMutablePath()
    var fill: CGPath?

    switch tipStyle {
    case .solid:
        stroke.move(to: start)
        stroke.addLine(to: layout.baseCenter)
        let head = CGMutablePath()
        head.move(to: layout.baseCenter)
        head.addLine(to: layout.wingLeft)
        head.addLine(to: end)
        head.addLine(to: layout.wingRight)
        head.closeSubpath()
        fill = head
    case .dot:
        let shaftEnd = CGPoint(
            x: end.x - cos(layout.angle) * arrowDotRadius,
            y: end.y - sin(layout.angle) * arrowDotRadius
        )
        stroke.move(to: start)
        stroke.addLine(to: shaftEnd)
    }
    return ArrowPaths(stroke: stroke, fill: fill)
}

// MARK: - AnnotationTextField

/// NSTextField subclass that intercepts Escape before AppKit can beep.
final class AnnotationTextField: NSTextField {
    var onEscape: (() -> Void)?
    var onTextDidChange: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        onTextDidChange?()
    }
}

// MARK: - StickerPickerPanel

final class StickerPickerPanel: NSObject, NSWindowDelegate {

    // 12 curated SF symbols that map to common annotation intents.
    private static let stickers: [String] = [
        "star.fill",
        "heart.fill",
        "hand.thumbsup.fill",
        "checkmark.circle.fill",
        "xmark.circle.fill",
        "exclamationmark.triangle.fill",
        "lightbulb.fill",
        "flame.fill",
        "eyes",
        "bubble.left.fill",
        "ant.fill",
        "flag.fill",
    ]

    private let panel: NSPanel
    private let onSelect: (String) -> Void
    private var color: NSColor
    private var symbolButtons: [NSButton] = []

    init(nearScreenPoint point: CGPoint, color: NSColor, onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect
        self.color = color

        let cols: CGFloat = 4
        let rows: CGFloat = 3
        let btnSz: CGFloat = 46
        let gap: CGFloat = 6
        let pad: CGFloat = 10
        let panelW = pad * 2 + cols * btnSz + (cols - 1) * gap
        let panelH = pad * 2 + rows * btnSz + (rows - 1) * gap

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var ox = point.x + 12
        var oy = point.y - panelH / 2
        ox = min(ox, screen.maxX - panelW - 10)
        ox = max(ox, screen.minX + 10)
        oy = min(oy, screen.maxY - panelH - 10)
        oy = max(oy, screen.minY + 10)

        panel = NSPanel(
            contentRect: NSRect(x: ox, y: oy, width: panelW, height: panelH),
            styleMask: [.nonactivatingPanel, .titled, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false

        super.init()
        panel.delegate = self
        buildUI()
    }

    private func buildUI() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let vStack = NSStackView()
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.orientation = .vertical
        vStack.spacing = 6

        let cols = 4
        var rowViews: [NSView] = []
        for (i, symbol) in Self.stickers.enumerated() {
            let btn = NSButton(frame: .zero)
            btn.title = ""
            btn.isBordered = false
            btn.bezelStyle = .regularSquare
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            btn.image = stickerSymbolImage(symbolName: symbol, pointSize: 22, color: color)
            btn.imageScaling = .scaleProportionallyDown
            symbolButtons.append(btn)
            btn.target = self
            btn.action = #selector(stickerTapped(_:))
            btn.identifier = NSUserInterfaceItemIdentifier(symbol)
            btn.widthAnchor.constraint(equalToConstant: 46).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 46).isActive = true
            rowViews.append(btn)
            if rowViews.count == cols || i == Self.stickers.count - 1 {
                let row = NSStackView(views: rowViews)
                row.orientation = .horizontal
                row.spacing = 6
                row.distribution = .fillEqually
                vStack.addArrangedSubview(row)
                rowViews = []
            }
        }

        container.addSubview(vStack)
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            vStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            vStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            vStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -10),
        ])
        panel.contentView = container
    }

    @objc private func stickerTapped(_ sender: NSButton) {
        let symbol = sender.identifier?.rawValue ?? ""
        panel.close()
        onSelect(symbol)
    }

    func show() { panel.makeKeyAndOrderFront(nil) }
    func close() { panel.close() }

    func updateColor(_ color: NSColor) {
        self.color = color
        for btn in symbolButtons {
            let symbol = btn.identifier?.rawValue ?? ""
            btn.image = stickerSymbolImage(symbolName: symbol, pointSize: 22, color: color)
        }
    }
}

// MARK: - AnnotationCanvasView

final class AnnotationCanvasView: NSView, NSTextFieldDelegate {

    private static let textHPadding: CGFloat = 10
    private static let textVPadding: CGFloat = 4

    // All committed annotations.
    var annotations: [PlacedAnnotation] = []
    // The annotation being drawn right now (not yet committed).
    var currentAnnotation: Annotation?

    var selectedTool: AnnotationTool = .marker {
        didSet {
            guard oldValue != selectedTool else { return }
            commitActiveTextField()
        }
    }
    var selectedColor: NSColor = NSColor.annotationPalette[0]
    var selectedArrowTipStyle: ArrowTipStyle = .solid

    /// When true, annotations are filtered by playback time and stamped on commit.
    var videoMode: Bool = false
    /// Current video playback time — drives visibility filtering in video mode.
    var playbackTime: Double = 0

    /// Called whenever the active tool changes via keyboard.
    var onToolChanged: ((AnnotationTool) -> Void)?
    /// Called when Escape is pressed (with or without an active text field).
    var onEscapeAction: (() -> Void)?
    /// Called just before the first mouse-down begins a new stroke/shape.
    var onWillDraw: (() -> Void)?
    /// Called when the selected annotation index changes (video mode duration UI).
    var onSelectionChanged: ((Int?) -> Void)?
    /// Called when the selected annotation moves (drag in select mode).
    var onSelectionGeometryChanged: (() -> Void)?

    var selectedIndex: Int? = nil
    private var dragOffset: CGPoint = .zero

    private enum RectResizeHandle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private enum SelectDragMode {
        case none
        case moveWhole
        case arrowStart
        case arrowEnd
        case textWidthLeft(anchorRight: CGFloat)
        case textWidthRight(anchorLeft: CGFloat)
        case rectResize(handle: RectResizeHandle, anchor: CGRect)
    }

    private let rectCornerHitRadius: CGFloat = 10
    private let rectEdgeHitThickness: CGFloat = 6
    private let rectMinSize: CGFloat = 20

    private var selectDragMode: SelectDragMode = .none

    private var strokePoints: [CGPoint] = []
    private var dragStart: CGPoint = .zero
    private var activeTextField: AnnotationTextField?
    private var activeEmojiPicker: StickerPickerPanel?
    private var pendingEmojiPoint: CGPoint = .zero

    func updateEmojiPickerColor(_ color: NSColor) {
        activeEmojiPicker?.updateColor(color)
    }

    private var undoStack: [[PlacedAnnotation]] = []
    private var redoStack: [[PlacedAnnotation]] = []
    private static let maxUndoLevels = 50
    private var selectDragSavedState: [PlacedAnnotation]?
    private var selectDidDrag = false

    private var nextNumberValue: Int {
        let used = annotations.compactMap { placed -> Int? in
            if case .number(_, let v, _) = placed.content { return v }
            return nil
        }
        return (used.max() ?? 0) + 1
    }

    private func appendAnnotation(_ content: Annotation) {
        pushUndoState()
        let start = videoMode ? playbackTime : 0
        annotations.append(PlacedAnnotation(content: content, startTime: start))
    }

    private func pushUndoState() {
        undoStack.append(annotations)
        if undoStack.count > Self.maxUndoLevels {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    func undo() {
        commitActiveTextField()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        setSelectedIndex(nil)
        needsDisplay = true
    }

    func redo() {
        commitActiveTextField()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        setSelectedIndex(nil)
        needsDisplay = true
    }

    /// Returns true when the event was handled (undo/redo).
    func handleUndoRedoKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "z" else { return false }
        if activeTextField != nil { return false }
        if let resp = window?.firstResponder as? NSTextView, resp.isFieldEditor { return false }
        if event.modifierFlags.contains(.shift) {
            redo()
        } else {
            undo()
        }
        return true
    }

    func installUndoRedoKeyMonitor(for window: NSWindow) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self, let window, event.window === window else { return event }
            return self.handleUndoRedoKeyEquivalent(event) ? nil : event
        }
    }

    private func setSelectedIndex(_ index: Int?) {
        selectedIndex = index
        onSelectionChanged?(index)
    }

    func setForever(for index: Int, forever: Bool) {
        guard annotations.indices.contains(index) else { return }
        if forever {
            annotations[index].visibleDuration = nil
        } else {
            annotations[index].visibleDuration = max(1, annotations[index].visibleDuration ?? 5)
        }
        needsDisplay = true
    }

    func setStartTime(for index: Int, seconds: Double, recordingDuration: Double) {
        guard annotations.indices.contains(index) else { return }
        let maxStart = max(0, floor(recordingDuration))
        let start = max(0, min(seconds.rounded(), maxStart))
        annotations[index].startTime = start
        if let duration = annotations[index].visibleDuration {
            let maxDuration = max(1, floor(recordingDuration) - start)
            annotations[index].visibleDuration = min(duration, maxDuration)
        }
        needsDisplay = true
    }

    func setVisibleDuration(for index: Int, seconds: Double, recordingDuration: Double = .infinity) {
        guard annotations.indices.contains(index) else { return }
        let start = annotations[index].startTime
        let maxDuration = recordingDuration.isFinite
            ? max(1, floor(recordingDuration) - start)
            : seconds
        annotations[index].visibleDuration = max(1, min(seconds.rounded(), maxDuration))
        needsDisplay = true
    }

    func selectionBoundingBox() -> CGRect? {
        guard let idx = selectedIndex, annotations.indices.contains(idx) else { return nil }
        return boundingBox(for: annotations[idx].content)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for placed in annotations {
            if !videoMode || placed.isVisible(at: playbackTime) {
                render(placed.content, in: ctx)
            }
        }
        if let cur = currentAnnotation { render(cur, in: ctx) }

        if selectedTool == .select, let idx = selectedIndex, idx < annotations.count {
            let content = annotations[idx].content
            switch content {
            case let .arrow(from, to, _, _):
                drawArrowSelectionHandles(from: from, to: to, in: ctx)
            case let .text(origin, text, _, maxWidth):
                drawTextSelectionHandles(metrics: textMetrics(origin: origin, text: text, maxWidth: maxWidth), in: ctx)
            case let .rect(rect, _):
                drawRectSelectionHandles(rect: rect, in: ctx)
            default:
                let box = boundingBox(for: content).insetBy(dx: -4, dy: -4)
                ctx.saveGState()
                ctx.setStrokeColor(NSColor.annotationSelectionAccent.cgColor)
                ctx.setLineWidth(1.5)
                ctx.addPath(CGPath(roundedRect: box, cornerWidth: 4, cornerHeight: 4, transform: nil))
                ctx.strokePath()
                ctx.restoreGState()
            }
        }
    }

    private struct TextMetrics {
        let origin: CGPoint
        let contentWidth: CGFloat
        let contentHeight: CGFloat
        let pillRect: CGRect
        let selectionRect: CGRect
        let leftHandle: CGPoint
        let rightHandle: CGPoint
    }

    private func textFont() -> NSFont {
        NSFont.systemFont(ofSize: 18, weight: .semibold)
    }

    private func textDrawAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        return [
            .font: textFont(),
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
    }

    private func textMetrics(origin: CGPoint, text: String, maxWidth: CGFloat?) -> TextMetrics {
        let font = textFont()
        let hPad = Self.textHPadding
        let vPad = Self.textVPadding
        let measureAttrs: [NSAttributedString.Key: Any] = [.font: font]
        let intrinsicWidth = (text as NSString).size(withAttributes: measureAttrs).width
        let contentWidth = max(maxWidth ?? intrinsicWidth, 1)
        let wrapAttrs = textDrawAttributes(color: .black)
        let contentHeight = ceil((text as NSString).boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: wrapAttrs
        ).height)
        let pillRect = CGRect(
            x: origin.x - hPad,
            y: origin.y - vPad,
            width: contentWidth + hPad * 2,
            height: contentHeight + vPad * 2
        )
        let midY = pillRect.midY
        return TextMetrics(
            origin: origin,
            contentWidth: contentWidth,
            contentHeight: contentHeight,
            pillRect: pillRect,
            selectionRect: pillRect,
            leftHandle: CGPoint(x: pillRect.minX, y: midY),
            rightHandle: CGPoint(x: pillRect.maxX, y: midY)
        )
    }

    private func drawRectSelectionHandles(rect: CGRect, in ctx: CGContext) {
        let armLength: CGFloat = 14
        let accent = NSColor.annotationSelectionAccent

        ctx.saveGState()
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(rect)

        ctx.setLineCap(.square)
        ctx.setLineWidth(3)
        ctx.setStrokeColor(NSColor.white.cgColor)
        addCornerBrackets(to: rect, armLength: armLength, in: ctx)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func addCornerBrackets(to rect: CGRect, armLength: CGFloat, in ctx: CGContext) {
        ctx.move(to: CGPoint(x: rect.minX, y: rect.minY + armLength))
        ctx.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        ctx.addLine(to: CGPoint(x: rect.minX + armLength, y: rect.minY))

        ctx.move(to: CGPoint(x: rect.maxX - armLength, y: rect.minY))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + armLength))

        ctx.move(to: CGPoint(x: rect.maxX, y: rect.maxY - armLength))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        ctx.addLine(to: CGPoint(x: rect.maxX - armLength, y: rect.maxY))

        ctx.move(to: CGPoint(x: rect.minX + armLength, y: rect.maxY))
        ctx.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        ctx.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - armLength))
    }

    private func drawTextSelectionHandles(metrics: TextMetrics, in ctx: CGContext) {
        let radius: CGFloat = 5
        let accent = NSColor.annotationSelectionAccent
        let cornerRadius: CGFloat = 2

        ctx.saveGState()
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(1.5)
        ctx.addPath(CGPath(
            roundedRect: metrics.selectionRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        ))
        ctx.strokePath()

        for point in [metrics.leftHandle, metrics.rightHandle] {
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: rect)
        }
        ctx.restoreGState()
    }

    private func drawArrowSelectionHandles(from: CGPoint, to: CGPoint, in ctx: CGContext) {
        let radius: CGFloat = 5
        let accent = NSColor.annotationSelectionAccent

        ctx.saveGState()
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(2)
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()
        ctx.restoreGState()

        for point in [from, to] {
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            ctx.saveGState()
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: rect)
            ctx.restoreGState()
        }
    }

    private func render(_ annotation: Annotation, in ctx: CGContext) {
        switch annotation {

        case let .stroke(points, color, lineWidth, tool):
            ctx.saveGState()
            ctx.setLineWidth(lineWidth)
            ctx.setStrokeColor(color.cgColor)
            ctx.setAlpha(tool == .highlighter ? 0.35 : 1.0)
            ctx.addPath(smoothPath(from: points))
            ctx.strokePath()
            ctx.restoreGState()

        case let .arrow(from, to, color, tipStyle):
            let lineWidth: CGFloat = 2.5
            guard let paths = arrowPaths(from: from, to: to, tipStyle: tipStyle, lineWidth: lineWidth) else { break }

            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -1),
                blur: 4,
                color: NSColor.black.withAlphaComponent(0.25).cgColor
            )
            ctx.setAlpha(1)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(tipStyle == .dot ? .round : .butt)
            ctx.setLineJoin(.miter)
            ctx.setMiterLimit(4)
            ctx.setStrokeColor(color.cgColor)
            ctx.addPath(paths.stroke)
            ctx.strokePath()

            if let fillPath = paths.fill {
                ctx.setFillColor(color.cgColor)
                ctx.addPath(fillPath)
                ctx.fillPath()
            }

            if tipStyle == .dot {
                let dotRect = CGRect(
                    x: to.x - arrowDotRadius,
                    y: to.y - arrowDotRadius,
                    width: arrowDotRadius * 2,
                    height: arrowDotRadius * 2
                )
                ctx.setFillColor(color.cgColor)
                ctx.fillEllipse(in: dotRect)
            }
            ctx.restoreGState()

        case let .rect(rect, color):
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -1),
                blur: 4,
                color: NSColor.black.withAlphaComponent(0.25).cgColor
            )
            ctx.setAlpha(1)
            let rounded = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
            ctx.setFillColor(color.withAlphaComponent(0.08).cgColor)
            ctx.addPath(rounded)
            ctx.fillPath()
            ctx.setLineWidth(2)
            ctx.setStrokeColor(color.cgColor)
            ctx.addPath(rounded)
            ctx.strokePath()
            ctx.restoreGState()

        case let .text(origin, text, color, maxWidth):
            ctx.saveGState()
            ctx.setAlpha(1)
            let metrics = textMetrics(origin: origin, text: text, maxWidth: maxWidth)
            let cornerRadius: CGFloat = 2
            let pillPath = CGPath(
                roundedRect: metrics.pillRect,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
            ctx.setFillColor(color.withAlphaComponent(0.12).cgColor)
            ctx.addPath(pillPath)
            ctx.fillPath()
            ctx.setStrokeColor(color.withAlphaComponent(0.18).cgColor)
            ctx.setLineWidth(1)
            ctx.addPath(pillPath)
            ctx.strokePath()
            let textRect = CGRect(
                origin: origin,
                size: CGSize(width: metrics.contentWidth, height: metrics.contentHeight)
            )
            (text as NSString).draw(
                with: textRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: textDrawAttributes(color: color)
            )
            ctx.restoreGState()

        case let .number(center, value, color):
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -1),
                blur: 4,
                color: NSColor.black.withAlphaComponent(0.25).cgColor
            )
            ctx.setAlpha(1)
            let sz: CGFloat = 24
            let circleRect = CGRect(x: center.x - sz / 2, y: center.y - sz / 2, width: sz, height: sz)
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: circleRect)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.2).cgColor)
            ctx.setLineWidth(0.5)
            ctx.strokeEllipse(in: circleRect.insetBy(dx: 0.25, dy: 0.25))

            let fg: NSColor = color.isLight ? .black : .white
            let numAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: fg,
            ]
            let s = "\(value)" as NSString
            let ss = s.size(withAttributes: numAttrs)
            s.draw(
                at: CGPoint(x: center.x - ss.width / 2, y: center.y - ss.height / 2),
                withAttributes: numAttrs
            )
            ctx.restoreGState()

        case let .emoji(center, symbolName, size, color):
            let symRect = NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
            let pointSize = size * 0.58
            guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { break }
            drawStickerSymbol(base: base, in: symRect, pointSize: pointSize, color: color)
        }
    }

    // MARK: Mouse Events

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

        if let field = activeTextField, !field.frame.contains(pt) {
            commitActiveTextField()
        }

        if selectedTool == .select {
            var found = false
            for i in stride(from: annotations.count - 1, through: 0, by: -1) {
                if hitTest(annotation: annotations[i].content, point: pt) {
                    setSelectedIndex(i)
                    selectDragSavedState = annotations
                    selectDidDrag = false
                    beginSelectDrag(at: pt, for: annotations[i].content)
                    found = true
                    break
                }
            }
            if !found {
                setSelectedIndex(nil)
                selectDragMode = .none
            }
            needsDisplay = true
            return
        }

        onWillDraw?()

        switch selectedTool {
        case .marker:
            strokePoints = [pt]
            currentAnnotation = .stroke(points: strokePoints, color: selectedColor, lineWidth: 4, tool: .marker)
        case .highlighter:
            strokePoints = [pt]
            currentAnnotation = .stroke(points: strokePoints, color: selectedColor, lineWidth: 14, tool: .highlighter)
        case .arrow:
            dragStart = pt
            currentAnnotation = .arrow(from: pt, to: pt, color: selectedColor, tipStyle: selectedArrowTipStyle)
        case .rect:
            dragStart = pt
            currentAnnotation = .rect(rect: CGRect(origin: pt, size: .zero), color: selectedColor)
        case .text:
            commitActiveTextField()
            placeTextField(at: pt)
            return
        case .number:
            appendAnnotation(.number(center: pt, value: nextNumberValue, color: selectedColor))
            needsDisplay = true
            return
        case .emoji:
            let winPt = convert(pt, to: nil)
            let screenPt = window.map { $0.convertPoint(toScreen: winPt) } ?? pt
            pendingEmojiPoint = pt
            activeEmojiPicker?.close()
            let picker = StickerPickerPanel(nearScreenPoint: screenPt, color: selectedColor) { [weak self] symbol in
                guard let self else { return }
                appendAnnotation(.emoji(center: pendingEmojiPoint, emoji: symbol, size: 40, color: selectedColor))
                activeEmojiPicker = nil
                needsDisplay = true
            }
            activeEmojiPicker = picker
            picker.show()
            return
        case .select:
            break
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

        switch selectedTool {
        case .marker:
            strokePoints.append(pt)
            currentAnnotation = .stroke(points: strokePoints, color: selectedColor, lineWidth: 4, tool: .marker)
        case .highlighter:
            strokePoints.append(pt)
            currentAnnotation = .stroke(points: strokePoints, color: selectedColor, lineWidth: 14, tool: .highlighter)
        case .arrow:
            currentAnnotation = .arrow(from: dragStart, to: pt, color: selectedColor, tipStyle: selectedArrowTipStyle)
        case .rect:
            currentAnnotation = .rect(
                rect: CGRect(
                    x: min(dragStart.x, pt.x), y: min(dragStart.y, pt.y),
                    width: abs(pt.x - dragStart.x), height: abs(pt.y - dragStart.y)
                ),
                color: selectedColor
            )
        case .select:
            if let idx = selectedIndex {
                selectDidDrag = true
                switch selectDragMode {
                case .moveWhole:
                    let delta = CGPoint(x: pt.x - dragOffset.x, y: pt.y - dragOffset.y)
                    annotations[idx].content = moved(annotations[idx].content, by: delta)
                    dragOffset = pt
                case .arrowStart:
                    if case let .arrow(_, to, color, tipStyle) = annotations[idx].content {
                        annotations[idx].content = .arrow(from: pt, to: to, color: color, tipStyle: tipStyle)
                    }
                case .arrowEnd:
                    if case let .arrow(from, _, color, tipStyle) = annotations[idx].content {
                        annotations[idx].content = .arrow(from: from, to: pt, color: color, tipStyle: tipStyle)
                    }
                case .textWidthLeft(let anchorRight):
                    if case let .text(origin, text, color, _) = annotations[idx].content {
                        let minWidth: CGFloat = 40
                        let newOriginX = min(pt.x + Self.textHPadding, anchorRight - minWidth)
                        let newWidth = anchorRight - newOriginX
                        annotations[idx].content = .text(
                            origin: CGPoint(x: newOriginX, y: origin.y),
                            text: text,
                            color: color,
                            maxWidth: newWidth
                        )
                    }
                case .textWidthRight(let anchorLeft):
                    if case let .text(origin, text, color, _) = annotations[idx].content {
                        let minWidth: CGFloat = 40
                        let newWidth = max(minWidth, pt.x - Self.textHPadding - anchorLeft)
                        annotations[idx].content = .text(
                            origin: origin,
                            text: text,
                            color: color,
                            maxWidth: newWidth
                        )
                    }
                case .rectResize(let handle, let anchor):
                    if case let .rect(_, color) = annotations[idx].content {
                        annotations[idx].content = .rect(
                            rect: resizedRect(anchor: anchor, handle: handle, to: pt),
                            color: color
                        )
                    }
                case .none:
                    break
                }
                onSelectionGeometryChanged?()
            }
        default:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let cur = currentAnnotation {
            appendAnnotation(cur)
            currentAnnotation = nil
            strokePoints = []
        }
        if let saved = selectDragSavedState, selectDidDrag {
            undoStack.append(saved)
            if undoStack.count > Self.maxUndoLevels {
                undoStack.removeFirst()
            }
            redoStack.removeAll()
        }
        selectDragSavedState = nil
        selectDidDrag = false
        selectDragMode = .none
        needsDisplay = true
    }

    // MARK: Text Tool

    private func textOrigin(for field: NSTextField) -> CGPoint {
        CGPoint(
            x: field.frame.minX + Self.textHPadding,
            y: field.frame.minY + Self.textVPadding
        )
    }

    private func textPillRect(origin: CGPoint, text: String, maxWidth: CGFloat?) -> CGRect {
        textMetrics(origin: origin, text: text, maxWidth: maxWidth).pillRect
    }

    private func resizeActiveTextField() {
        guard let field = activeTextField else { return }
        let origin = textOrigin(for: field)
        let measureText = field.stringValue.isEmpty
            ? (field.placeholderString ?? " ")
            : field.stringValue
        field.frame = textPillRect(origin: origin, text: measureText, maxWidth: nil)
    }

    private func placeTextField(at pt: CGPoint) {
        let placeholder = "Type here…"
        let frame = textPillRect(origin: pt, text: placeholder, maxWidth: nil)

        let field = AnnotationTextField(frame: frame)
        field.isEditable = true
        field.isBordered = false
        field.drawsBackground = false
        field.textColor = selectedColor
        field.font = textFont()
        field.placeholderString = placeholder
        field.focusRingType = .none

        field.target = self
        field.action = #selector(enterPressed(_:))
        field.onEscape = { [weak self] in
            self?.commitActiveTextField()
            self?.onEscapeAction?()
        }
        field.onTextDidChange = { [weak self] in
            self?.resizeActiveTextField()
        }
        field.delegate = self

        addSubview(field)
        activeTextField = field
        window?.makeFirstResponder(field)
    }

    @objc private func enterPressed(_ sender: Any) {
        commitActiveTextField()
        window?.makeFirstResponder(self)
    }

    func commitActiveTextField() {
        guard let field = activeTextField else { return }
        activeTextField = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            appendAnnotation(.text(
                origin: textOrigin(for: field),
                text: text,
                color: field.textColor ?? selectedColor,
                maxWidth: nil
            ))
        }
        field.removeFromSuperview()
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? AnnotationTextField, field === activeTextField else { return }
        commitActiveTextField()
    }

    // MARK: Keyboard

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleUndoRedoKeyEquivalent(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleUndoRedoKeyEquivalent(event) { return }

        let ch = event.charactersIgnoringModifiers ?? ""

        if selectedTool == .select, event.keyCode == 51, let idx = selectedIndex {
            pushUndoState()
            annotations.remove(at: idx)
            setSelectedIndex(nil)
            needsDisplay = true
            return
        }

        switch ch {
        case "s": activate(.select)
        case "m": activate(.marker)
        case "h": activate(.highlighter)
        case "a": activate(.arrow)
        case "r": activate(.rect)
        case "t": activate(.text)
        case "n": activate(.number)
        case "e": activate(.emoji)
        case "\u{1B}":
            commitActiveTextField()
            onEscapeAction?()
        default:
            super.keyDown(with: event)
        }
    }

    private func activate(_ tool: AnnotationTool) {
        commitActiveTextField()
        activeEmojiPicker?.close()
        activeEmojiPicker = nil
        setSelectedIndex(nil)
        selectedTool = tool
        onToolChanged?(tool)
    }

    // MARK: Select Helpers

    private enum ArrowDragTarget {
        case start, end, shaft
    }

    private func arrowDragTarget(point: CGPoint, from: CGPoint, to: CGPoint) -> ArrowDragTarget {
        let hitRadius: CGFloat = 8
        if hypot(point.x - from.x, point.y - from.y) <= hitRadius { return .start }
        if hypot(point.x - to.x, point.y - to.y) <= hitRadius { return .end }
        return .shaft
    }

    private func beginSelectDrag(at point: CGPoint, for annotation: Annotation) {
        if case let .arrow(from, to, _, _) = annotation {
            switch arrowDragTarget(point: point, from: from, to: to) {
            case .start: selectDragMode = .arrowStart
            case .end: selectDragMode = .arrowEnd
            case .shaft:
                selectDragMode = .moveWhole
                dragOffset = point
            }
        } else if case let .text(origin, text, _, maxWidth) = annotation {
            let metrics = textMetrics(origin: origin, text: text, maxWidth: maxWidth)
            let hitRadius: CGFloat = 8
            if hypot(point.x - metrics.leftHandle.x, point.y - metrics.leftHandle.y) <= hitRadius {
                selectDragMode = .textWidthLeft(anchorRight: metrics.origin.x + metrics.contentWidth)
            } else if hypot(point.x - metrics.rightHandle.x, point.y - metrics.rightHandle.y) <= hitRadius {
                selectDragMode = .textWidthRight(anchorLeft: metrics.origin.x)
            } else {
                selectDragMode = .moveWhole
                dragOffset = point
            }
        } else if case let .rect(rect, _) = annotation {
            if let handle = rectHitTestHandle(at: point, in: rect) {
                selectDragMode = .rectResize(handle: handle, anchor: rect)
            } else {
                selectDragMode = .moveWhole
                dragOffset = point
            }
        } else {
            selectDragMode = .moveWhole
            dragOffset = point
        }
    }

    private func distanceFromPoint(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private func rectCornerHitTargets(in rect: CGRect) -> [(CGPoint, RectResizeHandle)] {
        [
            (CGPoint(x: rect.minX, y: rect.minY), .bottomLeft),
            (CGPoint(x: rect.maxX, y: rect.minY), .bottomRight),
            (CGPoint(x: rect.maxX, y: rect.maxY), .topRight),
            (CGPoint(x: rect.minX, y: rect.maxY), .topLeft),
        ]
    }

    private func rectInterior(of rect: CGRect) -> CGRect {
        rect.insetBy(dx: rectCornerHitRadius + 2, dy: rectCornerHitRadius + 2)
    }

    private func rectHitTestHandle(at point: CGPoint, in rect: CGRect) -> RectResizeHandle? {
        for (p, handle) in rectCornerHitTargets(in: rect) {
            if hypot(point.x - p.x, point.y - p.y) <= rectCornerHitRadius {
                return handle
            }
        }

        let t = rectEdgeHitThickness / 2
        let inset = rectCornerHitRadius

        if point.y >= rect.minY - t, point.y <= rect.minY + t,
           point.x >= rect.minX + inset, point.x <= rect.maxX - inset {
            return .bottom
        }
        if point.y >= rect.maxY - t, point.y <= rect.maxY + t,
           point.x >= rect.minX + inset, point.x <= rect.maxX - inset {
            return .top
        }
        if point.x >= rect.minX - t, point.x <= rect.minX + t,
           point.y >= rect.minY + inset, point.y <= rect.maxY - inset {
            return .left
        }
        if point.x >= rect.maxX - t, point.x <= rect.maxX + t,
           point.y >= rect.minY + inset, point.y <= rect.maxY - inset {
            return .right
        }

        return nil
    }

    private func resizedRect(anchor: CGRect, handle: RectResizeHandle, to point: CGPoint) -> CGRect {
        let minSize = rectMinSize
        var minX = anchor.minX
        var minY = anchor.minY
        var maxX = anchor.maxX
        var maxY = anchor.maxY

        switch handle {
        case .topLeft:
            minX = min(point.x, maxX - minSize)
            maxY = max(point.y, minY + minSize)
        case .top:
            maxY = max(point.y, minY + minSize)
        case .topRight:
            maxX = max(point.x, minX + minSize)
            maxY = max(point.y, minY + minSize)
        case .right:
            maxX = max(point.x, minX + minSize)
        case .bottomRight:
            maxX = max(point.x, minX + minSize)
            minY = min(point.y, maxY - minSize)
        case .bottom:
            minY = min(point.y, maxY - minSize)
        case .bottomLeft:
            minX = min(point.x, maxX - minSize)
            minY = min(point.y, maxY - minSize)
        case .left:
            minX = min(point.x, maxX - minSize)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func hitTest(annotation: Annotation, point: CGPoint) -> Bool {
        switch annotation {
        case let .stroke(points, _, _, _):
            if points.count == 1, let p = points.first {
                return hypot(point.x - p.x, point.y - p.y) < 8
            }
            for i in 0 ..< points.count - 1 {
                if distanceFromPoint(point, toSegment: points[i], points[i + 1]) < 8 { return true }
            }
            return false
        case let .arrow(from, to, _, _):
            return distanceFromPoint(point, toSegment: from, to) < 8
        case let .rect(rect, _):
            return rectHitTestHandle(at: point, in: rect) != nil
                || rectInterior(of: rect).contains(point)
                || rect.insetBy(dx: -rectCornerHitRadius, dy: -rectCornerHitRadius).contains(point)
        case let .text(origin, text, _, maxWidth):
            return textMetrics(origin: origin, text: text, maxWidth: maxWidth).pillRect.contains(point)
        case let .number(center, _, _):
            return hypot(point.x - center.x, point.y - center.y) < 16
        case let .emoji(center, _, size, _):
            return hypot(point.x - center.x, point.y - center.y) < size / 2 + 4
        }
    }

    private func moved(_ annotation: Annotation, by delta: CGPoint) -> Annotation {
        switch annotation {
        case let .stroke(points, color, lineWidth, tool):
            return .stroke(
                points: points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) },
                color: color, lineWidth: lineWidth, tool: tool
            )
        case let .arrow(from, to, color, tipStyle):
            return .arrow(
                from: CGPoint(x: from.x + delta.x, y: from.y + delta.y),
                to: CGPoint(x: to.x + delta.x, y: to.y + delta.y),
                color: color,
                tipStyle: tipStyle
            )
        case let .rect(rect, color):
            return .rect(rect: rect.offsetBy(dx: delta.x, dy: delta.y), color: color)
        case let .text(origin, text, color, maxWidth):
            return .text(
                origin: CGPoint(x: origin.x + delta.x, y: origin.y + delta.y),
                text: text, color: color, maxWidth: maxWidth
            )
        case let .number(center, value, color):
            return .number(
                center: CGPoint(x: center.x + delta.x, y: center.y + delta.y),
                value: value, color: color
            )
        case let .emoji(center, emoji, size, color):
            return .emoji(
                center: CGPoint(x: center.x + delta.x, y: center.y + delta.y),
                emoji: emoji, size: size, color: color
            )
        }
    }

    private func boundingBox(for annotation: Annotation) -> CGRect {
        switch annotation {
        case let .stroke(points, _, lineWidth, _):
            guard !points.isEmpty else { return .zero }
            let xs = points.map(\.x), ys = points.map(\.y)
            let pad = lineWidth / 2 + 4
            return CGRect(
                x: xs.min()! - pad, y: ys.min()! - pad,
                width: xs.max()! - xs.min()! + pad * 2,
                height: ys.max()! - ys.min()! + pad * 2
            )
        case let .arrow(from, to, _, _):
            let minX = min(from.x, to.x), minY = min(from.y, to.y)
            return CGRect(
                x: minX - 12, y: minY - 12,
                width: abs(to.x - from.x) + 24, height: abs(to.y - from.y) + 24
            )
        case let .rect(rect, _):
            return rect
        case let .text(origin, text, _, maxWidth):
            return textMetrics(origin: origin, text: text, maxWidth: maxWidth).selectionRect
        case let .number(center, _, _):
            return CGRect(x: center.x - 16, y: center.y - 16, width: 32, height: 32)
        case let .emoji(center, _, size, _):
            let r = size / 2 + StickerStyle.outlineWidth
            return CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        }
    }

    // MARK: Flatten

    func flattenedImage(background: NSImage) -> NSImage {
        flattenedImage(
            background: background,
            at: playbackTime,
            outputSize: bounds.size,
            mapFromCanvasSize: bounds.size
        )
    }

    func flattenedImage(
        background: NSImage,
        at time: Double,
        outputSize: CGSize,
        mapFromCanvasSize canvasSize: CGSize
    ) -> NSImage {
        commitActiveTextField()
        guard outputSize.width > 0, outputSize.height > 0 else { return background }

        let result = NSImage(size: outputSize)
        result.lockFocus()
        defer { result.unlockFocus() }

        background.draw(
            in: NSRect(origin: .zero, size: outputSize),
            from: NSRect(origin: .zero, size: background.size),
            operation: .sourceOver,
            fraction: 1.0
        )

        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            if canvasSize.width > 0, canvasSize.height > 0,
               outputSize.width != canvasSize.width || outputSize.height != canvasSize.height {
                let sx = outputSize.width / canvasSize.width
                let sy = outputSize.height / canvasSize.height
                ctx.scaleBy(x: sx, y: sy)
            }
            for placed in annotations {
                if !videoMode || placed.isVisible(at: time) {
                    render(placed.content, in: ctx)
                }
            }
        }

        return result
    }
}

// MARK: - CircleColorButton

final class CircleColorButton: NSButton {
    let color: NSColor

    var isColorSelected: Bool = false {
        didSet { needsDisplay = true }
    }

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        bezelStyle = .regularSquare
        isBordered = false
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds

        if isColorSelected {
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: b)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.15).cgColor)
            ctx.setLineWidth(0.5)
            ctx.strokeEllipse(in: b.insetBy(dx: 0.25, dy: 0.25))
        }

        let inset: CGFloat = isColorSelected ? 3 : 0
        let cr = b.insetBy(dx: inset, dy: inset)
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: cr)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.12).cgColor)
        ctx.setLineWidth(0.5)
        ctx.strokeEllipse(in: cr.insetBy(dx: 0.25, dy: 0.25))
    }
}

// MARK: - ToolTooltipPanel

final class ToolTooltipPanel: NSPanel {

    private let nameLabel: NSTextField
    private let shortcutLabel: NSTextField
    private let box: NSView

    init() {
        box = NSView(frame: .zero)
        nameLabel = NSTextField(labelWithString: "")
        shortcutLabel = NSTextField(labelWithString: "")

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 26),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .popUpMenu
        hasShadow = true
        ignoresMouseEvents = true

        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        box.layer?.cornerRadius = 2

        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = .white
        nameLabel.isBezeled = false
        nameLabel.isEditable = false
        nameLabel.drawsBackground = false

        shortcutLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        shortcutLabel.textColor = NSColor.white.withAlphaComponent(0.48)
        shortcutLabel.isBezeled = false
        shortcutLabel.isEditable = false
        shortcutLabel.drawsBackground = false

        box.addSubview(nameLabel)
        box.addSubview(shortcutLabel)
        contentView = box
    }

    func show(for tool: AnnotationTool, aboveScreenRect buttonRect: NSRect) {
        nameLabel.stringValue = tool.displayName
        shortcutLabel.stringValue = tool.shortcutKey

        nameLabel.sizeToFit()
        shortcutLabel.sizeToFit()

        let hPad: CGFloat = 8
        let vPad: CGFloat = 5
        let gap: CGFloat = 5

        let nw = nameLabel.frame.width
        let nh = nameLabel.frame.height
        let sw = shortcutLabel.frame.width
        let sh = shortcutLabel.frame.height

        let totalW = hPad + nw + gap + sw + hPad
        let totalH = vPad + max(nh, sh) + vPad

        nameLabel.frame = NSRect(x: hPad, y: vPad, width: nw, height: nh)
        shortcutLabel.frame = NSRect(
            x: hPad + nw + gap,
            y: vPad + (nh - sh) / 2,
            width: sw, height: sh
        )
        box.frame = NSRect(x: 0, y: 0, width: totalW, height: totalH)

        let panelX = (buttonRect.midX - totalW / 2).rounded()
        let panelY = buttonRect.maxY + 6
        let finalFrame = NSRect(x: panelX, y: panelY, width: totalW, height: totalH)
        let startFrame = NSRect(x: panelX, y: panelY - 6, width: totalW, height: totalH)

        setFrame(startFrame, display: false)
        alphaValue = 0
        orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(finalFrame, display: true)
        }
    }

    func hide() { orderOut(nil) }
}

// MARK: - ArrowStyleMenuPanel

final class ArrowStyleMenuPanel: NSObject {

    private let panel: NSPanel
    private let onSelect: (ArrowTipStyle) -> Void
    private var styleButtons: [ArrowTipStyle: NSButton] = [:]
    private var clickOutsideMonitor: Any?
    private var accentColor: NSColor = .systemBlue
    private var anchorScreenRect: NSRect = .zero

    init(onSelect: @escaping (ArrowTipStyle) -> Void) {
        self.onSelect = onSelect

        let btnSz: CGFloat = 32
        let gap: CGFloat = 4
        let pad: CGFloat = 6
        let count = CGFloat(ArrowTipStyle.allCases.count)
        let panelW = pad * 2 + btnSz
        let panelH = pad * 2 + count * btnSz + (count - 1) * gap

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelW, height: panelH),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.hidesOnDeactivate = true

        super.init()
        buildUI(btnSz: btnSz, gap: gap, pad: pad)
    }

    private func buildUI(btnSz: CGFloat, gap: CGFloat, pad: CGFloat) {
        let container = NSView(frame: panel.contentView!.bounds)
        container.autoresizingMask = [.width, .height]

        let vfx = NSVisualEffectView(frame: container.bounds)
        vfx.autoresizingMask = [.width, .height]
        vfx.material = .popover
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = 12
        vfx.layer?.masksToBounds = true
        container.addSubview(vfx)

        var y = pad
        for style in ArrowTipStyle.allCases {
            let btn = NSButton(frame: CGRect(x: pad, y: y, width: btnSz, height: btnSz))
            btn.bezelStyle = .regularSquare
            btn.isBordered = false
            let cfg = NSImage.SymbolConfiguration(pointSize: style.menuSymbolPointSize, weight: .medium)
            btn.image = NSImage(systemSymbolName: style.menuSymbol, accessibilityDescription: style.accessibilityLabel)?
                .withSymbolConfiguration(cfg)
            btn.imageScaling = .scaleProportionallyDown
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            btn.target = self
            btn.action = #selector(styleTapped(_:))
            btn.tag = ArrowTipStyle.allCases.firstIndex(of: style) ?? 0
            btn.toolTip = style.accessibilityLabel
            container.addSubview(btn)
            styleButtons[style] = btn
            y += btnSz + gap
        }

        panel.contentView = container
    }

    func show(aboveScreenRect buttonRect: NSRect, selectedStyle: ArrowTipStyle, accentColor: NSColor) {
        hide()
        self.accentColor = accentColor
        self.anchorScreenRect = buttonRect
        refreshSelection(selectedStyle)

        let panelW = panel.frame.width
        let panelX = (buttonRect.midX - panelW / 2).rounded()
        let panelY = buttonRect.maxY + 6
        panel.setFrameOrigin(NSPoint(x: panelX, y: panelY))
        panel.orderFront(nil)

        clickOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if let contentView = self.panel.contentView {
                let point = contentView.convert(event.locationInWindow, from: nil)
                if contentView.bounds.contains(point) { return event }
            }
            if self.anchorScreenRect.contains(NSEvent.mouseLocation) { return event }
            self.hide()
            return event
        }
    }

    func hide() {
        if let clickOutsideMonitor {
            NSEvent.removeMonitor(clickOutsideMonitor)
            self.clickOutsideMonitor = nil
        }
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    private func refreshSelection(_ selectedStyle: ArrowTipStyle) {
        for (style, btn) in styleButtons {
            let on = style == selectedStyle
            btn.contentTintColor = on ? accentColor : .labelColor
            btn.layer?.backgroundColor = on ? accentColor.withAlphaComponent(0.2).cgColor : .clear
        }
    }

    @objc private func styleTapped(_ sender: NSButton) {
        let styles = ArrowTipStyle.allCases
        guard sender.tag < styles.count else { return }
        let style = styles[sender.tag]
        hide()
        onSelect(style)
    }
}

// MARK: - ToolHoverButton

final class ToolHoverButton: NSButton {

    var tool: AnnotationTool?
    var onTooltipRequested: ((NSRect) -> Void)?
    var onTooltipDismissed: (() -> Void)?

    private var hoverOverlay: CALayer?
    private var tooltipTimer: Timer?
    private var isInsideBounds = false

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
        super.mouseEntered(with: event)
        guard !isInsideBounds else { return }
        isInsideBounds = true
        showHoverOverlay()
        scheduleTooltip()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isInsideBounds = false
        removeHoverOverlay()
        cancelTooltip()
        onTooltipDismissed?()
    }

    private func showHoverOverlay() {
        guard hoverOverlay == nil, let layer else { return }
        let hl = CALayer()
        hl.frame = layer.bounds
        hl.cornerRadius = layer.cornerRadius
        hl.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor
        layer.addSublayer(hl)
        hoverOverlay = hl
    }

    private func removeHoverOverlay() {
        hoverOverlay?.removeFromSuperlayer()
        hoverOverlay = nil
    }

    private func scheduleTooltip() {
        tooltipTimer?.invalidate()
        tooltipTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.isInsideBounds, let win = self.window else { return }
                let winRect = self.convert(self.bounds, to: nil)
                let screenRect = win.convertToScreen(winRect)
                self.onTooltipRequested?(screenRect)
            }
        }
    }

    private func cancelTooltip() {
        tooltipTimer?.invalidate()
        tooltipTimer = nil
    }
}

// MARK: - ToolbarPillView

final class ToolbarPillView: NSView {

    var selectedTool: AnnotationTool = .marker { didSet { refresh() } }
    var selectedColorIndex: Int = 0 { didSet { refresh() } }
    var selectedArrowTipStyle: ArrowTipStyle = .solid { didSet { refresh() } }
    var selectedColor: NSColor { NSColor.annotationPalette[selectedColorIndex] }

    var onToolSelected: ((AnnotationTool) -> Void)?
    var onColorSelected: ((Int) -> Void)?
    var onArrowTipStyleSelected: ((ArrowTipStyle) -> Void)?
    var onCopy: (() -> Void)?

    private let showsCopyButton: Bool
    private var copyButton: NSButton?

    private var toolButtons: [AnnotationTool: ToolHoverButton] = [:]
    private var colorButtons: [Int: CircleColorButton] = [:]
    private let tooltipPanel = ToolTooltipPanel()
    private var arrowStyleMenu: ArrowStyleMenuPanel!

    init(frame: NSRect, showsCopyButton: Bool = true) {
        self.showsCopyButton = showsCopyButton
        super.init(frame: frame)
        build()
    }

    override init(frame: NSRect) {
        self.showsCopyButton = true
        super.init(frame: frame)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        arrowStyleMenu = ArrowStyleMenuPanel { [weak self] style in
            guard let self else { return }
            self.selectedArrowTipStyle = style
            self.onArrowTipStyleSelected?(style)
        }

        let h: CGFloat = 40
        let btnSz: CGFloat = 28
        let btnY = (h - btnSz) / 2
        var x: CGFloat = 0

        for (i, tool) in AnnotationTool.allCases.enumerated() {
            let btn = ToolHoverButton(frame: CGRect(x: x, y: btnY, width: btnSz, height: btnSz))
            btn.bezelStyle = .regularSquare
            btn.isBordered = false
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            btn.image = NSImage(systemSymbolName: tool.sfSymbol, accessibilityDescription: tool.sfSymbol)?
                            .withSymbolConfiguration(cfg)
            btn.imageScaling = .scaleProportionallyDown
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            btn.tag = i
            btn.target = self
            btn.action = #selector(toolTapped(_:))
            btn.tool = tool
            btn.onTooltipRequested = { [weak self] screenRect in
                self?.showTooltip(for: tool, at: screenRect)
            }
            btn.onTooltipDismissed = { [weak self] in
                self?.tooltipPanel.hide()
            }
            addSubview(btn)
            toolButtons[tool] = btn
            x += btnSz + 2
        }

        x += 6
        addSubview(makeSeparator(at: x, height: h))
        x += 9

        let swSz: CGFloat = 16
        let swY = (h - swSz) / 2
        for (i, color) in NSColor.annotationPalette.enumerated() {
            let btn = CircleColorButton(color: color)
            btn.frame = CGRect(x: x, y: swY, width: swSz, height: swSz)
            btn.tag = i
            btn.target = self
            btn.action = #selector(colorTapped(_:))
            addSubview(btn)
            colorButtons[i] = btn
            x += swSz + 5
        }

        if showsCopyButton {
            x += 4
            addSubview(makeSeparator(at: x, height: h))
            x += 9

            let copyBtn = NSButton(frame: CGRect(x: x, y: btnY, width: 50, height: btnSz))
            copyBtn.bezelStyle = .regularSquare
            copyBtn.isBordered = false
            copyBtn.title = "Copy"
            copyBtn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            copyBtn.target = self
            copyBtn.action = #selector(copyTapped)
            addSubview(copyBtn)
            copyButton = copyBtn
            x += 50
        }

        setFrameSize(NSSize(width: x, height: h))
        refresh()
    }

    private func makeSeparator(at x: CGFloat, height: CGFloat) -> NSView {
        let v = NSView(frame: CGRect(x: x, y: 8, width: 1, height: height - 16))
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.separatorColor.cgColor
        return v
    }

    // MARK: Actions

    @objc private func toolTapped(_ sender: NSButton) {
        tooltipPanel.hide()
        let tools = AnnotationTool.allCases
        guard sender.tag < tools.count else { return }
        let tool = tools[sender.tag]

        if tool == .arrow, tool == selectedTool, let btn = toolButtons[.arrow], let win = window {
            if arrowStyleMenu.isVisible {
                arrowStyleMenu.hide()
            } else {
                let btnRect = btn.convert(btn.bounds, to: nil)
                let screenRect = win.convertToScreen(btnRect)
                arrowStyleMenu.show(
                    aboveScreenRect: screenRect,
                    selectedStyle: selectedArrowTipStyle,
                    accentColor: selectedColor
                )
            }
            return
        }

        arrowStyleMenu.hide()
        onToolSelected?(tool)
    }

    private func showTooltip(for tool: AnnotationTool, at screenRect: NSRect) {
        tooltipPanel.show(for: tool, aboveScreenRect: screenRect)
    }

    @objc private func colorTapped(_ sender: NSButton) {
        arrowStyleMenu.hide()
        onColorSelected?(sender.tag)
    }

    @objc private func copyTapped() {
        onCopy?()
    }

    // MARK: Refresh

    private func refresh() {
        let active = selectedColor
        for (tool, btn) in toolButtons {
            let on = tool == selectedTool
            btn.layer?.backgroundColor = on ? active.withAlphaComponent(0.2).cgColor : .clear
            btn.contentTintColor = on ? active : .labelColor
        }
        for (i, btn) in colorButtons {
            btn.isColorSelected = (i == selectedColorIndex)
        }

        if selectedTool != .arrow {
            arrowStyleMenu?.hide()
        }
    }
}

// MARK: - AnnotationWindow

final class AnnotationWindow: NSWindow {

    private static var current: AnnotationWindow?

    private let screenshot: NSImage
    private let canvas: AnnotationCanvasView
    private var pill: ToolbarPillView!
    private var undoRedoKeyMonitor: Any?

    private let toolbarHeight: CGFloat = 40
    private let toolbarHorizontalInset: CGFloat = 12

    // MARK: Entry Point

    static func show(image: NSImage) {
        DispatchQueue.main.async {
            current = AnnotationWindow(image: image)
            current?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: Init

    private init(image: NSImage) {
        self.screenshot = image
        let imageSize = AnnotationWindow.fittedSize(for: image)
        self.canvas = AnnotationCanvasView(frame: NSRect(origin: .zero, size: imageSize))

        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: screenRect.midX - imageSize.width / 2,
            y: screenRect.midY - imageSize.height / 2
        )

        super.init(
            contentRect: NSRect(origin: origin, size: imageSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "Annotate"
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false

        buildLayout(imageSize: imageSize)
        wire()
    }

    // MARK: Layout

    private static func fittedSize(for image: NSImage) -> NSSize {
        let s = image.size
        guard s.width > 0, s.height > 0 else { return NSSize(width: 800, height: 600) }
        let scale = min(1200 / s.width, 800 / s.height, 1.0)
        return NSSize(width: (s.width * scale).rounded(), height: (s.height * scale).rounded())
    }

    private func buildLayout(imageSize: NSSize) {
        pill = ToolbarPillView(frame: CGRect(x: 0, y: 0, width: 100, height: 40))

        let minWidth = pill.frame.width + toolbarHorizontalInset * 2
        let contentWidth = max(imageSize.width, minWidth)
        let imageOffsetX = ((contentWidth - imageSize.width) / 2).rounded()

        let totalH = imageSize.height + toolbarHeight
        setContentSize(NSSize(width: contentWidth, height: totalH))

        let root = NSView(frame: NSRect(origin: .zero, size: NSSize(width: contentWidth, height: totalH)))

        let imageView = NSImageView(frame: NSRect(
            x: imageOffsetX, y: toolbarHeight, width: imageSize.width, height: imageSize.height
        ))
        imageView.image = screenshot
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        root.addSubview(imageView)

        canvas.frame = imageView.frame
        root.addSubview(canvas)

        let tbBg = NSView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: toolbarHeight))
        tbBg.wantsLayer = true
        tbBg.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.addSubview(tbBg)

        let sep = NSView(frame: NSRect(x: 0, y: toolbarHeight - 1, width: contentWidth, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        root.addSubview(sep)

        pill.frame.origin = CGPoint(x: toolbarHorizontalInset, y: 0)
        root.addSubview(pill)

        contentView = root
        makeFirstResponder(canvas)
    }

    // MARK: Wire

    private func wire() {
        pill.selectedTool = .marker
        pill.selectedColorIndex = 0

        canvas.onToolChanged = { [weak self] tool in
            self?.pill.selectedTool = tool
        }

        canvas.onEscapeAction = { [weak self] in
            self?.flattenCopyAndClose()
        }

        pill.onToolSelected = { [weak self] tool in
            guard let self else { return }
            canvas.selectedTool = tool
            pill.selectedTool = tool
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

        pill.onCopy = { [weak self] in
            self?.flattenAndCopy()
        }

        undoRedoKeyMonitor = canvas.installUndoRedoKeyMonitor(for: self)
    }

    override func close() {
        if let undoRedoKeyMonitor {
            NSEvent.removeMonitor(undoRedoKeyMonitor)
            self.undoRedoKeyMonitor = nil
        }
        super.close()
    }

    // MARK: Actions

    private func flattenAndCopy() {
        let img = canvas.flattenedImage(background: screenshot)
        guard let tiff = img.tiffRepresentation else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(tiff, forType: .tiff)
    }

    private func flattenCopyAndClose() {
        flattenAndCopy()
        close()
    }
}
