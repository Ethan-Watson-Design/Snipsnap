//
//  DesignTokens.swift
//  Snipsnap
//
//  Single source of truth for color, spacing, radius, type, and elevation.
//  Floating panels (Capture Bar, toast, annotation chrome) lean Figma: small
//  radii, soft directional shadows, a single accent used sparingly.
//  Content surfaces (Settings, Capture Library) lean Notion: neutral grays,
//  generous whitespace, restrained type, accent only on the primary action.
//

import AppKit
import CoreImage
import CoreText
import SwiftUI

// MARK: - Dual-platform tokens

/// A color available as both `NSColor` (AppKit) and `Color` (SwiftUI).
struct TokenColor {
    let ns: NSColor

    var swiftUI: Color { Color(nsColor: ns) }
    var cg: CGColor { ns.cgColor }
}

/// A multi-stop gradient available as `NSColor`, SwiftUI `Color`, and `CIColor`.
struct TokenGradient {
    let ns: [NSColor]

    var swiftUI: [Color] { ns.map { Color(nsColor: $0) } }
    var ci: [CIColor] { ns.map { CIColor(color: $0)! } }
}

/// A type-scale step available as both `NSFont` and SwiftUI `Font`.
/// Sizes are in Apple points (pt) — AppKit/SwiftUI’s logical unit, not CSS px.
struct TokenFont {
    let size: CGFloat
    let weight: NSFont.Weight

    var ns: NSFont { DesignTokens.Typography.font(size: size, weight: weight) }

    var swiftUI: Font {
        Font.custom(DesignTokens.Typography.postScriptName(for: weight), size: size)
    }

    /// Display name for kitchen sink / debugging (e.g. "Geist Medium").
    var typefaceLabel: String {
        "Geist \(DesignTokens.Typography.weightName(weight))"
    }
}

// MARK: - DesignTokens

enum DesignTokens {

    // MARK: Radius

    /// Three radii only — map every `cornerRadius` to one of these.
    enum Radius {
        /// Small chips, handles, swatches (replaces scattered 4 / 5 / 6).
        static let sm: CGFloat = 4
        /// Buttons, hover states, inline controls.
        static let md: CGFloat = 8
        /// Floating panel containers (toast, Capture Bar, Ship It, annotation panels).
        static let lg: CGFloat = 12
    }

    // MARK: Spacing

    /// 4pt grid.
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: Color

    enum Color {
        // Semantic — system colors, dark-mode-safe by default.

        static var background: TokenColor { TokenColor(ns: .windowBackgroundColor) }
        static var surface: TokenColor { TokenColor(ns: .controlColor) }
        static var surfaceElevated: TokenColor { TokenColor(ns: .controlBackgroundColor) }
        static var border: TokenColor { TokenColor(ns: .separatorColor) }
        static var textPrimary: TokenColor { TokenColor(ns: .labelColor) }
        static var textSecondary: TokenColor { TokenColor(ns: .secondaryLabelColor) }
        static var textTertiary: TokenColor { TokenColor(ns: .tertiaryLabelColor) }

        /// Hover / active fills on dark HUD chrome (Capture Bar mode buttons).
        static let panelHoverFill = TokenColor(ns: NSColor.white.withAlphaComponent(0.10))
        static let panelActiveFill = TokenColor(ns: NSColor.white.withAlphaComponent(0.14))

        /// Selected list / chip fill. Light L=93, dark L=22.
        static let listSelectionFill = dynamicNeutralSurface(light: 0.93, dark: 0.22)

        /// Neutral surface at HSL lightness (achromatic). AppKit HSB brightness matches HSL L when S=0.
        static func neutralSurface(lightness: CGFloat) -> TokenColor {
            TokenColor(ns: NSColor(calibratedHue: 0, saturation: 0, brightness: lightness, alpha: 1))
        }

        /// Appearance-aware neutral surface (content windows follow system light/dark).
        static func dynamicNeutralSurface(light: CGFloat, dark: CGFloat) -> TokenColor {
            TokenColor(ns: NSColor(name: nil, dynamicProvider: { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor(
                    calibratedHue: 0,
                    saturation: 0,
                    brightness: isDark ? dark : light,
                    alpha: 1
                )
            }))
        }

