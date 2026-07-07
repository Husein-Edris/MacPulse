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

// New failure-visibility fields (added to status.json by the collector). All optional;
// older files without them must still decode (covered by the partial-payload test above).
let backupJSONv2 = """
{"generated_at":"2026-06-22T12:09:35+0200","overall":"warn",
 "backups":{"projects":{"loaded":true,"last_exit":0,"last_run":"2026-06-21 13:08:38","ran_today":false,
   "schedule":"13:00","last_attempt":"2026-06-21 13:07:56","last_success":"2026-06-21 13:08:38",
   "run_state":"idle","archived":1,"failed":2,"db_failed":1,"covered":51,"never_backed":3,
   "project_folders":52,"size_today":"—","db_dumps_today":0,"drive_readable":true},
   "claude":{"loaded":true,"last_exit":0,"last_run":"2026-06-22 12:00:08","ran_today":true,
     "last_attempt":"2026-06-22 12:00:00","last_success":"2026-06-22 12:00:08","schedule":"12:00","drive_copies":7}},
 "security":{"high":1,"scanned":14},
 "drill":{"status":"ok","checked":"2026-06-21 15:06:23","detail":"ok","stale":true,
   "decrypt_ok":true,"file_count":120,"live_count":119,"pct":99,"db_ok":true},
 "disk":{"mac_free":"26Gi","mac_used_pct":"84%","drive_backup_used":"6.1G","ssd_mounted":false,
   "ssd_free":"—","ssd_last":"2026-05-28","ssd_stale_days":25},
 "events":[
   {"epoch":1782047183,"time":"2026-06-21 15:06:23","source":"drill","level":"fail","msg":"restore drill FAILED: x"},
   {"epoch":1782050000,"time":"2026-06-21 15:53:20","source":"projects","level":"warn","msg":"3 projects never backed up"}
 ]}
"""

do {
    let s = BackupParser.parse(Data(backupJSONv2.utf8))
    expect(s != nil, "v2 status.json decodes")
    let pj = s?.backups?.projects
    expectEq(pj?.dbFailed, 1, "db_failed parsed")
    expectEq(pj?.neverBacked, 3, "never_backed parsed")
    expectEq(pj?.runState, "idle", "run_state parsed")
    expectEq(pj?.lastSuccess, "2026-06-21 13:08:38", "projects last_success parsed")
    expectEq(pj?.lastAttempt, "2026-06-21 13:07:56", "projects last_attempt parsed")
    expectEq(s?.backups?.claude?.ranToday, true, "claude ran_today parsed")
    expectEq(s?.backups?.claude?.lastSuccess, "2026-06-22 12:00:08", "claude last_success parsed")
    expectEq(s?.drill?.stale, true, "drill stale parsed")
    expectEq(s?.drill?.decryptOk, true, "drill decrypt_ok parsed")
    expectEq(s?.drill?.fileCount, 120, "drill file_count parsed")
    expectEq(s?.drill?.liveCount, 119, "drill live_count parsed")
    expectEq(s?.drill?.pct, 99, "drill pct parsed")
    expectEq(s?.drill?.dbOk, true, "drill db_ok parsed")
    expectEq(s?.disk?.ssdLast, "2026-05-28", "disk ssd_last parsed")
    expectEq(s?.disk?.ssdStaleDays, 25, "disk ssd_stale_days parsed")
    expectEq(s?.events?.count, 2, "events array parsed")
    expectEq(s?.events?.first?.source, "drill", "event source parsed")
    expectEq(s?.events?.first?.level, "fail", "event level parsed")
    expectEq(s?.events?.first?.epoch, 1782047183, "event epoch parsed")
}

do {
    // brokenReasons mirrors the dashboard's failing-reason list.
    let s = BackupParser.parse(Data(backupJSONv2.utf8))!
    let reasons = BackupParser.brokenReasons(s)
    let texts = reasons.map(\.text)
    expect(texts.contains { $0.contains("2 project backups failed") }, "failed>0 reason present")
    expect(texts.contains { $0.contains("1 database dump failed") }, "db_failed>0 reason present")
    expect(texts.contains { $0.contains("3 projects never backed up") }, "never_backed>0 reason present")
    expect(texts.contains { $0.contains("projects-backup hasn't run today") }, "projects not-run-today reason present")
    expect(!texts.contains { $0.contains("claude-backup hasn't run today") }, "claude ran today → no reason")
    expect(texts.contains { $0.contains("restore drill stale") }, "drill stale (status ok) → warn reason")
    expect(!texts.contains { $0.contains("restore drill failed") }, "drill ok → no fail reason")
    expect(texts.contains { $0.contains("SSD backup is 25 days old") }, "ssd_stale_days>=14 reason present")
    expect(texts.contains { $0.contains("1 secret found") }, "security.high>0 reason present")
}

