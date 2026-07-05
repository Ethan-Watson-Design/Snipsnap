//
//  AnnotationWindow.swift
//  Snipsnap
//
//  Created by Ethan Watson on 6/27/26.
//

import AppKit
import CoreImage
import UniformTypeIdentifiers

// MARK: - Enums

enum StrokeTool: Equatable, CaseIterable {
    case marker, highlighter

    var lineWidth: CGFloat {
        switch self {
        case .marker:      return 4
        case .highlighter: return 14
        }
    }

    var menuSymbol: String {
        switch self {
        case .marker:      return "scribble"
        case .highlighter: return "highlighter"
        }
    }

    var menuSymbolPointSize: CGFloat { 14 }

    var accessibilityLabel: String {
        switch self {
        case .marker:      return "Marker"
        case .highlighter: return "Highlighter"
        }
    }
}

enum AnnotationTool: Hashable {
    case select, draw, arrow, rect, spotlight, zoom, crop, text, emoji

    static let screenshotTools: [AnnotationTool] = [
        .select, .draw, .arrow, .rect, .spotlight, .crop, .text, .emoji
    ]
    static let videoTools: [AnnotationTool] = [
        .zoom, .text
    ]

    var sfSymbol: String {
        switch self {
        case .select:    return "cursorarrow"
        case .draw:      return "scribble"
        case .arrow:     return "arrow.up.right"
        case .rect:      return "rectangle"
        case .spotlight: return "flashlight.on.fill"
        case .zoom:      return "plus.magnifyingglass"
        case .crop:      return "crop"
        case .text:      return "textformat"
        case .emoji:     return "face.smiling"
        }
    }

    var displayName: String {
        switch self {
        case .select:    return "Select"
        case .draw:      return "Draw"
        case .arrow:     return "Arrow"
        case .rect:      return "Rectangle"
        case .spotlight: return "Spotlight"
        case .zoom:      return "Zoom"
        case .crop:      return "Crop"
        case .text:      return "Text"
        case .emoji:     return "Sticker"
        }
    }

    var shortcutKey: String {
        switch self {
        case .select:    return "S"
        case .draw:      return "D"
        case .arrow:     return "A"
        case .rect:      return "R"
        case .spotlight: return "F"
        case .zoom:      return "Z"
        case .crop:      return "C"
        case .text:      return "T"
        case .emoji:     return "E"
        }
    }
}

enum SpotlightTechnique: String, Equatable, CaseIterable {
    case dim, blur, desaturate

    var menuSymbol: String {
        switch self {
        case .dim:         return "circle.lefthalf.filled"
        case .blur:        return "drop.halffull"
        case .desaturate:  return "paintpalette"
        }
    }

    var menuSymbolPointSize: CGFloat { 13 }

