import MajorTomStyle
import SwiftUI

/// The shelf: every book you have saved from, most recently read first.
///
/// Books skip the platform level that shows have. A book's site is its author,
/// and grouping a shelf by author would put most books alone in a group.
struct BooksView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var tablet: Syncer
    let openBook: (Source) -> Void

    @State private var dismissTask: Task<Void, Never>?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 24)]

    var body: some View {
        let books = store.sources(of: .book)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    PageTitle(title: "Books", subtitle: summary(books))
                    Spacer()
                    TranslateButton(scope: .kind(.book))
                    syncButton
                }

                if let outcome = tablet.outcome {
                    Banner(message: outcome.message, isFailure: outcome.isFailure) {
                        withAnimation { tablet.dismiss() }
                    }
                }

                if books.isEmpty {
                    EmptyState(icon: SourceKind.book.icon, title: "No books yet",
                               message: "Save a word or phrase while reading on the reMarkable, plug the tablet in, and press Sync.")
                        .frame(height: 360)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                        ForEach(books) { book in
                            BookCover(source: book) { openBook(book) }
                        }
                    }
                }
            }
            .padding(32)
        }
        .background(Palette.background)
        .navigationTitle("Books")
        .onChange(of: tablet.outcome) { _, outcome in scheduleDismiss(for: outcome) }
    }

    private var syncButton: some View {
        Button(action: tablet.sync) {
            HStack(spacing: 8) {
                if tablet.running {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                Text(tablet.running ? "Syncing…" : "Sync reMarkable")
            }
        }
        .buttonStyle(ProminentButtonStyle(fill: Palette.card, ink: Palette.text))
        .disabled(tablet.running)
        .help("Read anything saved on the reMarkable. Plug it in over USB first.")
    }

    /// Successes clear themselves; a failure stays until it is read or retried.
    private func scheduleDismiss(for outcome: Syncer.Outcome?) {
        dismissTask?.cancel()
        guard let outcome, !outcome.isFailure else { return }
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation { tablet.dismiss() }
        }
    }

    private func summary(_ books: [Source]) -> String {
        let saved = books.reduce(0) { $0 + $1.itemCount }
        return "\(books.count) \(books.count == 1 ? "book" : "books") · \(saved) saved"
    }
}

/// There are no cover images — the tablet only sends a title — so the cover is
/// drawn from the title rather than leaving a placeholder that reads as a
/// failed image.
private struct BookCover: View {
    let source: Source
    let open: () -> Void
    @State private var hovering = false
    @State private var deleting = false
    @State private var renaming = false

    private static let tints = [
        Palette.shows, Palette.books, Palette.calls,
        Palette.Tint(fill: Palette.dynamic(0xF6D5D0, 0x3D2020), ink: Palette.dynamic(0x5C1F16, 0xFFB8AD)),
        Palette.Tint(fill: Palette.dynamic(0xE2DAF6, 0x2A2440), ink: Palette.dynamic(0x33245E, 0xC9BBFF)),
        Palette.Tint(fill: Palette.dynamic(0xEDE3C8, 0x332B1A), ink: Palette.dynamic(0x4A3A12, 0xE8D29A)),
    ]

    /// Deterministic on purpose — Swift seeds `hashValue` per process, which
    /// would reshuffle the shelf every launch.
    private var tint: Palette.Tint {
        var hash: UInt64 = 5381
        for byte in source.title.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return Self.tints[Int(hash % UInt64(Self.tints.count))]
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading) {
                    Text(source.title)
                        .font(.rounded(18, .heavy))
                        .lineLimit(5)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if !source.site.isEmpty {
                        Text(source.site.uppercased())
                            .font(.rounded(10, .bold))
                            .kerning(1)
                            .lineLimit(2)
                            .opacity(0.75)
                    }
                }
                .foregroundStyle(tint.ink)
                .padding(EdgeInsets(top: 18, leading: 20, bottom: 14, trailing: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
                .aspectRatio(0.68, contentMode: .fit)
                .background(tint.fill)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.black.opacity(0.08)).frame(width: 7)
                }
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6,
                                                  bottomTrailingRadius: 16, topTrailingRadius: 16,
                                                  style: .continuous))
                .shadow(color: .black.opacity(hovering ? 0.22 : 0.12), radius: hovering ? 14 : 8, y: 6)
                .offset(y: hovering ? -4 : 0)

                Text("\(source.itemCount) saved · \(source.learnedCount) learned")
                    .font(.rounded(13, .medium))
                    .foregroundStyle(Palette.secondary)
                ProgressView(value: source.progress)
                    .progressViewStyle(.linear)
                    .tint(Palette.good)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: hovering)
        .contextMenu {
            Button("Rename…") { renaming = true }
            Button("Delete book…", role: .destructive) { deleting = true }
        }
        .confirmDeleting(source, isPresented: $deleting)
        .renaming(source, isPresented: $renaming)
    }
}
