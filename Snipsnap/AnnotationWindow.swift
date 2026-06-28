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
    case marker, highlighter, arrow, rect, text, number, emoji

    var sfSymbol: String {
        switch self {
        case .marker:      return "scribble"
        case .highlighter: return "highlighter"
        case .arrow:       return "arrow.up.right"
        case .rect:        return "rectangle"
        case .text:        return "textformat"
        case .number:      return "number.circle"
        case .emoji:       return "face.smiling"
        }
    }
}

enum Annotation {
    case stroke(points: [CGPoint], color: NSColor, lineWidth: CGFloat, tool: StrokeTool)
    case arrow(from: CGPoint, to: CGPoint, color: NSColor)
    case rect(rect: CGRect, color: NSColor)
    case text(origin: CGPoint, text: String, color: NSColor)
    case number(center: CGPoint, value: Int, color: NSColor)
    case emoji(center: CGPoint, emoji: String, size: CGFloat)
}

// MARK: - Color Palette

extension NSColor {
    static let annotationPalette: [NSColor] = [
        NSColor(hex24: 0xFF3B30),
        NSColor(hex24: 0xFF9500),
        NSColor(hex24: 0xFFCC00),
        NSColor(hex24: 0x34C759),
        NSColor(hex24: 0x007AFF),
        NSColor(hex24: 0xAF52DE),
        .black,
        .white,
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

func arrowPath(from start: CGPoint, to end: CGPoint) -> (shaft: CGPath, head: CGPath) {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let len = hypot(dx, dy)
    guard len > 4 else {
        let empty = CGMutablePath()
        return (empty, empty)
    }

    let angle = atan2(dy, dx)
    let headLen: CGFloat = min(16, len * 0.35)
    let headAngle: CGFloat = .pi / 6

    let shaft = CGMutablePath()
    shaft.move(to: start)
    shaft.addLine(to: CGPoint(
        x: end.x - cos(angle) * headLen * 0.55,
        y: end.y - sin(angle) * headLen * 0.55
    ))

    let head = CGMutablePath()
    head.move(to: end)
    head.addLine(to: CGPoint(
        x: end.x - headLen * cos(angle - headAngle),
        y: end.y - headLen * sin(angle - headAngle)
    ))
    head.addLine(to: CGPoint(
        x: end.x - headLen * cos(angle + headAngle),
        y: end.y - headLen * sin(angle + headAngle)
    ))
    head.closeSubpath()

    return (shaft, head)
}

// MARK: - AnnotationTextField

/// NSTextField subclass that intercepts Escape before AppKit can beep.
final class AnnotationTextField: NSTextField {
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - EmojiPickerPanel

final class EmojiPickerPanel: NSObject, NSWindowDelegate {

    private static let emojiKeywords: [(emoji: String, keys: [String])] = [
        ("👍", ["thumbs", "up", "like", "good", "ok"]),
        ("❤️", ["heart", "love", "red"]),
        ("🔥", ["fire", "hot", "flame"]),
        ("✅", ["check", "done", "yes", "ok", "green"]),
        ("❌", ["cross", "no", "wrong", "error", "x"]),
        ("⚠️", ["warning", "caution", "alert"]),
        ("💡", ["idea", "light", "bulb", "tip"]),
        ("🎉", ["party", "celebrate", "tada", "congrats"]),
        ("👀", ["eyes", "look", "watch", "see"]),
        ("💬", ["comment", "chat", "speech", "bubble", "message"]),
        ("🐛", ["bug", "error", "issue"]),
        ("⭐️", ["star", "favorite", "rate"]),
    ]
    private static let defaultEmojis: [String] = emojiKeywords.map(\.emoji)

    private let panel: NSPanel
    private let onSelect: (String) -> Void
    private var filteredEmojis: [String] = defaultEmojis
    private weak var gridStack: NSStackView?

    init(nearScreenPoint point: CGPoint, onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect

        let panelW: CGFloat = 220
        let panelH: CGFloat = 190
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

        let search = NSSearchField()
        search.translatesAutoresizingMaskIntoConstraints = false
        search.placeholderString = "Search emoji…"
        search.target = self
        search.action = #selector(searchChanged(_:))

        let grid = NSStackView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.orientation = .vertical
        grid.spacing = 2
        gridStack = grid

        container.addSubview(search)
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            search.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            search.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            grid.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 6),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -8),
        ])
        panel.contentView = container
        rebuildGrid()
    }

    private func rebuildGrid() {
        guard let grid = gridStack else { return }
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let cols = 4
        var rowViews: [NSView] = []
        for (i, em) in filteredEmojis.enumerated() {
            let btn = NSButton(frame: .zero)
            btn.title = em
            btn.font = NSFont.systemFont(ofSize: 24)
            btn.isBordered = false
            btn.bezelStyle = .regularSquare
            btn.target = self
            btn.action = #selector(emojiTapped(_:))
            rowViews.append(btn)
            if rowViews.count == cols || i == filteredEmojis.count - 1 {
                let row = NSStackView(views: rowViews)
                row.orientation = .horizontal
                row.spacing = 2
                row.distribution = .fillEqually
                grid.addArrangedSubview(row)
                rowViews = []
            }
        }
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        let q = sender.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            filteredEmojis = Self.defaultEmojis
        } else {
            let matches = Self.emojiKeywords.filter { _, keys in
                keys.contains { $0.hasPrefix(q) }
            }.map(\.emoji)
            filteredEmojis = matches.isEmpty ? Self.defaultEmojis : matches
        }
        rebuildGrid()
    }

    @objc private func emojiTapped(_ sender: NSButton) {
        let em = sender.title
        panel.close()
        onSelect(em)
    }

    func show() { panel.makeKeyAndOrderFront(nil) }
    func close() { panel.close() }
}

