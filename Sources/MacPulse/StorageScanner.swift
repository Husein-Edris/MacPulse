import Foundation

struct StorageHotspots {
    var cachesMB: Double?
    var trashMB: Double?
    var downloadsMB: Double?
    var scannedAt: Date = Date()
}

/// Sizes a few well-known space hogs with `du`. Runs only on demand (Tips tab),
/// never in the background. Folders protected by privacy consent (Downloads,
/// Trash) simply report nil if macOS denies access.
enum StorageScanner {
    static func scan() -> StorageHotspots {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return StorageHotspots(
            cachesMB: sizeMB("\(home)/Library/Caches"),
            trashMB: sizeMB("\(home)/.Trash"),
            downloadsMB: sizeMB("\(home)/Downloads")
        )
    }

    private static func sizeMB(_ path: String) -> Double? {
        guard FileManager.default.fileExists(atPath: path),
              let out = Shell.run("/usr/bin/du", ["-sk", path]),
              let kb = Double(out.split(separator: "\t").first ?? "")
        else { return nil }
        return kb / 1024
    }
}
