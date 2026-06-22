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
    var events: [Event]?

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case overall, backups, security, drill, disk, events
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
        var dbFailed: Int?
        var neverBacked: Int?
        var runState: String?
        var lastSuccess: String?
        var lastAttempt: String?
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
            case dbFailed = "db_failed"
            case neverBacked = "never_backed"
            case runState = "run_state"
            case lastSuccess = "last_success"
            case lastAttempt = "last_attempt"
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
        var ranToday: Bool?
        var lastSuccess: String?
        var lastAttempt: String?
        var schedule: String?
        var driveCopies: Int?

        enum CodingKeys: String, CodingKey {
            case loaded, schedule
            case lastExit = "last_exit"
            case lastRun = "last_run"
            case ranToday = "ran_today"
            case lastSuccess = "last_success"
            case lastAttempt = "last_attempt"
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
        var stale: Bool?
        var decryptOk: Bool?
        var fileCount: Int?
        var liveCount: Int?
        var pct: Int?
        var dbOk: Bool?

        enum CodingKeys: String, CodingKey {
            case status, checked, detail, stale, pct
            case decryptOk = "decrypt_ok"
            case fileCount = "file_count"
            case liveCount = "live_count"
            case dbOk = "db_ok"
        }
    }

    struct Disk: Codable {
        var macFree: String?
        var macUsedPct: String?
        var driveBackupUsed: String?
        var ssdMounted: Bool?
        var ssdFree: String?
        var ssdLast: String?
        var ssdStaleDays: Int?

        enum CodingKeys: String, CodingKey {
            case macFree = "mac_free"
            case macUsedPct = "mac_used_pct"
            case driveBackupUsed = "drive_backup_used"
            case ssdMounted = "ssd_mounted"
            case ssdFree = "ssd_free"
            case ssdLast = "ssd_last"
            case ssdStaleDays = "ssd_stale_days"
        }
    }

    struct Event: Codable {
        var epoch: Int?
        var time: String?
        var source: String?
        var level: String?
        var msg: String?
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

    /// SSD is considered stale (warn) when the last full-disk backup is 14+ days old.
    static let ssdStaleThresholdDays = 14

    /// A single human-readable line about something that's broken or needs attention,
    /// with a severity so the view can colour it. Mirrors the dashboard's reasons list.
    struct Reason: Equatable {
        let text: String
        let isFailure: Bool  // true → red (fail), false → orange (warn)
    }

    /// Reasons the backups are not fully healthy, mirroring the dashboard.
    /// Empty when nothing is wrong (or when `overall` is "ok").
    static func brokenReasons(_ status: BackupStatus) -> [Reason] {
        var reasons: [Reason] = []
        let pj = status.backups?.projects
        let cl = status.backups?.claude

        if let failed = pj?.failed, failed > 0 {
            reasons.append(Reason(text: "\(failed) project backup\(failed == 1 ? "" : "s") failed", isFailure: true))
        }
        if let dbFailed = pj?.dbFailed, dbFailed > 0 {
            reasons.append(Reason(text: "\(dbFailed) database dump\(dbFailed == 1 ? "" : "s") failed", isFailure: true))
        }
        if let never = pj?.neverBacked, never > 0 {
            reasons.append(Reason(text: "\(never) project\(never == 1 ? "" : "s") never backed up", isFailure: true))
        }
        if pj?.ranToday == false {
            reasons.append(Reason(text: "projects-backup hasn't run today", isFailure: false))
        }
        if cl?.ranToday == false {
            reasons.append(Reason(text: "claude-backup hasn't run today", isFailure: false))
        }
        if status.drill?.status == "fail" {
            reasons.append(Reason(text: "restore drill failed", isFailure: true))
        } else if status.drill?.stale == true {
            reasons.append(Reason(text: "restore drill stale — not verified in 14+ days", isFailure: false))
        }
        if let days = status.disk?.ssdStaleDays, days >= ssdStaleThresholdDays {
            reasons.append(Reason(text: "SSD backup is \(days) days old", isFailure: false))
        }
        if let high = status.security?.high, high > 0 {
            reasons.append(Reason(text: "\(high) secret\(high == 1 ? "" : "s") found in backups", isFailure: true))
        }
        return reasons
    }

    /// Newest-first events, defensively re-sorted by epoch (don't assume input order).
    static func sortedEvents(_ status: BackupStatus, limit: Int = 6) -> [BackupStatus.Event] {
        let events = status.events ?? []
        let sorted = events.sorted { ($0.epoch ?? 0) > ($1.epoch ?? 0) }
        return Array(sorted.prefix(limit))
    }
}
