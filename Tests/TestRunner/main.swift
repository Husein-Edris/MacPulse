import Foundation

// Self-contained test runner. XCTest isn't available with Command Line Tools
// alone, so this compiles the pure-logic sources together with plain asserts.
// Run via: make test

var passed = 0
var failed = 0

func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    if condition() {
        passed += 1
    } else {
        failed += 1
        print("  ✗ FAIL: \(label)")
    }
}

func expectEq<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    if actual == expected {
        passed += 1
    } else {
        failed += 1
        print("  ✗ FAIL: \(label) — got \(actual), expected \(expected)")
    }
}

// MARK: - GitHubParser

print("GitHubParser")

do {
    // Calendar parsing — attribute order varies on GitHub, cover both
    let html = """
    <h2>1,234 contributions in the last year</h2>
    <td data-date="2026-06-08" data-level="0"></td>
    <td data-level="2" data-date="2026-06-09"></td>
    <td data-date="2026-06-10" id="d2" data-level="3"></td>
    <td data-date="2026-06-11" data-level="1"></td>
    <td data-date="2026-06-12" data-level="4"></td>
    """
    let stats = GitHubParser.parseContributions(html: html, todayISO: "2026-06-11")
    expectEq(stats.totalYear, 1234, "parses comma-separated yearly total")
    expect(stats.activeToday, "detects activity today")
    expectEq(stats.streakDays, 3, "streak counts 9th–11th, ignores future cell")
    expectEq(stats.activeDaysLast7, 3, "active days in last 7")
}

do {
    let html = """
    <td data-date="2026-06-09" data-level="2"></td>
    <td data-date="2026-06-10" data-level="3"></td>
    <td data-date="2026-06-11" data-level="0"></td>
    """
    let stats = GitHubParser.parseContributions(html: html, todayISO: "2026-06-11")
    expect(!stats.activeToday, "no activity today detected")
    expectEq(stats.streakDays, 2, "today-without-commits doesn't break streak")
}

do {
    let html = """
    <td data-date="2026-06-08" data-level="3"></td>
    <td data-date="2026-06-09" data-level="0"></td>
    <td data-date="2026-06-10" data-level="2"></td>
    <td data-date="2026-06-11" data-level="1"></td>
    """
    let stats = GitHubParser.parseContributions(html: html, todayISO: "2026-06-11")
    expectEq(stats.streakDays, 2, "gap breaks streak")
}

do {
    let html = """
    <tool-tip>3 contributions on June 9th.</tool-tip>
    <tool-tip>No contributions on June 10th.</tool-tip>
    <tool-tip>5 contributions on June 11th.</tool-tip>
    """
    let stats = GitHubParser.parseContributions(html: html, todayISO: "2026-06-11")
    expectEq(stats.totalYear, 8, "total falls back to tooltip sum")
}

