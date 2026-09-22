import Foundation

/// Where the project lives. `build.sh` bakes the repo root into Info.plist so
/// the app still finds `data/` and `dist/extension` after being copied to
/// /Applications, where walking up from the binary would find nothing.
enum AppPaths {
    static let repoRoot: URL? = {
        let fm = FileManager.default

        if let baked = Bundle.main.object(forInfoDictionaryKey: "MTRepoRoot") as? String,
           !baked.isEmpty,
           fm.fileExists(atPath: (baked as NSString).appendingPathComponent("package.json")) {
            return URL(fileURLWithPath: baked)
        }

        var dir = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        while dir.path != "/" {
            if fm.fileExists(atPath: dir.appendingPathComponent("package.json").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }()

    /// The unpacked extension folder, whose absolute path determines the
    /// extension id the browsers will give it.
    static var unpackedExtension: URL? {
        repoRoot?.appendingPathComponent("dist/extension", isDirectory: true)
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
