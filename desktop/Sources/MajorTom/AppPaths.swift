import Foundation

/// Where the monorepo lives. `build.sh` bakes the root into Info.plist so the
/// app still finds `data/` and the unpacked extension after being copied to
/// /Applications, where walking up from the binary would find nothing.
enum AppPaths {
    /// What identifies the repo root. Each project owns its own `package.json`
    /// now, so the marker has to be one of those rather than a bare filename
    /// that any subfolder could match.
    private static let marker = "extension/package.json"

    static let repoRoot: URL? = {
        let fm = FileManager.default

        if let baked = Bundle.main.object(forInfoDictionaryKey: "MTRepoRoot") as? String,
           !baked.isEmpty,
           fm.fileExists(atPath: (baked as NSString).appendingPathComponent(marker)) {
            return URL(fileURLWithPath: baked)
        }

        var dir = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        while dir.path != "/" {
            if fm.fileExists(atPath: dir.appendingPathComponent(marker).path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }()

    /// The unpacked extension folder, whose absolute path determines the
    /// extension id the browsers will give it.
    static var unpackedExtension: URL? {
        repoRoot?.appendingPathComponent("extension/dist/unpacked", isDirectory: true)
    }

    static var dataDirectory: URL {
        let url = repoRoot?.appendingPathComponent("data", isDirectory: true)
            ?? FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MajorTom", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
