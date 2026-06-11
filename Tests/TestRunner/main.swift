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

// MARK: - LinkedInAnalyzer

print("LinkedInAnalyzer")

func fullProfile() -> LinkedInProfile {
    LinkedInProfile(
        profileURL: "linkedin.com/in/test",
        headline: "Senior Web Developer · WordPress & headless builds for SMEs",
        about: String(repeating: "Shipped 30+ client sites with measurable results. ", count: 12),
        hasPhoto: true,
        hasBanner: true,
        hasCustomURL: true,
        connections: 800,
        skillsCount: 20,
        experienceCount: 3,
        educationCount: 1,
        featuredCount: 2,
        recommendationsCount: 3,
        postsPerMonth: 4
    )
}

do {
    let analysis = LinkedInAnalyzer.analyze(LinkedInProfile())
    expectEq(analysis.totalPoints, 0, "empty profile scores zero")
    expectEq(analysis.grade, "F", "empty profile grades F")
    expect(!analysis.topTips.isEmpty, "empty profile produces tips")
}

do {
    let analysis = LinkedInAnalyzer.analyze(fullProfile())
    expectEq(analysis.totalPoints, analysis.maxPoints, "full profile hits maximum")
    expectEq(analysis.maxPoints, 100, "max points is 100")
    expectEq(analysis.grade, "A", "full profile grades A")
    expect(analysis.topTips.isEmpty, "full profile has no tips")
}

do {
    var profile = fullProfile()
    profile.headline = "Developer"
    let analysis = LinkedInAnalyzer.analyze(profile)
    let headline = analysis.sections.first { $0.name == "Headline" }
    expectEq(headline?.points, 5, "short headline gets partial credit")
    expect(headline?.tip != nil, "short headline produces a tip")
}

do {
    var profile = fullProfile()
    profile.about = String(repeating: "Passionate developer who loves clean code. ", count: 15)
    let analysis = LinkedInAnalyzer.analyze(profile)
    let about = analysis.sections.first { $0.name == "About" }
    expectEq(about?.points, 15, "about without numbers capped at 15")
    expect(about?.tip != nil, "capped about suggests quantified results")
}

do {
    var profile = fullProfile()
    profile.hasPhoto = false
    profile.hasBanner = false
    let analysis = LinkedInAnalyzer.analyze(profile)
    expectEq(analysis.totalPoints, 85, "missing photo+banner costs 15 points")
    expectEq(analysis.grade, "B", "85 points grades B")
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

// MARK: - Summary

print(String(repeating: "─", count: 40))
print("\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
