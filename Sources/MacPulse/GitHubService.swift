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

    func fetch(user: String) async throws -> GitHubSnapshot {
        let safeUser = user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user

        async let userData = get("https://api.github.com/users/\(safeUser)")
        async let eventsData = get("https://api.github.com/users/\(safeUser)/events/public?per_page=30")
        async let contribHTML = get("https://github.com/users/\(safeUser)/contributions")

        let (userInfo, events, html) = try await (userData, eventsData, contribHTML)

        guard let profile = GitHubParser.parseUser(data: userInfo) else {
            throw GitHubError.invalidUser
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let todayISO = formatter.string(from: Date())

        let stats = GitHubParser.parseContributions(
            html: String(data: html, encoding: .utf8) ?? "",
            todayISO: todayISO
        )

        return GitHubSnapshot(
            user: user,
            totalContributionsYear: stats.totalYear,
            streakDays: stats.streakDays,
            activeDaysLast7: stats.activeDaysLast7,
            activeToday: stats.activeToday,
            publicRepos: profile.repos,
            followers: profile.followers,
            events: GitHubParser.parseEvents(data: events),
            fetchedAt: Date()
        )
    }

    private func get(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw GitHubError.badStatus(http.statusCode)
        }
        return data
    }
}
