import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

struct Palette: Equatable {
    let id: String
    let name: String
    let bg: Color
    let card: Color
    let ink: Color
    let ink2: Color
    let accent: Color
    let accent2: Color
    let ring: Color
    let ringTrack: Color
    let soft: Color
    let positive: Color
    let danger: Color

    static let sage = Palette(
        id: "sage", name: "Sage & Cream",
        bg: Color(hex: 0xF5F0E6), card: .white,
        ink: Color(hex: 0x1F2A24), ink2: Color(hex: 0x5A6560),
        accent: Color(hex: 0x5C7A5A), accent2: Color(hex: 0xD49060),
        ring: Color(hex: 0x5C7A5A), ringTrack: Color(hex: 0x5C7A5A).opacity(0.14),
        soft: Color(hex: 0xEFE8DA), positive: Color(hex: 0x5C7A5A),
        danger: Color(hex: 0xB84D33)
    )

    static let sunrise = Palette(
        id: "sunrise", name: "Sunrise",
        bg: Color(hex: 0xFBF3EC), card: .white,
        ink: Color(hex: 0x2A1E16), ink2: Color(hex: 0x6A564A),
        accent: Color(hex: 0xC5622C), accent2: Color(hex: 0x4A6A8A),
        ring: Color(hex: 0xC5622C), ringTrack: Color(hex: 0xC5622C).opacity(0.15),
        soft: Color(hex: 0xF5E4D3), positive: Color(hex: 0x7A8A4A),
        danger: Color(hex: 0xB84D33)
    )

    static let calm = Palette(
        id: "calm", name: "Calm Blue",
        bg: Color(hex: 0xEEF1F4), card: .white,
        ink: Color(hex: 0x1A2330), ink2: Color(hex: 0x576372),
        accent: Color(hex: 0x3A6B8A), accent2: Color(hex: 0x8A6A4A),
        ring: Color(hex: 0x3A6B8A), ringTrack: Color(hex: 0x3A6B8A).opacity(0.14),
        soft: Color(hex: 0xE2E8EE), positive: Color(hex: 0x3A6B8A),
        danger: Color(hex: 0xB84D33)
    )

    static let all: [Palette] = [.sage, .sunrise, .calm]
    static func byId(_ id: String) -> Palette { all.first { $0.id == id } ?? .sage }
}

struct Typography: Equatable {
    let id: String
    let name: String
    let displayFontName: String?
    let bodyFontName: String?

    func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        if let displayFontName {
            return .custom(displayFontName, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .default)
    }

    func body(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        if let bodyFontName {
            return .custom(bodyFontName, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .default)
    }

    static let humanist = Typography(
        id: "humanist", name: "Humanist",
        displayFontName: "Fraunces", bodyFontName: nil
    )
    static let geometric = Typography(
        id: "geometric", name: "Geometric",
        displayFontName: nil, bodyFontName: nil
    )
    static let editorial = Typography(
        id: "editorial", name: "Editorial",
        displayFontName: "Fraunces", bodyFontName: nil
    )

    static let all: [Typography] = [.humanist, .geometric, .editorial]
    static func byId(_ id: String) -> Typography { all.first { $0.id == id } ?? .humanist }
}

/// Locked to Amble's hand-made defaults. Palette, typography, and text
/// scale are no longer user-configurable — the app ships with one
/// carefully considered look and everyone gets it. Kept as `@Observable`
/// so the existing `@Environment(Theme.self)` plumbing stays identical
/// in call sites; the stored values just never change.
@Observable
final class Theme {
    let palette: Palette = .sage
    let type: Typography = .humanist
    let textScale: Double = 1.0

    init() {
        // Clear the three UserDefaults keys that the old customizable
        // theme used to persist. Upgraders carry leftover values from
        // before the display options were removed; wipe them so we
        // don't leave dead state behind. Idempotent — once cleared,
        // these calls are no-ops on every subsequent launch.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "amble_palette")
        defaults.removeObject(forKey: "amble_typography")
        defaults.removeObject(forKey: "amble_text_scale")
    }
}
