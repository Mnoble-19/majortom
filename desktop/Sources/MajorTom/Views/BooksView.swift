import SwiftUI

/// The shelf: every book you have saved from, most recently read first.
///
/// Books skip the platform level that shows have. A show's site is a platform
/// worth grouping by; a book's is its author, and grouping a shelf by author
/// would put most books alone in their own group.
struct BooksView: View {
    @EnvironmentObject private var store: Store
    let onOpenBook: (Source) -> Void

    @StateObject private var syncer: Syncer
    @State private var dismissTask: Task<Void, Never>?

    init(onOpenBook: @escaping (Source) -> Void, store: Store) {
        self.onOpenBook = onOpenBook
        _syncer = StateObject(wrappedValue: Syncer { store.reload() })
    }

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 24)]

    var body: some View {
        let books = store.sources(of: .book)

        Group {
            if books.isEmpty {
                EmptyState(
                    icon: SourceKind.book.icon,
                    title: "No books yet",
                    message: "Save a word or phrase while reading on the reMarkable, plug the tablet in, and press Sync."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        SectionHeader(title: "Books", trailing: summary(books))
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                            ForEach(books) { book in
                                BookCard(source: book) { onOpenBook(book) }
                            }
                        }
                    }
                    .padding(30)
                }
                .background(Theme.bg)
            }
        }
        .navigationTitle(SourceKind.book.label)
        .safeAreaInset(edge: .top) { statusBar }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { syncButton }
        }
        .onChange(of: syncer.outcome) { _, outcome in
            scheduleDismiss(for: outcome)
        }
    }

    private var syncButton: some View {
        Button(action: syncer.sync) {
            HStack(spacing: 6) {
                if syncer.running {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                Text(syncer.running ? "Syncing…" : "Sync")
            }
            .font(Theme.ui(14, .medium))
        }
        .disabled(syncer.running)
        .help("Read anything saved on the reMarkable. Plug it in over USB first.")
    }

    @ViewBuilder
    private var statusBar: some View {
        if let outcome = syncer.outcome {
            HStack(spacing: 10) {
                Image(systemName: outcome.isFailure
                      ? "exclamationmark.triangle.fill"
                      : "info.circle")
                    .font(.system(size: 12))
                Text(outcome.message)
                    .font(Theme.ui(13))
                Spacer()
                Button {
                    syncer.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(outcome.isFailure ? Theme.accent : Theme.muted)
            .padding(.horizontal, 30)
            .padding(.vertical, 10)
            .background(
                (outcome.isFailure ? Theme.accent : Theme.muted)
                    .opacity(0.10)
            )
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.border).frame(height: 1)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Successes clear themselves; a failure stays until it is read or retried.
    private func scheduleDismiss(for outcome: Syncer.Outcome?) {
        dismissTask?.cancel()
        guard let outcome, !outcome.isFailure else { return }
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation { syncer.dismiss() }
        }
    }

    private func summary(_ books: [Source]) -> String {
        let saved = books.reduce(0) { $0 + $1.wordCount + $1.phraseCount }
        return "\(books.count) · \(saved) saved"
    }
}
