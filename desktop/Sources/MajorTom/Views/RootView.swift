import MajorTomStyle
import SwiftUI

enum SidebarItem: Hashable {
    case home, review, words
    case kind(SourceKind)

    var label: String {
        switch self {
        case .home: return "Home"
        case .review: return "Review"
        case .words: return "All words"
        case .kind(let kind): return kind.label
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .review: return "rectangle.stack.fill"
        case .words: return "text.book.closed.fill"
        case .kind(let kind): return kind.icon
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
            row(.home)
            row(.review).badge(store.stats.due)
            Section("Library") {
                ForEach(SourceKind.allCases, id: \.self) { kind in
                    row(.kind(kind)).badge(store.sources(of: kind).count)
                }
                row(.words)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
    }

    private func row(_ section: SidebarItem) -> some View {
        Label(section.label, systemImage: section.icon)
            .font(.rounded(14, .medium))
            .tag(section)
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
            case .words:
                AllWordsView()
            case .kind(.show):
                ShowsView { path.append(.platform(site: $0.id)) } openShow: { path.append(.source($0)) }
            case .kind(.call):
                CallsView { path.append(.source($0)) }
            case .kind(.book):
                BooksView { path.append(.source($0)) }
            }
        }
    }

    private func open(_ destination: SidebarItem) {
        section = destination
    }
}
