import Foundation

/// Reads the backup monitor's local status.json — the same file collect-status.sh writes and the
/// web dashboard renders. Local-only: no network, no auth, nothing leaves the Mac.
enum BackupService {
    /// Default location of the collector's output on this machine.
    static let defaultPath = NSString(string: "~/Projects/backup-automation/web/data/status.json").expandingTildeInPath

    /// Blocking file read; call off the main thread. Returns nil if the file is absent or unparseable.
    static func load(path: String = defaultPath) -> BackupStatus? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return BackupParser.parse(data)
    }
}
