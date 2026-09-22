import SwiftUI

struct MajorTomApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        Window("MajorTom", id: "main") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 940, minHeight: 600)
                .preferredColorScheme(.dark)
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSApplication.didBecomeActiveNotification
                    )
                ) { _ in store.reloadIfChanged() }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1080, height: 700)
    }
}
