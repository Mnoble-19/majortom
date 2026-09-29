import MajorTomStyle
import SwiftUI

/// Every conversation with the model, newest first. Most are about a word and
/// reopen with that word in view; a new one here is about whatever you like.
struct ChatsView: View {
    @EnvironmentObject private var store: Store
    @State private var open: Target?

    /// A conversation to push: an existing one, or a fresh one when `chatID`
    /// is nil.
    struct Target: Identifiable, Hashable {
        let id = UUID()
        let chatID: Int64?
        let item: Item?
    }

    var body: some View {
        // Read the version so a new message elsewhere re-sorts the list.
        let _ = store.chatsVersion
        let chats = store.chats()

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    PageTitle(title: "Ask",
                              subtitle: "Conversations with your local model. Nothing leaves this Mac.")
                    Spacer()
                    Button { open = Target(chatID: nil, item: nil) } label: {
                        Label("New conversation", systemImage: "plus")
                    }
                    .buttonStyle(ProminentButtonStyle(fill: Palette.accent, ink: .white))
                    .keyboardShortcut("n", modifiers: .command)
                }

                if chats.isEmpty {
                    EmptyState(icon: "bubble.left.and.bubble.right",
                               title: "No conversations yet",
                               message: "Open a word and press Ask about this word, or start a new conversation here.")
                        .frame(minHeight: 300)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(chats) { chat in
                            ChatRow(chat: chat) {
                                open = Target(chatID: chat.id, item: chat.itemID.flatMap(store.item(id:)))
                            }
                            .contextMenu {
                                Button("Delete conversation", role: .destructive) { store.deleteChat(chat.id) }
                            }
                        }
                    }
                }
            }
            .padding(32)
        }
        .background(Palette.background)
        .navigationTitle("Ask")
        .navigationDestination(item: $open) { target in
            AskView(chatID: target.chatID, item: target.item)
        }
    }
}

private struct ChatRow: View {
    let chat: ChatSummary
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: chat.itemID == nil ? "bubble.left.fill" : "character.book.closed.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accentText)
                    .frame(width: 36, height: 36)
                    .background(Palette.accentSoft, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.title)
                        .font(.rounded(16, .bold))
                        .lineLimit(1)
                    Text("\(chat.messageCount) \(chat.messageCount == 1 ? "message" : "messages") · \(chat.updatedAt.relativeDay)")
                        .font(.rounded(13))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.tertiary)
            }
            .padding(14)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(hovering ? Palette.accent : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
