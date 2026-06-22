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

struct UsageRecord: Equatable {
    var date: Date
    var sessionId: String
    var projectPath: String?
    var model: String?
    var inputTokens: Int
    var outputTokens: Int
    var toolCalls: Int
}

struct ActivityBucket: Codable, Equatable {
    var messages: Int
    var sessions: Int
    var toolCalls: Int
    var inputTokens: Int
    var outputTokens: Int
    static let empty = ActivityBucket(messages: 0, sessions: 0, toolCalls: 0, inputTokens: 0, outputTokens: 0)
}

struct ProjectActivity: Codable, Equatable, Identifiable {
    var id: String { name }
    var name: String
    var messages: Int
    var sessions: Int
    var toolCalls: Int
    var inputTokens: Int
    var outputTokens: Int
    var lastActive: Date?
}

struct ClaudeActivity: Codable, Equatable {
    var today: ActivityBucket
    var last7: ActivityBucket
    var last30: ActivityBucket
    var allTime: ActivityBucket
    var projects: [ProjectActivity]
    static let empty = ClaudeActivity(today: .empty, last7: .empty, last30: .empty, allTime: .empty, projects: [])
}

/// What the Claude tab renders. Cached in UserDefaults — token is NEVER part of it.
struct ClaudeUsageSnapshot: Codable {
    var activity: ClaudeActivity
    var limits: ClaudeLimits?
    var updatedAt: Date
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

    /// One JSONL transcript line → a record, counting only assistant (model) turns.
    /// Returns nil for user/system/other lines and unparseable input.
    static func decodeRecord(_ line: String) -> UsageRecord? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["type"] as? String) == "assistant",
              let sessionId = obj["sessionId"] as? String,
              let ts = obj["timestamp"] as? String,
              let date = parseDate(ts)
        else { return nil }
        let msg = obj["message"] as? [String: Any]
        let usage = msg?["usage"] as? [String: Any]
        var toolCalls = 0
        if let content = msg?["content"] as? [[String: Any]] {
            toolCalls = content.filter { ($0["type"] as? String) == "tool_use" }.count
        }
        return UsageRecord(
            date: date,
            sessionId: sessionId,
            projectPath: obj["cwd"] as? String,
            model: msg?["model"] as? String,
            inputTokens: (usage?["input_tokens"] as? Int) ?? 0,
            outputTokens: (usage?["output_tokens"] as? Int) ?? 0,
            toolCalls: toolCalls
        )
    }

    private static func bucket(_ records: [UsageRecord]) -> ActivityBucket {
        ActivityBucket(
            messages: records.count,
            sessions: Set(records.map(\.sessionId)).count,
            toolCalls: records.reduce(0) { $0 + $1.toolCalls },
            inputTokens: records.reduce(0) { $0 + $1.inputTokens },
            outputTokens: records.reduce(0) { $0 + $1.outputTokens }
        )
    }

    /// Rolls per-project records into windowed buckets + a per-project breakdown.
    static func activity(byProject: [String: [UsageRecord]], now: Date) -> ClaudeActivity {
        let all = byProject.values.flatMap { $0 }
        let cal = Calendar.current
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let monthAgo = now.addingTimeInterval(-30 * 86_400)

        let projects = byProject.map { name, recs -> ProjectActivity in
            let b = bucket(recs)
            return ProjectActivity(name: name, messages: b.messages, sessions: b.sessions,
                                   toolCalls: b.toolCalls, inputTokens: b.inputTokens,
                                   outputTokens: b.outputTokens, lastActive: recs.map(\.date).max())
        }.sorted { $0.messages > $1.messages }

        return ClaudeActivity(
            today: bucket(all.filter { cal.isDate($0.date, inSameDayAs: now) }),
            last7: bucket(all.filter { $0.date >= weekAgo }),
            last30: bucket(all.filter { $0.date >= monthAgo }),
            allTime: bucket(all),
            projects: projects
        )
    }
}
