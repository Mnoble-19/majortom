import MajorTomStyle
import SwiftUI

extension SourceKind {
    var label: String {
        switch self {
        case .show: return "Shows"
        case .call: return "Calls"
        case .book: return "Books"
        case .own: return "My words"
        }
    }

    var icon: String {
        switch self {
        case .show: return "play.rectangle.fill"
        case .call: return "bubble.left.and.bubble.right.fill"
        case .book: return "book.closed.fill"
        case .own: return "pencil.line"
        }
    }

    var tint: Palette.Tint {
        switch self {
        case .show: return Palette.shows
        case .call: return Palette.calls
        case .book: return Palette.books
        case .own: return Palette.Tint(fill: Palette.accentSoft, ink: Palette.accentText)
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    var message = ""

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Palette.accent)
                .frame(width: 84, height: 84)
                .background(Palette.accentSoft, in: Circle())
            Text(title)
                .font(.rounded(22, .bold))
            if !message.isEmpty {
                Text(message)
                    .font(.rounded(15))
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}

struct SectionHeader: View {
    let title: String
    var trailing = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.rounded(17, .bold))
            Spacer()
            if !trailing.isEmpty {
                Text(trailing).font(.rounded(14, .medium)).foregroundStyle(Palette.secondary)
            }
        }
    }
}

/// A progress ring in the Activity style: a faint full track, a bright arc.
struct Ring: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.4), value: progress)
    }
}

/// A tinted tile that opens something: a platform, a show, a call, a source
/// kind on the home screen.
struct Tile<Content: View>: View {
    let tint: Palette.Tint
    var height: CGFloat? = nil
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) { content() }
                .foregroundStyle(tint.ink)
                .padding(22)
                .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
                .background(tint.fill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .scaleEffect(hovering ? 1.015 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: hovering)
    }
}

/// The small square that holds a source glyph on tiles and rows.
struct KindBadge: View {
    let kind: SourceKind
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: kind.icon)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(kind.tint.ink)
            .frame(width: size, height: size)
            .background(kind.tint.fill, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}

struct Pill: View {
    let text: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.rounded(14, .semibold))
                .padding(.horizontal, 16)
                .frame(height: 34)
                .foregroundStyle(selected ? Palette.card : Palette.text)
                .background(selected ? Palette.text : Palette.card, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A one-line notice under the toolbar: sync results, translation results.
struct Banner: View {
    let message: String
    var isFailure = false
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isFailure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isFailure ? Palette.warmText : Palette.goodText)
            Text(message).font(.rounded(14, .medium))
            Spacer()
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.secondary)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(isFailure ? Palette.badSoft : Palette.goodSoft,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Button look for the one main action on a screen.
struct ProminentButtonStyle: ButtonStyle {
    var fill: Color = Palette.accent
    var ink: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rounded(16, .bold))
            .padding(.horizontal, 24)
            .frame(minHeight: 46)
            .foregroundStyle(ink)
            .background(fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

extension Date {
    /// "2h ago", "Yesterday", "Tuesday", "12 Sep": how recent a save reads.
    var relativeDay: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: self, to: Date()).day, days < 7 {
            return formatted(.dateTime.weekday(.wide))
        }
        return formatted(.dateTime.day().month(.abbreviated))
    }
}
