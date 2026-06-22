# Claude Code Usage Tab — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Claude" tab to MacPulse showing Claude Code subscription-limit usage, activity stats, and a per-project breakdown, with a manual reload button.

**Architecture:** A pure parser (`ClaudeUsageParser`) decodes the `/api/oauth/usage` response and aggregates local JSONL transcript records; an I/O layer (`ClaudeAuth` + `ClaudeUsageService`) reads the keychain token, fetches limits, and walks `~/.claude/projects`. `AppState` owns the snapshot (cached in UserDefaults, token never persisted) and refreshes on tab-open + reload. A new SwiftUI tab renders it.

**Tech Stack:** Swift 5.8 / SwiftUI, SDK 13.3, zero third-party deps. Built via `make test` / `make app` (Command Line Tools only — `swift build`/`swift test` DO NOT WORK).

## Global Constraints

- No third-party dependencies.
- System binaries via `Shell.run(path, args)` only — absolute path, array args, never a shell string.
- Swift 5.8 / SDK 13.3: `ObservableObject` (no `@Observable`), `NSRegularExpression`/`JSONSerialization` (no bare regex), ViewBuilder caps at 10 children (wrap in `Group`).
- Pure logic vs I/O is a hard boundary. New pure-logic files MUST be added to the source list in `scripts/test.sh`, or the test runner won't see them.
- Tests use the homegrown assert runner (`expect`/`expectEq` in `Tests/TestRunner/main.swift`), NOT XCTest. There is no single-test selection; `make test` builds and runs the whole binary.
- Security: the Claude OAuth token is read into memory per-refresh and never written to disk. Only public-to-user aggregates (utilization %s, counts) are cached.
- Build: `make test` (~30s) and `make app` (release bundle). Verify with these, never `swift build`.
- Don't touch `legacy/`.

---

### Task 1: Limit-window models, `parseLimits`, and `Fmt.until`

Pure decoding of the `/api/oauth/usage` body plus a reset-countdown formatter. Defensive decoding via `JSONSerialization` because the exact JSON nesting is confirmed only by field names (`five_hour`, `seven_day`, `weekly`, each with `utilization` + `resets_at`) — all fields optional, like `BackupStatus`.

**Files:**
- Create: `Sources/MacPulse/ClaudeUsageParser.swift`
- Modify: `Sources/MacPulse/Formatters.swift` (add `Fmt.until`)
- Modify: `scripts/test.sh` (add `ClaudeUsageParser.swift` to the swiftc source list)
- Test: `Tests/TestRunner/main.swift` (append a `ClaudeUsageParser — limits` section and a `Fmt.until` section)

**Interfaces:**
- Produces:
  - `struct LimitWindow: Codable, Equatable { var utilization: Double?; var resetsAt: Date?; var percent: Double? }` where `percent` is computed: `utilization.map { $0 <= 1 ? $0 * 100 : $0 }`.
  - `struct ClaudeLimits: Codable, Equatable { var fiveHour: LimitWindow?; var sevenDay: LimitWindow?; var weekly: LimitWindow? }`
  - `enum ClaudeUsageParser { static func parseLimits(_ data: Data) -> ClaudeLimits? }`
  - `Fmt.until(_ date: Date, now: Date = Date()) -> String`

- [ ] **Step 1: Add `Fmt.until` to `Formatters.swift`**

Add inside `enum Fmt`, after `ago`:

```swift
/// Countdown to a future reset, e.g. "2h 14m" or "1d 3h". "now" when past.
static func until(_ date: Date, now: Date = Date()) -> String {
    let diff = Int(date.timeIntervalSince(now))
    if diff <= 0 { return "now" }
    if diff >= 86_400 { return "\(diff / 86_400)d \((diff % 86_400) / 3_600)h" }
    let h = diff / 3_600, m = (diff % 3_600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}
```

- [ ] **Step 2: Create `ClaudeUsageParser.swift` with limit models + `parseLimits`**

```swift
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
```

- [ ] **Step 3: Add `ClaudeUsageParser.swift` to `scripts/test.sh`**

