import Foundation

// Chromium browsers spawn the host with the calling extension's origin as the
// first argument ("chrome-extension://<id>/"); Firefox passes the manifest
// path instead. Either means we were started as a native messaging host
// rather than launched as an app.
let args = Array(CommandLine.arguments.dropFirst())
let isHost = args.contains { arg in
    arg == "--native-host" || arg.hasPrefix("chrome-extension://") || arg.hasSuffix(".json")
}

if isHost {
    AppLog.start(as: "browser-sync")
    NativeHost.run()
} else {
    AppLog.start(as: "desktop")
    AppLog.info("MajorTom opened")
    MajorTomApp.main()
}
