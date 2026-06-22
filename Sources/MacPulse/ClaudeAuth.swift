import Foundation

/// Borrows the Claude Code OAuth token from the macOS keychain. In memory only —
/// never written to UserDefaults or any file. Mirrors `GitHubAuth`.
/// First read triggers the standard keychain "allow access" dialog once.
enum ClaudeAuth {
    static func token() -> String? {
        guard let out = Shell.run("/usr/bin/security",
                                  ["find-generic-password", "-s", "Claude Code-credentials", "-w"]),
              let data = out.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { return nil }
        return token
    }
}