In the `swiftc -O \` source list, add the line (anywhere among the `Sources/MacPulse/*.swift` lines):

```
    Sources/MacPulse/ClaudeUsageParser.swift \
```

- [ ] **Step 4: Append failing tests to `Tests/TestRunner/main.swift`**

Add before the `// MARK: - Summary` block at the end:

```swift
// MARK: - ClaudeUsageParser (limits)

print("ClaudeUsageParser — limits")

do {
    let json = """
    {"five_hour":{"utilization":0.42,"resets_at":"2026-06-22T20:00:00Z"},
     "seven_day":{"utilization":12,"resets_at":"2026-06-29T00:00:00Z"},
     "weekly":{"utilization":0.9}}
    """.data(using: .utf8)!
    let limits = ClaudeUsageParser.parseLimits(json)
    expect(limits != nil, "parses a usage response")
    expectEq(limits?.fiveHour?.percent ?? -1, 42, "0–1 fraction → percent")
    expectEq(limits?.sevenDay?.percent ?? -1, 12, "already-percent value kept as-is")
    expect(limits?.weekly?.resetsAt == nil, "missing resets_at decodes to nil")
    expect(limits?.fiveHour?.resetsAt != nil, "resets_at parses")
}

do {
    expect(ClaudeUsageParser.parseLimits("not json".data(using: .utf8)!) == nil, "garbage → nil")
    expect(ClaudeUsageParser.parseLimits("{}".data(using: .utf8)!) == nil, "no windows → nil")
}

// MARK: - Fmt.until

print("Fmt.until")

do {
    let now = Date(timeIntervalSince1970: 1_000_000)
    expectEq(Fmt.until(now.addingTimeInterval(60 * 134), now: now), "2h 14m", "hours+minutes")
    expectEq(Fmt.until(now.addingTimeInterval(45 * 60), now: now), "45m", "minutes only")
    expectEq(Fmt.until(now.addingTimeInterval(-10), now: now), "now", "past → now")
    expectEq(Fmt.until(now.addingTimeInterval(86_400 + 3 * 3_600), now: now), "1d 3h", "days+hours")
}
```

- [ ] **Step 5: Run the tests and verify they pass**

Run: `make test`
Expected: builds cleanly; final line `N passed, 0 failed` (N higher than before; the new `ClaudeUsageParser — limits` and `Fmt.until` sections print with no `✗ FAIL`).

- [ ] **Step 6: Commit**

```bash
git add Sources/MacPulse/ClaudeUsageParser.swift Sources/MacPulse/Formatters.swift scripts/test.sh Tests/TestRunner/main.swift
git commit -m "feat(claude-usage): pure limit-window parsing and reset-countdown formatter"
```

---

### Task 2: Activity record decoding + aggregation

Pure conversion of JSONL transcript lines into per-project activity buckets (today / 7d / 30d / all-time).

**Files:**
- Modify: `Sources/MacPulse/ClaudeUsageParser.swift` (add record + activity types and functions)
- Test: `Tests/TestRunner/main.swift` (append a `ClaudeUsageParser — activity` section)

**Interfaces:**
- Consumes: `ClaudeUsageParser.parseDate` (from Task 1).
- Produces:
  - `struct UsageRecord: Equatable { var date: Date; var sessionId: String; var projectPath: String?; var model: String?; var inputTokens: Int; var outputTokens: Int; var toolCalls: Int }`
  - `struct ActivityBucket: Codable, Equatable { var messages: Int; var sessions: Int; var toolCalls: Int; var inputTokens: Int; var outputTokens: Int; static let empty: ActivityBucket }`
  - `struct ProjectActivity: Codable, Equatable, Identifiable { var id: String { name }; var name: String; var messages: Int; var sessions: Int; var toolCalls: Int; var inputTokens: Int; var outputTokens: Int; var lastActive: Date? }`
  - `struct ClaudeActivity: Codable, Equatable { var today, last7, last30, allTime: ActivityBucket; var projects: [ProjectActivity] }`
  - `ClaudeUsageParser.decodeRecord(_ line: String) -> UsageRecord?`
  - `ClaudeUsageParser.activity(byProject: [String: [UsageRecord]], now: Date) -> ClaudeActivity`

- [ ] **Step 1: Add the activity types and functions to `ClaudeUsageParser.swift`**

Add the structs at the top of the file (after `ClaudeLimits`), and the functions inside `enum ClaudeUsageParser`:

```swift
struct UsageRecord: Equatable {
    var date: Date
    var sessionId: String
    var projectPath: String?   // top-level `cwd` from the transcript line
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
    var projects: [ProjectActivity]   // sorted by messages, descending
    static let empty = ClaudeActivity(today: .empty, last7: .empty, last30: .empty, allTime: .empty, projects: [])
}
```

Add inside `enum ClaudeUsageParser`:

```swift
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
```

- [ ] **Step 2: Append failing tests to `Tests/TestRunner/main.swift`**

Add before the `// MARK: - Summary` block:

```swift
// MARK: - ClaudeUsageParser (activity)

print("ClaudeUsageParser — activity")

do {
    let line = """
    {"type":"assistant","sessionId":"s1","timestamp":"2026-06-22T10:00:00Z","cwd":"/Users/x/Projects/MacPulse","message":{"model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":20},"content":[{"type":"tool_use"},{"type":"text"},{"type":"tool_use"}]}}
    """
    let rec = ClaudeUsageParser.decodeRecord(line)
    expect(rec != nil, "decodes an assistant line")
    expectEq(rec?.sessionId ?? "", "s1", "captures sessionId")
    expectEq(rec?.toolCalls ?? -1, 2, "counts tool_use blocks")
    expectEq(rec?.inputTokens ?? -1, 100, "captures input tokens")
    expectEq(rec?.projectPath ?? "", "/Users/x/Projects/MacPulse", "captures cwd")

    expect(ClaudeUsageParser.decodeRecord("{\"type\":\"user\"}") == nil, "skips non-assistant lines")
    expect(ClaudeUsageParser.decodeRecord("") == nil, "skips blank lines")
}

do {
    let now = ISO8601DateFormatter().date(from: "2026-06-22T12:00:00Z")!
    func rec(_ session: String, _ iso: String, tools: Int = 0) -> UsageRecord {
        UsageRecord(date: ISO8601DateFormatter().date(from: iso)!, sessionId: session,
                    projectPath: nil, model: nil, inputTokens: 10, outputTokens: 5, toolCalls: tools)
    }
    let byProject: [String: [UsageRecord]] = [
        "MacPulse": [rec("s1", "2026-06-22T09:00:00Z", tools: 3),    // today
                     rec("s1", "2026-06-20T09:00:00Z")],              // within 7d, same session
        "other":    [rec("s2", "2026-06-01T09:00:00Z")],             // within 30d
    ]
    let a = ClaudeUsageParser.activity(byProject: byProject, now: now)
    expectEq(a.today.messages, 1, "today counts only same-day records")
    expectEq(a.last7.messages, 2, "7-day window")
    expectEq(a.last7.sessions, 1, "7-day distinct sessions")
    expectEq(a.last30.messages, 3, "30-day window")
    expectEq(a.allTime.toolCalls, 3, "all-time tool calls summed")
    expectEq(a.projects.first?.name ?? "", "MacPulse", "projects sorted by messages desc")
}
```

- [ ] **Step 3: Run the tests and verify they pass**

Run: `make test`
Expected: `N passed, 0 failed`; the new `ClaudeUsageParser — activity` section prints with no failures.

- [ ] **Step 4: Commit**

```bash
git add Sources/MacPulse/ClaudeUsageParser.swift Tests/TestRunner/main.swift
git commit -m "feat(claude-usage): pure transcript record decoding and activity aggregation"
```

---

### Task 3: Token reader + I/O service

Reads the keychain token in-memory, fetches `/api/oauth/usage`, and walks the JSONL transcripts. No unit tests (shells out / hits the network / reads files) — the gate is a clean `make app` plus a one-off smoke run.

**Files:**
- Create: `Sources/MacPulse/ClaudeAuth.swift`
- Create: `Sources/MacPulse/ClaudeUsageService.swift`

**Interfaces:**
- Consumes: `Shell.run` (existing); `ClaudeUsageParser.{decodeRecord,parseLimits,activity}`, `ClaudeActivity`, `ClaudeLimits` (Tasks 1–2).
- Produces:
  - `enum ClaudeAuth { static func token() -> String? }`
  - `enum ClaudeUsageService { static func loadActivity(dir:String, now:Date) -> ClaudeActivity; static func fetchLimits() async -> ClaudeLimits? }`

- [ ] **Step 1: Create `ClaudeAuth.swift`**

```swift
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
```

- [ ] **Step 2: Create `ClaudeUsageService.swift`**

```swift
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
```

- [ ] **Step 3: Verify it compiles in the app build**

Run: `make app`
Expected: completes with `dist/MacPulse.app` and `codesign --verify` passing (the script reports success). No compile errors referencing the new files.

- [ ] **Step 4: Smoke-test the service end-to-end (one-off, deleted after)**

Create `Sources/MacPulse/__smoke.swift` temporarily:

```swift
import Foundation
// Temporary smoke check — DELETE before committing.
let a = ClaudeUsageService.loadActivity()
print("all-time messages:", a.allTime.messages, "projects:", a.projects.count)
print("top project:", a.projects.first?.name ?? "none")
Task {
    let limits = await ClaudeUsageService.fetchLimits()
    print("limits:", limits as Any)
    exit(0)
}
RunLoop.main.run()
```

Compile + run just the logic (this confirms the keychain read, the live `/api/oauth/usage` shape, and the walk):

Run:
```bash
swiftc -O Sources/MacPulse/Shell.swift Sources/MacPulse/Formatters.swift \
  Sources/MacPulse/ClaudeUsageParser.swift Sources/MacPulse/ClaudeAuth.swift \
  Sources/MacPulse/ClaudeUsageService.swift Sources/MacPulse/__smoke.swift \
  -o .build/smoke && .build/smoke
```
Expected: prints non-zero `all-time messages` and a project name; either a populated `ClaudeLimits(...)` (approve the keychain dialog if prompted) or `nil` if Claude Code is signed out. **If `limits` is non-nil but every window is nil, the live JSON nesting differs from the assumed shape** — capture the raw body (`print(String(data: data, encoding: .utf8))` in `fetchLimits`), adjust `parseLimits` + its Task 1 test to match, and re-run `make test`.

- [ ] **Step 5: Delete the smoke file and commit**

```bash
rm Sources/MacPulse/__smoke.swift
git add Sources/MacPulse/ClaudeAuth.swift Sources/MacPulse/ClaudeUsageService.swift
git commit -m "feat(claude-usage): keychain token reader and usage I/O service"
```

---

### Task 4: AppState integration + caching

Adds the published snapshot, the refresh method (tab-open-gated + reload), and UserDefaults caching of aggregates only.

**Files:**
- Modify: `Sources/MacPulse/AppState.swift`

**Interfaces:**
- Consumes: `ClaudeUsageService.{loadActivity,fetchLimits}`, `ClaudeActivity`, `ClaudeLimits` (Tasks 1–3).
- Produces:
  - `struct ClaudeUsageSnapshot: Codable { var activity: ClaudeActivity; var limits: ClaudeLimits?; var updatedAt: Date }` (add to `ClaudeUsageParser.swift`)
  - `AppState.claudeUsage: ClaudeUsageSnapshot?` (published)
  - `AppState.claudeUsageLoading: Bool` (published)
  - `AppState.refreshClaudeUsage(force: Bool = false)`

- [ ] **Step 1: Add the snapshot type to `ClaudeUsageParser.swift`**

Append after `ClaudeActivity`:

```swift
/// What the Claude tab renders. Cached in UserDefaults — token is NEVER part of it.
struct ClaudeUsageSnapshot: Codable {
    var activity: ClaudeActivity
    var limits: ClaudeLimits?
    var updatedAt: Date
}
```

- [ ] **Step 2: Add published properties + cache key to `AppState`**

In the `// MARK: - Live data` block, after `backup`:

```swift
    @Published var claudeUsage: ClaudeUsageSnapshot?
    @Published var claudeUsageLoading = false
```

In `private enum Keys`, add:

```swift
        static let claudeUsage = "claudeUsageCacheV1"
```

Add the staleness constant near `githubInterval`:

```swift
    private static let claudeUsageStaleAfter: TimeInterval = 30
```

- [ ] **Step 3: Load the cache in `init()`**

After the existing GitHub cache-load block in `init()`:

```swift
        if let data = defaults.data(forKey: Keys.claudeUsage),
           let cached = try? JSONDecoder().decode(ClaudeUsageSnapshot.self, from: data) {
            claudeUsage = cached
        }
```

- [ ] **Step 4: Add `refreshClaudeUsage`**

Add after `refreshGitHub(...)`:

```swift
    /// Parses local transcripts + fetches subscription limits. Tab-open-gated
    /// (skips when a recent snapshot exists) unless forced by the reload button.
    /// Only the resulting aggregates are cached — the OAuth token never is.
    func refreshClaudeUsage(force: Bool = false) {
        guard !claudeUsageLoading else { return }
        if !force, let snap = claudeUsage,
           Date().timeIntervalSince(snap.updatedAt) < Self.claudeUsageStaleAfter { return }
        claudeUsageLoading = true
        Task {
            let activity = await Task.detached(priority: .utility) {
                ClaudeUsageService.loadActivity()
            }.value
            let limits = await ClaudeUsageService.fetchLimits()
            let snapshot = ClaudeUsageSnapshot(activity: activity, limits: limits, updatedAt: Date())
            self.claudeUsage = snapshot
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: Keys.claudeUsage)
            }
            self.claudeUsageLoading = false
        }
    }
```

- [ ] **Step 5: Verify it compiles**

Run: `make app`
Expected: builds to `dist/MacPulse.app` with no errors.

- [ ] **Step 6: Commit**

```bash
git add Sources/MacPulse/AppState.swift Sources/MacPulse/ClaudeUsageParser.swift
git commit -m "feat(claude-usage): AppState snapshot, refresh, and aggregate caching"
```

---

### Task 5: Claude tab UI + RootView wiring

Renders limit gauges, activity stats, the per-project list, and a reload button; refreshes on appear.

**Files:**
- Create: `Sources/MacPulse/Views/ClaudeUsageView.swift`
- Modify: `Sources/MacPulse/Views/RootView.swift`

**Interfaces:**
- Consumes: `AppState.{claudeUsage,claudeUsageLoading,refreshClaudeUsage}` (Task 4); `MetricBar`, `StatTile`, `SectionHeader` (existing `Components.swift`); `Fmt.{until,ago}`.

- [ ] **Step 1: Create `ClaudeUsageView.swift`**

```swift
import SwiftUI

struct ClaudeUsageView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let snap = state.claudeUsage {
                limitsSection(snap.limits)
                Divider()
                activitySection(snap.activity)
                Divider()
                projectsSection(snap.activity.projects)
            } else if state.claudeUsageLoading {
                Text("Reading Claude Code usage…").font(.caption).foregroundColor(.secondary)
            } else {
                Text("No usage data yet.").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(12)
        .onAppear { state.refreshClaudeUsage() }
    }

    private var header: some View {
        HStack {
            SectionHeader(title: "Claude Code")
            Spacer()
            if let snap = state.claudeUsage {
                Text("updated \(Fmt.ago(snap.updatedAt))")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Button { state.refreshClaudeUsage(force: true) } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(state.claudeUsageLoading)
            .help("Reload usage now")
        }
    }

    @ViewBuilder
    private func limitsSection(_ limits: ClaudeLimits?) -> some View {
        if let limits {
            VStack(alignment: .leading, spacing: 8) {
                limitRow("5-hour", limits.fiveHour)
                limitRow("7-day", limits.sevenDay)
                limitRow("Weekly", limits.weekly)
            }
        } else {
            Text("Limits unavailable — is Claude Code signed in?")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func limitRow(_ label: String, _ window: LimitWindow?) -> some View {
        if let window, let pct = window.percent {
            VStack(alignment: .leading, spacing: 2) {
                MetricBar(label: label, valueText: String(format: "%.0f%%", pct),
                          percent: pct, warnAt: 75, critAt: 90)
                if let resets = window.resetsAt {
                    Text("resets in \(Fmt.until(resets))")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
    }

    private func activitySection(_ a: ClaudeActivity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Activity")
            HStack(spacing: 8) {
                StatTile(value: "\(a.today.messages)", label: "today")
                StatTile(value: "\(a.last7.messages)", label: "7 days")
                StatTile(value: "\(a.last30.messages)", label: "30 days")
                StatTile(value: "\(a.allTime.messages)", label: "all-time")
            }
            HStack(spacing: 8) {
                StatTile(value: "\(a.allTime.sessions)", label: "sessions")
                StatTile(value: "\(a.allTime.toolCalls)", label: "tool calls")
                StatTile(value: tokens(a.allTime), label: "tokens")
            }
        }
    }

    private func projectsSection(_ projects: [ProjectActivity]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "By project")
            if projects.isEmpty {
                Text("No project activity found.").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(projects.prefix(8)) { p in
                    HStack {
                        Text(p.name).font(.caption).lineLimit(1)
                        Spacer()
                        Text("\(p.messages) msg").font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    /// Compact total-token count, e.g. "1.2M" / "340K".
    private func tokens(_ b: ActivityBucket) -> String {
        let total = b.inputTokens + b.outputTokens
        if total >= 1_000_000 { return String(format: "%.1fM", Double(total) / 1_000_000) }
        if total >= 1_000 { return "\(total / 1_000)K" }
        return "\(total)"
    }
}
```

- [ ] **Step 2: Add the tab to `RootView.swift`**

In `enum Tab`, add a case (after `backups`):

```swift
        case claude = "Claude"
```

In the `switch tab` block, add a case:

```swift
                    case .claude: ClaudeUsageView()
```

(The `Picker`'s `ForEach(Tab.allCases…)` and the `switch` both pick up the new case automatically. Five tabs and one switch remain well under the ViewBuilder 10-child cap.)

- [ ] **Step 3: Build and verify the tab renders**

Run: `make run`
Expected: app launches; the menu-bar popover shows a new "Claude" segment. Opening it shows limit gauges (or "Limits unavailable…" if signed out — approve the keychain dialog the first time), activity tiles, and the per-project list. The reload button refreshes "updated Xs ago".

- [ ] **Step 4: Commit**

```bash
git add Sources/MacPulse/Views/ClaudeUsageView.swift Sources/MacPulse/Views/RootView.swift
git commit -m "feat(claude-usage): Claude tab with limit gauges, activity, and per-project breakdown"
```

---

### Task 6: Full verification + docs

Final gate: full suite, signed build, secret scan, and documentation.

**Files:**
- Modify: `CLAUDE.md` (add a bullet under Architecture for the Claude usage tab)
- Modify: `README.md` (mention the Claude tab in the feature list)

- [ ] **Step 1: Run the full test suite**

Run: `make test`
Expected: `N passed, 0 failed`.

- [ ] **Step 2: Build the signed release bundle**

Run: `make app`
Expected: `dist/MacPulse.app` produced; codesign verification passes.

- [ ] **Step 3: Confirm no secrets are committed**

Run: `git log -p -5 | grep -iE "accessToken|sk-ant|Bearer [A-Za-z0-9]" || echo "clean"`
Expected: `clean` (the token is read at runtime and never written to source, tests, or cache).

- [ ] **Step 4: Document the feature in `CLAUDE.md`**

Add a bullet in the Architecture section (after the Backups tab bullet):

```markdown
- **Claude tab reads local transcripts + one usage call.** `ClaudeUsageService.loadActivity()`
  walks `~/.claude/projects/**/*.jsonl` (assistant turns only) and the pure, tested
  `ClaudeUsageParser` aggregates per-day/per-project activity; `fetchLimits()` GETs
  `https://api.anthropic.com/api/oauth/usage` for the 5-hour/7-day/weekly utilization.
  **Security boundary:** the OAuth token is read in-memory from the keychain
  (`Claude Code-credentials`) via `ClaudeAuth` — never persisted; only the utilization
  %s and counts are cached (`claudeUsageCacheV1`). Refresh is tab-open-gated + manual
  reload, like the popover-gated `ps` scan. `ClaudeUsageParser` is in the
  `scripts/test.sh` pure-logic list.