do {
    // Healthy status → no broken reasons (using the original warn fixture's ok parts isn't
    // enough; build a clean one explicitly).
    let healthy = """
    {"backups":{"projects":{"failed":0,"db_failed":0,"never_backed":0,"ran_today":true},
      "claude":{"ran_today":true}},
     "security":{"high":0},"drill":{"status":"ok","stale":false},"disk":{"ssd_stale_days":2}}
    """
    let s = BackupParser.parse(Data(healthy.utf8))!
    expect(BackupParser.brokenReasons(s).isEmpty, "fully-healthy status has no broken reasons")
}

do {
    // sortedEvents must return newest-first by epoch even when input is out of order.
    let json = """
    {"events":[
      {"epoch":100,"source":"a","level":"warn","msg":"old"},
      {"epoch":300,"source":"b","level":"fail","msg":"new"},
      {"epoch":200,"source":"c","level":"warn","msg":"mid"}
    ]}
    """
    let s = BackupParser.parse(Data(json.utf8))!
    let sorted = BackupParser.sortedEvents(s, limit: 6)
    expectEq(sorted.count, 3, "all three events returned")
    expectEq(sorted[0].epoch, 300, "newest event first")
    expectEq(sorted[2].epoch, 100, "oldest event last")
    expectEq(BackupParser.sortedEvents(s, limit: 2).count, 2, "event limit respected")
    expect(BackupParser.sortedEvents(BackupParser.parse(Data("{}".utf8))!).isEmpty, "no events → empty list")
}

// MARK: - ProcessParser

print("ProcessParser")