    var accessibilityLabel: String {
        switch self {
        case .dim:         return "Dim"
        case .blur:        return "Blur"
        case .desaturate:  return "Desaturate"
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

enum ArrowPathStyle: Equatable, CaseIterable {
    case autoBend, squiggle

    var menuSymbol: String {
        switch self {
        case .autoBend: return "arrow.turn.up.right"
        case .squiggle: return "scribble.variable"
        }
    }

    var menuSymbolPointSize: CGFloat {
        switch self {
        case .autoBend: return 13
        case .squiggle: return 13
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .autoBend: return "Auto bend"
        case .squiggle: return "Squiggle"
        }
    }
}

enum Annotation {
    /// Hard-edge rounded-rect cutout for spotlight; not user-exposed in v1.
    static let spotlightCornerRadius: CGFloat = 8

    case stroke(points: [CGPoint], color: NSColor, lineWidth: CGFloat, tool: StrokeTool)
    case arrow(from: CGPoint, to: CGPoint, bend: CGPoint?, color: NSColor, tipStyle: ArrowTipStyle, pathStyle: ArrowPathStyle, seed: UInt64)
    case rect(rect: CGRect, color: NSColor)
    case spotlight(region: CGRect, technique: SpotlightTechnique)
    case zoom(rect: CGRect)
    case crop(rect: CGRect)
    case text(origin: CGPoint, text: String, color: NSColor, maxWidth: CGFloat?)
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

struct AnnotationExportSnapshot {
    let annotations: [PlacedAnnotation]
    let canvasSize: CGSize
}

// MARK: - Color Palette

extension NSColor {
    /// Selection outline for annotations in select mode (solid pink, Figma-style handles).
    /// Forwards to `DesignTokens.Color.accent` during the design-token migration.
    static var annotationSelectionAccent: NSColor { DesignTokens.Color.accent.ns }
    /// Region capture overlay border and handles.
    static var regionSelectionAccent: NSColor { DesignTokens.Color.regionSelectionAccent.ns }

    static var annotationPalette: [NSColor] { DesignTokens.Color.annotationPaletteNS }

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

    var rgb24Value: UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        (usingColorSpace(.sRGB) ?? self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt32((r * 255).rounded()) << 16)
             | (UInt32((g * 255).rounded()) << 8)
             |  UInt32((b * 255).rounded())
    }

    var hexString: String {
        String(format: "%06X", rgb24Value)
    }

    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(hex24: value)
    }

    static func paletteIndex(matching color: NSColor) -> Int? {
        let value = color.rgb24Value
        return annotationPalette.firstIndex { $0.rgb24Value == value }
    }

    /// Two-step darker shade for selection rings (palette-500 → palette-700).
    func darkenedPaletteSteps(_ steps: Int = 2) -> NSColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard let rgb = usingColorSpace(.sRGB) else { return self }
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        if s < 0.08 {
            let factor = pow(0.82, CGFloat(steps))
            return NSColor(calibratedWhite: max(0.12, b * factor), alpha: a)
        }

        let brightnessFactor = pow(0.80, CGFloat(steps))
        let saturationBoost = 1 + 0.08 * CGFloat(steps)
        return NSColor(
            calibratedHue: h,
            saturation: min(1, s * saturationBoost),
            brightness: max(0.15, b * brightnessFactor),
            alpha: a
        )
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

/// Soft corner radius at an elbow bend (~8pt, clamped per segment).
private let arrowBendCornerRadius: CGFloat = 8

/// Minimum axis offset before an auto elbow is introduced (already straight-ish otherwise).
private let arrowAutoBendThreshold: CGFloat = 8

/// Collapses duplicate and axis-colinear points so L-elbows and straight runs stay clean.
private func collapseArrowWaypoints(_ points: [CGPoint]) -> [CGPoint] {
    guard let first = points.first else { return [] }
    var result = [first]
    for point in points.dropFirst() {
        guard let last = result.last else { continue }
        if hypot(point.x - last.x, point.y - last.y) < 0.5 { continue }
        if result.count >= 2 {
            let prior = result[result.count - 2]
            let colinearH = abs(prior.y - last.y) < 0.5 && abs(last.y - point.y) < 0.5
            let colinearV = abs(prior.x - last.x) < 0.5 && abs(last.x - point.x) < 0.5
            if colinearH || colinearV {
                result[result.count - 1] = point
                continue
            }
        }
        result.append(point)
    }
    return result
}

/// FigJam-style orthogonal route through a free control point.
/// Hidden corners sit on either side of `bend`; every joint is 90°.
/// Orientation is locked to the start–end box (wider → leave start horizontally) so
/// dragging the handle does not flip the route.
/// Horizontal-first: `start → (bend.x, start.y) → bend → (end.x, bend.y) → end`
/// Vertical-first:   `start → (start.x, bend.y) → bend → (bend.x, end.y) → end`
private func arrowWaypoints(from start: CGPoint, to end: CGPoint, bend: CGPoint?) -> [CGPoint] {
    guard let bend else { return [start, end] }
    let leaveHorizontally = abs(end.x - start.x) >= abs(end.y - start.y)
    let corners: [CGPoint]
    if leaveHorizontally {
        corners = [
            CGPoint(x: bend.x, y: start.y),
            bend,
            CGPoint(x: end.x, y: bend.y),
        ]
    } else {
        corners = [
            CGPoint(x: start.x, y: bend.y),
            bend,
            CGPoint(x: bend.x, y: end.y),
        ]
    }
    return collapseArrowWaypoints([start] + corners + [end])
}

/// Bend handle is the free control point (or the shaft midpoint when straight).
private func arrowBendHandle(from start: CGPoint, to end: CGPoint, bend: CGPoint?) -> CGPoint {
    bend ?? CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
}

/// Default control at the start–end midpoint when both axes have meaningful offset.
private func autoArrowBend(from start: CGPoint, to end: CGPoint) -> CGPoint? {
    let dx = abs(end.x - start.x)
    let dy = abs(end.y - start.y)
    guard dx >= arrowAutoBendThreshold, dy >= arrowAutoBendThreshold else { return nil }
    return CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
}

/// Placement / live preview: free-angle endpoints; auto orthogonal route unless Shift keeps it straight.
private func arrowPlacementBend(from start: CGPoint, to end: CGPoint, forceStraight: Bool, pathStyle: ArrowPathStyle) -> CGPoint? {
    guard pathStyle == .autoBend else { return nil }
    return forceStraight ? nil : autoArrowBend(from: start, to: end)
}

/// Endpoint edit: Shift clears the bend (straight); otherwise keep the free control or auto-create one.
private func arrowEditBend(from start: CGPoint, to end: CGPoint, existing: CGPoint?, forceStraight: Bool, pathStyle: ArrowPathStyle) -> CGPoint? {
    guard pathStyle == .autoBend else { return nil }
    if forceStraight { return nil }
    if let existing { return existing }
    return autoArrowBend(from: start, to: end)
}

/// Tiny seeded PRNG so squiggles stay stable while endpoints move.
private struct ArrowSquiggleRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xC0FFEE : seed
    }

    mutating func nextUnit() -> CGFloat {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return CGFloat(state % 10_000) / 9_999
    }

    mutating func nextSigned() -> CGFloat {
        nextUnit() * 2 - 1
    }
}

/// Organic but clean polyline between endpoints (seeded, ends pinned).
private func arrowSquigglePoints(from start: CGPoint, to end: CGPoint, seed: UInt64) -> [CGPoint] {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let len = hypot(dx, dy)
    guard len > 4 else { return [start, end] }

    let ux = dx / len
    let uy = dy / len
    let px = -uy
    let py = ux

    let interiorCount = max(3, min(7, Int(len / 70)))
    let amplitude = min(32, max(12, len * 0.14))

    var rng = ArrowSquiggleRNG(seed: seed)
    var walk: CGFloat = 0
    var points = [start]

    for i in 1 ... interiorCount {
        let t = CGFloat(i) / CGFloat(interiorCount + 1)
        let envelope = sin(t * .pi)
        // Correlated walk keeps the curve smooth rather than noisy.
        walk = walk * 0.55 + rng.nextSigned() * 0.45
        let offset = walk * amplitude * envelope
        let tJitter = rng.nextSigned() * 0.06 * (1 / CGFloat(interiorCount + 1))
        let tt = min(0.97, max(0.03, t + tJitter))
        let base = CGPoint(x: start.x + dx * tt, y: start.y + dy * tt)
        points.append(CGPoint(x: base.x + px * offset, y: base.y + py * offset))
    }
    points.append(end)
    return points
}

/// Shaft sample points for hit-testing / bounds (orthogonal waypoints or squiggle polyline).
private func arrowShaftPoints(
    from start: CGPoint,
    to end: CGPoint,
    bend: CGPoint?,
    pathStyle: ArrowPathStyle,
    seed: UInt64
) -> [CGPoint] {
    switch pathStyle {
    case .autoBend:
        return arrowWaypoints(from: start, to: end, bend: bend)
    case .squiggle:
        return arrowSquigglePoints(from: start, to: end, seed: seed)
    }
}

/// Appends an orthogonal shaft through `points`, rounding each interior joint.
private func appendOrthogonalArrowShaft(to path: CGMutablePath, points: [CGPoint]) {
    guard let first = points.first else { return }
    path.move(to: first)
    guard points.count >= 2 else { return }
    if points.count == 2 {
        path.addLine(to: points[1])
        return
    }
    for i in 1 ..< points.count - 1 {
        let prev = points[i - 1]
        let corner = points[i]
        let next = points[i + 1]
        let segIn = hypot(corner.x - prev.x, corner.y - prev.y)
        let segOut = hypot(next.x - corner.x, next.y - corner.y)
        let radius = min(arrowBendCornerRadius, segIn / 2, segOut / 2)
        if radius > 0.5 {
            path.addArc(tangent1End: corner, tangent2End: next, radius: radius)
        } else {
            path.addLine(to: corner)
        }
    }
    path.addLine(to: points[points.count - 1])
}

private func appendArrowShaft(
    to path: CGMutablePath,
    from start: CGPoint,
    bend: CGPoint?,
    to end: CGPoint,
    pathStyle: ArrowPathStyle,
    seed: UInt64
) {
    let points = arrowShaftPoints(from: start, to: end, bend: bend, pathStyle: pathStyle, seed: seed)
    switch pathStyle {
    case .autoBend:
        appendOrthogonalArrowShaft(to: path, points: points)
    case .squiggle:
        path.addPath(smoothPath(from: points))
    }
}

private func arrowPaths(
    from start: CGPoint,
    to end: CGPoint,
    bend: CGPoint? = nil,
    tipStyle: ArrowTipStyle,
    pathStyle: ArrowPathStyle,
    seed: UInt64,
    lineWidth: CGFloat
) -> ArrowPaths? {
    let points = arrowShaftPoints(from: start, to: end, bend: bend, pathStyle: pathStyle, seed: seed)
    guard points.count >= 2 else { return nil }
    let headStart = points[points.count - 2]
    guard let layout = arrowLayout(from: headStart, to: end) else { return nil }

    let stroke = CGMutablePath()
    var fill: CGPath?
    var shaftPoints = points

    switch tipStyle {
    case .solid:
        shaftPoints[shaftPoints.count - 1] = layout.baseCenter
        switch pathStyle {
        case .autoBend:
            appendOrthogonalArrowShaft(to: stroke, points: collapseArrowWaypoints(shaftPoints))
        case .squiggle:
            stroke.addPath(smoothPath(from: shaftPoints))
        }
        let head = CGMutablePath()
        head.move(to: layout.baseCenter)
        head.addLine(to: layout.wingLeft)
        head.addLine(to: end)
        head.addLine(to: layout.wingRight)
        head.closeSubpath()
        fill = head
    case .dot:
        shaftPoints[shaftPoints.count - 1] = CGPoint(
            x: end.x - cos(layout.angle) * arrowDotRadius,
            y: end.y - sin(layout.angle) * arrowDotRadius
        )
        switch pathStyle {
        case .autoBend:
            appendOrthogonalArrowShaft(to: stroke, points: collapseArrowWaypoints(shaftPoints))
        case .squiggle:
            stroke.addPath(smoothPath(from: shaftPoints))
        }
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
            btn.layer?.cornerRadius = DesignTokens.Radius.md
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

    var selectedTool: AnnotationTool = .draw {
        didSet {
            guard oldValue != selectedTool else { return }
            commitActiveTextField()
            resetArrowPlacement()
            if oldValue == .crop {
                commitCropEditing()
            }
            if selectedTool == .crop {
                beginCropEditing()
            }
            notifyCommittedCropPreviewIfNeeded()
        }
    }
    var selectedColor: NSColor = NSColor.annotationPalette[0]
    var selectedStrokeTool: StrokeTool = .marker
    var selectedArrowTipStyle: ArrowTipStyle = .solid
    var selectedArrowPathStyle: ArrowPathStyle = .autoBend
    /// Last-used spotlight technique (recents, same as stroke color/weight).
    var selectedSpotlightTechnique: SpotlightTechnique = .dim
    /// Stage background for spotlight blur/desaturate (canvas-sized).
    var stageBackgroundImage: NSImage?
    /// Stable seed for the in-progress squiggle arrow.
    private var activeArrowSeed: UInt64 = 1
    private var spotlightEffectCache: (technique: SpotlightTechnique, imageID: ObjectIdentifier, image: NSImage)?

    /// When true, annotations are filtered by playback time and stamped on commit.
    var videoMode: Bool = false
    /// Current video playback time — drives visibility filtering in video mode.
    var playbackTime: Double = 0
    /// When true, zoom overlays are hidden and zoom is applied to the video layer instead.
    var isPlaybackActive: Bool = false
    /// When true, scrubbing the timeline — same live zoom behavior as playback.
    var isScrubbing: Bool = false
    /// When true, user input is ignored while a video export is in progress.
    var isExporting: Bool = false
    /// Tools available in this canvas (screenshot vs video).
    var allowedTools: Set<AnnotationTool> = Set(AnnotationTool.videoTools)

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
    /// Called when a committed crop preview should be applied or cleared.
    var onCommittedCropPreviewChanged: ((CGRect?) -> Void)?

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
        case arrowBend
        case textWidthLeft(anchorRight: CGFloat)
        case textWidthRight(anchorLeft: CGFloat)
        case rectResize(handle: RectResizeHandle, anchor: CGRect)
    }

    private let rectCornerHitRadius: CGFloat = 10
    private let rectEdgeHitThickness: CGFloat = 6
    private let rectMinSize: CGFloat = 20

    private var selectDragMode: SelectDragMode = .none

    private enum CropDragMode {
        case none
        case creating
        case moving(origin: CGRect, start: CGPoint)
        case resizing(handle: RectResizeHandle, anchor: CGRect)
    }

    private var cropEditingRect: CGRect?
    private var cropDragMode: CropDragMode = .none
    private var cropDragStart: CGPoint = .zero

    private var strokePoints: [CGPoint] = []
    private var dragStart: CGPoint = .zero

    private enum ArrowPlacementState {
        case idle
        case drawingStart(start: CGPoint)
        case awaitingEndpoint(start: CGPoint)
        case drawingEnd(start: CGPoint)
    }

    private var arrowPlacementState: ArrowPlacementState = .idle
    private var arrowDragExceededThreshold = false
    private let arrowDragThreshold: CGFloat = 4
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

    private func appendAnnotation(_ content: Annotation) {
        pushUndoState()
        if case .crop = content {
            annotations.removeAll { if case .crop = $0.content { return true }; return false }
        }
        let start = videoMode ? playbackTime : 0
        var placed = PlacedAnnotation(content: content, startTime: start)
        if videoMode, case .zoom = content {
            placed.visibleDuration = 4
        }
        annotations.append(placed)
        if videoMode {
            setSelectedIndex(annotations.count - 1)
        }
        if case .crop = content {
            notifyCommittedCropPreviewIfNeeded()
        }
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
        notifyCommittedCropPreviewIfNeeded()
    }

    func redo() {
        commitActiveTextField()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        setSelectedIndex(nil)
        needsDisplay = true
        notifyCommittedCropPreviewIfNeeded()
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

    private func shouldRenderOverlay(for content: Annotation) -> Bool {
        if videoMode, (isPlaybackActive || isScrubbing), case .zoom = content { return false }
        return true
    }

    private func committedCropRect() -> CGRect? {
        guard let rect = annotations.compactMap({ placed -> CGRect? in
            if case .crop(let rect) = placed.content { return rect }
            return nil
        }).last else { return nil }
        guard rect.width > 1, rect.height > 1, !isFullBoundsCrop(rect) else { return nil }
        return rect
    }

    private func committedCropPreviewRect() -> CGRect? {
        guard selectedTool != .crop else { return nil }
        return committedCropRect()
    }

    private func notifyCommittedCropPreviewIfNeeded() {
        onCommittedCropPreviewChanged?(committedCropPreviewRect())
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Spotlights first so they suppress the capture, not other annotations.
        for placed in annotations {
            if case .crop = placed.content { continue }
            guard case let .spotlight(region, technique) = placed.content else { continue }
            if !videoMode || placed.isVisible(at: playbackTime) {
                renderSpotlight(region: region, technique: technique, in: ctx)
            }
        }
        if case let .spotlight(region, technique)? = currentAnnotation {
            renderSpotlight(region: region, technique: technique, in: ctx)
        }

        for placed in annotations {
            if case .crop = placed.content { continue }
            if case .spotlight = placed.content { continue }
            if !videoMode || placed.isVisible(at: playbackTime) {
                if shouldRenderOverlay(for: placed.content) {
                    render(placed.content, in: ctx)
                }
            }
        }
        if let cur = currentAnnotation, shouldRenderOverlay(for: cur) {
            if case .spotlight = cur {
                // Already drawn in the spotlight pass.
            } else {
                render(cur, in: ctx)
            }
        }

        if selectedTool == .crop, let cropRect = cropEditingRect {
            drawCropEditingOverlay(rect: cropRect, in: ctx)
        }

        if selectedTool == .select, let idx = selectedIndex, idx < annotations.count {
            let content = annotations[idx].content
            if case .crop = content {
                // Crop is edited via the crop tool, not select handles.
            } else {
            switch content {
            case let .arrow(from, to, bend, _, _, pathStyle, seed):
                drawArrowSelectionHandles(from: from, to: to, bend: bend, pathStyle: pathStyle, seed: seed, in: ctx)
            case let .text(origin, text, _, maxWidth):
                drawTextSelectionHandles(metrics: textMetrics(origin: origin, text: text, maxWidth: maxWidth), in: ctx)
            case let .rect(rect, _):
                drawRectAnnotationSelectionHandles(rect: rect, in: ctx)
            case let .spotlight(region, _):
                drawRectAnnotationSelectionHandles(rect: region, in: ctx)
            case let .zoom(rect):
                drawRectAnnotationSelectionHandles(rect: rect, in: ctx)
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
        NSFont.snipsnap(.panelTitle)
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

    private func drawRectAnnotationSelectionHandles(rect: CGRect, in ctx: CGContext) {
        let radius: CGFloat = 5
        let accent = NSColor.annotationSelectionAccent
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ]

        ctx.saveGState()
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(rect)

        for point in corners {
            let dotRect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: dotRect)
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: dotRect)
        }
        ctx.restoreGState()
    }

    private func drawCropSelectionHandles(rect: CGRect, in ctx: CGContext) {
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

    private func drawCropEditingOverlay(rect: CGRect, in ctx: CGContext) {
        ctx.saveGState()
        let dimPath = CGMutablePath()
        dimPath.addRect(bounds)
        dimPath.addRect(rect)
        ctx.addPath(dimPath)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.fillPath(using: .evenOdd)

        ctx.setStrokeColor(NSColor.annotationSelectionAccent.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(rect)
        ctx.restoreGState()

        drawCropSelectionHandles(rect: rect, in: ctx)
    }

    private func beginCropEditing() {
        if let existing = annotations.compactMap({ placed -> CGRect? in
            if case .crop(let rect) = placed.content { return rect }
            return nil
        }).last {
            cropEditingRect = clampedCropRect(existing)
        } else {
            cropEditingRect = bounds
        }
        cropDragMode = .none
        needsDisplay = true
    }

    private func commitCropEditing() {
        guard let rect = cropEditingRect else {
            cropDragMode = .none
            return
        }
        cropEditingRect = nil
        cropDragMode = .none

        if isFullBoundsCrop(rect) {
            let hadCrop = annotations.contains { if case .crop = $0.content { return true }; return false }
            if hadCrop {
                pushUndoState()
                annotations.removeAll { if case .crop = $0.content { return true }; return false }
            }
        } else if rect.width > 1, rect.height > 1 {
            appendAnnotation(.crop(rect: rect))
        }
        notifyCommittedCropPreviewIfNeeded()
        needsDisplay = true
    }

    private func isFullBoundsCrop(_ rect: CGRect) -> Bool {
        let b = bounds
        return abs(rect.minX - b.minX) < 1
            && abs(rect.minY - b.minY) < 1
            && abs(rect.maxX - b.maxX) < 1
            && abs(rect.maxY - b.maxY) < 1
    }

    private func clampedCropRect(_ rect: CGRect) -> CGRect {
        let b = bounds
        guard b.width > 0, b.height > 0 else { return rect }
        var minX = max(b.minX, rect.minX)
        var minY = max(b.minY, rect.minY)
        var maxX = min(b.maxX, rect.maxX)
        var maxY = min(b.maxY, rect.maxY)
        if maxX - minX < rectMinSize {
            if rect.midX < b.midX {
                maxX = min(b.maxX, minX + rectMinSize)
            } else {
                minX = max(b.minX, maxX - rectMinSize)
            }
        }
        if maxY - minY < rectMinSize {
            if rect.midY < b.midY {
                maxY = min(b.maxY, minY + rectMinSize)
            } else {
                minY = max(b.minY, maxY - rectMinSize)
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func cropRectBetween(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }

    private func resizedCropRect(anchor: CGRect, handle: RectResizeHandle, to point: CGPoint) -> CGRect {
        clampedCropRect(resizedRect(anchor: anchor, handle: handle, to: point))
    }

    private func handleCropMouseDown(at pt: CGPoint) {
        cropDragStart = pt
        if let rect = cropEditingRect, rect.width > 1, rect.height > 1 {
            if let handle = rectHitTestHandle(at: pt, in: rect) {
                cropDragMode = .resizing(handle: handle, anchor: rect)
                return
            }
            if rectInterior(of: rect).contains(pt) {
                if isFullBoundsCrop(rect) {
                    cropDragMode = .creating
                } else {
                    cropDragMode = .moving(origin: rect, start: pt)
                }
                return
            }
        }
        cropDragMode = .creating
    }

    private func handleCropMouseDragged(to pt: CGPoint) {
        switch cropDragMode {
        case .none:
            break
        case .creating:
            cropEditingRect = clampedCropRect(cropRectBetween(cropDragStart, pt))
        case .moving(let origin, let start):
            let dx = pt.x - start.x
            let dy = pt.y - start.y
            var moved = origin.offsetBy(dx: dx, dy: dy)
            let b = bounds
            if moved.minX < b.minX { moved.origin.x += b.minX - moved.minX }
            if moved.minY < b.minY { moved.origin.y += b.minY - moved.minY }
            if moved.maxX > b.maxX { moved.origin.x -= moved.maxX - b.maxX }
            if moved.maxY > b.maxY { moved.origin.y -= moved.maxY - b.maxY }
            cropEditingRect = moved
        case .resizing(let handle, let anchor):
            cropEditingRect = resizedCropRect(anchor: anchor, handle: handle, to: pt)
        }
    }

    private func drawArrowSelectionHandles(
        from: CGPoint,
        to: CGPoint,
        bend: CGPoint?,
        pathStyle: ArrowPathStyle,
        seed: UInt64,
        in ctx: CGContext
    ) {
        let radius: CGFloat = 5
        let accent = NSColor.annotationSelectionAccent

        ctx.saveGState()
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(2)
        let shaft = CGMutablePath()
        appendArrowShaft(to: shaft, from: from, bend: bend, to: to, pathStyle: pathStyle, seed: seed)
        ctx.addPath(shaft)
        ctx.strokePath()
        ctx.restoreGState()

        var handles = [from, to]
        if pathStyle == .autoBend {
            handles.append(arrowBendHandle(from: from, to: to, bend: bend))
        }
        for point in handles {
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

    private func renderSpotlight(
        region: CGRect,
        technique: SpotlightTechnique,
        in ctx: CGContext,
        canvasBounds: CGRect? = nil
    ) {
        guard region.width > 0.5, region.height > 0.5 else { return }
        let bounds = canvasBounds ?? self.bounds
        let radius = Annotation.spotlightCornerRadius
        let cutout = CGPath(
            roundedRect: region,
            cornerWidth: min(radius, region.width / 2),
            cornerHeight: min(radius, region.height / 2),
            transform: nil
        )

        ctx.saveGState()
        ctx.addRect(bounds)
        ctx.addPath(cutout)
        ctx.clip(using: .evenOdd)

        switch technique {
        case .dim:
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
            ctx.fill(bounds)
        case .blur, .desaturate:
            if let effect = spotlightSuppressionImage(for: technique) {
                let imageRect = NSRect(origin: .zero, size: effect.size)
                effect.draw(
                    in: bounds,
                    from: imageRect,
                    operation: .sourceOver,
                    fraction: 1.0
                )
            } else {
                // Fallback while background is unavailable.
                ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
                ctx.fill(bounds)
            }
        }
        ctx.restoreGState()
    }

    private func spotlightSuppressionImage(for technique: SpotlightTechnique) -> NSImage? {
        guard let background = stageBackgroundImage else { return nil }
        let imageID = ObjectIdentifier(background)
        if let cache = spotlightEffectCache,
           cache.technique == technique,
           cache.imageID == imageID {
            return cache.image
        }
        guard let image = RecordingBackgroundRenderer.spotlightSuppressionImage(
            from: background,
            technique: technique
        ) else { return nil }
        spotlightEffectCache = (technique, imageID, image)
        return image
    }

    private func render(_ annotation: Annotation, in ctx: CGContext) {
        switch annotation {

        case .spotlight:
            break

        case let .stroke(points, color, lineWidth, tool):
            ctx.saveGState()
            ctx.setLineWidth(lineWidth)
            ctx.setStrokeColor(color.cgColor)
            ctx.setAlpha(tool == .highlighter ? 0.35 : 1.0)
            ctx.addPath(smoothPath(from: points))
            ctx.strokePath()
            ctx.restoreGState()

        case let .arrow(from, to, bend, color, tipStyle, pathStyle, seed):
            let lineWidth: CGFloat = 2.5
            guard let paths = arrowPaths(
                from: from,
                to: to,
                bend: bend,
                tipStyle: tipStyle,
                pathStyle: pathStyle,
                seed: seed,
                lineWidth: lineWidth
            ) else { break }

            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -1),
                blur: 4,
                color: NSColor.black.withAlphaComponent(0.25).cgColor
            )
            ctx.setAlpha(1)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(tipStyle == .dot || pathStyle == .squiggle ? .round : .butt)
            ctx.setLineJoin(pathStyle == .squiggle ? .round : .miter)
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

        case let .zoom(rect):
            ctx.saveGState()
            ctx.setAlpha(1)
            ctx.setLineWidth(2)
            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineDash(phase: 0, lengths: [6, 3])
            ctx.stroke(rect)
            ctx.setLineDash(phase: 0, lengths: [])
            let badgeSize: CGFloat = 20
            let badgeOrigin = CGPoint(x: rect.minX + 4, y: rect.maxY - badgeSize - 4)
            let badgeRect = CGRect(origin: badgeOrigin, size: CGSize(width: badgeSize, height: badgeSize))
            if let badge = NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: nil) {
                let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [.systemBlue]))
                if let tinted = badge.withSymbolConfiguration(cfg) {
                    tinted.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                }
            }
            ctx.restoreGState()

        case let .crop(rect):
            ctx.saveGState()
            ctx.setAlpha(1)
            ctx.setLineWidth(2)
            ctx.setStrokeColor(NSColor.labelColor.cgColor)
            ctx.setLineDash(phase: 0, lengths: [6, 3])
            ctx.stroke(rect)
            ctx.setLineDash(phase: 0, lengths: [])
            let badgeSize: CGFloat = 20
            let badgeOrigin = CGPoint(x: rect.minX + 4, y: rect.maxY - badgeSize - 4)
            let badgeRect = CGRect(origin: badgeOrigin, size: CGSize(width: badgeSize, height: badgeSize))
            if let badge = NSImage(systemSymbolName: "crop", accessibilityDescription: nil) {
                let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))
                if let tinted = badge.withSymbolConfiguration(cfg) {
                    tinted.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                }
            }
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

        case let .emoji(center, symbolName, size, color):
            let symRect = NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
            let pointSize = size * 0.58
            guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { break }
            drawStickerSymbol(base: base, in: symRect, pointSize: pointSize, color: color)
        }
    }

    // MARK: Mouse Events

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if selectedTool == .arrow, case .awaitingEndpoint(let start) = arrowPlacementState {
            let forceStraight = event.modifierFlags.contains(.shift)
            let bend = arrowPlacementBend(
                from: start,
                to: pt,
                forceStraight: forceStraight,
                pathStyle: selectedArrowPathStyle
            )
            currentAnnotation = makeArrow(from: start, to: pt, bend: bend)
            needsDisplay = true
        }
    }

    private func makeArrow(from: CGPoint, to: CGPoint, bend: CGPoint?) -> Annotation {
        .arrow(
            from: from,
            to: to,
            bend: bend,
            color: selectedColor,
            tipStyle: selectedArrowTipStyle,
            pathStyle: selectedArrowPathStyle,
            seed: activeArrowSeed
        )
    }

    private func resetArrowPlacement() {
        arrowPlacementState = .idle
        arrowDragExceededThreshold = false
        if case .arrow = currentAnnotation {
            currentAnnotation = nil
        }
    }

    private func commitPlacedArrow(_ content: Annotation) {
        appendAnnotation(content)
        resetArrowPlacement()
        selectedTool = .select
        onToolChanged?(.select)
        setSelectedIndex(annotations.count - 1)
    }

    private func commitPlacedSpotlight(_ content: Annotation) {
        appendAnnotation(content)
        currentAnnotation = nil
        selectedTool = .select
        onToolChanged?(.select)
        setSelectedIndex(annotations.count - 1)
    }

    /// Updates the default technique and, when a spotlight is selected, its live technique.
    func applySpotlightTechnique(_ technique: SpotlightTechnique) {
        selectedSpotlightTechnique = technique
        guard let idx = selectedIndex,
              annotations.indices.contains(idx),
              case let .spotlight(region, current) = annotations[idx].content,
              current != technique else { return }
        pushUndoState()
        annotations[idx].content = .spotlight(region: region, technique: technique)
        needsDisplay = true
    }

    private func handleArrowMouseUp(at pt: CGPoint, forceStraight: Bool) {
        switch arrowPlacementState {
        case .drawingStart(let start):
            if arrowDragExceededThreshold, let cur = currentAnnotation {
                commitPlacedArrow(cur)
            } else {
                arrowPlacementState = .awaitingEndpoint(start: start)
                let bend = arrowPlacementBend(
                    from: start,
                    to: pt,
                    forceStraight: forceStraight,
                    pathStyle: selectedArrowPathStyle
                )
                currentAnnotation = makeArrow(from: start, to: pt, bend: bend)
            }
        case .drawingEnd:
            if let cur = currentAnnotation {
                commitPlacedArrow(cur)
            } else {
                resetArrowPlacement()
            }
        case .idle, .awaitingEndpoint:
            break
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard !isExporting else { return }
        let pt = convert(event.locationInWindow, from: nil)

        if let field = activeTextField, !field.frame.contains(pt) {
            commitActiveTextField()
        }

        if selectedTool == .select {
            if event.clickCount == 2,
               let idx = selectedIndex,
               idx < annotations.count,
               case let .arrow(from, to, bend, color, tipStyle, pathStyle, seed) = annotations[idx].content,
               pathStyle == .autoBend {
                let bendHandle = arrowBendHandle(from: from, to: to, bend: bend)
                let hitsBendHandle = hypot(pt.x - bendHandle.x, pt.y - bendHandle.y) <= 10
                if hitsBendHandle || hitTest(annotation: annotations[idx].content, point: pt) {
                    annotations[idx].content = .arrow(
                        from: from,
                        to: to,
                        bend: nil,
                        color: color,
                        tipStyle: tipStyle,
                        pathStyle: pathStyle,
                        seed: seed
                    )
                    selectDragMode = .none
                    needsDisplay = true
                    return
                }
            }

            var found = false
            for i in stride(from: annotations.count - 1, through: 0, by: -1) {
                if case .crop = annotations[i].content { continue }
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

        if selectedTool == .crop {
            handleCropMouseDown(at: pt)
            needsDisplay = true
            return
        }

        if selectedTool == .arrow, case .awaitingEndpoint(let start) = arrowPlacementState {
            arrowPlacementState = .drawingEnd(start: start)
            arrowDragExceededThreshold = false
            dragStart = pt
            let forceStraight = event.modifierFlags.contains(.shift)
            let bend = arrowPlacementBend(
                from: start,
                to: pt,
                forceStraight: forceStraight,
                pathStyle: selectedArrowPathStyle
            )
            currentAnnotation = makeArrow(from: start, to: pt, bend: bend)
            needsDisplay = true
            return
        }

        onWillDraw?()

        switch selectedTool {
        case .draw:
            strokePoints = [pt]
            currentAnnotation = .stroke(
                points: strokePoints,
                color: selectedColor,
                lineWidth: selectedStrokeTool.lineWidth,
                tool: selectedStrokeTool
            )
        case .arrow:
            arrowPlacementState = .drawingStart(start: pt)
            arrowDragExceededThreshold = false
            dragStart = pt
            activeArrowSeed = UInt64.random(in: 1 ... .max)
            currentAnnotation = makeArrow(from: pt, to: pt, bend: nil)
        case .rect:
            dragStart = pt
            currentAnnotation = .rect(rect: CGRect(origin: pt, size: .zero), color: selectedColor)
        case .spotlight:
            dragStart = pt
            currentAnnotation = .spotlight(
                region: CGRect(origin: pt, size: .zero),
                technique: selectedSpotlightTechnique
            )
        case .zoom:
            dragStart = pt
            currentAnnotation = .zoom(rect: CGRect(origin: pt, size: .zero))
        case .text:
            commitActiveTextField()
            placeTextField(at: pt)
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
        case .crop:
            break
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

        if selectedTool == .crop {
            handleCropMouseDragged(to: pt)
            needsDisplay = true
            return
        }

        switch selectedTool {
        case .draw:
            strokePoints.append(pt)
            currentAnnotation = .stroke(
                points: strokePoints,
                color: selectedColor,
                lineWidth: selectedStrokeTool.lineWidth,
                tool: selectedStrokeTool
            )
        case .arrow:
            switch arrowPlacementState {
            case .drawingStart(let start), .drawingEnd(let start):
                if hypot(pt.x - dragStart.x, pt.y - dragStart.y) > arrowDragThreshold {
                    arrowDragExceededThreshold = true
                }
                let forceStraight = event.modifierFlags.contains(.shift)
                let bend = arrowPlacementBend(
                    from: start,
                    to: pt,
                    forceStraight: forceStraight,
                    pathStyle: selectedArrowPathStyle
                )
                currentAnnotation = makeArrow(from: start, to: pt, bend: bend)
            case .idle, .awaitingEndpoint:
                break
            }
        case .rect:
            currentAnnotation = .rect(
                rect: CGRect(
                    x: min(dragStart.x, pt.x), y: min(dragStart.y, pt.y),
                    width: abs(pt.x - dragStart.x), height: abs(pt.y - dragStart.y)
                ),
                color: selectedColor
            )
        case .spotlight:
            currentAnnotation = .spotlight(
                region: CGRect(
                    x: min(dragStart.x, pt.x), y: min(dragStart.y, pt.y),
                    width: abs(pt.x - dragStart.x), height: abs(pt.y - dragStart.y)
                ),
                technique: selectedSpotlightTechnique
            )
        case .zoom:
            currentAnnotation = .zoom(
                rect: CGRect(
                    x: min(dragStart.x, pt.x), y: min(dragStart.y, pt.y),
                    width: abs(pt.x - dragStart.x), height: abs(pt.y - dragStart.y)
                )
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
                    if case let .arrow(_, to, bend, color, tipStyle, pathStyle, seed) = annotations[idx].content {
                        let forceStraight = event.modifierFlags.contains(.shift)
                        let start = pt
                        let newBend = arrowEditBend(
                            from: start,
                            to: to,
                            existing: bend,
                            forceStraight: forceStraight,
                            pathStyle: pathStyle
                        )
                        annotations[idx].content = .arrow(
                            from: start,
                            to: to,
                            bend: newBend,
                            color: color,
                            tipStyle: tipStyle,
                            pathStyle: pathStyle,
                            seed: seed
                        )
                    }
                case .arrowEnd:
                    if case let .arrow(from, _, bend, color, tipStyle, pathStyle, seed) = annotations[idx].content {
                        let forceStraight = event.modifierFlags.contains(.shift)
                        let end = pt
                        let newBend = arrowEditBend(
                            from: from,
                            to: end,
                            existing: bend,
                            forceStraight: forceStraight,
                            pathStyle: pathStyle
                        )
                        annotations[idx].content = .arrow(
                            from: from,
                            to: end,
                            bend: newBend,
                            color: color,
                            tipStyle: tipStyle,
                            pathStyle: pathStyle,
                            seed: seed
                        )
                    }
                case .arrowBend:
                    if case let .arrow(from, to, _, color, tipStyle, pathStyle, seed) = annotations[idx].content,
                       pathStyle == .autoBend {
                        // Free control point; hidden corners on either side keep the path at 90°.
                        annotations[idx].content = .arrow(
                            from: from,
                            to: to,
                            bend: pt,
                            color: color,
                            tipStyle: tipStyle,
                            pathStyle: pathStyle,
                            seed: seed
                        )
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
                    } else if case let .spotlight(_, technique) = annotations[idx].content {
                        annotations[idx].content = .spotlight(
                            region: resizedRect(anchor: anchor, handle: handle, to: pt),
                            technique: technique
                        )
                    } else if case .zoom = annotations[idx].content {
                        annotations[idx].content = .zoom(
                            rect: resizedRect(anchor: anchor, handle: handle, to: pt)
                        )
                    } else if case .crop = annotations[idx].content {
                        annotations[idx].content = .crop(
                            rect: resizedRect(anchor: anchor, handle: handle, to: pt)
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
        if selectedTool == .crop {
            cropDragMode = .none
            needsDisplay = true
            return
        }

        if selectedTool == .arrow {
            let forceStraight = event.modifierFlags.contains(.shift)
            handleArrowMouseUp(at: convert(event.locationInWindow, from: nil), forceStraight: forceStraight)
            selectDragSavedState = nil
            selectDidDrag = false
            selectDragMode = .none
            needsDisplay = true
            return
        }

        if selectedTool == .spotlight, let cur = currentAnnotation {
            if case let .spotlight(region, _) = cur, region.width > 2, region.height > 2 {
                commitPlacedSpotlight(cur)
            } else {
                currentAnnotation = nil
            }
            selectDragSavedState = nil
            selectDidDrag = false
            selectDragMode = .none
            needsDisplay = true
            return
        }

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
        case "d": activate(.draw)
        case "a": activate(.arrow)
        case "r": activate(.rect)
        case "f": activate(.spotlight)
        case "z": activate(.zoom)
        case "c": activate(.crop)
        case "t": activate(.text)
        case "e": activate(.emoji)
        case "\u{1B}":
            commitActiveTextField()
            guard case .idle = arrowPlacementState else {
                resetArrowPlacement()
                needsDisplay = true
                return
            }
            onEscapeAction?()
        default:
            super.keyDown(with: event)
        }
    }

    private func activate(_ tool: AnnotationTool) {
        guard allowedTools.contains(tool) else { return }
        commitActiveTextField()
        activeEmojiPicker?.close()
        activeEmojiPicker = nil
        setSelectedIndex(nil)
        selectedTool = tool
        onToolChanged?(tool)
    }

    // MARK: Select Helpers

    private enum ArrowDragTarget {
        case start, end, bend, shaft
    }

    private func arrowDragTarget(
        point: CGPoint,
        from: CGPoint,
        to: CGPoint,
        bend: CGPoint?,
        pathStyle: ArrowPathStyle
    ) -> ArrowDragTarget {
        let hitRadius: CGFloat = 8
        let bendHitRadius: CGFloat = 10
        if hypot(point.x - from.x, point.y - from.y) <= hitRadius { return .start }
        if hypot(point.x - to.x, point.y - to.y) <= hitRadius { return .end }
        if pathStyle == .autoBend {
            let bendHandle = arrowBendHandle(from: from, to: to, bend: bend)
            if hypot(point.x - bendHandle.x, point.y - bendHandle.y) <= bendHitRadius { return .bend }
        }
        return .shaft
    }

    private func beginSelectDrag(at point: CGPoint, for annotation: Annotation) {
        if case let .arrow(from, to, bend, _, _, pathStyle, _) = annotation {
            switch arrowDragTarget(point: point, from: from, to: to, bend: bend, pathStyle: pathStyle) {
            case .start: selectDragMode = .arrowStart
            case .end: selectDragMode = .arrowEnd
            case .bend: selectDragMode = .arrowBend
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
        } else if case let .spotlight(region, _) = annotation {
            if let handle = rectHitTestHandle(at: point, in: region) {
                selectDragMode = .rectResize(handle: handle, anchor: region)
            } else {
                selectDragMode = .moveWhole
                dragOffset = point
            }
        } else if case let .zoom(rect) = annotation {
            if let handle = rectHitTestHandle(at: point, in: rect) {
                selectDragMode = .rectResize(handle: handle, anchor: rect)
            } else {
                selectDragMode = .moveWhole
                dragOffset = point
            }
        } else if case let .crop(rect) = annotation {
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
        case let .arrow(from, to, bend, _, _, pathStyle, seed):
            let points = arrowShaftPoints(from: from, to: to, bend: bend, pathStyle: pathStyle, seed: seed)
            for i in 0 ..< points.count - 1 {
                if distanceFromPoint(point, toSegment: points[i], points[i + 1]) < 8 { return true }
            }
            return false
        case let .rect(rect, _):
            return rectHitTestHandle(at: point, in: rect) != nil
                || rectInterior(of: rect).contains(point)
                || rect.insetBy(dx: -rectCornerHitRadius, dy: -rectCornerHitRadius).contains(point)
        case let .spotlight(region, _):
            return rectHitTestHandle(at: point, in: region) != nil
                || rectInterior(of: region).contains(point)
                || region.insetBy(dx: -rectCornerHitRadius, dy: -rectCornerHitRadius).contains(point)
        case let .zoom(rect):
            return rectHitTestHandle(at: point, in: rect) != nil
                || rectInterior(of: rect).contains(point)
                || rect.insetBy(dx: -rectCornerHitRadius, dy: -rectCornerHitRadius).contains(point)
        case let .crop(rect):
            return rectHitTestHandle(at: point, in: rect) != nil
                || rectInterior(of: rect).contains(point)
                || rect.insetBy(dx: -rectCornerHitRadius, dy: -rectCornerHitRadius).contains(point)
        case let .text(origin, text, _, maxWidth):
            return textMetrics(origin: origin, text: text, maxWidth: maxWidth).pillRect.contains(point)
        case let .emoji(center, _, size, _):
            return hypot(point.x - center.x, point.y - center.y) < size / 2 + 4
        }
    }

    func remapAnnotations(fromContent oldContent: CGRect, toContent newContent: CGRect) {
        guard oldContent.width > 0, oldContent.height > 0,
              newContent.width > 0, newContent.height > 0,
              oldContent != newContent else { return }

        let scale = (newContent.width / oldContent.width + newContent.height / oldContent.height) / 2
        annotations = annotations.map { placed in
            var copy = placed
            copy.content = transformed(placed.content, from: oldContent, to: newContent, scale: scale)
            return copy
        }
        if let current = currentAnnotation {
            currentAnnotation = transformed(current, from: oldContent, to: newContent, scale: scale)
        }
        needsDisplay = true
    }

    private func mapPoint(_ point: CGPoint, from oldContent: CGRect, to newContent: CGRect) -> CGPoint {
        let u = (point.x - oldContent.minX) / oldContent.width
        let v = (point.y - oldContent.minY) / oldContent.height
        return CGPoint(
            x: newContent.minX + u * newContent.width,
            y: newContent.minY + v * newContent.height
        )
    }

    private func mapRect(_ rect: CGRect, from oldContent: CGRect, to newContent: CGRect) -> CGRect {
        let topLeft = mapPoint(rect.origin, from: oldContent, to: newContent)
        let bottomRight = mapPoint(
            CGPoint(x: rect.maxX, y: rect.maxY),
            from: oldContent,
            to: newContent
        )
        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        )
    }

    private func transformed(
        _ annotation: Annotation,
        from oldContent: CGRect,
        to newContent: CGRect,
        scale: CGFloat
    ) -> Annotation {
        switch annotation {
        case let .stroke(points, color, lineWidth, tool):
            return .stroke(
                points: points.map { mapPoint($0, from: oldContent, to: newContent) },
                color: color,
                lineWidth: lineWidth * scale,
                tool: tool
            )
        case let .arrow(from, to, bend, color, tipStyle, pathStyle, seed):
            return .arrow(
                from: mapPoint(from, from: oldContent, to: newContent),
                to: mapPoint(to, from: oldContent, to: newContent),
                bend: bend.map { mapPoint($0, from: oldContent, to: newContent) },
                color: color,
                tipStyle: tipStyle,
                pathStyle: pathStyle,
                seed: seed
            )
        case let .rect(rect, color):
            return .rect(rect: mapRect(rect, from: oldContent, to: newContent), color: color)
        case let .spotlight(region, technique):
            return .spotlight(region: mapRect(region, from: oldContent, to: newContent), technique: technique)
        case let .zoom(rect):
            return .zoom(rect: mapRect(rect, from: oldContent, to: newContent))
        case let .crop(rect):
            return .crop(rect: mapRect(rect, from: oldContent, to: newContent))
        case let .text(origin, text, color, maxWidth):
            return .text(
                origin: mapPoint(origin, from: oldContent, to: newContent),
                text: text,
                color: color,
                maxWidth: maxWidth.map { $0 * scale }
            )
        case let .emoji(center, emoji, size, color):
            return .emoji(
                center: mapPoint(center, from: oldContent, to: newContent),
                emoji: emoji,
                size: size * scale,
                color: color
            )
        }
    }

    private func moved(_ annotation: Annotation, by delta: CGPoint) -> Annotation {
        switch annotation {
        case let .stroke(points, color, lineWidth, tool):
            return .stroke(
                points: points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) },
                color: color, lineWidth: lineWidth, tool: tool
            )
        case let .arrow(from, to, bend, color, tipStyle, pathStyle, seed):
            return .arrow(
                from: CGPoint(x: from.x + delta.x, y: from.y + delta.y),
                to: CGPoint(x: to.x + delta.x, y: to.y + delta.y),
                bend: bend.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) },
                color: color,
                tipStyle: tipStyle,
                pathStyle: pathStyle,
                seed: seed
            )
        case let .rect(rect, color):
            return .rect(rect: rect.offsetBy(dx: delta.x, dy: delta.y), color: color)
        case let .spotlight(region, technique):
            return .spotlight(region: region.offsetBy(dx: delta.x, dy: delta.y), technique: technique)
        case let .zoom(rect):
            return .zoom(rect: rect.offsetBy(dx: delta.x, dy: delta.y))
        case let .crop(rect):
            return .crop(rect: rect.offsetBy(dx: delta.x, dy: delta.y))
        case let .text(origin, text, color, maxWidth):
            return .text(
                origin: CGPoint(x: origin.x + delta.x, y: origin.y + delta.y),
                text: text, color: color, maxWidth: maxWidth
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
        case let .arrow(from, to, bend, _, _, pathStyle, seed):
            let points = arrowShaftPoints(from: from, to: to, bend: bend, pathStyle: pathStyle, seed: seed)
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            let minX = xs.min() ?? min(from.x, to.x)
            let maxX = xs.max() ?? max(from.x, to.x)
            let minY = ys.min() ?? min(from.y, to.y)
            let maxY = ys.max() ?? max(from.y, to.y)
            return CGRect(
                x: minX - 12, y: minY - 12,
                width: maxX - minX + 24, height: maxY - minY + 24
            )
        case let .rect(rect, _):
            return rect
        case let .spotlight(region, _):
            return region
        case let .zoom(rect):
            return rect
        case let .crop(rect):
            return rect
        case let .text(origin, text, _, maxWidth):
            return textMetrics(origin: origin, text: text, maxWidth: maxWidth).selectionRect
        case let .emoji(center, _, size, _):
            let r = size / 2 + StickerStyle.outlineWidth
            return CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        }
    }

    // MARK: Flatten

    func flattenedImage(background: NSImage) -> NSImage {
        commitActiveTextField()
        guard bounds.width > 0, bounds.height > 0 else { return background }

        let cropRect: CGRect? = {
            if selectedTool == .crop, let rect = cropEditingRect, !isFullBoundsCrop(rect), rect.width > 1, rect.height > 1 {
                return rect
            }
            return annotations.compactMap { placed -> CGRect? in
                if case .crop(let rect) = placed.content { return rect }
                return nil
            }.last
        }()

        let canvasSize = bounds.size
        let imageSize = background.size

        if let crop = cropRect, crop.width > 1, crop.height > 1 {
            let sx = imageSize.width / canvasSize.width
            let sy = imageSize.height / canvasSize.height
            let imageCrop = CGRect(
                x: (crop.origin.x * sx).rounded(),
                y: (crop.origin.y * sy).rounded(),
                width: (crop.width * sx).rounded(),
                height: (crop.height * sy).rounded()
            )
            let croppedBackground = Self.croppedImage(background, to: imageCrop)
            let offset = CGPoint(x: -crop.origin.x, y: -crop.origin.y)
            let outputCanvasSize = crop.size
            return flattenedImage(
                background: croppedBackground,
                at: playbackTime,
                outputSize: CGSize(
                    width: (outputCanvasSize.width * sx).rounded(),
                    height: (outputCanvasSize.height * sy).rounded()
                ),
                mapFromCanvasSize: canvasSize,
                annotationOffset: offset,
                skipCropOverlays: true
            )
        }

        return flattenedImage(
            background: background,
            at: playbackTime,
            outputSize: canvasSize,
            mapFromCanvasSize: canvasSize
        )
    }

    private static func croppedImage(_ image: NSImage, to rect: CGRect) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cropped = cgImage.cropping(to: rect) else { return image }
        return NSImage(cgImage: cropped, size: rect.size)
    }

    func flattenedImage(
        background: NSImage,
        at time: Double,
        outputSize: CGSize,
        mapFromCanvasSize canvasSize: CGSize,
        annotationOffset: CGPoint = .zero,
        skipCropOverlays: Bool = false
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

        let previousBackground = stageBackgroundImage
        stageBackgroundImage = background
        defer { stageBackgroundImage = previousBackground }

        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            if canvasSize.width > 0, canvasSize.height > 0,
               outputSize.width != canvasSize.width || outputSize.height != canvasSize.height {
                let sx = outputSize.width / canvasSize.width
                let sy = outputSize.height / canvasSize.height
                ctx.scaleBy(x: sx, y: sy)
            }
            let renderBounds = CGRect(origin: .zero, size: canvasSize)
            for placed in annotations {
                if !videoMode || placed.isVisible(at: time) {
                    let content = annotationOffset == .zero
                        ? placed.content
                        : moved(placed.content, by: annotationOffset)
                    guard case let .spotlight(region, technique) = content else { continue }
                    renderSpotlight(
                        region: region,
                        technique: technique,
                        in: ctx,
                        canvasBounds: renderBounds
                    )
                }
            }
            for placed in annotations {
                if !videoMode || placed.isVisible(at: time) {
                    if case .zoom = placed.content { continue }
                    if case .spotlight = placed.content { continue }
                    if skipCropOverlays, case .crop = placed.content { continue }
                    let content = annotationOffset == .zero
                        ? placed.content
                        : moved(placed.content, by: annotationOffset)
                    render(content, in: ctx)
                }
            }
        }

        return result
    }

    func makeExportSnapshot() -> AnnotationExportSnapshot {
        commitActiveTextField()
        return AnnotationExportSnapshot(annotations: annotations, canvasSize: bounds.size)
    }

    /// Renders a single export frame using a frozen annotation snapshot. Must run on the main thread.
    func flattenedImageForExport(
        background: NSImage,
        at time: Double,
        outputSize: CGSize,
        mapFromCanvasSize canvasSize: CGSize,
        annotations: [PlacedAnnotation]
    ) -> NSImage {
        guard outputSize.width > 0, outputSize.height > 0 else { return background }

        let width = Int(outputSize.width)
        let height = Int(outputSize.height)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphicsContext = NSGraphicsContext(bitmapImageRep: rep) else {
            return background
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        defer { NSGraphicsContext.restoreGraphicsState() }

        background.draw(
            in: NSRect(origin: .zero, size: outputSize),
            from: NSRect(origin: .zero, size: background.size),
            operation: .sourceOver,
            fraction: 1.0
        )

        let previousBackground = stageBackgroundImage
        stageBackgroundImage = background
        defer { stageBackgroundImage = previousBackground }

        let ctx = graphicsContext.cgContext
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if canvasSize.width > 0, canvasSize.height > 0,
           outputSize.width != canvasSize.width || outputSize.height != canvasSize.height {
            let sx = outputSize.width / canvasSize.width
            let sy = outputSize.height / canvasSize.height
            ctx.scaleBy(x: sx, y: sy)
        }
        let renderBounds = CGRect(origin: .zero, size: canvasSize)
        for placed in annotations {
            if placed.isVisible(at: time) {
                guard case let .spotlight(region, technique) = placed.content else { continue }
                renderSpotlight(
                    region: region,
                    technique: technique,
                    in: ctx,
                    canvasBounds: renderBounds
                )
            }
        }
        for placed in annotations {
            if placed.isVisible(at: time) {
                if case .zoom = placed.content { continue }
                if case .spotlight = placed.content { continue }
                render(placed.content, in: ctx)
            }
        }

        let result = NSImage(size: outputSize)
        result.addRepresentation(rep)
        return result
    }
}

// MARK: - CircleColorButton

final class CircleColorButton: NSButton {
    var color: NSColor
    var isCustomSlot: Bool = false
    var customPreviewColor: NSColor?
    /// Insets the drawn circle within the button bounds; hit area stays full `bounds`.
    var visualInset: CGFloat = 0

    var isColorSelected: Bool = false {
        didSet { needsDisplay = true }
    }

    init(color: NSColor, isCustomSlot: Bool = false, visualInset: CGFloat = 0) {
        self.color = color
        self.isCustomSlot = isCustomSlot
        self.visualInset = visualInset
        super.init(frame: .zero)
        bezelStyle = .regularSquare
        isBordered = false
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let dotBounds = bounds.insetBy(dx: visualInset, dy: visualInset)

        if isCustomSlot {
            drawCustomSlot(in: dotBounds, context: ctx)
        } else {
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: dotBounds)
        }

        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.12).cgColor)
        ctx.setLineWidth(0.5)
        ctx.strokeEllipse(in: dotBounds.insetBy(dx: 0.25, dy: 0.25))

        if isColorSelected {
            let ringColor: NSColor = {
                if isCustomSlot {
                    return (customPreviewColor ?? NSColor.secondaryLabelColor).darkenedPaletteSteps()
                }
                return color.darkenedPaletteSteps()
            }()
            let ringWidth: CGFloat = 3
            ctx.setStrokeColor(ringColor.cgColor)
            ctx.setLineWidth(ringWidth)
            ctx.strokeEllipse(in: dotBounds.insetBy(dx: -ringWidth / 2, dy: -ringWidth / 2))
        }
    }

    private func drawCustomSlot(in rect: NSRect, context ctx: CGContext) {
        if let preview = customPreviewColor {
            ctx.setFillColor(preview.cgColor)
            ctx.fillEllipse(in: rect)
        } else {
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: rect)
        }

        let ring = rect.insetBy(dx: 1.5, dy: 1.5)
        let segments = 24
        let center = CGPoint(x: ring.midX, y: ring.midY)
        let radius = min(ring.width, ring.height) / 2
        ctx.setLineWidth(2.5)
        for i in 0..<segments {
            let t0 = CGFloat(i) / CGFloat(segments)
            let t1 = CGFloat(i + 1) / CGFloat(segments)
            let c0 = NSColor(calibratedHue: t0, saturation: 0.95, brightness: 0.95, alpha: 1)
            let c1 = NSColor(calibratedHue: t1, saturation: 0.95, brightness: 0.95, alpha: 1)
            ctx.setStrokeColor(c0.cgColor)
            let a0 = t0 * .pi * 2 - .pi / 2
            let a1 = t1 * .pi * 2 - .pi / 2
            ctx.beginPath()
            ctx.addArc(center: center, radius: radius, startAngle: a0, endAngle: a1, clockwise: false)
            ctx.strokePath()
            _ = c1
        }

        if customPreviewColor == nil {
            let plus = min(rect.width, rect.height) * 0.22
            ctx.setStrokeColor(NSColor.secondaryLabelColor.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: rect.midX - plus, y: rect.midY))
            ctx.addLine(to: CGPoint(x: rect.midX + plus, y: rect.midY))
            ctx.move(to: CGPoint(x: rect.midX, y: rect.midY - plus))
            ctx.addLine(to: CGPoint(x: rect.midX, y: rect.midY + plus))
            ctx.strokePath()
        }
    }
}

