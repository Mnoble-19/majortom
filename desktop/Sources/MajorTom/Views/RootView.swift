import SwiftUI

/// Shows go platforms → that platform's shows → one show's words. Books skip
/// the middle step and open straight from the shelf.
enum Route: Hashable {
    case platform(kind: SourceKind, site: String)
    case source(Source)
}

struct RootView: View {
    @EnvironmentObject private var store: Store
    @State private var tab: SourceKind = .show
    @State private var path: [Route] = []

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack(path: $path) {
                content
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case let .platform(kind, site):
                            PlatformDetailView(kind: kind, site: site) {
                                path.append(.source($0))
                            }
                        case let .source(source):
                            SourceDetailView(source: source)
                        }
                    }
            }
        }
        .background(Theme.bg)
    }

    private var sidebar: some View {
        List(selection: $tab) {
            Section {
                ForEach(SourceKind.allCases, id: \.self) { kind in
                    HStack(spacing: 12) {
                        Image(systemName: kind.icon)
                            .font(.system(size: 15))
                            .frame(width: 22)
                        Text(kind.label)
                            .font(Theme.ui(15, .medium))
                        Spacer()
                        let n = store.sources(of: kind).count
                        if n > 0 {
                            Text("\(n)")
                                .font(Theme.ui(13, .medium))
                                .foregroundStyle(Theme.faint)
                        }
                    }
                    .padding(.vertical, 6)
                    .tag(kind)
                }
            } header: {
                Text("Library")
                    .font(Theme.ui(12, .semibold))
                    .foregroundStyle(Theme.faint)
                    .kerning(1.2)
                    .textCase(.uppercase)
                    .padding(.bottom, 4)
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        .onChange(of: tab) { _, _ in path.removeAll() }
        .safeAreaInset(edge: .bottom) { wordmark }
    }

    private var wordmark: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 8, height: 8)
                .shadow(color: Theme.accent.opacity(0.6), radius: 5)
            Text("MajorTom")
                .font(Theme.serif(16, .semibold))
                .foregroundStyle(Theme.muted)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var content: some View {
        if let error = store.loadError {
            EmptyState(
                icon: "exclamationmark.triangle",
                title: "Could not open the library",
                message: error
            )
        } else {
            switch tab {
            case .show:
                PlatformsView(
                    kind: .show,
                    onOpenPlatform: { path.append(.platform(kind: .show, site: $0.id)) },
                    onOpenShow: { path.append(.source($0)) }
                )
            case .call:
                EmptyState(
                    icon: SourceKind.call.icon,
                    title: "No calls yet",
                    message: "Keywords from practice calls will collect here once transcription is wired up."
                )
            case .book:
                BooksView(onOpenBook: { path.append(.source($0)) })
            }
        }
    }
}

extension SourceKind {
    var label: String {
        switch self {
        case .show: return "Shows"
        case .call: return "Calls"
        case .book: return "Books"
        }
    }

    var icon: String {
        switch self {
        case .show: return "play.rectangle"
        case .call: return "phone"
        case .book: return "book"
        }
    }
}