        private static func dynamicAlphaFill(light: NSColor, dark: NSColor) -> TokenColor {
            TokenColor(ns: NSColor(name: nil, dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            }))
        }

        /// Active toolbar controls, emphasis strokes. Light L=15, dark L=90.
        static let primary = dynamicNeutralSurface(light: 0.15, dark: 0.90)

        /// Icons and labels on `primary` surfaces.
        static let textOnPrimary = dynamicAlphaFill(
            light: NSColor.white.withAlphaComponent(0.85),
            dark: NSColor.black.withAlphaComponent(0.85)
        )

        /// Dividers on `primary` surfaces.
        static let borderOnPrimary = dynamicAlphaFill(
            light: NSColor.white.withAlphaComponent(0.12),
            dark: NSColor.black.withAlphaComponent(0.12)
        )

        /// Floating / elevated panel surface. Light L=97, dark L=18.
        static let panelSurface = dynamicNeutralSurface(light: 0.97, dark: 0.18)

        /// Dividers on `panelSurface`.
        static let borderOnPanel = dynamicAlphaFill(
            light: NSColor.black.withAlphaComponent(0.12),
            dark: NSColor.white.withAlphaComponent(0.12)
        )

        // Brand

        /// Primary accent — focus rings, highlights (pink).
        static let accent = TokenColor(ns: NSColor(calibratedRed: 0xE8 / 255, green: 0x32 / 255, blue: 0x8C / 255, alpha: 1))

        /// Secondary accent — selection outlines, interactive emphasis (blue).
        static let secondary = TokenColor(ns: NSColor(calibratedRed: 0x50 / 255, green: 0x80 / 255, blue: 0xFF / 255, alpha: 1))

        /// Region capture overlay border and handles.
        static let regionSelectionAccent = TokenColor(ns: NSColor(calibratedWhite: 0.72, alpha: 0.55))

        /// Preset recording-background gradients. Single source for Ship It + renderer.
        enum RecordingGradient {
            static let warm = TokenGradient(ns: [
                NSColor(red: 0.98, green: 0.72, blue: 0.45, alpha: 1),
                NSColor(red: 0.92, green: 0.38, blue: 0.55, alpha: 1),
            ])
            static let cool = TokenGradient(ns: [
                NSColor(red: 0.35, green: 0.75, blue: 0.98, alpha: 1),
                NSColor(red: 0.18, green: 0.42, blue: 0.92, alpha: 1),
            ])
            static let midnight = TokenGradient(ns: [
                NSColor(red: 0.12, green: 0.14, blue: 0.22, alpha: 1),
                NSColor(red: 0.04, green: 0.05, blue: 0.10, alpha: 1),
            ])

            static func colors(for style: RecordingBackgroundStyle) -> TokenGradient? {
                switch style {
                case .warm:     return warm
                case .cool:     return cool
                case .midnight: return midnight
                case .none, .custom: return nil
                }
            }
        }

        /// Annotation stroke / fill palette (unchanged values, re-homed).
        static let annotationPalette: [TokenColor] = [
            TokenColor(ns: NSColor(calibratedRed: 0xFF / 255, green: 0x4A / 255, blue: 0x45 / 255, alpha: 1)), // Tomato
            TokenColor(ns: NSColor(calibratedRed: 0xFF / 255, green: 0x8A / 255, blue: 0x38 / 255, alpha: 1)), // Tangerine
            TokenColor(ns: NSColor(calibratedRed: 0xF0 / 255, green: 0xA8 / 255, blue: 0x00 / 255, alpha: 1)), // Gold
            TokenColor(ns: NSColor(calibratedRed: 0x2E / 255, green: 0xC8 / 255, blue: 0x7A / 255, alpha: 1)), // Sage
            TokenColor(ns: NSColor(calibratedRed: 0x00 / 255, green: 0xB4 / 255, blue: 0xD4 / 255, alpha: 1)), // Peacock
            TokenColor(ns: NSColor(calibratedRed: 0x50 / 255, green: 0x80 / 255, blue: 0xFF / 255, alpha: 1)), // Blueberry
            TokenColor(ns: NSColor(calibratedRed: 0x9D / 255, green: 0x66 / 255, blue: 0xF0 / 255, alpha: 1)), // Grape
            TokenColor(ns: NSColor(calibratedRed: 0xF0 / 255, green: 0x4E / 255, blue: 0x88 / 255, alpha: 1)), // Flamingo
        ]

