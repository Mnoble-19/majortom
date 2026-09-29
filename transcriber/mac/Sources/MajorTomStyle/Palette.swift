import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The one palette every MajorTom app draws with. Each colour has a light and a
/// dark value; the dark side is deliberately soft — no pure black, no pure
/// white — because it is meant to be read for a long time.
public enum Palette {
    public static let background = dynamic(0xF2F2F7, 0x131316)
    public static let card = dynamic(0xFFFFFF, 0x1D1D22)
    public static let raised = dynamic(0xF6F5F9, 0x26262D)
    public static let hairline = dynamic(0xE5E5EA, 0x2E2E36)

    public static let text = dynamic(0x1C1C1E, 0xE9E9EE)
    public static let secondary = dynamic(0x5E5E63, 0xA3A3AD)
    public static let tertiary = dynamic(0x8A8A8F, 0x76767F)

    public static let accent = dynamic(0x6C4DF5, 0x7F66FF)
    public static let accentText = dynamic(0x5A3BE0, 0xB3A5FF)
    public static let accentSoft = dynamic(0xEDE9FF, 0x2A2448)

    /// The highlighter behind a saved word, everywhere it appears.
    public static let highlight = dynamic(0xFFE08A, 0x564615)
    public static let onHighlight = dynamic(0x2E2100, 0xFFE9A8)

    public static let good = dynamic(0x34C759, 0x30D158)
    public static let goodText = dynamic(0x1E7B3A, 0x6EDC8F)
    public static let goodSoft = dynamic(0xE3F7E8, 0x17301F)
    public static let warm = dynamic(0xFF9500, 0xFF9F0A)
    public static let warmText = dynamic(0xA35A00, 0xFFB45C)
    public static let warmSoft = dynamic(0xFFF1DE, 0x33240F)
    public static let bad = dynamic(0xFF3B30, 0xFF453A)
    public static let badText = dynamic(0xB3261E, 0xFF8A80)
    public static let badSoft = dynamic(0xFFE4E1, 0x3A1C1A)

    /// Each kind of source keeps one colour pair throughout: a tile fill and the
    /// ink that reads on it.
    public struct Tint: Sendable {
        public let fill: Color
        public let ink: Color

        public init(fill: Color, ink: Color) {
            self.fill = fill
            self.ink = ink
        }
    }

    public static let shows = Tint(fill: dynamic(0xFFE8A3, 0x3A3116), ink: dynamic(0x4D3800, 0xFFD970))
    public static let calls = Tint(fill: dynamic(0xCFE6FF, 0x15283D), ink: dynamic(0x0B3560, 0x9FD0FF))
    public static let books = Tint(fill: dynamic(0xCDEFD9, 0x15301F), ink: dynamic(0x0F4526, 0x8FE0AE))

    public static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
        #else
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #endif
    }
}

/// SF Rounded throughout: friendlier than the default face, and still native.
public extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

public extension View {
    /// The standard content card: flat fill, generous corners, no border.
    func card(padding: CGFloat = 20, radius: CGFloat = 24) -> some View {
        self.padding(padding)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Marks a saved word the same way on every surface.
    func highlighted(_ on: Bool = true) -> some View {
        self.padding(.horizontal, on ? 6 : 0)
            .background(on ? Palette.highlight : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .foregroundStyle(on ? Palette.onHighlight : Palette.text)
    }
}

#if os(macOS)
private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
#else
private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
#endif