// MARK: - AnnotationCanvasView

final class AnnotationCanvasView: NSView {

    // All committed annotations.
    var annotations: [Annotation] = []
    // The annotation being drawn right now (not yet committed).
    var currentAnnotation: Annotation?

    var selectedTool: AnnotationTool = .marker
    var selectedColor: NSColor = NSColor.annotationPalette[0]

    /// Called whenever the active tool changes via keyboard.
    var onToolChanged: ((AnnotationTool) -> Void)?
    /// Called when Escape is pressed (with or without an active text field).
    var onEscapeAction: (() -> Void)?
    /// Called just before the first mouse-down begins a new stroke/shape.
    var onWillDraw: (() -> Void)?

    private var strokePoints: [CGPoint] = []
    private var dragStart: CGPoint = .zero
    private var activeTextField: AnnotationTextField?
    private var activeEmojiPicker: EmojiPickerPanel?
    private var pendingEmojiPoint: CGPoint = .zero

    private var nextNumberValue: Int {
        let used = annotations.compactMap { ann -> Int? in
            if case .number(_, let v, _) = ann { return v }
            return nil
        }
        return (used.max() ?? 0) + 1
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for ann in annotations { render(ann, in: ctx) }
        if let cur = currentAnnotation { render(cur, in: ctx) }
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

        case let .arrow(from, to, color):
            ctx.saveGState()
            ctx.setAlpha(1)
            ctx.setLineWidth(2.5)
            ctx.setStrokeColor(color.cgColor)
            ctx.setFillColor(color.cgColor)
            let (shaft, head) = arrowPath(from: from, to: to)
            ctx.addPath(shaft)
            ctx.strokePath()
            ctx.addPath(head)
            ctx.fillPath()
            ctx.restoreGState()

        case let .rect(rect, color):
            ctx.saveGState()
            ctx.setAlpha(1)
            ctx.setLineWidth(2)
            ctx.setStrokeColor(color.cgColor)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil))
            ctx.strokePath()
            ctx.restoreGState()

        case let .text(origin, text, color):
            ctx.saveGState()
            ctx.setAlpha(1)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: color,
            ]
            (text as NSString).draw(at: origin, withAttributes: attrs)
            ctx.restoreGState()

        case let .number(center, value, color):
            ctx.saveGState()
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

        case let .emoji(center, emojiStr, size):
            ctx.saveGState()
            ctx.setAlpha(1)
            let emojiAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size),
            ]
            let es = emojiStr as NSString
            let esz = es.size(withAttributes: emojiAttrs)
            es.draw(
                at: CGPoint(x: center.x - esz.width / 2, y: center.y - esz.height / 2),
                withAttributes: emojiAttrs
            )
            ctx.restoreGState()
        }
    }

    // MARK: Mouse Events

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onWillDraw?()
        let pt = convert(event.locationInWindow, from: nil)

        switch selectedTool {
        case .marker:
            strokePoints = [pt]
            currentAnnotation = .stroke(points: strokePoints, color: selectedColor, lineWidth: 3, tool: .marker)
        case .highlighter:
            strokePoints = [pt]
            currentAnnotation = .stroke(points: strokePoints, color: selectedColor, lineWidth: 14, tool: .highlighter)
        case .arrow:
            dragStart = pt
            currentAnnotation = .arrow(from: pt, to: pt, color: selectedColor)
        case .rect:
            dragStart = pt
            currentAnnotation = .rect(rect: CGRect(origin: pt, size: .zero), color: selectedColor)
        case .text:
            commitActiveTextField()
            placeTextField(at: pt)
            return
        case .number:
            annotations.append(.number(center: pt, value: nextNumberValue, color: selectedColor))
            needsDisplay = true
            return
        case .emoji:
            let winPt = convert(pt, to: nil)
            let screenPt = window.map { $0.convertPoint(toScreen: winPt) } ?? pt
            pendingEmojiPoint = pt
            activeEmojiPicker?.close()
            let picker = EmojiPickerPanel(nearScreenPoint: screenPt) { [weak self] em in
                guard let self else { return }
                annotations.append(.emoji(center: pendingEmojiPoint, emoji: em, size: 32))
                activeEmojiPicker = nil
                needsDisplay = true
            }
            activeEmojiPicker = picker
            picker.show()
            return
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

        switch selectedTool {
        case .marker:
            strokePoints.append(pt)
            currentAnnotation = .stroke(points: strokePoints, color: selectedColor, lineWidth: 3, tool: .marker)
        case .highlighter:
            strokePoints.append(pt)
            currentAnnotation = .stroke(points: strokePoints, color: selectedColor, lineWidth: 14, tool: .highlighter)
        case .arrow:
            currentAnnotation = .arrow(from: dragStart, to: pt, color: selectedColor)
        case .rect:
            currentAnnotation = .rect(
                rect: CGRect(
                    x: min(dragStart.x, pt.x), y: min(dragStart.y, pt.y),
                    width: abs(pt.x - dragStart.x), height: abs(pt.y - dragStart.y)
                ),
                color: selectedColor
            )
        default:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let cur = currentAnnotation {
            annotations.append(cur)
            currentAnnotation = nil
            strokePoints = []
        }
        needsDisplay = true
    }

    // MARK: Text Tool

    private func placeTextField(at pt: CGPoint) {
        let field = AnnotationTextField(frame: NSRect(x: pt.x, y: pt.y - 28, width: 220, height: 32))
        field.isEditable = true
        field.isBordered = false
        field.drawsBackground = false
        field.textColor = selectedColor
        field.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        field.placeholderString = "Type here…"
        field.focusRingType = .none

        let shadow = NSShadow()
        shadow.shadowBlurRadius = 3
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        field.shadow = shadow

        field.target = self
        field.action = #selector(enterPressed(_:))
        field.onEscape = { [weak self] in
            self?.commitActiveTextField()
            self?.onEscapeAction?()
        }

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
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            annotations.append(.text(
                origin: CGPoint(x: field.frame.minX, y: field.frame.minY + 4),
                text: text,
                color: field.textColor ?? selectedColor
            ))
        }
        field.removeFromSuperview()
        activeTextField = nil
        needsDisplay = true
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let ch = event.charactersIgnoringModifiers ?? ""

        if event.modifierFlags.contains(.command), ch == "z" {
            undoLast()
            return
        }

        switch ch {
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
        selectedTool = tool
        onToolChanged?(tool)
    }

    func undoLast() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        needsDisplay = true
    }

    // MARK: Flatten

    func flattenedImage(background: NSImage) -> NSImage {
        commitActiveTextField()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return background }

        let result = NSImage(size: size)
        result.lockFocus()
        defer { result.unlockFocus() }

        background.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: background.size),
            operation: .sourceOver,
            fraction: 1.0
        )

        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for ann in annotations { render(ann, in: ctx) }
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

