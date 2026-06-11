import Foundation

struct ContributionStats: Equatable {
    var totalYear: Int
    var streakDays: Int
    var activeDaysLast7: Int
    var activeToday: Bool
}

struct GitHubEvent: Codable, Identifiable, Equatable {
    var id: String
    var repo: String
    var message: String
    var date: Date?
}

/// Pure parsing logic, separated from networking so it is unit-testable.
enum GitHubParser {
    // MARK: - Regex helper

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).map { i in
                guard let r = Range(match.range(at: i), in: text) else { return "" }
                return String(text[r])
            }
        }
    }

    // MARK: - Contributions calendar (HTML fragment)

    static func parseContributions(html: String, todayISO: String) -> ContributionStats {
        // Day cells carry data-date + data-level; attribute order varies, so scan each <td> tag.
        var days: [(date: String, level: Int)] = []
        for tag in matches(#"<td[^>]*data-date="[^"]*"[^>]*>"#, in: html) {
            let td = tag[0]
            guard let date = matches(#"data-date="(\d{4}-\d{2}-\d{2})""#, in: td).first?[1],
                  let levelStr = matches(#"data-level="(\d)""#, in: td).first?[1],
                  let level = Int(levelStr)
            else { continue }
            days.append((date, level))
        }
        days.sort { $0.date < $1.date }
        // Ignore future placeholder cells.
        days = days.filter { $0.date <= todayISO }

        // Yearly total: prefer the headline, fall back to summing day tooltips.
        var total = 0
        if let headline = matches(#"([\d,]+)\s+contributions?\s+in the last year"#, in: html).first?[1] {
            total = Int(headline.replacingOccurrences(of: ",", with: "")) ?? 0
        }
        if total == 0 {
            total = matches(#"(\d+) contributions? on"#, in: html)
                .compactMap { Int($0[1]) }
                .reduce(0, +)
        }

        let activeToday = days.last(where: { $0.date == todayISO }).map { $0.level > 0 } ?? false

        // Streak: consecutive active days ending today — or ending yesterday if today
        // has no contributions yet (the day isn't over).
        var streak = 0
        var remaining = days
        if let last = remaining.last, last.date == todayISO {
            if last.level > 0 { streak += 1 }
            remaining.removeLast()
        }
        for day in remaining.reversed() {
            if day.level > 0 { streak += 1 } else { break }
        }
        if !activeToday && streak == 0 {
            // No streak at all.
        }

        let activeLast7 = days.suffix(7).filter { $0.level > 0 }.count

        return ContributionStats(
            totalYear: total,
            streakDays: streak,
            activeDaysLast7: activeLast7,
            activeToday: activeToday
        )
    }

    // MARK: - User JSON

    static func parseUser(data: Data) -> (repos: Int, followers: Int)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["public_repos"] as? Int ?? 0, json["followers"] as? Int ?? 0)
    }

    // MARK: - Public events JSON

    static func parseEvents(data: Data, limit: Int = 5) -> [GitHubEvent] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        var events: [GitHubEvent] = []

        for item in array {
            guard events.count < limit else { break }
            guard let type = item["type"] as? String,
                  let repoDict = item["repo"] as? [String: Any],
                  let repoFull = repoDict["name"] as? String
            else { continue }
            let repo = repoFull.components(separatedBy: "/").last ?? repoFull
            let payload = item["payload"] as? [String: Any] ?? [:]
            let id = item["id"] as? String ?? UUID().uuidString
            let date = (item["created_at"] as? String).flatMap { iso.date(from: $0) }

            let message: String
            switch type {
            case "PushEvent":
                let commits = payload["commits"] as? [[String: Any]] ?? []
                if let last = commits.last, let msg = last["message"] as? String {
                    message = String(msg.components(separatedBy: "\n")[0].prefix(60))
                } else {
                    message = "Merge"
                }
            case "CreateEvent":
                let refType = payload["ref_type"] as? String ?? ""
                let ref = payload["ref"] as? String ?? ""
                message = "Create \(refType) \(ref)".trimmingCharacters(in: .whitespaces)
            case "DeleteEvent":
                let refType = payload["ref_type"] as? String ?? ""
                let ref = payload["ref"] as? String ?? ""
                message = "Delete \(refType) \(ref)".trimmingCharacters(in: .whitespaces)
            case "PullRequestEvent":
                let action = payload["action"] as? String ?? ""
                let pr = payload["pull_request"] as? [String: Any] ?? [:]
                let title = pr["title"] as? String ?? ""
                message = String("PR \(action): \(title)".prefix(60))
            case "IssuesEvent":
                let action = payload["action"] as? String ?? ""
                let issue = payload["issue"] as? [String: Any] ?? [:]
                let title = issue["title"] as? String ?? ""
                message = String("Issue \(action): \(title)".prefix(60))
            case "WatchEvent":
                message = "Starred"
            case "ForkEvent":
                message = "Forked"
            default:
                message = type.replacingOccurrences(of: "Event", with: "")
            }

            events.append(GitHubEvent(id: id, repo: repo, message: message, date: date))
        }
        return events
    }
}