// MARK: - Color Grid Menu

final class ColorGridMenuPanel: NSObject {

    private let panel: NSPanel
    private let onSelectPalette: (Int) -> Void
    private let onSelectCustom: () -> Void
    private var colorButtons: [Int: CircleColorButton] = [:]
    private var customButton: CircleColorButton!
    private var clickOutsideMonitor: Any?
    private var anchorScreenRect: NSRect = .zero
    private var customPreviewColor: NSColor?

    init(onSelectPalette: @escaping (Int) -> Void, onSelectCustom: @escaping () -> Void) {
        self.onSelectPalette = onSelectPalette
        self.onSelectCustom = onSelectCustom

        let cellSz: CGFloat = 28
        let dotInset: CGFloat = 6
        let gap: CGFloat = 6
        let pad: CGFloat = 8
        let cols: CGFloat = 3
        let panelW = pad * 2 + cols * cellSz + (cols - 1) * gap
        let panelH = panelW

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
        buildUI(cellSz: cellSz, dotInset: dotInset, gap: gap, pad: pad)
    }

    private func buildUI(cellSz: CGFloat, dotInset: CGFloat, gap: CGFloat, pad: CGFloat) {
        let container = NSView(frame: panel.contentView!.bounds)
        container.autoresizingMask = [.width, .height]

        let vfx = NSVisualEffectView(frame: container.bounds)
        vfx.autoresizingMask = [.width, .height]
        vfx.material = .popover
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = DesignTokens.Radius.lg
        vfx.layer?.masksToBounds = true
        container.addSubview(vfx)

        for (i, color) in NSColor.annotationPalette.enumerated() {
            let row = i / 3
            let col = i % 3
            let x = pad + CGFloat(col) * (cellSz + gap)
            let y = pad + CGFloat(2 - row) * (cellSz + gap)
            let btn = CircleColorButton(color: color, visualInset: dotInset)
            btn.frame = CGRect(x: x, y: y, width: cellSz, height: cellSz)
            btn.tag = i
            btn.target = self
            btn.action = #selector(paletteTapped(_:))
            container.addSubview(btn)
            colorButtons[i] = btn
        }

        let customBtn = CircleColorButton(color: .white, isCustomSlot: true, visualInset: dotInset)
        customBtn.frame = CGRect(
            x: pad + 2 * (cellSz + gap),
            y: pad,
            width: cellSz,
            height: cellSz
        )
        customBtn.target = self
        customBtn.action = #selector(customTapped)
        container.addSubview(customBtn)
        customButton = customBtn

        panel.contentView = container
    }