        static var annotationPaletteNS: [NSColor] { annotationPalette.map(\.ns) }
        static var annotationPaletteSwiftUI: [SwiftUI.Color] { annotationPalette.map(\.swiftUI) }
    }

    // MARK: Typography
    // Named `Typography` rather than `Type` — `DesignTokens.Type` is the metatype in Swift.
    //
    // Units: sizes and spacing use Apple points (pt). On a 1× display 1 pt = 1 px;
    // on Retina 1 pt = 2 device pixels. There is no separate px scale in AppKit —
    // pass these numbers straight through (14 pt body ≈ 14 CSS px at 100% / 1×).

    enum Typography {
        static let familyName = "Geist"
        static let monoFamilyName = "Geist Mono"

        static let caption = TokenFont(size: 12, weight: .regular)
        static let label = TokenFont(size: 12, weight: .medium)
        static let body = TokenFont(size: 14, weight: .medium)
        static let bodyEmphasized = TokenFont(size: 14, weight: .semibold)
        static let title = TokenFont(size: 14, weight: .semibold)
        static let panelTitle = TokenFont(size: 18, weight: .semibold)

        enum Style {
            case caption, label, body, bodyEmphasized, title, panelTitle

            var token: TokenFont {
                switch self {
                case .caption:         return Typography.caption
                case .label:           return Typography.label
                case .body:            return Typography.body
                case .bodyEmphasized:  return Typography.bodyEmphasized
                case .title:           return Typography.title
                case .panelTitle:      return Typography.panelTitle
                }
            }
        }

        static func registerBundledFonts() {
            let fileNames = [
                "Geist-Regular", "Geist-Medium", "Geist-SemiBold", "Geist-Bold",
                "GeistMono-Regular", "GeistMono-Medium",
            ]
            for name in fileNames {
                guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }

        static func postScriptName(for weight: NSFont.Weight) -> String {
            switch weight {
            case .ultraLight, .thin, .light, .regular:
                return "Geist-Regular"
            case .medium:
                return "Geist-Medium"
            case .semibold:
                return "Geist-SemiBold"
            case .bold, .heavy, .black:
                return "Geist-Bold"
            default:
                return weight.rawValue < NSFont.Weight.medium.rawValue
                    ? "Geist-Regular"
                    : weight.rawValue < NSFont.Weight.semibold.rawValue
                        ? "Geist-Medium"
                        : weight.rawValue < NSFont.Weight.bold.rawValue
                            ? "Geist-SemiBold"
                            : "Geist-Bold"
            }
        }

        static func monoPostScriptName(for weight: NSFont.Weight) -> String {
            weight.rawValue >= NSFont.Weight.medium.rawValue
                ? "GeistMono-Medium"
                : "GeistMono-Regular"
        }

        static func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
            NSFont(name: postScriptName(for: weight), size: size)
                ?? NSFont.systemFont(ofSize: size, weight: weight)
        }

        static func monoFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
            NSFont(name: monoPostScriptName(for: weight), size: size)
                ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }

        static func monoSwiftUI(size: CGFloat, weight: NSFont.Weight = .regular) -> Font {
            Font.custom(monoPostScriptName(for: weight), size: size)
        }

        static func weightName(_ weight: NSFont.Weight) -> String {
            switch weight {
            case .ultraLight: return "Ultralight"
            case .thin:       return "Thin"
            case .light:      return "Light"
            case .regular:    return "Regular"
            case .medium:     return "Medium"
            case .semibold:   return "Semibold"
            case .bold:       return "Bold"
            case .heavy:      return "Heavy"
            case .black:      return "Black"
            default:          return "Regular"
            }
        }
    }

    // MARK: Elevation

    /// Soft directional shadows for floating panels (Figma-style lift).
    enum Elevation {
        /// Resting floating chrome (annotation toolbar, compact panels).
        case panel
        /// Stronger lift while dragging or for preview cards.
        case panelRaised

        var color: NSColor { .black }

        var opacity: Float {
            switch self {
            case .panel:       return 0.18
            case .panelRaised: return 0.45
            }
        }

        var radius: CGFloat {
            switch self {
            case .panel:       return 6
            case .panelRaised: return 10
            }
        }

        /// AppKit layer coords: negative Y casts shadow downward.
        var offset: CGSize {
            switch self {
            case .panel:       return CGSize(width: 0, height: -1)
            case .panelRaised: return CGSize(width: 0, height: -2)
            }
        }

        func apply(to layer: CALayer, roundedPathIn bounds: CGRect? = nil, cornerRadius: CGFloat = 0) {
            layer.shadowColor = color.cgColor
            layer.shadowOpacity = opacity
            layer.shadowRadius = radius
            layer.shadowOffset = offset
            if let bounds {
                layer.shadowPath = CGPath(
                    roundedRect: bounds,
                    cornerWidth: cornerRadius,
                    cornerHeight: cornerRadius,
                    transform: nil
                )
            } else {
                layer.shadowPath = nil
            }
        }
    }
}

