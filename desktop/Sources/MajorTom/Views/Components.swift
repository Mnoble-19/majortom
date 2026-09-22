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

struct ShowCard: View {
    let source: Source
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accent.opacity(hovering ? 1 : 0.7))

                Text(source.title)
                    .font(Theme.serif(18, .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Text(source.site.isEmpty ? "unknown" : source.site)
                        .pill(Theme.secondary)
                    Spacer()
                    Text("\(source.wordCount)")
                        .font(Theme.ui(15, .semibold))
                        .foregroundStyle(Theme.muted)
                    Text(source.wordCount == 1 ? "word" : "words")
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.faint)
                }
            }
            .padding(20)
            .frame(height: 210, alignment: .topLeading)
            .frame(maxWidth: .infinity)
            .cardSurface(hovering: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
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