    func show(
        aboveScreenRect buttonRect: NSRect,
        selectedColor: NSColor,
        customPreviewColor: NSColor?
    ) {
        hide()
        self.anchorScreenRect = buttonRect
        self.customPreviewColor = customPreviewColor
        customButton.customPreviewColor = customPreviewColor

        let paletteIdx = NSColor.paletteIndex(matching: selectedColor)
        for (i, btn) in colorButtons {
            btn.isColorSelected = (i == paletteIdx)
        }
        customButton.isColorSelected = (paletteIdx == nil)

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

    @objc private func paletteTapped(_ sender: NSButton) {
        hide()
        onSelectPalette(sender.tag)
    }

    @objc private func customTapped() {
        hide()
        onSelectCustom()
    }
}

// MARK: - Figma-Style Color Picker

private final class ColorPickerSBView: NSView {
    var hue: CGFloat = 0 { didSet { needsDisplay = true } }
    var saturation: CGFloat = 1
    var brightness: CGFloat = 1
    var onChanged: ((CGFloat, CGFloat) -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds

        let hueColor = NSColor(calibratedHue: hue, saturation: 1, brightness: 1, alpha: 1)
        ctx.setFillColor(hueColor.cgColor)
        ctx.fill(b)

        let white = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawLinearGradient(
            white,
            start: CGPoint(x: b.minX, y: b.midY),
            end: CGPoint(x: b.maxX, y: b.midY),
            options: []
        )

        let black = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.cgColor] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawLinearGradient(
            black,
            start: CGPoint(x: b.midX, y: b.minY),
            end: CGPoint(x: b.midX, y: b.maxY),
            options: []
        )

        let x = b.minX + saturation * b.width
        let y = b.minY + (1 - brightness) * b.height
        let indicator = CGRect(x: x - 5, y: y - 5, width: 10, height: 10)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth( 2)
        ctx.strokeEllipse(in: indicator)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: indicator.insetBy(dx: 1, dy: 1))
    }

    private func update(from event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        saturation = min(1, max(0, loc.x / bounds.width))
        brightness = min(1, max(0, 1 - loc.y / bounds.height))
        onChanged?(saturation, brightness)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) { update(from: event) }
    override func mouseDragged(with event: NSEvent) { update(from: event) }
}

private final class ColorPickerHueSlider: NSView {
    var hue: CGFloat = 0 { didSet { needsDisplay = true } }
    var onChanged: ((CGFloat) -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds
        let steps = 60
        let stepW = b.width / CGFloat(steps)
        for i in 0..<steps {
            let t = CGFloat(i) / CGFloat(steps)
            let color = NSColor(calibratedHue: t, saturation: 1, brightness: 1, alpha: 1)
            ctx.setFillColor(color.cgColor)
            ctx.fill(CGRect(x: b.minX + CGFloat(i) * stepW, y: b.minY, width: stepW + 1, height: b.height))
        }

        let x = b.minX + hue * b.width
        let thumb = CGRect(x: x - 4, y: b.midY - 6, width: 8, height: 12)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(thumb)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.25).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(thumb)
    }

    private func update(from event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        hue = min(1, max(0, loc.x / bounds.width))
        onChanged?(hue)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) { update(from: event) }
    override func mouseDragged(with event: NSEvent) { update(from: event) }
}

final class FigmaStyleColorPickerPanel: NSObject, NSTextFieldDelegate {

    private let panel: NSPanel
    private let onColorChanged: (NSColor) -> Void
    private var clickOutsideMonitor: Any?
    private var anchorScreenRect: NSRect = .zero

    private var hue: CGFloat = 0
    private var saturation: CGFloat = 1
    private var brightness: CGFloat = 1

    private let sbView = ColorPickerSBView()
    private let hueSlider = ColorPickerHueSlider()
    private let hexField = NSTextField()
    private let previewSwatch = NSView()
    private var isUpdatingHex = false

    init(onColorChanged: @escaping (NSColor) -> Void) {
        self.onColorChanged = onColorChanged

        let pad: CGFloat = 10
        let sbSize: CGFloat = 200
        let hueH: CGFloat = 14
        let rowH: CGFloat = 24
        let gap: CGFloat = 8
        let panelW = pad * 2 + sbSize
        let panelH = pad + sbSize + gap + hueH + gap + rowH + pad

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
        panel.hidesOnDeactivate = false

        super.init()
        buildUI(pad: pad, sbSize: sbSize, hueH: hueH, rowH: rowH, gap: gap)
    }

