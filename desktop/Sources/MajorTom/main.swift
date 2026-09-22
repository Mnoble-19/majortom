import Foundation

// Chrome passes the host manifest path (and --parent-window=) as arguments,
// so any argument at all means we were spawned as a native messaging host
// rather than launched as an app.
let args = Array(CommandLine.arguments.dropFirst())
let isHost = args.contains("--native-host") || args.contains { $0.hasSuffix(".json") }

if isHost {
    NativeHost.run()
} else {
    MajorTomApp.main()
}
