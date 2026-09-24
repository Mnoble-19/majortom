import SwiftUI

struct EmptyState: View {
    let icon: String
    let title: String
    var message: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 46, weight: .ultraLight))
                .foregroundStyle(Theme.faint)
            Text(title)
                .font(Theme.serif(22, .medium))
                .foregroundStyle(Theme.text)
            if !message.isEmpty {
                Text(message)
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.ui(12, .semibold))
                .foregroundStyle(Theme.faint)
                .textCase(.uppercase)
                .kerning(1.2)
            Spacer()
            if !trailing.isEmpty {
                Text(trailing)
                    .font(Theme.ui(13, .medium))
                    .foregroundStyle(Theme.faint)
            }
        }
    }
}

struct PlatformCard: View {
    let platform: Platform
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: platform.icon)
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.accent.opacity(hovering ? 1 : 0.7))

                Spacer(minLength: 0)

                Text(platform.name)
                    .font(Theme.serif(24, .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(platform.showCount)")
                        .font(Theme.ui(14, .semibold))
                        .foregroundStyle(Theme.muted)
                    Text(platform.showCount == 1 ? "show" : "shows")
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.faint)
                    Text("·").foregroundStyle(Theme.faint)
                    Text("\(platform.wordCount)")
                        .font(Theme.ui(14, .semibold))
                        .foregroundStyle(Theme.muted)
                    Text(platform.wordCount == 1 ? "word" : "words")
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.faint)
                }
            }
            .padding(22)
            .frame(height: 200, alignment: .topLeading)
            .frame(maxWidth: .infinity)
            .cardSurface(hovering: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

struct ShowCard: View {
    let source: Source
    var showsPlatform: Bool = false
    /// Calls reuse this card; only the glyph differs.
    var icon: String = "play.rectangle.fill"
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent.opacity(hovering ? 1 : 0.7))

                Text(source.title)
                    .font(Theme.serif(16, .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if showsPlatform {
                        Text(Platform.displayName(for: source.site)).pill(Theme.secondary)
                    }
                    Spacer()
                    if source.learnedCount > 0 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.success)
                        Text("\(source.learnedCount)/\(source.wordCount)")
                            .font(Theme.ui(13, .semibold))
                            .foregroundStyle(Theme.muted)
                    } else {
                        Text("\(source.wordCount)")
                            .font(Theme.ui(14, .semibold))
                            .foregroundStyle(Theme.muted)
                        Text(source.wordCount == 1 ? "word" : "words")
                            .font(Theme.ui(12))
                            .foregroundStyle(Theme.faint)
                    }
                }
            }
            .padding(16)
            .frame(height: 165, alignment: .topLeading)
            .frame(maxWidth: .infinity)
            .cardSurface(hovering: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

/// A book on the shelf. There are no cover images to show — the tablet only
/// ever sends a title — so the cover is drawn from the title itself rather
/// than leaving a placeholder that reads as a failed image.
struct BookCard: View {
    let source: Source
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                cover

                Text(source.title)
                    .font(Theme.ui(14, .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !source.site.isEmpty {
                    Text(source.site)
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                }

                counts
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }

    private var cover: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [source.coverTint.opacity(0.55), source.coverTint.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // The spine, so a tile reads as a book edge-on rather than a card.
            Rectangle()
                .fill(Color.black.opacity(0.28))
                .frame(width: 10)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1)
                }

            Text(source.title)
                .font(Theme.serif(16, .semibold))
                .foregroundStyle(Theme.text.opacity(0.92))
                .lineLimit(5)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .padding(.leading, 22)
                .padding(.trailing, 14)
                .padding(.vertical, 16)
        }
        .aspectRatio(0.68, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(hovering ? Theme.accent.opacity(0.45) : Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(hovering ? 0.45 : 0.3), radius: hovering ? 12 : 6, y: 4)
        .offset(y: hovering ? -3 : 0)
    }

    private var counts: some View {
        HStack(spacing: 8) {
            if source.learnedCount > 0 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.success)
                Text("\(source.learnedCount)/\(source.wordCount + source.phraseCount)")
                    .font(Theme.ui(13, .semibold))
                    .foregroundStyle(Theme.muted)
            } else {
                Text("\(source.wordCount + source.phraseCount)")
                    .font(Theme.ui(13, .semibold))
                    .foregroundStyle(Theme.muted)
                Text("saved")
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.faint)
            }
        }
    }
}

/// A recently watched episode, on the landing screen — any platform.
struct RecentShowRow: View {
    let source: Source
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 16) {
                Text(source.title)
                    .font(Theme.serif(16, .medium))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)

                Text(Platform.displayName(for: source.site))
                    .pill(Theme.secondary)

                HStack(spacing: 5) {
                    Text("\(source.wordCount)")
                        .font(Theme.ui(14, .semibold))
                        .foregroundStyle(Theme.muted)
                    Text(source.wordCount == 1 ? "word" : "words")
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.faint)
                }
                .frame(width: 90, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.faint.opacity(hovering ? 1 : 0.4))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .background(hovering ? Color.white.opacity(0.03) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct LearnedButton: View {
    let status: ItemStatus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: status == .learned ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(status == .learned ? Theme.success : Theme.faint.opacity(0.45))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(status == .learned ? "Move back to still learning" : "Mark as learned")
    }
}

struct StarButton: View {
    let starred: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: starred ? "star.fill" : "star")
                .font(.system(size: 14))
                .foregroundStyle(starred ? Theme.accent : Theme.faint.opacity(0.45))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension Source {
    /// A stable colour per book, so a shelf reads as distinct spines rather
    /// than one tile repeated. Deterministic on purpose — Swift seeds
    /// `hashValue` per process, which would reshuffle the shelf every launch.
    var coverTint: Color {
        var hash: UInt64 = 5381
        for byte in title.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.45, brightness: 0.62)
    }
}