    private func buildUI(pad: CGFloat, sbSize: CGFloat, hueH: CGFloat, rowH: CGFloat, gap: CGFloat) {
        let container = NSView(frame: panel.contentView!.bounds)
        container.autoresizingMask = [.width, .height]

        let vfx = NSVisualEffectView(frame: container.bounds)
        vfx.autoresizingMask = [.width, .height]
        vfx.material = .popover
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = DesignTokens.Radius.lg
        vfx.layer?.masksToBounds = true
        container.addSubview(vfx)

        var y = pad

        sbView.frame = CGRect(x: pad, y: y, width: sbSize, height: sbSize)
        sbView.wantsLayer = true
        sbView.layer?.cornerRadius = DesignTokens.Radius.md
        sbView.layer?.masksToBounds = true
        sbView.onChanged = { [weak self] sat, bri in
            self?.setSaturationBrightness(saturation: sat, brightness: bri)
        }
        container.addSubview(sbView)
        y += sbSize + gap

        hueSlider.frame = CGRect(x: pad, y: y, width: sbSize, height: hueH)
        hueSlider.wantsLayer = true
        hueSlider.layer?.cornerRadius = DesignTokens.Radius.sm
        hueSlider.layer?.masksToBounds = true
        hueSlider.onChanged = { [weak self] h in
            self?.setHue(h)
        }
        container.addSubview(hueSlider)
        y += hueH + gap

        previewSwatch.frame = CGRect(x: pad, y: y, width: rowH, height: rowH)
        previewSwatch.wantsLayer = true
        previewSwatch.layer?.cornerRadius = DesignTokens.Radius.sm
        previewSwatch.layer?.borderWidth = 1
        previewSwatch.layer?.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor
        container.addSubview(previewSwatch)

        hexField.frame = CGRect(x: pad + rowH + 8, y: y, width: sbSize - rowH - 8, height: rowH)
        hexField.isBezeled = true
        hexField.bezelStyle = .roundedBezel
        hexField.font = NSFont.monospacedSystemFont(ofSize: DesignTokens.Typography.label.size, weight: .regular)
        hexField.placeholderString = "Hex"
        hexField.delegate = self
        container.addSubview(hexField)

        panel.contentView = container
    }

    func show(aboveScreenRect buttonRect: NSRect, initialColor: NSColor) {
        hide()
        anchorScreenRect = buttonRect
        setColor(initialColor, notify: false)

        let panelW = panel.frame.width
        let panelX = (buttonRect.midX - panelW / 2).rounded()
        let panelY = buttonRect.maxY + 6
        panel.setFrameOrigin(NSPoint(x: panelX, y: panelY))
        panel.makeKeyAndOrderFront(nil)

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

    private func currentColor() -> NSColor {
        NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1)
    }

