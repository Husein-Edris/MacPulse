import Foundation

/// Resolves backup destinations on disk (no hardcoded account email). Each
/// location reports whether it currently exists so the UI can disable dead buttons.
struct BackupLocation {
    let label: String
    let path: String
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
}

enum BackupLocations {
    /// First Google Drive "My Drive" under CloudStorage, if mounted.
    private static func driveRoot() -> String? {
        let base = NSHomeDirectory() + "/Library/CloudStorage"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: base) else { return nil }
        guard let gd = entries.first(where: { $0.hasPrefix("GoogleDrive-") }) else { return nil }
        return "\(base)/\(gd)/My Drive"
    }

    static var projectsBackup: BackupLocation? {
        driveRoot().map { BackupLocation(label: "Projects backup", path: "\($0)/projects-backup") }
    }
    static var claudeBackup: BackupLocation? {
        driveRoot().map { BackupLocation(label: "Claude backup", path: "\($0)/claude-backups") }
    }
    static var ssd: BackupLocation {
        BackupLocation(label: "SSD backup", path: "/Volumes/SSK SSD")
    }
    static var projectsLog: BackupLocation {
        BackupLocation(label: "projects-backup.log", path: NSHomeDirectory() + "/Library/Logs/projects-backup.log")
    }
    static var claudeLog: BackupLocation {
        BackupLocation(label: "claude-backup.log", path: NSHomeDirectory() + "/Library/Logs/claude-backup.log")
    }
}
