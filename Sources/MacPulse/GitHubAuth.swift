import Foundation

/// Borrows the existing `gh` CLI login. The token lives only in memory for the
/// session — never written to UserDefaults or any file.
enum GitHubAuth {
    private static let candidates = ["/usr/local/bin/gh", "/opt/homebrew/bin/gh"]

    static func token() -> String? {
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            if let out = Shell.run(path, ["auth", "token"]) {
                let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}
