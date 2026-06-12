import Foundation

struct GitHubSnapshot: Codable {
    var user: String
    var totalContributionsYear: Int
    var streakDays: Int
    var activeDaysLast7: Int
    var activeToday: Bool
    var publicRepos: Int
    var followers: Int
    var events: [GitHubEvent]
    var fetchedAt: Date
    var recentCommits: [GitHubCommit]
    var privateRepos: Int?
    var authenticated: Bool
}

extension GitHubSnapshot {
    /// Cache-safe copy: private activity never touches disk. When authenticated,
    /// both the recent-commits list and the raw events feed can carry private repo
    /// names/messages, so both are dropped from the cached copy. Public (unauthenticated)
    /// events are safe to cache so the UI has data on relaunch.
    func redactedForCache() -> GitHubSnapshot {
        var copy = self
        copy.recentCommits = []
        if authenticated { copy.events = [] }
        return copy
    }
}

enum GitHubError: LocalizedError {
    case badStatus(Int)
    case invalidUser

    var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            return code == 403
                ? "GitHub rate limit reached — retrying later"
                : "GitHub returned HTTP \(code)"
        case .invalidUser:
            return "GitHub user not found"
        }
    }
}

/// Fetches public GitHub data — no token, no stored credentials.
/// Uses an ephemeral URLSession so nothing is cached or persisted to disk.
final class GitHubService {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["User-Agent": "MacPulse/1.0"]
        session = URLSession(configuration: config)
    }

    func fetch(user: String, token: String?) async throws -> GitHubSnapshot {
        let safeUser = user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user
        let eventsURL = token == nil
            ? "https://api.github.com/users/\(safeUser)/events/public?per_page=30"
            : "https://api.github.com/users/\(safeUser)/events?per_page=30"

        async let userData = get("https://api.github.com/users/\(safeUser)", token: token)
        async let eventsData = get(eventsURL, token: token)
        async let contribHTML = get("https://github.com/users/\(safeUser)/contributions", token: nil)
        async let selfData = token == nil
            ? get("https://api.github.com/users/\(safeUser)", token: nil)
            : get("https://api.github.com/user", token: token)

        let (userInfo, events, html, selfInfo) = try await (userData, eventsData, contribHTML, selfData)

        guard let profile = GitHubParser.parseUser(data: userInfo) else { throw GitHubError.invalidUser }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = .current
        let todayISO = formatter.string(from: Date())
        let stats = GitHubParser.parseContributions(html: String(data: html, encoding: .utf8) ?? "", todayISO: todayISO)

        return GitHubSnapshot(
            user: user,
            totalContributionsYear: stats.totalYear,
            streakDays: stats.streakDays,
            activeDaysLast7: stats.activeDaysLast7,
            activeToday: stats.activeToday,
            publicRepos: profile.repos,
            followers: profile.followers,
            events: GitHubParser.parseEvents(data: events),
            fetchedAt: Date(),
            recentCommits: GitHubParser.parseRecentCommits(data: events),
            privateRepos: token == nil ? nil : GitHubParser.parsePrivateRepos(data: selfInfo),
            authenticated: token != nil
        )
    }

    private func get(_ urlString: String, token: String?) async throws -> Data {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw GitHubError.badStatus(http.statusCode)
        }
        return data
    }
}
