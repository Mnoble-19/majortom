import MajorTomStyle
import SwiftUI

@main
struct MajorTomPhoneApp: App {
    @State private var pending = PendingWords()

    var body: some Scene {
        WindowGroup {
            ContentView(pending: pending)
                .tint(Palette.accent)
        }
    }
}

struct ContentView: View {
    let pending: PendingWords
    @State private var session = PhoneSession()
    @State private var sync = SyncModel()

    var body: some View {
        TabView {
            Tab("Talk", systemImage: "waveform") {
                NavigationStack { TalkView(session: session, pending: pending) }
            }
            Tab("Waiting", systemImage: "tray.full") {
                NavigationStack { PendingView(pending: pending, sync: sync) }
            }
            .badge(pending.totalWords)
        }
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 44

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.rounded(size * 0.42, .heavy))
            .foregroundStyle(Palette.accentText)
            .frame(width: size, height: size)
            .background(Palette.accentSoft, in: Circle())
    }
}
