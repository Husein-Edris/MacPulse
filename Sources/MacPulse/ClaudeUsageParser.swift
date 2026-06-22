import Foundation

struct LimitWindow: Codable, Equatable {
    var utilization: Double?
    var resetsAt: Date?
    /// Utilization as a 0–100 percentage. The API may report a 0–1 fraction or an
    /// already-scaled 0–100 value; normalize both.
    var percent: Double? { utilization.map { $0 <= 1 ? $0 * 100 : $0 } }
}

struct ClaudeLimits: Codable, Equatable {
    var fiveHour: LimitWindow?
    var sevenDay: LimitWindow?
    var weekly: LimitWindow?
}

/// Pure parsing/aggregation for Claude Code usage. No file or network I/O.
enum ClaudeUsageParser {
    /// Decodes the `GET /api/oauth/usage` body. Defensive: unknown shape variants
    /// and missing fields decode to nil rather than throwing. Returns nil only when
    /// no window could be read at all.
    static func parseLimits(_ data: Data) -> ClaudeLimits? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func window(_ key: String) -> LimitWindow? {
            guard let w = obj[key] as? [String: Any] else { return nil }
            let util = (w["utilization"] as? Double) ?? (w["utilization"] as? Int).map(Double.init)
            let resets = (w["resets_at"] as? String).flatMap(parseDate)
            if util == nil && resets == nil { return nil }
            return LimitWindow(utilization: util, resetsAt: resets)
        }
        let limits = ClaudeLimits(fiveHour: window("five_hour"),
                                  sevenDay: window("seven_day"),
                                  weekly: window("weekly"))
        if limits.fiveHour == nil && limits.sevenDay == nil && limits.weekly == nil { return nil }
        return limits
    }

    /// ISO-8601 with or without fractional seconds.
    static func parseDate(_ s: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}
