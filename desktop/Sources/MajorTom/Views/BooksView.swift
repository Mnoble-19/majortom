import SwiftUI

/// The shelf: every book you have saved from, most recently read first.
///
/// Books skip the platform level that shows have. A show's site is a platform
/// worth grouping by; a book's is its author, and grouping a shelf by author
/// would put most books alone in their own group.
struct BooksView: View {
    @EnvironmentObject private var store: Store
    let onOpenBook: (Source) -> Void

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 24)]

    var body: some View {
        let books = store.sources(of: .book)

        Group {
            if books.isEmpty {
                EmptyState(
                    icon: SourceKind.book.icon,
                    title: "No books yet",
                    message: "Save a word or phrase while reading on the reMarkable and it will appear here the next time the tablet is plugged in."
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
    }

    private func summary(_ books: [Source]) -> String {
        let saved = books.reduce(0) { $0 + $1.wordCount + $1.phraseCount }
        return "\(books.count) · \(saved) saved"
    }
}
