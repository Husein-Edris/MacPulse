import Foundation

/// Mirrors the backup monitor's status.json (written by backup-automation/scripts/collect-status.sh).
/// Every field is optional so a partial or older status.json can never fail to decode; unknown keys
/// (e.g. the per-project stale list, github drift) are simply ignored.
struct BackupStatus: Codable {
    var generatedAt: String?
    var overall: String?
    var backups: Backups?
    var security: Security?
    var drill: Drill?
    var disk: Disk?

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case overall, backups, security, drill, disk
    }

    struct Backups: Codable {
        var projects: Projects?
        var claude: Claude?
    }

    struct Projects: Codable {
        var loaded: Bool?
        var lastExit: Int?
        var lastRun: String?
        var ranToday: Bool?
        var schedule: String?
        var archived: Int?
        var failed: Int?
        var covered: Int?
        var projectFolders: Int?
        var sizeToday: String?
        var dbDumpsToday: Int?
        var driveReadable: Bool?

        enum CodingKeys: String, CodingKey {
            case loaded, schedule, archived, failed, covered
            case lastExit = "last_exit"
            case lastRun = "last_run"
            case ranToday = "ran_today"
            case projectFolders = "project_folders"
            case sizeToday = "size_today"
            case dbDumpsToday = "db_dumps_today"
            case driveReadable = "drive_readable"
        }
    }

    struct Claude: Codable {
        var loaded: Bool?
        var lastExit: Int?
        var lastRun: String?
        var schedule: String?
        var driveCopies: Int?

        enum CodingKeys: String, CodingKey {
            case loaded, schedule
            case lastExit = "last_exit"
            case lastRun = "last_run"
            case driveCopies = "drive_copies"
        }
    }

    struct Security: Codable {
        var high: Int?
        var scanned: Int?
    }

    struct Drill: Codable {
        var status: String?
        var checked: String?
        var detail: String?
    }

    struct Disk: Codable {
        var macFree: String?
        var macUsedPct: String?
        var driveBackupUsed: String?
        var ssdMounted: Bool?
        var ssdFree: String?

        enum CodingKeys: String, CodingKey {
            case macFree = "mac_free"
            case macUsedPct = "mac_used_pct"
            case driveBackupUsed = "drive_backup_used"
            case ssdMounted = "ssd_mounted"
            case ssdFree = "ssd_free"
        }
    }
}

/// Pure decoding + staleness logic (no file or network I/O), so it can be unit-tested.
enum BackupParser {
    static let defaultStaleHours: Double = 26

    static func parse(_ data: Data) -> BackupStatus? {
        try? JSONDecoder().decode(BackupStatus.self, from: data)
    }

    // collect-status.sh stamps generated_at as e.g. "2026-06-12T08:25:45+0200" (numeric TZ, no colon).
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return f
    }()

    static func generatedDate(_ status: BackupStatus) -> Date? {
        guard let raw = status.generatedAt else { return nil }
        return formatter.date(from: raw)
    }

    static func ageHours(_ status: BackupStatus, now: Date) -> Double? {
        guard let date = generatedDate(status) else { return nil }
        return now.timeIntervalSince(date) / 3600
    }

    static func isStale(_ status: BackupStatus, now: Date, staleHours: Double = defaultStaleHours) -> Bool {
        guard let age = ageHours(status, now: now) else { return true }
        return age > staleHours
    }

    /// Same rule the dashboard uses: stale data (or an unexpected value) counts as failing.
    static func effectiveOverall(_ status: BackupStatus, now: Date, staleHours: Double = defaultStaleHours) -> String {
        if isStale(status, now: now, staleHours: staleHours) { return "fail" }
        switch status.overall {
        case "ok", "warn", "fail": return status.overall!
        default: return "fail"
        }
    }
}
