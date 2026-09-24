import MajorTomStyle
import SwiftUI

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct MajorTomApp: App {
    @StateObject private var store: Store
    /// Owned here rather than by a screen: the phone can push at any moment,
    /// so the listener has to live as long as the app, not as long as a tab.
    @StateObject private var phone: PhoneSync
    @StateObject private var tablet: Syncer
    @AppStorage("appearance") private var appearance = Appearance.system

    init() {
        // Cheap, idempotent, and self-healing if the app is moved.
        HostInstaller.register()
        let store = Store()
        _store = StateObject(wrappedValue: store)
        _phone = StateObject(wrappedValue: PhoneSync { store.reload() })
        _tablet = StateObject(wrappedValue: Syncer { store.reload() })
    }

    var body: some Scene {
        Window("MajorTom", id: "main") {
            RootView()
                .environmentObject(store)
                .environmentObject(phone)
                .environmentObject(tablet)
                .frame(minWidth: 980, minHeight: 640)
                .tint(Palette.accent)
                .preferredColorScheme(appearance.colorScheme)
                .task { phone.start() }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification
                )) { _ in store.reloadIfChanged() }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1180, height: 760)

        Settings {
            SettingsView()
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
