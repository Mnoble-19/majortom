import CryptoKit
import Foundation

/// Registers this binary as the browsers' native messaging host, on every
/// launch, so installing the app is just moving it to /Applications.
///
/// Chromium derives an unpacked extension's id from the absolute path of its
/// folder, so the id can be computed rather than asked for.
enum HostInstaller {
    private static let hostName = "com.majortom.host"

    @discardableResult
    static func register() -> [String] {
        guard let extensionDir = AppPaths.unpackedExtension,
              let binary = Bundle.main.executableURL?.resolvingSymlinksInPath().path
        else { return [] }

        let id = unpackedID(for: extensionDir.path)
        let manifest = """
            {
              "name": "\(hostName)",
              "description": "MajorTom desktop sync",
              "path": "\(binary)",
              "type": "stdio",
              "allowed_origins": ["chrome-extension://\(id)/"]
            }
            """

        var installed: [String] = []
        let fm = FileManager.default
        for dir in hostDirectories() {
            let parent = dir.deletingLastPathComponent()
            guard fm.fileExists(atPath: parent.path) else { continue }
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("\(hostName).json")
            try? manifest.write(to: file, atomically: true, encoding: .utf8)
            installed.append(parent.lastPathComponent)
        }
        return installed
    }

    /// sha256 of the path, first 16 bytes, each nibble mapped 0–f → a–p.
    static func unpackedID(for path: String) -> String {
        SHA256.hash(data: Data(path.utf8)).prefix(16).map { byte -> String in
            let hi = UnicodeScalar(UInt8(97 + (byte >> 4)))
            let lo = UnicodeScalar(UInt8(97 + (byte & 0x0F)))
            return "\(hi)\(lo)"
        }.joined()
    }

    private static func hostDirectories() -> [URL] {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return [
            "Google/Chrome", "Google/Chrome Beta", "Google/Chrome Canary",
            "BraveSoftware/Brave-Browser", "BraveSoftware/Brave-Browser-Beta",
            "Chromium", "Microsoft Edge", "Vivaldi", "Arc/User Data",
        ].map {
            support.appendingPathComponent($0).appendingPathComponent("NativeMessagingHosts")
        }
    }
}
