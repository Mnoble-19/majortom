import MajorTomStyle
import SwiftUI

/// Flat, with no associated values, so each row's tag is a plain value the
/// sidebar's selection can match.
enum SidebarItem: Hashable, CaseIterable {
    case home, review, shows, calls, books, mine

    static let library: [SidebarItem] = [.shows, .calls, .books, .mine]

    init(_ kind: SourceKind) {
        switch kind {
        case .show: self = .shows
        case .call: self = .calls
        case .book: self = .books
        case .own: self = .mine
        }
    }

    var kind: SourceKind? {
        switch self {
        case .shows: return .show
        case .calls: return .call
        case .books: return .book
        case .mine: return .own
        case .home, .review: return nil
        }
    }

    var label: String {
        switch self {
        case .home: return "Home"
        case .review: return "Review"
        default: return kind!.label
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .review: return "rectangle.stack.fill"
        default: return kind!.icon
        }
    }
}

/// Shows go platform → show → words; calls and books skip the middle step.
enum Route: Hashable {
    case platform(site: String)
    case source(Source)
}

struct RootView: View {
    @EnvironmentObject private var store: Store
    @State private var section: SidebarItem = .home
    @State private var path: [Route] = []

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack(path: $path) {
                content
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .platform(let site):
                            PlatformView(site: site) { path.append(.source($0)) }
                        case .source(let source):
                            SourceDetailView(source: source)
                        }
                    }
            }
        }
        .onChange(of: section) { _, _ in path.removeAll() }
    }

    private var sidebar: some View {
        List(selection: $section) {
            row(.home, badge: 0)
            row(.review, badge: store.stats.due)
            Section("Library") {
                ForEach(SidebarItem.library, id: \.self) { item in
                    row(item, badge: count(item))
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        .safeAreaInset(edge: .bottom) {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    .font(.rounded(13, .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    /// The tag goes last: a List only reads it off the row's outermost view.
    private func row(_ item: SidebarItem, badge: Int) -> some View {
        Label(item.label, systemImage: item.icon)
            .font(.rounded(14, .medium))
            .badge(badge)
            .tag(item)
    }

    private func count(_ item: SidebarItem) -> Int {
        guard let kind = item.kind else { return 0 }
        if kind == .own { return store.sources(of: .own).first?.itemCount ?? 0 }
        return store.sources(of: kind).count
    }

    @ViewBuilder
    private var content: some View {
        if let error = store.loadError {
            EmptyState(icon: "exclamationmark.triangle", title: "Could not open the library",
                       message: error)
        } else {
            switch section {
            case .home:
                HomeView(open: open) { path.append(.source($0)) }
            case .review:
                ReviewView(source: nil) { section = .home }
            case .shows:
                ShowsView { path.append(.platform(site: $0.id)) } openShow: { path.append(.source($0)) }
            case .calls:
                CallsView { path.append(.source($0)) }
            case .books:
                BooksView { path.append(.source($0)) }
            case .mine:
                MyWordsView()
            }
        }
    }

    private func open(_ destination: SidebarItem) {
        section = destination
    }
}
