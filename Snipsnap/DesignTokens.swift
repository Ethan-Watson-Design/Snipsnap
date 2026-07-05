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
struct TokenFont {
    let size: CGFloat
    let weight: NSFont.Weight

    var ns: NSFont { NSFont.systemFont(ofSize: size, weight: weight) }

    var swiftUI: Font {
        Font.system(size: size, weight: Self.swiftUIWeight(weight))
    }

    private static func swiftUIWeight(_ weight: NSFont.Weight) -> Font.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin:       return .thin
        case .light:      return .light
        case .regular:    return .regular
        case .medium:     return .medium
        case .semibold:   return .semibold
        case .bold:       return .bold
        case .heavy:      return .heavy
        case .black:      return .black
        default:          return .regular
        }
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

        // Brand

        /// Primary accent — selection handles, focus rings (pink).
        static let accent = TokenColor(ns: NSColor(calibratedRed: 0xE8 / 255, green: 0x32 / 255, blue: 0x8C / 255, alpha: 1))

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

    enum Typography {
        static let caption = TokenFont(size: 11, weight: .regular)
        static let label = TokenFont(size: 12, weight: .medium)
        static let body = TokenFont(size: 13, weight: .medium)
        static let bodyEmphasized = TokenFont(size: 13, weight: .semibold)
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

        func apply(to layer: CALayer) {
            layer.shadowColor = color.cgColor
            layer.shadowOpacity = opacity
            layer.shadowRadius = radius
            layer.shadowOffset = offset
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