// MARK: - Font helpers

extension Font {
    /// SwiftUI type scale — e.g. `.font(.snipsnap(.body))`.
    static func snipsnap(_ style: DesignTokens.Typography.Style) -> Font {
        style.token.swiftUI
    }
}

extension NSFont {
    /// AppKit type scale — e.g. `NSFont.snipsnap(.body)`.
    static func snipsnap(_ style: DesignTokens.Typography.Style) -> NSFont {
        style.token.ns
    }
}

// MARK: - Buttons

/// Custom content-window button — Geist type, token colors, no AppKit chrome.
/// Compact Vercel-like sizing: 14 pt Medium, tight padding.
struct SnipsnapButtonStyle: ButtonStyle {
    enum Kind {
        /// Filled primary action (Confirm, default).
        case prominent
        /// Outlined / soft secondary action (Cancel, Reject, Auto-Tag).
        case secondary
    }

    enum Size {
        case regular
        case compact
    }

    var kind: Kind = .secondary
    var size: Size = .regular

    @Environment(\.isEnabled) private var isEnabled

    private static let labelFont = Font.custom(
        DesignTokens.Typography.postScriptName(for: .medium),
        size: 14
    )

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Self.labelFont)
            .foregroundStyle(foreground)
            .padding(.horizontal, size == .compact ? 8 : 10)
            .padding(.vertical, size == .compact ? 2 : 4)
            .background(background(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            .overlay(borderOverlay)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
    }

    private var foreground: Color {
        switch kind {
        case .prominent: return DesignTokens.Color.textOnPrimary.swiftUI
        case .secondary: return DesignTokens.Color.textPrimary.swiftUI
        }
    }

    @ViewBuilder
    private func background(isPressed: Bool) -> some View {
        let pressedOpacity = isPressed ? 0.82 : 1.0
        switch kind {
        case .prominent:
            DesignTokens.Color.primary.swiftUI.opacity(pressedOpacity)
        case .secondary:
            DesignTokens.Color.listSelectionFill.swiftUI.opacity(pressedOpacity)
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if kind == .secondary {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .stroke(DesignTokens.Color.border.swiftUI, lineWidth: 1)
        }
    }
}

extension ButtonStyle where Self == SnipsnapButtonStyle {
    static var snipsnap: SnipsnapButtonStyle { SnipsnapButtonStyle() }
    static var snipsnapProminent: SnipsnapButtonStyle { SnipsnapButtonStyle(kind: .prominent) }
    static var snipsnapCompact: SnipsnapButtonStyle { SnipsnapButtonStyle(size: .compact) }
}