do {
    let out = """
      PID %CPU %MEM COMM
     1234 12.5  3.2 /Applications/cmux.app/Contents/MacOS/cmux
       42  0.0  0.1 tar
     garbage line here
        0  9.9  9.9 kernel_task
    """
    let items = ProcessParser.parse(out)
    expectEq(items.count, 2, "parses two valid rows")
    expectEq(items[0].pid, 1234, "first pid parsed")
    expectEq(items[0].name, "cmux", "name resolved to friendly app name")
    expectEq(items[0].rawName, "/Applications/cmux.app/Contents/MacOS/cmux", "raw path retained")
    expectEq(items[0].cpuPercent, 12.5, "cpu parsed")
    expectEq(items[1].name, "tar", "second row name parsed")
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

// MARK: - ProcessNamer

print("ProcessNamer")

do { // real app path resolves to the outermost .app name
    let l = ProcessNamer.label(for: "/Applications/cmux.app/Contents/MacOS/cmux")
    expectEq(l.name, "cmux", "app bundle name from path")
    expectEq(l.safety, ProcessSafety.safe, "user app is safe to quit")
}

do { // nested helper/renderer collapses to the parent app + a hint
    let raw = "/Applications/Brave Browser.app/Contents/Frameworks/Brave Browser Framework.framework/Versions/1/Helpers/Brave Browser Helper (Renderer).app/Contents/MacOS/Brave Browser Helper (Renderer)"
    let l = ProcessNamer.label(for: raw)
    expectEq(l.name, "Brave Browser", "outermost .app wins over nested helper .app")
    expectEq(l.detail, "a browser tab", "renderer helper detail")
    expectEq(l.safety, ProcessSafety.safe, "browser tab is safe to quit")
}

do { // known daemon by basename hits the dictionary
    let l = ProcessNamer.label(for: "/System/Library/CoreServices/WindowServer")
    expectEq(l.name, "macOS display engine", "WindowServer friendly name")
    expectEq(l.safety, ProcessSafety.system, "WindowServer is a system process")
}

do { // Spotlight indexing family
    expectEq(ProcessNamer.label(for: "/usr/libexec/mds_stores").name, "Spotlight indexing", "mds_stores friendly name")
    expectEq(ProcessNamer.label(for: "mdworker_shared").name, "Spotlight indexing", "mdworker friendly name")
}

do { // WebKit content process has no user .app, resolved by reverse-DNS id
    let l = ProcessNamer.label(for: "com.apple.WebKit.WebContent")
    expectEq(l.name, "Safari web page", "WebKit content friendly name")
    expectEq(l.detail, "a browser tab", "WebKit content detail")
}

do { // unknown reverse-DNS id falls back to a cleaned basename
    let l = ProcessNamer.label(for: "com.apple.somethingunknownd")
    expectEq(l.name, "somethingunknownd", "strips com.apple. prefix on fallback")
    expectEq(l.safety, ProcessSafety.caution, "unknown process is caution")
}

do { // bare short name with no path is kept as-is
    expectEq(ProcessNamer.label(for: "tar").name, "tar", "bare basename kept")
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
    ctx.swapUsedGB = 0.3
    expect(!ImprovementsEngine.evaluate(ctx).contains { $0.id == "swap" }, "light swap is not flagged")
    ctx.swapUsedGB = 1.5
    let elevated = ImprovementsEngine.evaluate(ctx).first { $0.id == "swap" }
    expectEq(elevated?.severity, .info, "elevated swap is info")
    ctx.swapUsedGB = 5.0
    ctx.topRAMProcessName = "Brave"
    ctx.topRAMProcessPct = 9.1
    let heavy = ImprovementsEngine.evaluate(ctx).first { $0.id == "swap" }
    expectEq(heavy?.severity, .warning, "heavy swap is a warning")
    expect(heavy?.detail.contains("Brave") == true, "swap finding names the biggest consumer")
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

expectEq(Fmt.swapLevel(usedGB: 0.4), .ok, "a little swap is healthy")
expectEq(Fmt.swapLevel(usedGB: 1.0), .elevated, "1 GB swap is elevated")
expectEq(Fmt.swapLevel(usedGB: 2.9), .elevated, "under 3 GB stays elevated")
expectEq(Fmt.swapLevel(usedGB: 3.0), .heavy, "3 GB+ swap is heavy paging")

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

// MARK: - CPUHistory

print("CPUHistory")

do {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    var h = CPUHistory(window: 60, spikeThreshold: 80, spikeCooldown: 30, maxSpikes: 3)

    // Sampling + windowing
    h.addSample(percent: 10, at: t0)
    h.addSample(percent: 20, at: t0.addingTimeInterval(30))
    h.addSample(percent: 95, at: t0.addingTimeInterval(61))   // t0 (age 61s) now outside 60s window
    expectEq(h.samples.count, 2, "samples older than window are dropped")
    expectEq(h.samples.first?.percent ?? 0, 20, "oldest retained sample is the 20% one")
    expectEq(h.peakPercent, 95, "peak reflects retained window")
}

do {
    let t0 = Date(timeIntervalSince1970: 2_000_000)
    var h = CPUHistory(window: 900, spikeThreshold: 80, spikeCooldown: 30, maxSpikes: 3)

    // Threshold gating
    expect(!h.shouldCaptureSpike(percent: 79.9, at: t0), "below threshold does not capture")
    expect(h.shouldCaptureSpike(percent: 80, at: t0), "at threshold captures when never fired")

    h.recordSpike(SpikeEvent(date: t0, cpuPercent: 90,
                             processes: [ProcessItem(pid: 1, name: "node", cpuPercent: 88, memPercent: 0)]))
    expect(!h.shouldCaptureSpike(percent: 95, at: t0.addingTimeInterval(10)), "within cooldown suppresses capture")
    expect(h.shouldCaptureSpike(percent: 95, at: t0.addingTimeInterval(30)), "cooldown elapsed re-arms capture")
    expectEq(h.lastSpikeCaptureAt, t0, "cooldown clock tracks last capture")
}

do {
    let t0 = Date(timeIntervalSince1970: 3_000_000)
    var h = CPUHistory(window: 900, spikeThreshold: 80, spikeCooldown: 0, maxSpikes: 2)
    for i in 0..<4 {
        h.recordSpike(SpikeEvent(date: t0.addingTimeInterval(Double(i)), cpuPercent: 90,
                                 processes: [ProcessItem(pid: Int32(i), name: "p\(i)", cpuPercent: 90, memPercent: 0)]))
    }
    expectEq(h.spikes.count, 2, "spike buffer capped at maxSpikes")
    expectEq(h.recentSpikes.first?.topProcess?.name ?? "", "p3", "recentSpikes is newest-first")
    expectEq(h.spikes.first?.topProcess?.name ?? "", "p2", "oldest spikes evicted first")
}

// MARK: - EventLog

print("EventLog")

do {
    // A fixed instant: 2026-07-07 12:55:04 UTC. formatLine renders in UTC so the
    // test is timezone-stable.
    let date = Date(timeIntervalSince1970: 1_783_428_904)
    let cpu = EventLog.formatLine(kind: .cpu, percent: 87, name: "node", at: date)
    expectEq(cpu, "2026-07-07 12:55:04  CPU 87%  node", "cpu line format")
    let mem = EventLog.formatLine(kind: .mem, percent: 76, name: "Safari web page", at: date)
    expectEq(mem, "2026-07-07 12:55:04  MEM 76%  Safari web page", "mem line format")
}

// MARK: - Summary

print(String(repeating: "─", count: 40))
print("\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
