import SwiftUI

/// Palette descends from the extension overlay — same amber for the original
/// language, same cyan for the translation — deepened for a full-size window
/// where the extension's translucent-over-video treatment has nothing to sit on.
enum Theme {
    static let bg = Color(hex: 0x0B0D12)
    static let raised = Color(hex: 0x11141C)
    static let surface = Color(hex: 0x171B25)
    static let surfaceHi = Color(hex: 0x1F2532)

    static let border = Color.white.opacity(0.07)
    static let borderHi = Color.white.opacity(0.14)

    static let text = Color(hex: 0xF2F4F9)
    static let muted = Color(hex: 0xA8AEC0)
    static let faint = Color(hex: 0x6E7588)

    /// The language you are learning.
    static let accent = Color(hex: 0xFFD479)
    /// What it means.
    static let secondary = Color(hex: 0x7EC8E3)
    /// Learned — also from the extension palette.
    static let success = Color(hex: 0x7FD6A0)

    static let radius: CGFloat = 14

    /// New York, for vocabulary and titles. Serif gives the saved material a
    /// bookish weight that the default UI face does not.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// SF Pro, for chrome: labels, counts, buttons.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension View {
    func cardSurface(hovering: Bool = false) -> some View {
        background(
            LinearGradient(
                colors: hovering
                    ? [Theme.surfaceHi, Theme.surface]
                    : [Theme.surface, Theme.raised],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(hovering ? Theme.accent.opacity(0.35) : Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(hovering ? 0.35 : 0.2), radius: hovering ? 14 : 8, y: 4)
    }

    /// Small pill used for site names and counts.
    func pill(_ tint: Color) -> some View {
        font(Theme.ui(12, .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tint.opacity(0.13), in: Capsule())
    }
}