// MARK: - ToolbarPillView

final class ToolbarPillView: NSView {

    var selectedTool: AnnotationTool = .marker { didSet { refresh() } }
    var selectedColorIndex: Int = 0 { didSet { refresh() } }
    var selectedColor: NSColor { NSColor.annotationPalette[selectedColorIndex] }

    var onToolSelected: ((AnnotationTool) -> Void)?
    var onColorSelected: ((Int) -> Void)?
    var onCopy: (() -> Void)?

    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private var colorButtons: [Int: CircleColorButton] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -3)

        let vfx = NSVisualEffectView(frame: bounds)
        vfx.autoresizingMask = [.width, .height]
        vfx.material = .popover
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = 20
        vfx.layer?.masksToBounds = true
        addSubview(vfx)

        let h: CGFloat = 48
        let btnSz: CGFloat = 32
        let btnY = (h - btnSz) / 2
        var x: CGFloat = 12

        for (i, tool) in AnnotationTool.allCases.enumerated() {
            let btn = NSButton(frame: CGRect(x: x, y: btnY, width: btnSz, height: btnSz))
            btn.bezelStyle = .regularSquare
            btn.isBordered = false
            let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            btn.image = NSImage(systemSymbolName: tool.sfSymbol, accessibilityDescription: tool.sfSymbol)?
                            .withSymbolConfiguration(cfg)
            btn.imageScaling = .scaleProportionallyDown
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 8
            btn.tag = i
            btn.target = self
            btn.action = #selector(toolTapped(_:))
            addSubview(btn)
            toolButtons[tool] = btn
            x += btnSz + 4
        }

        x += 4
        addSubview(makeSeparator(at: x, height: h))
        x += 13

        let swSz: CGFloat = 18
        let swY = (h - swSz) / 2
        for (i, color) in NSColor.annotationPalette.enumerated() {
            let btn = CircleColorButton(color: color)
            btn.frame = CGRect(x: x, y: swY, width: swSz, height: swSz)
            btn.tag = i
            btn.target = self
            btn.action = #selector(colorTapped(_:))
            addSubview(btn)
            colorButtons[i] = btn
            x += swSz + 6
        }

        x += 2
        addSubview(makeSeparator(at: x, height: h))
        x += 13

        let copyBtn = NSButton(frame: CGRect(x: x, y: btnY, width: 54, height: btnSz))
        copyBtn.bezelStyle = .regularSquare
        copyBtn.isBordered = false
        copyBtn.title = "Copy"
        copyBtn.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        copyBtn.target = self
        copyBtn.action = #selector(copyTapped)
        addSubview(copyBtn)
        x += 54 + 12

        frame.size.width = x
        refresh()
    }

    private func makeSeparator(at x: CGFloat, height: CGFloat) -> NSView {
        let v = NSView(frame: CGRect(x: x, y: 10, width: 1, height: height - 20))
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.separatorColor.cgColor
        return v
    }

    // MARK: Actions

    @objc private func toolTapped(_ sender: NSButton) {
        let tools = AnnotationTool.allCases
        guard sender.tag < tools.count else { return }
        onToolSelected?(tools[sender.tag])
    }

    @objc private func colorTapped(_ sender: NSButton) {
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
    }
}

// MARK: - AnnotationWindow

final class AnnotationWindow: NSWindow {

    private static var current: AnnotationWindow?

    private let screenshot: NSImage
    private let canvas: AnnotationCanvasView
    private var pill: ToolbarPillView!

    private let toolbarHeight: CGFloat = 68

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
        // Build pill first so we know its computed width.
        pill = ToolbarPillView(frame: CGRect(x: 0, y: 0, width: 100, height: 48))

        // Ensure the content is always wide enough to show the full toolbar.
        let minWidth = pill.frame.width + 24  // 12 pt padding on each side
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

        // Center pill horizontally, 10 pt from bottom edge.
        let pillX = ((contentWidth - pill.frame.width) / 2).rounded()
        pill.frame.origin = CGPoint(x: pillX, y: 10)
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
            canvas.selectedColor = NSColor.annotationPalette[idx]
            pill.selectedColorIndex = idx
        }

        pill.onCopy = { [weak self] in
            self?.flattenAndCopy()
        }
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