```

- [ ] **Step 5: Document the feature in `README.md`**

Add a line to the user-facing feature list (matching the existing style) describing the Claude tab: subscription-limit gauges (5h/7d/weekly + reset countdowns), activity stats, and per-project breakdown, with a reload button.

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: document the Claude Code usage tab"
```

---

## Self-Review notes

- **Spec coverage:** subscription limits (Tasks 1, 3, 5) ✓; per-project breakdown (Tasks 2, 3, 5) ✓; activity stats today/7d/30d/all-time (Tasks 2, 5) ✓; reload button + "updated Xs ago" (Task 5) ✓; tab-open + reload refresh model (Task 4) ✓; in-memory keychain token, aggregates-only cache (Tasks 3, 4) ✓; pure/IO boundary + `scripts/test.sh` (Tasks 1–3) ✓; graceful not-signed-in state (Tasks 3, 5) ✓.
- **Type consistency:** `ClaudeLimits`/`LimitWindow`/`UsageRecord`/`ActivityBucket`/`ProjectActivity`/`ClaudeActivity`/`ClaudeUsageSnapshot` defined once (Tasks 1–4) and consumed with the same names/signatures in service, AppState, and view. `loadActivity`/`fetchLimits`/`refreshClaudeUsage`/`decodeRecord`/`activity(byProject:now:)`/`parseLimits`/`Fmt.until` names match across tasks.
- **Open risk handled inline:** the live `/api/oauth/usage` JSON nesting is confirmed against a real response in Task 3 Step 4, with explicit instructions to adjust `parseLimits` + its test if the shape differs.