do {
    let json = Data(#"{"login":"x","public_repos":16,"followers":42}"#.utf8)
    let user = GitHubParser.parseUser(data: json)
    expectEq(user?.repos, 16, "parses public_repos")
    expectEq(user?.followers, 42, "parses followers")
}

do {
    let json = Data("""
    [
      {"id":"1","type":"PushEvent","repo":{"name":"u/my-repo"},
       "payload":{"commits":[{"message":"fix: bug\\nbody"}]},
       "created_at":"2026-06-11T08:00:00Z"},
      {"id":"2","type":"PullRequestEvent","repo":{"name":"u/other"},
       "payload":{"action":"closed","pull_request":{"title":"Add feature"}},
       "created_at":"2026-06-10T08:00:00Z"},
      {"id":"3","type":"CreateEvent","repo":{"name":"u/third"},
       "payload":{"ref_type":"branch","ref":"feat-x"},
       "created_at":"2026-06-09T08:00:00Z"}
    ]
    """.utf8)
    let events = GitHubParser.parseEvents(data: json)
    expectEq(events.count, 3, "parses three events")
    expectEq(events[0].message, "fix: bug", "push event uses first commit line")
    expectEq(events[0].repo, "my-repo", "repo name strips owner")
    expectEq(events[1].message, "PR closed: Add feature", "PR event message")
    expectEq(events[2].message, "Create branch feat-x", "create event message")
    expect(events[0].date != nil, "parses ISO8601 created_at")
}

do {
    let items = (0..<10).map {
        #"{"id":"\#($0)","type":"WatchEvent","repo":{"name":"u/r"},"payload":{}}"#
    }
    let json = Data("[\(items.joined(separator: ","))]".utf8)
    expectEq(GitHubParser.parseEvents(data: json, limit: 5).count, 5, "event limit respected")
}

do {
    // Authenticated events feed carries a top-level "public" flag and full repo name.
    let json = Data("""
    [
      {"id":"1","type":"PushEvent","public":false,"repo":{"name":"me/secret-app"},
       "payload":{"commits":[{"sha":"abc123","message":"feat: private work\\nbody"}]},
       "created_at":"2026-06-12T08:00:00Z"},
      {"id":"2","type":"PushEvent","public":true,"repo":{"name":"me/MacPulse"},
       "payload":{"commits":[{"sha":"def456","message":"docs: readme"}]},
       "created_at":"2026-06-11T08:00:00Z"},
      {"id":"3","type":"WatchEvent","public":true,"repo":{"name":"me/other"},"payload":{}}
    ]
    """.utf8)
    let commits = GitHubParser.parseRecentCommits(data: json, limit: 10)
    expectEq(commits.count, 2, "only PushEvents become commits")
    expectEq(commits[0].repo, "secret-app", "repo short name")
    expect(commits[0].isPrivate, "private push flagged private")
    expectEq(commits[0].message, "feat: private work", "first commit line only")
    expectEq(commits[0].url, "https://github.com/me/secret-app/commit/abc123", "commit URL built")
    expect(!commits[1].isPrivate, "public push not private")
}
do {
    let json = Data(#"{"total_private_repos":7,"owned_private_repos":5}"#.utf8)
    expectEq(GitHubParser.parsePrivateRepos(data: json), Optional(7), "reads total_private_repos")
    expectEq(GitHubParser.parsePrivateRepos(data: Data("{}".utf8)), nil, "absent private repo count is nil")
}

// MARK: - BackupParser

print("BackupParser")

let backupJSON = """
{"generated_at":"2026-06-12T08:25:45+0200","overall":"warn",
 "backups":{"projects":{"loaded":true,"last_exit":0,"last_run":"2026-06-11 17:02:43","ran_today":false,
   "schedule":"13:00","failed":0,"covered":53,"project_folders":53,"size_today":"","db_dumps_today":0,"drive_readable":true,
   "stale":[{"project":"x","last":"2026-06-11"}]},
   "claude":{"loaded":true,"last_exit":0,"schedule":"12:00","drive_copies":7}},
 "security":{"high":0,"scanned":40},
 "github":{"on_github":30,"local_only":23,"drifted":[]},
 "drill":{"status":"ok","checked":"2026-06-11 19:52:51","detail":"all good"},
 "disk":{"mac_free":"19Gi","mac_used_pct":"85%","drive_backup_used":"12G","ssd_mounted":false,"ssd_free":"—"}}
"""

do {
    let s = BackupParser.parse(Data(backupJSON.utf8))
    expect(s != nil, "parses status.json")
    expectEq(s?.overall, "warn", "overall parsed")
    expectEq(s?.backups?.projects?.covered, 53, "covered parsed")
    expectEq(s?.backups?.projects?.loaded, true, "projects loaded parsed")
    expectEq(s?.backups?.claude?.driveCopies, 7, "claude drive copies parsed")
    expectEq(s?.security?.high, 0, "security high parsed")
    expectEq(s?.drill?.status, "ok", "drill status parsed")
    expectEq(s?.disk?.macUsedPct, "85%", "disk percent parsed")
    expectEq(s?.disk?.ssdMounted, false, "ssd mounted parsed")
}

do {
    let s = BackupParser.parse(Data(backupJSON.utf8))!
    let gen = BackupParser.generatedDate(s)!
    expectEq(BackupParser.isStale(s, now: gen.addingTimeInterval(3600)), false, "fresh within 26h not stale")
    expectEq(BackupParser.isStale(s, now: gen.addingTimeInterval(30 * 3600)), true, "older than 26h is stale")
    expectEq(BackupParser.effectiveOverall(s, now: gen.addingTimeInterval(3600)), "warn", "fresh keeps reported overall")
    expectEq(BackupParser.effectiveOverall(s, now: gen.addingTimeInterval(30 * 3600)), "fail", "stale forces fail")
}

do {
    // Partial/garbage payloads must decode (or fail) without crashing.
    expect(BackupParser.parse(Data("{}".utf8)) != nil, "empty object still decodes")
    expect(BackupParser.parse(Data("not json".utf8)) == nil, "garbage returns nil")
    let partial = BackupParser.parse(Data(#"{"overall":"ok"}"#.utf8))
    expectEq(partial?.backups?.projects?.covered, nil, "missing nested fields stay nil")
    expect(BackupParser.isStale(partial!, now: Date()), "missing timestamp counts as stale")
}

// MARK: - ProcessParser

print("ProcessParser")

do {
    let out = """
      PID %CPU %MEM COMM
     1234 12.5  3.2 Google Chrome Helper
       42  0.0  0.1 launchd
     garbage line here
        0  9.9  9.9 kernel_task
    """
    let items = ProcessParser.parse(out)
    expectEq(items.count, 2, "parses two valid rows")
    expectEq(items[0].pid, 1234, "first pid parsed")
    expectEq(items[0].name, "Google Chrome Helper", "comm keeps internal spaces")
    expectEq(items[0].cpuPercent, 12.5, "cpu parsed")
    expectEq(items[1].name, "launchd", "second row name parsed")
    expectEq(items[1].memPercent, 0.1, "mem parsed")
}

do { // header row is always dropped
    expectEq(ProcessParser.parse("  PID %CPU %MEM COMM\n  1 1.0 1.0 init").count, 1, "drops header, keeps one row")
}

do { // malformed rows are skipped for distinct reasons
    expectEq(ProcessParser.parse("h\n  garbage line here").count, 0, "row with fewer than 4 columns skipped")
    expectEq(ProcessParser.parse("h\n   0  9.9  9.9 kernel_task").count, 0, "pid 0 (kernel_task) skipped")
    expectEq(ProcessParser.parse("h\n  x  1.0  1.0 name").count, 0, "non-numeric pid skipped")
}

// MARK: - LargeFileRanker

print("LargeFileRanker")

do {
    let files = [
        LargeFile(path: "/a", sizeBytes: 50_000_000),
        LargeFile(path: "/b", sizeBytes: 300_000_000),
        LargeFile(path: "/c", sizeBytes: 150_000_000),
    ]
    let top = LargeFileRanker.top(files, minBytes: 100_000_000, limit: 10)
    expectEq(top.count, 2, "drops files under the threshold")
    expectEq(top[0].path, "/b", "biggest first")
    expectEq(top[1].path, "/c", "second biggest next")
}
do {
    let files = (0..<5).map { LargeFile(path: "/f\($0)", sizeBytes: Int64(200_000_000 + $0)) }
    expectEq(LargeFileRanker.top(files, minBytes: 0, limit: 3).count, 3, "limit caps the result")
}

// MARK: - ImprovementsEngine

print("ImprovementsEngine")

func healthyContext() -> ImprovementContext {
    var ctx = ImprovementContext()
    ctx.cpuPercent = 12
    ctx.ramPercent = 55
    ctx.diskPercent = 40
    ctx.diskFreeGB = 150
    ctx.uptimeDays = 2
    ctx.security = SecurityStatus(firewall: true, fileVault: true, sip: true, gatekeeper: true)
    return ctx
}

do {
    expect(ImprovementsEngine.evaluate(healthyContext()).isEmpty, "healthy system has no findings")
}

do {
    var ctx = healthyContext()
    ctx.diskPercent = 93
    ctx.diskFreeGB = 16
    let items = ImprovementsEngine.evaluate(ctx)
    expectEq(items.first?.id, "disk-critical", "93% disk is the top finding")
    expectEq(items.first?.severity, .critical, "93% disk is critical")
}

do {
    var ctx = healthyContext()
    ctx.security?.firewall = false
    let items = ImprovementsEngine.evaluate(ctx)
    expect(items.contains { $0.id == "firewall" && $0.severity == .critical }, "firewall off is critical")
}

do {
    var ctx = healthyContext()
    ctx.ramPercent = 91
    ctx.topRAMProcessName = "Brave"
    ctx.topRAMProcessPct = 8.2
    let ram = ImprovementsEngine.evaluate(ctx).first { $0.id == "ram" }
    expect(ram != nil, "high RAM produces a finding")
    expect(ram?.detail.contains("Brave") == true, "high RAM names top process")
}

do {
    var ctx = healthyContext()
    ctx.uptimeDays = 21
    let items = ImprovementsEngine.evaluate(ctx)
    expectEq(items.count, 1, "long uptime is the only finding")
    expectEq(items.first?.severity, .info, "long uptime is info severity")
}

do {
    var ctx = healthyContext()
    ctx.uptimeDays = 30
    ctx.ramPercent = 88
    ctx.security?.fileVault = false
    let severities = ImprovementsEngine.evaluate(ctx).map(\.severity)
    expectEq(severities, severities.sorted(), "results sorted by severity")
}

do {
    var ctx = healthyContext()
    ctx.trashMB = nil
    expect(!ImprovementsEngine.evaluate(ctx).contains { $0.id == "trash" }, "trash not reported when unscanned")
    ctx.trashMB = 4_096
    expect(ImprovementsEngine.evaluate(ctx).contains { $0.id == "trash" }, "big trash reported after scan")
}

// MARK: - Formatters

print("Fmt")

expectEq(Fmt.gb(UInt64(16 * 1_073_741_824)), "16.0", "bytes to GB")
expectEq(Fmt.uptime(86_400 * 13 + 3_600 * 4), "13d 4h", "uptime days+hours")
expectEq(Fmt.uptime(125 * 60), "2h 5m", "uptime hours+minutes")

expectEq(Fmt.sampleInterval(onBattery: false), 5, "AC power samples every 5s")
expectEq(Fmt.sampleInterval(onBattery: true), 12, "battery stretches the sample interval")

expectEq(Fmt.menuBarMetrics(cpuPercent: 8, ramPercent: 61, diskPercent: 85,
                            showCPU: true, showRAM: true, showDisk: true),
         [MenuMetric(label: "CPU", value: "8%"), MenuMetric(label: "RAM", value: "61%"), MenuMetric(label: "SSD", value: "85%")],
         "menu bar shows all three metrics labelled CPU/RAM/SSD")
expectEq(Fmt.menuBarMetrics(cpuPercent: 8.4, ramPercent: 61, diskPercent: 85,
                            showCPU: true, showRAM: false, showDisk: false),
         [MenuMetric(label: "CPU", value: "8%")], "menu bar CPU-only, rounded")
expectEq(Fmt.menuBarMetrics(cpuPercent: 8, ramPercent: 61, diskPercent: 85,
                            showCPU: false, showRAM: true, showDisk: true),
         [MenuMetric(label: "RAM", value: "61%"), MenuMetric(label: "SSD", value: "85%")], "menu bar respects disabled CPU")
expectEq(Fmt.menuBarMetrics(cpuPercent: 8, ramPercent: 61, diskPercent: 85,
                            showCPU: false, showRAM: false, showDisk: false),
         [], "menu bar empty when all metrics off")

// MARK: - Summary

print(String(repeating: "─", count: 40))
print("\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
