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
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "play.rectangle.fill")
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
                    Text("\(source.wordCount)")
                        .font(Theme.ui(14, .semibold))
                        .foregroundStyle(Theme.muted)
                    Text(source.wordCount == 1 ? "word" : "words")
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.faint)
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

                Text("\(source.wordCount)")
                    .font(Theme.ui(14, .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 34, alignment: .trailing)

                Text(source.lastSavedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.faint)
                    .frame(width: 100, alignment: .trailing)

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
