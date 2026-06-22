import Foundation

/// I/O for Claude Code usage. Walks the local transcripts and fetches the
/// subscription-limit endpoint. Decoding/aggregation lives in ClaudeUsageParser.
enum ClaudeUsageService {
    static let projectsDir = NSString(string: "~/.claude/projects").expandingTildeInPath

    /// Walks `~/.claude/projects/<project>/*.jsonl`, decoding assistant turns.
    /// Blocking + potentially slow (hundreds of files) — call off the main thread.
    static func loadActivity(dir: String = projectsDir, now: Date = Date()) -> ClaudeActivity {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return .empty }
        var byProject: [String: [UsageRecord]] = [:]

        for entry in entries {
            let projectPath = "\(dir)/\(entry)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: projectPath, isDirectory: &isDir), isDir.boolValue,
                  let files = try? fm.contentsOfDirectory(atPath: projectPath) else { continue }
            let fallback = displayName(forFolder: entry)

            for file in files where file.hasSuffix(".jsonl") {
                guard let content = try? String(contentsOfFile: "\(projectPath)/\(file)", encoding: .utf8)
                else { continue }
                for sub in content.split(separator: "\n") {
                    // Cheap pre-filter: only assistant lines carry the data we count.
                    guard sub.contains("\"assistant\"") else { continue }
                    guard let rec = ClaudeUsageParser.decodeRecord(String(sub)) else { continue }
                    let name = rec.projectPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? fallback
                    byProject[name, default: []].append(rec)
                }
            }
        }
        return ClaudeUsageParser.activity(byProject: byProject, now: now)
    }

    /// Fetches subscription-limit utilization. Returns nil when not signed in,
    /// the token is expired (401), or the network call fails — the UI degrades gracefully.
    static func fetchLimits() async -> ClaudeLimits? {
        guard let token = ClaudeAuth.token(),
              let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config)
        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode < 400 else { return nil }
        return ClaudeUsageParser.parseLimits(data)
    }

    /// Folder name "-Users-me-Projects-MacPulse" → "MacPulse" (last segment).
    /// Only a fallback; the per-record `cwd` gives the accurate name when present.
    static func displayName(forFolder folder: String) -> String {
        folder.split(separator: "-").map(String.init).last ?? folder
    }
}