    private func setColor(_ color: NSColor, notify: Bool) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        (color.usingColorSpace(.deviceRGB) ?? color).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = h.isNaN ? 0 : h
        saturation = s
        brightness = b
        syncViews(notify: notify)
    }

    private func setHue(_ h: CGFloat) {
        hue = h
        syncViews(notify: true)
    }

    private func setSaturationBrightness(saturation s: CGFloat, brightness b: CGFloat) {
        saturation = s
        brightness = b
        syncViews(notify: true)
    }

    private func syncViews(notify: Bool) {
        sbView.hue = hue
        sbView.saturation = saturation
        sbView.brightness = brightness
        hueSlider.hue = hue
        sbView.needsDisplay = true
        hueSlider.needsDisplay = true
        previewSwatch.layer?.backgroundColor = currentColor().cgColor

        isUpdatingHex = true
        hexField.stringValue = "#\(currentColor().hexString)"
        isUpdatingHex = false

        if notify {
            onColorChanged(currentColor())
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard !isUpdatingHex, obj.object as? NSTextField === hexField else { return }
        guard let color = NSColor(hexString: hexField.stringValue) else { return }
        setColor(color, notify: true)
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

        nameLabel.font = NSFont.snipsnap(.label)
        nameLabel.textColor = .white
        nameLabel.isBezeled = false
        nameLabel.isEditable = false
        nameLabel.drawsBackground = false

        shortcutLabel.font = NSFont.snipsnap(.caption)
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

// MARK: - View background (file setting)

enum AnnotationViewBackground {
    static let presetStyles: [RecordingBackgroundStyle] = [.none, .warm, .cool, .midnight]

    static func stageLayout(
        for screenshotSize: NSSize,
        background: RecordingBackgroundStyle
    ) -> (stage: NSSize, contentFrame: NSRect) {
        guard background != .none else {
            let stage = fittedStageSize(screenshotSize)
            return (stage, NSRect(origin: .zero, size: stage))
        }

        let canvasSize = RecordingBackgroundRenderer.canvasSize(for: 1)
        let stage = fittedStageSize(canvasSize)
        let content = RecordingBackgroundRenderer.windowFrame(
            inCanvas: screenshotSize,
            canvasSize: canvasSize
        )
        let scale = stage.width / canvasSize.width
        let contentFrame = NSRect(
            x: (content.origin.x * scale).rounded(),
            y: (content.origin.y * scale).rounded(),
            width: (content.width * scale).rounded(),
            height: (content.height * scale).rounded()
        )
        return (stage, contentFrame)
    }

    static func fittedStageSize(_ size: NSSize) -> NSSize {
        guard size.width > 0, size.height > 0 else { return NSSize(width: 800, height: 600) }
        let scale = min(1200 / size.width, 800 / size.height, 1.0)
        return NSSize(
            width: (size.width * scale).rounded(),
            height: (size.height * scale).rounded()
        )
    }

    static func renderStage(
        screenshot: NSImage,
        layout: (stage: NSSize, contentFrame: NSRect),
        background: RecordingBackgroundStyle
    ) -> NSImage {
        let size = layout.stage
        guard size.width > 0, size.height > 0 else { return screenshot }

        let width = max(1, Int(size.width))
        let height = max(1, Int(size.height))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphicsContext = NSGraphicsContext(bitmapImageRep: rep) else {
            return screenshot
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        if background != .none,
           let bg = RecordingBackgroundRenderer.backgroundPreviewImage(for: background) {
            bg.draw(
                in: NSRect(origin: .zero, size: size),
                from: NSRect(origin: .zero, size: bg.size),
                operation: .sourceOver,
                fraction: 1
            )
        }

        screenshot.draw(
            in: layout.contentFrame,
            from: NSRect(origin: .zero, size: screenshot.size),
            operation: .sourceOver,
            fraction: 1
        )

        let result = NSImage(size: size)
        result.addRepresentation(rep)
        return result
    }
}

// MARK: - DrawStyleMenuPanel

final class DrawStyleMenuPanel: NSObject {

    private let panel: NSPanel
    private let onSelect: (StrokeTool) -> Void
    private var styleButtons: [StrokeTool: NSButton] = [:]
    private var clickOutsideMonitor: Any?
    private var accentColor: NSColor = .systemBlue
    private var anchorScreenRect: NSRect = .zero
    private var selectedStyle: StrokeTool = .marker

    init(onSelect: @escaping (StrokeTool) -> Void) {
        self.onSelect = onSelect

        let btnSz: CGFloat = 32
        let gap: CGFloat = 4
        let pad: CGFloat = 6
        let count = CGFloat(StrokeTool.allCases.count)
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
        vfx.layer?.cornerRadius = DesignTokens.Radius.lg
        vfx.layer?.masksToBounds = true
        container.addSubview(vfx)

        var y = pad
        for (index, style) in StrokeTool.allCases.enumerated() {
            let btn = NSButton(frame: CGRect(x: pad, y: y, width: btnSz, height: btnSz))
            btn.bezelStyle = .regularSquare
            btn.isBordered = false
            let cfg = NSImage.SymbolConfiguration(pointSize: style.menuSymbolPointSize, weight: .medium)
            btn.image = NSImage(systemSymbolName: style.menuSymbol, accessibilityDescription: style.accessibilityLabel)?
                .withSymbolConfiguration(cfg)
            btn.imageScaling = .scaleProportionallyDown
            btn.wantsLayer = true
            btn.layer?.cornerRadius = DesignTokens.Radius.md
            btn.target = self
            btn.action = #selector(styleTapped(_:))
            btn.tag = index
            btn.toolTip = style.accessibilityLabel
            container.addSubview(btn)
            styleButtons[style] = btn
            y += btnSz + gap
        }

        panel.contentView = container
    }

    func show(
        aboveScreenRect buttonRect: NSRect,
        selectedStyle: StrokeTool,
        accentColor: NSColor
    ) {
        hide()
        self.accentColor = accentColor
        self.anchorScreenRect = buttonRect
        self.selectedStyle = selectedStyle
        refreshSelection()

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

    private func refreshSelection() {
        for (style, btn) in styleButtons {
            let on = style == selectedStyle
            btn.contentTintColor = on ? accentColor : .labelColor
            btn.layer?.backgroundColor = on ? accentColor.withAlphaComponent(0.2).cgColor : .clear
        }
    }

    @objc private func styleTapped(_ sender: NSButton) {
        let styles = StrokeTool.allCases
        guard sender.tag < styles.count else { return }
        selectedStyle = styles[sender.tag]
        refreshSelection()
        hide()
        onSelect(selectedStyle)
    }
}

// MARK: - ArrowStyleMenuPanel

final class ArrowStyleMenuPanel: NSObject {

    private let panel: NSPanel
    private let onTipSelect: (ArrowTipStyle) -> Void
    private let onPathSelect: (ArrowPathStyle) -> Void
    private var tipButtons: [ArrowTipStyle: NSButton] = [:]
    private var pathButtons: [ArrowPathStyle: NSButton] = [:]
    private var clickOutsideMonitor: Any?
    private var accentColor: NSColor = .systemBlue
    private var anchorScreenRect: NSRect = .zero
    private var selectedTipStyle: ArrowTipStyle = .solid
    private var selectedPathStyle: ArrowPathStyle = .autoBend

    private let tipTagBase = 0
    private let pathTagBase = 100

    init(
        onTipSelect: @escaping (ArrowTipStyle) -> Void,
        onPathSelect: @escaping (ArrowPathStyle) -> Void
    ) {
        self.onTipSelect = onTipSelect
        self.onPathSelect = onPathSelect

        let btnSz: CGFloat = 32
        let gap: CGFloat = 4
        let pad: CGFloat = 6
        let separatorH: CGFloat = 9
        let tipCount = CGFloat(ArrowTipStyle.allCases.count)
        let pathCount = CGFloat(ArrowPathStyle.allCases.count)
        let panelW = pad * 2 + btnSz
        let panelH = pad * 2
            + tipCount * btnSz + (tipCount - 1) * gap
            + separatorH
            + pathCount * btnSz + (pathCount - 1) * gap

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
        buildUI(btnSz: btnSz, gap: gap, pad: pad, separatorH: separatorH)
    }

    private func buildUI(btnSz: CGFloat, gap: CGFloat, pad: CGFloat, separatorH: CGFloat) {
        let container = NSView(frame: panel.contentView!.bounds)
        container.autoresizingMask = [.width, .height]

        let vfx = NSVisualEffectView(frame: container.bounds)
        vfx.autoresizingMask = [.width, .height]
        vfx.material = .popover
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = DesignTokens.Radius.lg
        vfx.layer?.masksToBounds = true
        container.addSubview(vfx)

        // Bottom group (closest to toolbar): tip styles. Top group: path styles.
        var y = pad
        for (index, style) in ArrowTipStyle.allCases.enumerated() {
            let btn = makeStyleButton(
                symbol: style.menuSymbol,
                pointSize: style.menuSymbolPointSize,
                label: style.accessibilityLabel,
                tag: tipTagBase + index,
                frame: CGRect(x: pad, y: y, width: btnSz, height: btnSz)
            )
            container.addSubview(btn)
            tipButtons[style] = btn
            y += btnSz + gap
        }

        y -= gap
        let separator = NSView(frame: CGRect(x: pad + 4, y: y + (separatorH - 1) / 2, width: btnSz - 8, height: 1))
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        container.addSubview(separator)
        y += separatorH

        for (index, style) in ArrowPathStyle.allCases.enumerated() {
            let btn = makeStyleButton(
                symbol: style.menuSymbol,
                pointSize: style.menuSymbolPointSize,
                label: style.accessibilityLabel,
                tag: pathTagBase + index,
                frame: CGRect(x: pad, y: y, width: btnSz, height: btnSz)
            )
            container.addSubview(btn)
            pathButtons[style] = btn
            y += btnSz + gap
        }

        panel.contentView = container
    }

    private func makeStyleButton(
        symbol: String,
        pointSize: CGFloat,
        label: String,
        tag: Int,
        frame: CGRect
    ) -> NSButton {
        let btn = NSButton(frame: frame)
        btn.bezelStyle = .regularSquare
        btn.isBordered = false
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(cfg)
        btn.imageScaling = .scaleProportionallyDown
        btn.wantsLayer = true
        btn.layer?.cornerRadius = DesignTokens.Radius.md
        btn.target = self
        btn.action = #selector(styleTapped(_:))
        btn.tag = tag
        btn.toolTip = label
        return btn
    }

    func show(
        aboveScreenRect buttonRect: NSRect,
        selectedTipStyle: ArrowTipStyle,
        selectedPathStyle: ArrowPathStyle,
        accentColor: NSColor
    ) {
        hide()
        self.accentColor = accentColor
        self.anchorScreenRect = buttonRect
        self.selectedTipStyle = selectedTipStyle
        self.selectedPathStyle = selectedPathStyle
        refreshSelection()

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

    private func refreshSelection() {
        for (style, btn) in tipButtons {
            let on = style == selectedTipStyle
            btn.contentTintColor = on ? accentColor : .labelColor
            btn.layer?.backgroundColor = on ? accentColor.withAlphaComponent(0.2).cgColor : .clear
        }
        for (style, btn) in pathButtons {
            let on = style == selectedPathStyle
            btn.contentTintColor = on ? accentColor : .labelColor
            btn.layer?.backgroundColor = on ? accentColor.withAlphaComponent(0.2).cgColor : .clear
        }
    }

    @objc private func styleTapped(_ sender: NSButton) {
        if sender.tag >= pathTagBase {
            let styles = ArrowPathStyle.allCases
            let index = sender.tag - pathTagBase
            guard index < styles.count else { return }
            selectedPathStyle = styles[index]
            refreshSelection()
            hide()
            onPathSelect(selectedPathStyle)
            return
        }

        let styles = ArrowTipStyle.allCases
        guard sender.tag < styles.count else { return }
        selectedTipStyle = styles[sender.tag]
        refreshSelection()
        hide()
        onTipSelect(selectedTipStyle)
    }
}

// MARK: - ToolHoverButton

final class ToolHoverButton: NSButton {

    var tool: AnnotationTool?
    var onTooltipRequested: ((NSRect) -> Void)?
    var onTooltipDismissed: (() -> Void)?
    /// When true, tooltips show immediately instead of after the initial delay.
    var areTooltipsPrimed: (() -> Bool)?

    private static let initialTooltipDelay: TimeInterval = 1.0

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
        let delay = areTooltipsPrimed?() == true ? 0 : Self.initialTooltipDelay
        tooltipTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
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

    var selectedTool: AnnotationTool = .draw {
        didSet {
            refresh()
            if selectedTool == .select {
                setProximityFaded(false, passThroughMouse: false)
            } else if let win = window {
                updateProximityFade(at: win.mouseLocationOutsideOfEventStream)
            }
        }
    }
    var selectedColor: NSColor = NSColor.annotationPalette[0] { didSet { refresh() } }
    var selectedStrokeTool: StrokeTool = .marker { didSet { refresh() } }
    var selectedArrowTipStyle: ArrowTipStyle = .solid { didSet { refresh() } }
    var selectedArrowPathStyle: ArrowPathStyle = .autoBend { didSet { refresh() } }
    var selectedSpotlightTechnique: SpotlightTechnique = .dim { didSet { refresh() } }
    /// When true, the color swatch is replaced by the Dim/Blur/Desaturate picker.
    var showsSpotlightTechniquePicker: Bool = false {
        didSet {
            guard oldValue != showsSpotlightTechniquePicker else { return }
            layoutAccessoryControls()
            refresh()
        }
    }
    var customColor: NSColor?

    var onToolSelected: ((AnnotationTool) -> Void)?
    var onColorSelected: ((NSColor) -> Void)?
    var onStrokeToolSelected: ((StrokeTool) -> Void)?
    var onArrowTipStyleSelected: ((ArrowTipStyle) -> Void)?
    var onArrowPathStyleSelected: ((ArrowPathStyle) -> Void)?
    var onSpotlightTechniqueSelected: ((SpotlightTechnique) -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?

    private let showsCopyButton: Bool
    private let showsSaveButton: Bool
    private let availableTools: [AnnotationTool]
    private var copyButton: NSButton?
    private var saveButton: NSButton?

    private var toolButtons: [AnnotationTool: ToolHoverButton] = [:]
    private var colorSwatchButton: CircleColorButton!
    private var techniqueButtons: [SpotlightTechnique: NSButton] = [:]
    private var accessorySeparator: NSView!
    private var trailingSeparator: NSView?
    private let tooltipPanel = ToolTooltipPanel()
    private var tooltipsPrimed = false
    private var drawStyleMenu: DrawStyleMenuPanel!
    private var arrowStyleMenu: ArrowStyleMenuPanel!
    private var colorGridMenu: ColorGridMenuPanel!
    private var customColorPicker: FigmaStyleColorPickerPanel!
    private var backgroundEffect: NSVisualEffectView!
    private let pillHeight: CGFloat = 40
    private let toolButtonSize: CGFloat = 28
    private let toolSectionPadding: CGFloat = 6
    private var toolsSectionEndX: CGFloat = 0

    private var dragStartMouseLocation: NSPoint?
    private var dragStartFrameOrigin: NSPoint?

    /// When set, dragging is clamped to this rect in the superview's coordinate space.
    var dragBounds: CGRect?

    private let proximityMargin: CGFloat = 16
    private let fadedAlpha: CGFloat = 0.3
    private var mouseMonitor: Any?
    private var isProximityFaded = false
    private var isRepositionDragging = false
    private var passThroughMouse = false
    private var pressStartedInToolbar = false
    private var dragCursorTrackingArea: NSTrackingArea?

    init(
        frame: NSRect,
        showsCopyButton: Bool = true,
        showsSaveButton: Bool = false,
        availableTools: [AnnotationTool] = AnnotationTool.videoTools
    ) {
        self.showsCopyButton = showsCopyButton
        self.showsSaveButton = showsSaveButton
        self.availableTools = availableTools
        super.init(frame: frame)
        build()
    }

    override init(frame: NSRect) {
        self.showsCopyButton = true
        self.showsSaveButton = false
        self.availableTools = AnnotationTool.videoTools
        super.init(frame: frame)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }

    deinit {
        removeMouseMonitor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            window?.acceptsMouseMovedEvents = true
            installMouseMonitor()
        } else {
            removeMouseMonitor()
            pressStartedInToolbar = false
            setProximityFaded(false, passThroughMouse: false)
        }
    }

    static func defaultOrigin(pillSize: NSSize, in containerSize: NSSize, bottomInset: CGFloat = 16) -> NSPoint {
        NSPoint(
            x: ((containerSize.width - pillSize.width) / 2).rounded(),
            y: bottomInset
        )
    }

    private func build() {
        wantsLayer = true
        if let layer {
            DesignTokens.Elevation.panel.apply(to: layer)
        }

        let h = pillHeight
        let vfx = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: 100, height: h))
        vfx.autoresizingMask = [.width, .height]
        vfx.material = .menu
        vfx.blendingMode = .withinWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = DesignTokens.Radius.sm
        vfx.layer?.masksToBounds = true
        addSubview(vfx)
        backgroundEffect = vfx

        drawStyleMenu = DrawStyleMenuPanel { [weak self] style in
            guard let self else { return }
            self.selectedStrokeTool = style
            self.onStrokeToolSelected?(style)
        }

        arrowStyleMenu = ArrowStyleMenuPanel(
            onTipSelect: { [weak self] style in
                guard let self else { return }
                self.selectedArrowTipStyle = style
                self.onArrowTipStyleSelected?(style)
            },
            onPathSelect: { [weak self] style in
                guard let self else { return }
                self.selectedArrowPathStyle = style
                self.onArrowPathStyleSelected?(style)
            }
        )

        colorGridMenu = ColorGridMenuPanel(
            onSelectPalette: { [weak self] index in
                guard let self else { return }
                let color = NSColor.annotationPalette[index]
                self.customColor = nil
                self.selectedColor = color
                self.onColorSelected?(color)
            },
            onSelectCustom: { [weak self] in
                self?.showCustomColorPicker()
            }
        )

        customColorPicker = FigmaStyleColorPickerPanel { [weak self] color in
            guard let self else { return }
            self.customColor = color
            self.selectedColor = color
            self.onColorSelected?(color)
        }

        let btnSz = toolButtonSize
        let btnY = (h - btnSz) / 2
        var x: CGFloat = toolSectionPadding

        for (i, tool) in availableTools.enumerated() {
            let btn = ToolHoverButton(frame: CGRect(x: x, y: btnY, width: btnSz, height: btnSz))
            btn.bezelStyle = .regularSquare
            btn.isBordered = false
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            btn.image = NSImage(systemSymbolName: tool.sfSymbol, accessibilityDescription: tool.sfSymbol)?
                            .withSymbolConfiguration(cfg)
            btn.imageScaling = .scaleProportionallyDown
            btn.wantsLayer = true
            btn.layer?.cornerRadius = DesignTokens.Radius.md
            btn.tag = i
            btn.target = self
            btn.action = #selector(toolTapped(_:))
            btn.tool = tool
            btn.areTooltipsPrimed = { [weak self] in self?.tooltipsPrimed ?? false }
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

        x += toolSectionPadding
        toolsSectionEndX = x
        accessorySeparator = makeSeparator(at: x, height: h)
        addSubview(accessorySeparator)

        let swSz = btnSz
        let swInset: CGFloat = 6
        let swatch = CircleColorButton(color: selectedColor, visualInset: swInset)
        swatch.frame = CGRect(x: 0, y: btnY, width: swSz, height: swSz)
        swatch.target = self
        swatch.action = #selector(colorSwatchTapped)
        swatch.toolTip = "Color"
        addSubview(swatch)
        colorSwatchButton = swatch

        for (index, technique) in SpotlightTechnique.allCases.enumerated() {
            let btn = NSButton(frame: CGRect(x: 0, y: btnY, width: btnSz, height: btnSz))
            btn.bezelStyle = .regularSquare
            btn.isBordered = false
            let cfg = NSImage.SymbolConfiguration(pointSize: technique.menuSymbolPointSize, weight: .medium)
            btn.image = NSImage(
                systemSymbolName: technique.menuSymbol,
                accessibilityDescription: technique.accessibilityLabel
            )?.withSymbolConfiguration(cfg)
            btn.imageScaling = .scaleProportionallyDown
            btn.wantsLayer = true
            btn.layer?.cornerRadius = DesignTokens.Radius.md
            btn.tag = index
            btn.target = self
            btn.action = #selector(techniqueTapped(_:))
            btn.toolTip = technique.accessibilityLabel
            btn.isHidden = true
            addSubview(btn)
            techniqueButtons[technique] = btn
        }

        if showsCopyButton {
            let trailing = makeSeparator(at: 0, height: h)
            addSubview(trailing)
            trailingSeparator = trailing

            let copyBtn = NSButton(frame: CGRect(x: 0, y: btnY, width: 50, height: btnSz))
            copyBtn.bezelStyle = .regularSquare
            copyBtn.isBordered = false
            copyBtn.title = "Copy"
            copyBtn.font = NSFont.snipsnap(.label)
            copyBtn.target = self
            copyBtn.action = #selector(copyTapped)
            addSubview(copyBtn)
            copyButton = copyBtn

            if showsSaveButton {
                let saveBtn = NSButton(frame: CGRect(x: 0, y: btnY, width: 50, height: btnSz))
                saveBtn.bezelStyle = .regularSquare
                saveBtn.isBordered = false
                saveBtn.title = "Save"
                saveBtn.font = NSFont.snipsnap(.label)
                saveBtn.target = self
                saveBtn.action = #selector(saveTapped)
                addSubview(saveBtn)
                saveButton = saveBtn
            }
        }

        layoutAccessoryControls()
        refresh()
        updateTrackingAreas()
    }

    private func layoutAccessoryControls() {
        let h = pillHeight
        let btnSz = toolButtonSize
        let btnY = (h - btnSz) / 2
        var x = toolsSectionEndX

        accessorySeparator.frame.origin.x = x
        x += 9

        let showTechniques = showsSpotlightTechniquePicker
        colorSwatchButton.isHidden = showTechniques
        for (technique, btn) in techniqueButtons {
            btn.isHidden = !showTechniques
            if showTechniques {
                btn.frame.origin = CGPoint(x: x, y: btnY)
                x += btnSz + 2
            }
            _ = technique
        }

        if !showTechniques {
            colorSwatchButton.frame.origin = CGPoint(x: x, y: btnY)
            x += btnSz + 2
        }

        if let trailingSeparator {
            x += 4
            trailingSeparator.frame.origin.x = x
            x += 9
        }

        if let copyButton {
            copyButton.frame.origin = CGPoint(x: x, y: btnY)
            x += 50
        }
        if let saveButton {
            x += 4
            saveButton.frame.origin = CGPoint(x: x, y: btnY)
            x += 50
        }

        let oldWidth = bounds.width
        let newWidth = x
        setFrameSize(NSSize(width: newWidth, height: h))
        if oldWidth > 0, oldWidth != newWidth {
            // Keep the pill centered as its accessory width changes.
            frame.origin.x += ((oldWidth - newWidth) / 2).rounded()
            if let dragBounds {
                frame.origin.x = min(max(frame.origin.x, dragBounds.minX), dragBounds.maxX - newWidth)
            }
        }
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
        colorGridMenu.hide()
        customColorPicker.hide()
        let tools = availableTools
        guard sender.tag < tools.count else { return }
        let tool = tools[sender.tag]

        if tool == .draw, tool == selectedTool, let btn = toolButtons[.draw], let win = window {
            arrowStyleMenu.hide()
            if drawStyleMenu.isVisible {
                drawStyleMenu.hide()
            } else {
                let btnRect = btn.convert(btn.bounds, to: nil)
                let screenRect = win.convertToScreen(btnRect)
                drawStyleMenu.show(
                    aboveScreenRect: screenRect,
                    selectedStyle: selectedStrokeTool,
                    accentColor: selectedColor
                )
            }
            return
        }

        if tool == .arrow, tool == selectedTool, let btn = toolButtons[.arrow], let win = window {
            drawStyleMenu.hide()
            if arrowStyleMenu.isVisible {
                arrowStyleMenu.hide()
            } else {
                let btnRect = btn.convert(btn.bounds, to: nil)
                let screenRect = win.convertToScreen(btnRect)
                arrowStyleMenu.show(
                    aboveScreenRect: screenRect,
                    selectedTipStyle: selectedArrowTipStyle,
                    selectedPathStyle: selectedArrowPathStyle,
                    accentColor: selectedColor
                )
            }
            return
        }

        drawStyleMenu.hide()
        arrowStyleMenu.hide()
        onToolSelected?(tool)
    }

    private func showTooltip(for tool: AnnotationTool, at screenRect: NSRect) {
        tooltipsPrimed = true
        tooltipPanel.show(for: tool, aboveScreenRect: screenRect)
    }

    @objc private func colorSwatchTapped() {
        drawStyleMenu.hide()
        arrowStyleMenu.hide()
        customColorPicker.hide()

        guard let win = window else { return }
        let btnRect = colorSwatchButton.convert(colorSwatchButton.bounds, to: nil)
        let screenRect = win.convertToScreen(btnRect)

        if colorGridMenu.isVisible {
            colorGridMenu.hide()
        } else {
            colorGridMenu.show(
                aboveScreenRect: screenRect,
                selectedColor: selectedColor,
                customPreviewColor: customColor
            )
        }
    }

    @objc private func techniqueTapped(_ sender: NSButton) {
        let techniques = SpotlightTechnique.allCases
        guard sender.tag < techniques.count else { return }
        let technique = techniques[sender.tag]
        selectedSpotlightTechnique = technique
        onSpotlightTechniqueSelected?(technique)
    }

    private func showCustomColorPicker() {
        guard let win = window else { return }
        let btnRect = colorSwatchButton.convert(colorSwatchButton.bounds, to: nil)
        let screenRect = win.convertToScreen(btnRect)
        let initial = customColor ?? selectedColor
        customColorPicker.show(aboveScreenRect: screenRect, initialColor: initial)
    }

    @objc private func copyTapped() {
        onCopy?()
    }

    @objc private func saveTapped() {
        onSave?()
    }

    // MARK: Refresh

    private func refresh() {
        let active = selectedColor
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        for (tool, btn) in toolButtons {
            let on = tool == selectedTool
            btn.layer?.backgroundColor = on ? active.withAlphaComponent(0.2).cgColor : .clear
            btn.contentTintColor = on ? active : .labelColor
            let symbol = tool == .draw ? selectedStrokeTool.menuSymbol : tool.sfSymbol
            btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)?
                .withSymbolConfiguration(cfg)
        }
        colorSwatchButton.color = selectedColor
        colorSwatchButton.needsDisplay = true

        for (technique, btn) in techniqueButtons {
            let on = technique == selectedSpotlightTechnique
            btn.layer?.backgroundColor = on ? active.withAlphaComponent(0.2).cgColor : .clear
            btn.contentTintColor = on ? active : .labelColor
        }

        if selectedTool != .draw {
            drawStyleMenu?.hide()
        }
        if selectedTool != .arrow {
            arrowStyleMenu?.hide()
        }
        if showsSpotlightTechniquePicker {
            colorGridMenu?.hide()
            customColorPicker?.hide()
        }
    }

    // MARK: Proximity fade

    private var isDrawingToolActive: Bool {
        selectedTool != .select
    }

    private func toolbarRectInWindow() -> CGRect {
        guard window != nil else { return .zero }
        return convert(bounds, to: nil)
    }

    private func proximityRectInWindow() -> CGRect {
        guard window != nil else { return .zero }
        return convert(bounds, to: nil).insetBy(dx: -proximityMargin, dy: -proximityMargin)
    }

    private func installMouseMonitor() {
        removeMouseMonitor()
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .leftMouseDown:
                self.pressStartedInToolbar = self.toolbarRectInWindow().contains(event.locationInWindow)
            case .leftMouseUp:
                self.pressStartedInToolbar = false
            default:
                break
            }
            self.updateProximityFade(at: event.locationInWindow)
            return event
        }
    }

    private func removeMouseMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }

    private func updateProximityFade(at locationInWindow: NSPoint) {
        guard window?.isKeyWindow == true else {
            setProximityFaded(false, passThroughMouse: false)
            return
        }
        let inProximity = proximityRectInWindow().contains(locationInWindow)
        let isDrawing = NSEvent.pressedMouseButtons & (1 << 0) != 0
        let shouldFade = isDrawingToolActive && inProximity && isDrawing && !pressStartedInToolbar
        let shouldPassThrough = shouldFade && !isRepositionDragging
        setProximityFaded(shouldFade, passThroughMouse: shouldPassThrough)
    }

    private func setProximityFaded(_ faded: Bool, passThroughMouse: Bool) {
        let targetAlpha = faded ? fadedAlpha : 1
        if faded != isProximityFaded {
            isProximityFaded = faded
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                animator().alphaValue = targetAlpha
            }
        } else if !faded && alphaValue != 1 {
            alphaValue = 1
        }
        self.passThroughMouse = passThroughMouse
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if passThroughMouse { return nil }
        return super.hitTest(point)
    }

    // MARK: Drag repositioning

    private func isDraggable(at point: NSPoint) -> Bool {
        guard bounds.contains(point) else { return false }
        guard let hit = super.hitTest(point) else { return false }
        if hit === self || hit === backgroundEffect { return true }
        if hit is NSControl { return false }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard isDraggable(at: point) else {
            super.mouseDown(with: event)
            return
        }
        dragStartMouseLocation = event.locationInWindow
        dragStartFrameOrigin = frame.origin
        isRepositionDragging = true
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        if isRepositionDragging {
            NSCursor.closedHand.set()
        }
        guard let startMouse = dragStartMouseLocation,
              let startOrigin = dragStartFrameOrigin,
              let parent = superview else {
            super.mouseDragged(with: event)
            return
        }
        let parentStart = parent.convert(startMouse, from: nil)
        let parentCurrent = parent.convert(event.locationInWindow, from: nil)
        let dx = parentCurrent.x - parentStart.x
        let dy = parentCurrent.y - parentStart.y
        var newOrigin = NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy)
        let clampRect = dragBounds ?? parent.bounds
        newOrigin.x = max(clampRect.minX, min(newOrigin.x, clampRect.maxX - frame.width))
        newOrigin.y = max(clampRect.minY, min(newOrigin.y, clampRect.maxY - frame.height))
        frame.origin = newOrigin
    }

    override func mouseUp(with event: NSEvent) {
        dragStartMouseLocation = nil
        dragStartFrameOrigin = nil
        isRepositionDragging = false
        updateProximityFade(at: event.locationInWindow)
        updateDragCursor(at: convert(event.locationInWindow, from: nil))
        super.mouseUp(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let dragCursorTrackingArea {
            removeTrackingArea(dragCursorTrackingArea)
        }
        let options: NSTrackingArea.Options = [.activeInKeyWindow, .mouseMoved, .cursorUpdate, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        dragCursorTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        updateDragCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func cursorUpdate(with event: NSEvent) {
        updateDragCursor(at: convert(event.locationInWindow, from: nil))
    }

    private func updateDragCursor(at point: NSPoint) {
        guard window?.isKeyWindow == true else {
            NSCursor.arrow.set()
            return
        }
        if isRepositionDragging {
            NSCursor.closedHand.set()
        } else if isDraggable(at: point) {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
    }
}

// MARK: - Annotation action bar

final class AnnotationActionBarView: NSView {
    var showsSaveButton = true {
        didSet {
            saveButton.isHidden = !showsSaveButton
            layoutButtons()
        }
    }

    var onSave: (() -> Void)?
    var onCopy: (() -> Void)?
    var onMore: (() -> Void)?

    private let saveButton = NSButton()
    private let copyButton = NSButton()
    private let moreButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let font = NSFont.snipsnap(.body)
        for (button, title, action) in [
            (saveButton, "Save", #selector(saveTapped)),
            (copyButton, "Copy", #selector(copyTapped)),
            (moreButton, "More...", #selector(moreTapped)),
        ] as [(NSButton, String, Selector)] {
            button.title = title
            button.bezelStyle = .inline
            button.isBordered = false
            button.font = font
            button.target = self
            button.action = action
            button.sizeToFit()
            addSubview(button)
        }
        layoutButtons()
    }

    private func layoutButtons() {
        let gap: CGFloat = 12
        let barH: CGFloat = bounds.height > 0 ? bounds.height : 28

        var x: CGFloat = 0
        for button in [saveButton, copyButton, moreButton] {
            if button === saveButton && !showsSaveButton {
                button.isHidden = true
                continue
            }
            button.isHidden = false
            button.sizeToFit()
            let size = button.fittingSize
            let height = max(size.height, 22)
            let y = (barH - height) / 2
            button.frame = NSRect(x: x, y: y, width: max(size.width, 40), height: height)
            x += button.frame.width + gap
        }
        if x > 0 { x -= gap }

        frame.size = NSSize(width: x, height: barH)
    }

    override func layout() {
        super.layout()
        layoutButtons()
    }

    override func resetCursorRects() {
        discardCursorRects()
        for button in [saveButton, copyButton, moreButton] where !button.isHidden {
            addCursorRect(button.frame, cursor: .pointingHand)
        }
    }

    @objc private func saveTapped() { onSave?() }
    @objc private func copyTapped() { onCopy?() }
    @objc private func moreTapped() { onMore?() }
}

// MARK: - AnnotationWindow

final class AnnotationWindow: NSWindow {

    private static var current: AnnotationWindow?

    private var screenshot: NSImage
    private var viewBackground: RecordingBackgroundStyle = .none
    private var sideBySideSettings = SideBySideSettings()
    private var sideBySideComposition: SideBySideComposition?
    private let canvas: AnnotationCanvasView
    private var backgroundImageView: NSImageView?
    private var screenshotImageView: NSImageView?
    private var leftImageView: NSImageView?
    private var rightImageView: NSImageView?
    private var pill: ToolbarPillView!
    private var shipItPanel: ShipItPanelView!
    private var actionBar: AnnotationActionBarView!
    private var undoRedoKeyMonitor: Any?
    private var fileName: String
    private var titleControl: AnnotationTitlebarTitleControl!
    private var fileSettingsPanel: AnnotationFileSettingsPanel!

    private let toolbarBottomInset: CGFloat = 16
    private let titlebarColor: NSColor
    private var contentContainer: NSView?
    private var stageContentFrame: NSRect = .zero
    private var savedAnnotationContentFrame: NSRect = .zero

    // MARK: Entry Point

    static func show(image: NSImage, fileName: String? = nil, captureID: UUID? = nil) {
        DispatchQueue.main.async {
            current = AnnotationWindow(image: image, fileName: fileName, captureID: captureID)
            current?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: Init

    private let captureID: UUID?

    private init(image: NSImage, fileName: String?, captureID: UUID?) {
        self.captureID = captureID
        self.screenshot = image
        self.titlebarColor = image.annotationTitlebarColor()
        let displayName = fileName ?? CaptureNaming.baseName()
        self.fileName = displayName
        let imageSize = AnnotationWindow.fittedSize(for: image)
        self.canvas = AnnotationCanvasView(frame: NSRect(origin: .zero, size: imageSize))

        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let styleMask: NSWindow.StyleMask = [.titled, .closable]
        let frameRect = NSWindow.frameRect(
            forContentRect: NSRect(origin: .zero, size: imageSize),
            styleMask: styleMask
        )
        let centeredFrame = NSRect(
            x: screenRect.midX - frameRect.width / 2,
            y: screenRect.midY - frameRect.height / 2,
            width: frameRect.width,
            height: frameRect.height
        )
        let contentRect = NSWindow.contentRect(forFrameRect: centeredFrame, styleMask: styleMask)

        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false

        AnnotationTitlebarStyle.apply(
            to: self,
            title: displayName,
            backgroundColor: titlebarColor,
            laysContentBelowTitlebar: true
        )

        titleControl = AnnotationTitlebarTitleControl(title: displayName)
        titleControl.target = self
        titleControl.action = #selector(titleControlTapped)
        AnnotationTitlebarStyle.installCenteredTitle(titleControl, in: self)

        fileSettingsPanel = AnnotationFileSettingsPanel(
            onNameCommitted: { [weak self] newName in
                self?.applyFileName(newName)
            },
            onSaveLocationChanged: { [weak self] in
                self?.fileSettingsPanel.refreshSaveLocation()
            }
        )

        actionBar = AnnotationActionBarView(frame: NSRect(x: 0, y: 0, width: 180, height: 28))
        actionBar.showsSaveButton = captureID != nil
        AnnotationTitlebarStyle.installTrailingAccessory(actionBar, in: self)

        buildLayout()
        wire()
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
        super.setFrame(frameRect, display: displayFlag)
        AnnotationTitlebarStyle.layoutCenteredTitle(in: self)
        if let contentContainer {
            AnnotationTitlebarStyle.layoutContentContainer(
                contentContainer,
                in: self,
                laysContentBelowTitlebar: true
            )
            layoutShipItPanel(in: contentContainer)
        }
    }

    // MARK: Layout

    private static func fittedSize(for image: NSImage) -> NSSize {
        AnnotationViewBackground.fittedStageSize(image.size)
    }

    private func buildLayout() {
        pill = ToolbarPillView(
            frame: CGRect(x: 0, y: 0, width: 100, height: 40),
            showsCopyButton: false,
            showsSaveButton: false,
            availableTools: AnnotationTool.screenshotTools
        )

        shipItPanel = ShipItPanelView(frame: .zero)
        shipItPanel.showsSideBySide = true
        shipItPanel.selectedBackground = viewBackground
        shipItPanel.sideBySideSettings = sideBySideSettings
        shipItPanel.onBackgroundChanged = { [weak self] style in
            self?.applyViewBackground(style)
        }
        shipItPanel.onSideBySideChanged = { [weak self] settings in
            self?.applySideBySideSettings(settings)
        }
        shipItPanel.onPresentationChanged = { [weak self] in
            guard let self, let container = contentContainer else { return }
            layoutShipItPanel(in: container)
        }
        refreshShipItSideBySideChoices()

        applyStageLayout()
    }

    private func applyStageLayout() {
        guard let container = contentContainer ?? setupContentContainer() else { return }

        let oldStageSize = canvas.frame.size
        let oldContentFrame = savedAnnotationContentFrame.width > 0 && savedAnnotationContentFrame.height > 0
            ? savedAnnotationContentFrame
            : NSRect(origin: .zero, size: oldStageSize)

        let stageSize: NSSize
        let newContentFrame: NSRect

        if sideBySideSettings.isEnabled,
           let previous = sideBySideSettings.previousImage {
            let composition = SideBySideLayout.compose(
                current: screenshot,
                previous: previous,
                order: sideBySideSettings.order,
                background: viewBackground
            )
            sideBySideComposition = composition
            stageSize = composition.stageSize
            newContentFrame = NSRect(origin: .zero, size: stageSize)
            layoutSideBySideImages(in: container, composition: composition)
        } else {
            sideBySideComposition = nil
            let layout = AnnotationViewBackground.stageLayout(
                for: screenshot.size,
                background: viewBackground
            )
            stageSize = layout.stage
            newContentFrame = viewBackground == .none
                ? NSRect(origin: .zero, size: stageSize)
                : layout.contentFrame
            stageContentFrame = layout.contentFrame
            layoutSingleImage(in: container, layout: layout)
        }

        if oldStageSize.width > 0, oldStageSize.height > 0,
           !canvas.annotations.isEmpty,
           oldContentFrame != newContentFrame {
            canvas.remapAnnotations(fromContent: oldContentFrame, toContent: newContentFrame)
        }

        setContentSize(stageSize)
        container.setFrameSize(stageSize)
        container.superview?.setFrameSize(stageSize)

        canvas.frame = NSRect(origin: .zero, size: stageSize)
        savedAnnotationContentFrame = newContentFrame
        updateCanvasStageBackground()
        pill.dragBounds = NSRect(origin: .zero, size: stageSize)
        pill.frame.origin = ToolbarPillView.defaultOrigin(
            pillSize: pill.frame.size,
            in: stageSize,
            bottomInset: toolbarBottomInset
        )
        bringToolbarToFront(in: container)
        layoutShipItPanel(in: container)

        if let contentContainer {
            AnnotationTitlebarStyle.layoutContentContainer(
                contentContainer,
                in: self,
                laysContentBelowTitlebar: true
            )
        }
    }

    private func setupContentContainer() -> NSView? {
        let layout = AnnotationViewBackground.stageLayout(
            for: screenshot.size,
            background: viewBackground
        )
        stageContentFrame = layout.contentFrame

        let shell = NSView(frame: NSRect(origin: .zero, size: layout.stage))
        shell.wantsLayer = true
        shell.layer?.backgroundColor = titlebarColor.cgColor
        shell.autoresizingMask = [.width, .height]

        let container = NSView(frame: NSRect(origin: .zero, size: layout.stage))
        shell.addSubview(container)

        container.addSubview(canvas)
        pill.frame.origin = ToolbarPillView.defaultOrigin(
            pillSize: pill.frame.size,
            in: layout.stage,
            bottomInset: toolbarBottomInset
        )
        container.addSubview(pill, positioned: .above, relativeTo: canvas)
        container.addSubview(shipItPanel, positioned: .above, relativeTo: canvas)
        layoutShipItPanel(in: container)

        contentView = shell
        contentContainer = container
        makeFirstResponder(canvas)
        return container
    }

    private func bringToolbarToFront(in container: NSView) {
        if shipItPanel.isPresented {
            container.addSubview(shipItPanel, positioned: .above, relativeTo: nil)
        }
        container.addSubview(pill, positioned: .above, relativeTo: nil)
    }

    private func layoutShipItPanel(in container: NSView) {
        shipItPanel.layoutOverlay(in: container.bounds)
    }

    private func refreshShipItSideBySideChoices() {
        shipItPanel.sideBySideChoices = CaptureHistory.shared.screenshotChoices(excluding: captureID).map {
            ShipItSideBySideChoice(
                id: $0.entry.id,
                thumbnail: $0.image,
                title: $0.entry.displayName
            )
        }
        if shipItPanel.sideBySideSettings.previousImage == nil,
           let previous = CaptureHistory.shared.previousScreenshot(excluding: captureID) {
            var settings = shipItPanel.sideBySideSettings
            settings.previousCaptureID = previous.entry.id
            settings.previousImage = previous.image
            shipItPanel.sideBySideSettings = settings
            sideBySideSettings = settings
        }
    }

    private func layoutSingleImage(in container: NSView, layout: (stage: NSSize, contentFrame: NSRect)) {
        leftImageView?.removeFromSuperview()
        rightImageView?.removeFromSuperview()
        leftImageView = nil
        rightImageView = nil

        if viewBackground != .none {
            if let bgView = backgroundImageView {
                bgView.frame = NSRect(origin: .zero, size: layout.stage)
                bgView.image = RecordingBackgroundRenderer.backgroundPreviewImage(for: viewBackground)
                container.addSubview(bgView, positioned: .below, relativeTo: canvas)
            } else {
                let bgView = NSImageView(frame: NSRect(origin: .zero, size: layout.stage))
                bgView.imageScaling = .scaleAxesIndependently
                bgView.imageAlignment = .alignCenter
                bgView.wantsLayer = true
                bgView.image = RecordingBackgroundRenderer.backgroundPreviewImage(for: viewBackground)
                container.addSubview(bgView, positioned: .below, relativeTo: canvas)
                backgroundImageView = bgView
            }
        } else {
            backgroundImageView?.removeFromSuperview()
            backgroundImageView = nil
        }

        if let imageView = screenshotImageView {
            imageView.frame = layout.contentFrame
            imageView.image = screenshot
            container.addSubview(imageView, positioned: .below, relativeTo: canvas)
        } else {
            let imageView = NSImageView(frame: layout.contentFrame)
            imageView.image = screenshot
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.imageAlignment = .alignCenter
            imageView.wantsLayer = true
            container.addSubview(imageView, positioned: .below, relativeTo: canvas)
            screenshotImageView = imageView
        }
    }

    private func layoutSideBySideImages(in container: NSView, composition: SideBySideComposition) {
        screenshotImageView?.removeFromSuperview()
        screenshotImageView = nil

        if viewBackground != .none {
            if let bgView = backgroundImageView {
                bgView.frame = NSRect(origin: .zero, size: composition.stageSize)
                bgView.image = SideBySideLayout.renderStage(
                    composition,
                    background: viewBackground
                )
                container.addSubview(bgView, positioned: .below, relativeTo: canvas)
            } else {
                let bgView = NSImageView(frame: NSRect(origin: .zero, size: composition.stageSize))
                bgView.imageScaling = .scaleAxesIndependently
                bgView.imageAlignment = .alignCenter
                bgView.wantsLayer = true
                bgView.image = SideBySideLayout.renderStage(
                    composition,
                    background: viewBackground
                )
                container.addSubview(bgView, positioned: .below, relativeTo: canvas)
                backgroundImageView = bgView
            }
            leftImageView?.isHidden = true
            rightImageView?.isHidden = true
            return
        }

        backgroundImageView?.removeFromSuperview()
        backgroundImageView = nil

        if let leftView = leftImageView {
            leftView.frame = composition.leftFrame
            leftView.image = composition.leftImage
            leftView.isHidden = false
            container.addSubview(leftView, positioned: .below, relativeTo: canvas)
        } else {
            let leftView = NSImageView(frame: composition.leftFrame)
            leftView.image = composition.leftImage
            leftView.imageScaling = .scaleProportionallyUpOrDown
            leftView.imageAlignment = .alignCenter
            leftView.wantsLayer = true
            container.addSubview(leftView, positioned: .below, relativeTo: canvas)
            leftImageView = leftView
        }

        if let rightView = rightImageView {
            rightView.frame = composition.rightFrame
            rightView.image = composition.rightImage
            rightView.isHidden = false
            container.addSubview(rightView, positioned: .below, relativeTo: canvas)
        } else {
            let rightView = NSImageView(frame: composition.rightFrame)
            rightView.image = composition.rightImage
            rightView.imageScaling = .scaleProportionallyUpOrDown
            rightView.imageAlignment = .alignCenter
            rightView.wantsLayer = true
            container.addSubview(rightView, positioned: .below, relativeTo: canvas)
            rightImageView = rightView
        }
    }

    private func applyViewBackground(_ style: RecordingBackgroundStyle) {
        guard style != viewBackground else { return }
        viewBackground = style
        shipItPanel.selectedBackground = style
        applyStageLayout()
    }

    private func applySideBySideSettings(_ settings: SideBySideSettings) {
        let wasEnabled = sideBySideSettings.isEnabled
        sideBySideSettings = settings
        shipItPanel.sideBySideSettings = settings

        if settings.isEnabled, settings.previousImage == nil {
            sideBySideSettings.isEnabled = false
            shipItPanel.sideBySideSettings.isEnabled = false
            return
        }

        if wasEnabled != settings.isEnabled || settings.isEnabled {
            canvas.annotations = []
            canvas.currentAnnotation = nil
            canvas.selectedIndex = nil
            canvas.needsDisplay = true
            updateScreenshotCropMask(nil)
        }

        applyStageLayout()
    }

    // MARK: Wire

    private func updateCanvasStageBackground() {
        let stageImage: NSImage
        if let composition = sideBySideComposition {
            stageImage = SideBySideLayout.renderStage(composition, background: viewBackground)
        } else {
            let layout = AnnotationViewBackground.stageLayout(
                for: screenshot.size,
                background: viewBackground
            )
            stageImage = AnnotationViewBackground.renderStage(
                screenshot: screenshot,
                layout: layout,
                background: viewBackground
            )
        }
        canvas.stageBackgroundImage = stageImage
        canvas.needsDisplay = true
    }

    private func updateSpotlightTechniquePickerVisibility() {
        let spotlightSelected: Bool = {
            guard let idx = canvas.selectedIndex,
                  canvas.annotations.indices.contains(idx),
                  case .spotlight = canvas.annotations[idx].content else { return false }
            return true
        }()
        pill.showsSpotlightTechniquePicker = canvas.selectedTool == .spotlight || spotlightSelected
        if spotlightSelected,
           let idx = canvas.selectedIndex,
           case let .spotlight(_, technique) = canvas.annotations[idx].content {
            pill.selectedSpotlightTechnique = technique
            canvas.selectedSpotlightTechnique = technique
        }
    }

    private func wire() {
        canvas.allowedTools = Set(AnnotationTool.screenshotTools)
        pill.selectedTool = .draw
        pill.selectedColor = NSColor.annotationPalette[0]
        pill.selectedSpotlightTechnique = canvas.selectedSpotlightTechnique
        updateCanvasStageBackground()

        canvas.onToolChanged = { [weak self] tool in
            guard let self else { return }
            self.pill.selectedTool = tool
            self.updateSpotlightTechniquePickerVisibility()
        }

        canvas.onEscapeAction = { [weak self] in
            self?.flattenCopyAndClose()
        }

        canvas.onCommittedCropPreviewChanged = { [weak self] cropRect in
            self?.updateScreenshotCropMask(cropRect)
        }

        canvas.onSelectionChanged = { [weak self] _ in
            self?.updateSpotlightTechniquePickerVisibility()
        }

        pill.onToolSelected = { [weak self] tool in
            guard let self else { return }
            canvas.selectedTool = tool
            pill.selectedTool = tool
            updateSpotlightTechniquePickerVisibility()
        }

        pill.onColorSelected = { [weak self] color in
            guard let self else { return }
            canvas.selectedColor = color
            pill.selectedColor = color
            canvas.updateEmojiPickerColor(color)
        }

        pill.onStrokeToolSelected = { [weak self] style in
            guard let self else { return }
            canvas.selectedStrokeTool = style
            pill.selectedStrokeTool = style
        }

        pill.onArrowTipStyleSelected = { [weak self] style in
            guard let self else { return }
            canvas.selectedArrowTipStyle = style
            pill.selectedArrowTipStyle = style
        }

        pill.onArrowPathStyleSelected = { [weak self] style in
            guard let self else { return }
            canvas.selectedArrowPathStyle = style
            pill.selectedArrowPathStyle = style
        }

        pill.onSpotlightTechniqueSelected = { [weak self] technique in
            guard let self else { return }
            canvas.applySpotlightTechnique(technique)
            pill.selectedSpotlightTechnique = technique
        }

        actionBar.onCopy = { [weak self] in
            guard let self, self.flattenAndCopy() else { return }
            ToastWindow.show(message: "Copied to clipboard")
        }

        actionBar.onSave = { [weak self] in
            guard let self, self.flattenAndSave() else { return }
            ToastWindow.show(message: "Saved to PNG")
        }

        actionBar.onMore = { [weak self] in
            guard let self, let container = contentContainer else { return }
            shipItPanel.isPresented.toggle()
            layoutShipItPanel(in: container)
            if shipItPanel.isPresented {
                container.addSubview(shipItPanel, positioned: .above, relativeTo: nil)
            }
        }

        undoRedoKeyMonitor = canvas.installUndoRedoKeyMonitor(for: self)
    }

    private func updateScreenshotCropMask(_ cropRect: CGRect?) {
        let imageView: NSImageView?
        if sideBySideComposition != nil {
            if viewBackground != .none {
                imageView = backgroundImageView
            } else {
                imageView = sideBySideSettings.order == .currentLeft ? leftImageView : rightImageView
            }
        } else {
            imageView = screenshotImageView
        }

        guard let imageView else { return }
        if let cropRect, cropRect.width > 1, cropRect.height > 1 {
            let mask = CAShapeLayer()
            mask.path = CGPath(rect: cropRect, transform: nil)
            imageView.layer?.mask = mask
        } else {
            imageView.layer?.mask = nil
        }
    }

    override func close() {
        fileSettingsPanel.hide()
        if let undoRedoKeyMonitor {
            NSEvent.removeMonitor(undoRedoKeyMonitor)
            self.undoRedoKeyMonitor = nil
        }
        super.close()
    }

    // MARK: Title / file settings

    @objc private func titleControlTapped() {
        if fileSettingsPanel.isVisible {
            fileSettingsPanel.hide()
            return
        }

        let controlRect = titleControl.convert(titleControl.bounds, to: nil)
        let screenRect = convertToScreen(controlRect)
        fileSettingsPanel.show(
            from: self,
            anchorScreenRect: screenRect,
            name: fileName,
            saveLocation: AppSettings.destinationFolderDisplayPath
        )
    }

    private func applyFileName(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != fileName else { return }

        if let captureID {
            guard CaptureHistory.shared.renameCapture(id: captureID, to: trimmed) else {
                ToastWindow.show(message: "Couldn’t rename file")
                return
            }
        }

        fileName = trimmed
        AnnotationTitlebarStyle.updateCenteredTitle(trimmed, in: self)
        titleControl.setTitle(trimmed)
        AnnotationTitlebarStyle.layoutCenteredTitle(in: self)
    }

    // MARK: Actions

    @discardableResult
    private func flattenAndCopy() -> Bool {
        let img = flattenedOutputImage()
        guard let tiff = img.tiffRepresentation else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.setData(tiff, forType: .tiff)
    }

    @discardableResult
    private func flattenAndSave() -> Bool {
        let img = flattenedOutputImage()
        guard let captureID,
              CaptureHistory.shared.replaceScreenshot(id: captureID, with: img) else {
            return false
        }

        screenshot = img
        viewBackground = .none
        sideBySideSettings = SideBySideSettings()
        shipItPanel.selectedBackground = .none
        shipItPanel.sideBySideSettings = SideBySideSettings()
        shipItPanel.dismiss()
        screenshotImageView?.image = img
        canvas.annotations = []
        canvas.currentAnnotation = nil
        canvas.selectedIndex = nil
        canvas.needsDisplay = true
        updateScreenshotCropMask(nil)
        applyStageLayout()
        return true
    }

    private func flattenedOutputImage() -> NSImage {
        if let composition = sideBySideComposition {
            let bg = SideBySideLayout.renderStage(composition, background: viewBackground)
            return canvas.flattenedImage(background: bg)
        }

        let layout = AnnotationViewBackground.stageLayout(
            for: screenshot.size,
            background: viewBackground
        )
        let stageImage = AnnotationViewBackground.renderStage(
            screenshot: screenshot,
            layout: layout,
            background: viewBackground
        )
        return canvas.flattenedImage(background: stageImage)
    }

    private func flattenCopyAndClose() {
        flattenAndCopy()
        close()
    }
}

// MARK: - Annotation titlebar file settings

final class AnnotationTitlebarTitleControl: NSButton {
    private let maxTitleWidth: CGFloat = 280

    init(title: String) {
        super.init(frame: .zero)
        bezelStyle = .inline
        isBordered = false
        font = NSFont.snipsnap(.body)
        lineBreakMode = .byTruncatingTail
        cell?.truncatesLastVisibleLine = true
        setTitle(title)
        toolTip = "Rename and file settings"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    func setTitle(_ title: String, maxWidth: CGFloat? = nil) {
        self.title = title
        sizeToFit()
        let fitted = fittingSize
        let widthCap = max(40, min(maxTitleWidth, maxWidth ?? maxTitleWidth))
        frame.size = NSSize(
            width: min(max(fitted.width, 40), widthCap),
            height: max(fitted.height, 22)
        )
    }
}

final class AnnotationFileSettingsPanel: NSObject, NSTextFieldDelegate {
    private let panel: NSPanel
    private let nameField: NSTextField
    private let saveLocationLabel: NSTextField
    private let formatLabel: NSTextField
    private let onNameCommitted: (String) -> Void
    private let onSaveLocationChanged: () -> Void
    private var clickOutsideMonitor: Any?
    private var anchorScreenRect: NSRect = .zero
    private weak var hostWindow: NSWindow?

    init(
        onNameCommitted: @escaping (String) -> Void,
        onSaveLocationChanged: @escaping () -> Void
    ) {
        self.onNameCommitted = onNameCommitted
        self.onSaveLocationChanged = onSaveLocationChanged

        let panelWidth: CGFloat = 280
        let panelHeight: CGFloat = 168
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.hidesOnDeactivate = true

        nameField = NSTextField(string: "")
        saveLocationLabel = NSTextField(labelWithString: "")
        formatLabel = NSTextField(labelWithString: "PNG")

        super.init()

        let side: CGFloat = 14
        let rowH: CGFloat = 22
        let fieldH: CGFloat = 24
        var y = panelHeight - side - 14

        let container = NSView(frame: panel.contentView!.bounds)
        container.autoresizingMask = [.width, .height]

        let vfx = NSVisualEffectView(frame: container.bounds)
        vfx.autoresizingMask = [.width, .height]
        vfx.material = .popover
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = DesignTokens.Radius.lg
        vfx.layer?.masksToBounds = true
        container.addSubview(vfx)

        let nameHeader = sectionLabel("Name", x: side, y: y, width: panelWidth - side * 2)
        container.addSubview(nameHeader)
        y -= rowH + 4

        nameField.frame = NSRect(x: side, y: y - fieldH + 4, width: panelWidth - side * 2, height: fieldH)
        nameField.font = NSFont.snipsnap(.body)
        nameField.isBezeled = true
        nameField.bezelStyle = .roundedBezel
        nameField.delegate = self
        container.addSubview(nameField)
        y -= fieldH + 14

        let saveHeader = sectionLabel("Save to", x: side, y: y, width: 60)
        container.addSubview(saveHeader)

        saveLocationLabel.font = NSFont.snipsnap(.label)
        saveLocationLabel.textColor = DesignTokens.Color.textSecondary.ns
        saveLocationLabel.lineBreakMode = .byTruncatingMiddle
        saveLocationLabel.frame = NSRect(x: side + 58, y: y, width: panelWidth - side * 2 - 58 - 72, height: 16)
        container.addSubview(saveLocationLabel)

        let changeButton = NSButton(title: "Change…", target: self, action: #selector(changeSaveLocation))
        changeButton.bezelStyle = .rounded
        changeButton.controlSize = .small
        changeButton.font = NSFont.snipsnap(.label)
        changeButton.frame = NSRect(x: panelWidth - side - 68, y: y - 2, width: 68, height: 22)
        container.addSubview(changeButton)
        y -= rowH + 12

        let formatHeader = sectionLabel("Format", x: side, y: y, width: 60)
        container.addSubview(formatHeader)

        formatLabel.font = NSFont.snipsnap(.label)
        formatLabel.textColor = DesignTokens.Color.textSecondary.ns
        formatLabel.frame = NSRect(x: side + 58, y: y, width: panelWidth - side * 2 - 58, height: 16)
        container.addSubview(formatLabel)

        panel.contentView = container
    }

    private func sectionLabel(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.snipsnap(.caption)
        label.textColor = DesignTokens.Color.textSecondary.ns
        label.frame = NSRect(x: x, y: y, width: width, height: 14)
        return label
    }

    func show(
        from window: NSWindow,
        anchorScreenRect: NSRect,
        name: String,
        saveLocation: String
    ) {
        hide()
        hostWindow = window
        self.anchorScreenRect = anchorScreenRect
        nameField.stringValue = name
        saveLocationLabel.stringValue = saveLocation

        let panelW = panel.frame.width
        let panelX = (anchorScreenRect.midX - panelW / 2).rounded()
        let panelY = anchorScreenRect.minY - panel.frame.height - 6
        panel.setFrameOrigin(NSPoint(x: panelX, y: panelY))
        panel.orderFront(nil)
        window.makeFirstResponder(nameField)
        nameField.currentEditor()?.selectAll(nil)

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
        if panel.isVisible {
            commitNameIfNeeded()
        }
        if let clickOutsideMonitor {
            NSEvent.removeMonitor(clickOutsideMonitor)
            self.clickOutsideMonitor = nil
        }
        panel.orderOut(nil)
        hostWindow = nil
    }

    var isVisible: Bool { panel.isVisible }

    func refreshSaveLocation() {
        saveLocationLabel.stringValue = AppSettings.destinationFolderDisplayPath
    }

    private func commitNameIfNeeded() {
        let trimmed = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onNameCommitted(trimmed)
    }

    @objc private func changeSaveLocation() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = "Choose"
        openPanel.message = "Choose where Snipsnap saves recordings and exports."
        openPanel.directoryURL = AppSettings.destinationFolderURL

        openPanel.beginSheetModal(for: hostWindow ?? panel) { [weak self] response in
            guard response == .OK, let url = openPanel.url else { return }
            AppSettings.destinationFolderURL = url
            self?.refreshSaveLocation()
            self?.onSaveLocationChanged()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitNameIfNeeded()
            hide()
            return true
        }
        return false
    }
}

// MARK: - Annotation titlebar

enum AnnotationTitlebarStyle {
    private static weak var centeredTitleControl: NSView?

    static func apply(
        to window: NSWindow,
        title: String,
        backgroundColor color: NSColor,
        laysContentBelowTitlebar: Bool = false,
        usesSystemAppearance: Bool = false
    ) {
        window.title = title
        if laysContentBelowTitlebar {
            window.styleMask.remove(.fullSizeContentView)
            window.titlebarAppearsTransparent = false
        } else {
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
        }
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        window.backgroundColor = color
        if usesSystemAppearance {
            window.appearance = nil
        } else {
            window.appearance = NSAppearance(named: color.isLightAnnotationBackground ? .aqua : .darkAqua)
        }
        window.isMovableByWindowBackground = !laysContentBelowTitlebar
        hideNonCloseWindowButtons(on: window)
        DispatchQueue.main.async {
            layoutCloseButton(in: window)
        }
    }

    static func installCenteredTitle(_ control: NSView, in window: NSWindow) {
        centeredTitleControl = control
        window.titleVisibility = .hidden
        DispatchQueue.main.async {
            layoutCenteredTitle(in: window)
        }
    }

    static func updateCenteredTitle(_ title: String, in window: NSWindow) {
        if let control = centeredTitleControl as? AnnotationTitlebarTitleControl {
            control.setTitle(title)
            layoutCenteredTitle(in: window)
        } else {
            window.title = title
        }
    }

    static func installTrailingAccessory(_ view: NSView, in window: NSWindow) {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing
        accessory.view = view
        window.addTitlebarAccessoryViewController(accessory)
    }

    private static let closeButtonLeftPadding = DesignTokens.Spacing.md
    private static let closeButtonTopPadding: CGFloat = 10

    private static func hideNonCloseWindowButtons(on window: NSWindow) {
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }

    static func layoutCloseButton(in window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton),
              let container = closeButton.superview else { return }

        let size = closeButton.frame.size
        let y = container.isFlipped
            ? closeButtonTopPadding
            : container.bounds.height - size.height - closeButtonTopPadding
        closeButton.setFrameOrigin(NSPoint(x: closeButtonLeftPadding, y: y))
        layoutCenteredTitle(in: window)
    }

    static func layoutCenteredTitle(in window: NSWindow) {
        guard let control = centeredTitleControl,
              let closeButton = window.standardWindowButton(.closeButton),
              let titlebar = closeButton.superview else { return }

        if control.superview !== titlebar {
            titlebar.addSubview(control)
        }

        let gap = DesignTokens.Spacing.sm
        let leftLimit = closeButton.frame.maxX + gap
        var rightLimit = titlebar.bounds.width - gap
        for accessory in window.titlebarAccessoryViewControllers {
            let accessoryView = accessory.view
            guard accessoryView.superview != nil else { continue }
            let frameInTitlebar = accessoryView.convert(accessoryView.bounds, to: titlebar)
            rightLimit = min(rightLimit, frameInTitlebar.minX - gap)
        }

        let availableWidth = max(40, rightLimit - leftLimit)
        if let titleControl = control as? AnnotationTitlebarTitleControl {
            titleControl.setTitle(titleControl.title, maxWidth: availableWidth)
        } else {
            control.frame.size.width = min(control.frame.width, availableWidth)
        }

        let barWidth = titlebar.bounds.width
        let controlWidth = control.frame.width
        var x = ((barWidth - controlWidth) / 2).rounded(.down)
        // Prefer centered; when the trailing Save/Copy/More bar is too close, pin left of it.
        if x + controlWidth > rightLimit {
            x = rightLimit - controlWidth
        }
        if x < leftLimit {
            x = leftLimit
        }

        let y = titlebar.isFlipped
            ? closeButtonTopPadding + (closeButton.frame.height - control.frame.height) / 2
            : titlebar.bounds.height - closeButtonTopPadding - closeButton.frame.height
            + (closeButton.frame.height - control.frame.height) / 2
        control.setFrameOrigin(NSPoint(x: x, y: y))
        control.autoresizingMask = [.minYMargin, .maxYMargin]
    }

    /// Positions annotation content in the window. When `laysContentBelowTitlebar` is true,
    /// content fills the area below the standard titlebar instead of underlapping it.
    static func layoutContentContainer(
        _ container: NSView,
        in window: NSWindow,
        laysContentBelowTitlebar: Bool = false
    ) {
        guard let contentView = window.contentView else { return }
        if laysContentBelowTitlebar {
            container.frame = contentView.bounds
            container.autoresizingMask = [.width, .height]
        } else {
            let safeRect = contentView.convert(window.contentLayoutRect, from: nil)
            container.frame = safeRect
            container.autoresizingMask = [.width, .maxYMargin]
        }
        layoutCloseButton(in: window)
    }
}

private extension NSColor {
    var isLightAnnotationBackground: Bool {
        guard let rgb = usingColorSpace(.sRGB) else { return true }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.55
    }
}

private extension NSImage {
    func annotationTitlebarColor() -> NSColor {
        guard let tiff = tiffRepresentation,
              let ciImage = CIImage(data: tiff) else {
            return .windowBackgroundColor
        }

        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return .windowBackgroundColor }

        let stripHeight = max(1, extent.height * 0.03)
        let cropRect = CGRect(
            x: extent.minX + extent.width * 0.1,
            y: extent.maxY - stripHeight,
            width: extent.width * 0.8,
            height: stripHeight
        )
        let cropped = ciImage.cropped(to: cropRect)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: cropped,
            kCIInputExtentKey: CIVector(cgRect: cropped.extent),
        ]),
              let output = filter.outputImage else {
            return .windowBackgroundColor
        }

        var rgba = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            output,
            toBitmap: &rgba,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        return NSColor(
            red: CGFloat(rgba[0]) / 255,
            green: CGFloat(rgba[1]) / 255,
            blue: CGFloat(rgba[2]) / 255,
            alpha: 1
        )
    }
}
