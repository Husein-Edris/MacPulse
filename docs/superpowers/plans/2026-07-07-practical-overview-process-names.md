# Practical Overview: human-readable processes, safe cleanup, event log (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Overview tab readable for non-technical users: friendly process names for CPU and memory hogs, a plain-language "what is it / safe to quit" line with safe actions, and a rolling event log with an "Open log file" button.

**Architecture:** Keep the project's hard pure-logic / I-O boundary. A new pure `ProcessNamer` maps a raw executable path to a friendly `ProcessLabel`; `ProcessParser` calls it so `ProcessItem` carries friendly fields end to end. `SystemMonitor` changes its `ps` invocation to emit full executable paths. A new `EventLog` has a pure line formatter (tested) plus an I-O writer that `AppState` calls on threshold crossings. Views render the new fields.

**Tech Stack:** Swift 5.8 / SwiftUI / AppKit, no third-party dependencies, homegrown assert test runner (`Tests/TestRunner/main.swift`), Makefile-driven `swiftc` build.

## Global Constraints

- No third-party dependencies. Foundation / AppKit / SwiftUI only.
- No em dash (U+2014) anywhere in any file. Use commas, colons, parentheses. A PreToolUse hook hard-blocks writes containing one.
- Swift 5.8 / SDK 13.3: `ObservableObject` (no `@Observable`), `NSRegularExpression` (no bare `/regex/`), ViewBuilder caps at 10 children (wrap extras in `Group`).
- Build with the Makefile only: `make test`, `make app`, `make install`. `swift build` / `swift test` DO NOT WORK (CLT-only machine).
- After install, launch `/Applications/MacPulse.app` (opening `dist/MacPulse.app` runs the old installed copy, same bundle id).
- System binaries: absolute path + array args via `Shell.run`, never a shell string.
- Pure-logic files referenced by tests must be added to the `swiftc` list in `scripts/test.sh`.
- Do NOT commit unless the user explicitly says so. The commit steps below stage and commit locally; the user's standing rule is commit-only-on-explicit-OK, so treat each "Commit" step as "prepare the commit and ask" unless the user has already greenlit committing this session.
- No AI co-author / attribution in commit messages.

---

### Task 1: ProcessNamer + friendly ProcessItem fields (pure, tested)

**Files:**
- Create: `Sources/MacPulse/ProcessNamer.swift`
- Modify: `Sources/MacPulse/ProcessParser.swift`
- Modify: `Tests/TestRunner/main.swift` (ProcessParser section ~lines 285-314, and a new ProcessNamer section)
- Modify: `scripts/test.sh:8-19` (add `ProcessNamer.swift`)

**Interfaces:**
- Produces: `enum ProcessSafety: Equatable { case safe, caution, system }`
- Produces: `struct ProcessLabel: Equatable { let name: String; let detail: String?; let safety: ProcessSafety }`
- Produces: `enum ProcessNamer { static func label(for raw: String) -> ProcessLabel }`
- Produces: extended `ProcessItem` with trailing defaulted fields `rawName: String = ""`, `detail: String? = nil`, `safety: ProcessSafety = .caution` (so existing `ProcessItem(pid:name:cpuPercent:memPercent:)` call sites in tests keep compiling).

- [ ] **Step 1: Add ProcessNamer to the test compile list**

In `scripts/test.sh`, add the new file after `CPUHistory.swift` (line 18):

```sh
    Sources/MacPulse/CPUHistory.swift \
    Sources/MacPulse/ProcessNamer.swift \
    Tests/TestRunner/main.swift \
```

- [ ] **Step 2: Write the failing ProcessNamer tests**

Append a new section to `Tests/TestRunner/main.swift` (after the ProcessParser section, before the next `// MARK:`):

```swift
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with "cannot find 'ProcessNamer' in scope" (and `ProcessSafety`).

- [ ] **Step 4: Create `ProcessNamer.swift`**

```swift
import Foundation

/// How risky it is to quit a process, in plain terms.
enum ProcessSafety: Equatable {
    case safe      // a user app or browser tab; closing it just closes that thing
    case caution   // a background helper; usually fine but may interrupt something
    case system    // core macOS; leave it running
}

/// The human-readable identity of a process, derived from its raw `ps` string.
struct ProcessLabel: Equatable {
    let name: String
    let detail: String?
    let safety: ProcessSafety
}

/// Pure mapping from a raw `ps comm` value (a full executable path, or a bare
/// name / reverse-DNS id for kernel and helper processes) to a friendly label.
/// No syscalls, no I-O, so it is unit-testable without XCTest.
enum ProcessNamer {

    /// Curated dictionary for daemons and helpers that have no user-facing `.app`.
    /// Keyed by the executable basename or a reverse-DNS id (matched case-sensitively).
    private static let known: [String: ProcessLabel] = [
        "WindowServer":     ProcessLabel(name: "macOS display engine", detail: "draws everything on screen", safety: .system),
        "kernel_task":      ProcessLabel(name: "macOS CPU manager", detail: "protects the CPU from overheating", safety: .system),
        "launchd":          ProcessLabel(name: "macOS service manager", detail: "starts background services", safety: .system),
        "mds":              ProcessLabel(name: "Spotlight indexing", detail: "building the search index", safety: .caution),
        "mds_stores":       ProcessLabel(name: "Spotlight indexing", detail: "building the search index", safety: .caution),
        "mdworker":         ProcessLabel(name: "Spotlight indexing", detail: "building the search index", safety: .caution),
        "mdworker_shared":  ProcessLabel(name: "Spotlight indexing", detail: "building the search index", safety: .caution),
        "assistantd":       ProcessLabel(name: "Siri and Suggestions", detail: "on-device assistant", safety: .caution),
        "assistant_service":ProcessLabel(name: "Siri and Suggestions", detail: "on-device assistant", safety: .caution),
        "photoanalysisd":   ProcessLabel(name: "Photos analysis", detail: "scanning your photo library", safety: .caution),
        "backupd":          ProcessLabel(name: "Time Machine backup", detail: "backing up your Mac", safety: .caution),
        "com.apple.WebKit.WebContent":   ProcessLabel(name: "Safari web page", detail: "a browser tab", safety: .safe),
        "com.apple.WebKit.GPU":          ProcessLabel(name: "Safari (helper)", detail: "browser graphics", safety: .safe),
        "com.apple.WebKit.Networking":   ProcessLabel(name: "Safari (helper)", detail: "browser networking", safety: .safe),
    ]

    static func label(for raw: String) -> ProcessLabel {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        // 1. A real app: use the outermost ".app" component's base name.
        if let app = outermostAppName(in: trimmed) {
            if isBrowserRenderer(trimmed) {
                return ProcessLabel(name: app, detail: "a browser tab", safety: .safe)
            }
            if isHelper(trimmed) {
                return ProcessLabel(name: app, detail: "a helper process", safety: .safe)
            }
            return ProcessLabel(name: app, detail: nil, safety: .safe)
        }

        // 2. Known daemon / helper by basename or reverse-DNS id.
        let base = (trimmed as NSString).lastPathComponent
        if let hit = known[trimmed] ?? known[base] {
            return hit
        }

        // 3. Fallback: cleaned basename, caution.
        return ProcessLabel(name: cleaned(base), detail: nil, safety: .caution)
    }

    /// The name (without ".app") of the FIRST ".app" bundle in the path, or nil.
    private static func outermostAppName(in path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            if component.hasSuffix(".app") {
                return String(component.dropLast(4))   // strip ".app"
            }
        }
        return nil
    }

    private static func isBrowserRenderer(_ path: String) -> Bool {
        let p = path.lowercased()
        return p.contains("(renderer)") || p.contains("webcontent")
    }

    private static func isHelper(_ path: String) -> Bool {
        path.lowercased().contains("helper")
    }

    /// Strip a leading reverse-DNS prefix (com.apple., com.google., ...) so the
    /// fallback shows the meaningful tail rather than the vendor id.
    private static func cleaned(_ base: String) -> String {
        let parts = base.split(separator: ".")
        if parts.count >= 3, parts[0] == "com" || parts[0] == "org" || parts[0] == "io" {
            return String(parts.last ?? Substring(base))
        }
        return base
    }
}
```

- [ ] **Step 5: Run the ProcessNamer tests to verify they pass**

Run: `make test`
Expected: the new `ProcessNamer` assertions PASS. (ProcessParser assertions may now fail on `.name`; fixed next.)

- [ ] **Step 6: Extend `ProcessItem` and wire `ProcessParser` to `ProcessNamer`**

Replace the top of `Sources/MacPulse/ProcessParser.swift` (the `ProcessItem` struct and the `parse` body) with:

```swift
import Foundation

/// One running process. `id` is the pid so SwiftUI lists keep stable identity across refreshes.
struct ProcessItem: Identifiable, Equatable {
    let pid: Int32
    let name: String          // friendly, human-readable
    let cpuPercent: Double
    let memPercent: Double
    let rawName: String       // original ps string (full path or bare name)
    let detail: String?       // "a browser tab", "building the search index"
    let safety: ProcessSafety
    var id: Int32 { pid }

    init(pid: Int32, name: String, cpuPercent: Double, memPercent: Double,
         rawName: String = "", detail: String? = nil, safety: ProcessSafety = .caution) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memPercent = memPercent
        self.rawName = rawName
        self.detail = detail
        self.safety = safety
    }
}

struct ProcessSnapshot {
    let topCPU: [ProcessItem]
    let topRAM: [ProcessItem]
}

/// Pure parser for `ps -Aeo pid,pcpu,pmem,comm -r -ww` output, separated from the
/// subprocess call so it is unit-testable. `comm` is the full executable path and
/// may contain spaces (e.g. "/Applications/Google Chrome.app/..."), so the command
/// is the trailing remainder. Each row is named via `ProcessNamer`.
enum ProcessParser {
    static func parse(_ output: String) -> [ProcessItem] {
        var items: [ProcessItem] = []
        for line in output.split(separator: "\n").dropFirst() {       // drop the header row
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4,
                  let pid = Int32(parts[0]), pid > 0,
                  let cpu = Double(parts[1]),
                  let mem = Double(parts[2]) else { continue }
            let raw = parts[3].trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { continue }
            let label = ProcessNamer.label(for: raw)
            items.append(ProcessItem(pid: pid, name: label.name, cpuPercent: cpu,
                                     memPercent: mem, rawName: raw,
                                     detail: label.detail, safety: label.safety))
        }
        return items
    }
}
```

- [ ] **Step 7: Update the existing ProcessParser tests for full-path input**

Replace the first ProcessParser `do { ... }` block in `Tests/TestRunner/main.swift` (currently ~lines 289-304) with:

```swift
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
```

(The two later ProcessParser `do` blocks at ~lines 306-314 stay as they are.)

- [ ] **Step 8: Run the full suite to verify it passes**

Run: `make test`
Expected: PASS, 0 failed (ProcessNamer + ProcessParser sections green).

- [ ] **Step 9: Commit**

```bash
git add Sources/MacPulse/ProcessNamer.swift Sources/MacPulse/ProcessParser.swift Tests/TestRunner/main.swift scripts/test.sh
git commit -m "feat(processes): friendly process names via pure ProcessNamer"
```

---

### Task 2: Emit full executable paths from `ps`

**Files:**
- Modify: `Sources/MacPulse/SystemMonitor.swift:71`

**Interfaces:**
- Consumes: `ProcessParser.parse` (now expects full paths, Task 1).
- Produces: no signature change; `sampleProcesses` output now carries friendly names.

- [ ] **Step 1: Change the ps invocation**

In `Sources/MacPulse/SystemMonitor.swift`, replace line 71:

```swift
        guard let output = Shell.run("/bin/ps", ["-Aceo", "pid,pcpu,pmem,comm", "-r"]) else {
```

with:

```swift
        guard let output = Shell.run("/bin/ps", ["-Aeo", "pid,pcpu,pmem,comm", "-r", "-ww"]) else {
```

(Dropping `-c` makes `comm` the full executable path; `-ww` disables width truncation so long paths survive the pipe.)

- [ ] **Step 2: Verify the raw command output shape by hand**

Run: `/bin/ps -Aeo pid,pcpu,pmem,comm -r -ww | head -5`
Expected: rows whose last column is a full path like `/Applications/cmux.app/Contents/MacOS/cmux`, plus some bare names like `tar`.

- [ ] **Step 3: Build the app and confirm it compiles**

Run: `make app`
Expected: clean build, `dist/MacPulse.app` produced.

- [ ] **Step 4: Run and eyeball friendly names in Top processes**

Run: `make install && open /Applications/MacPulse.app`
Expected: the Overview "Top processes" rows show names like "cmux", "Brave Browser", "Spotlight indexing" instead of truncated ids. (No unit test: this is the I-O boundary.)

- [ ] **Step 5: Commit**

```bash
git add Sources/MacPulse/SystemMonitor.swift
git commit -m "feat(processes): read full executable paths from ps for naming"
```

---

### Task 3: Overview UI for memory size, what-is-it line, safe actions

**Files:**
- Modify: `Sources/MacPulse/AppState.swift` (add `revealInFinder`/`openInActivityMonitor` near `endProcess` ~line 199-213)
- Modify: `Sources/MacPulse/Views/OverviewView.swift` (`processRow(icon:items:isCPU:)` ~189, `processRow(_:)` ~215, `spikeProcessRow(_:)` ~166)

**Interfaces:**
- Consumes: `ProcessItem.name/detail/safety/rawName` (Task 1), `SystemSnapshot.ramTotalBytes`, `Fmt` helpers.
- Produces: `AppState.revealInFinder(_ item: ProcessItem)`, `AppState.openInActivityMonitor(_ item: ProcessItem)`, `AppState.canReveal(_ item: ProcessItem) -> Bool`; a private `OverviewView.memSizeText(_:)` helper and a `safetyHint(_:)` helper.

- [ ] **Step 1: Add reveal / Activity Monitor actions to `AppState`**

In `Sources/MacPulse/AppState.swift`, immediately after `endProcess(_:force:)` (after line 213), add:

```swift
    /// Reveals the process's executable in Finder. No-op when the raw name is not a real path.
    func revealInFinder(_ item: ProcessItem) {
        guard canReveal(item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.rawName)])
    }

    /// Opens Activity Monitor so the user can inspect the process there.
    func openInActivityMonitor(_ item: ProcessItem) {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.open(url)
    }

    /// True when Reveal in Finder can act on this process (it has a real file path).
    func canReveal(_ item: ProcessItem) -> Bool {
        item.rawName.hasPrefix("/") && FileManager.default.fileExists(atPath: item.rawName)
    }
```

If `AppState.swift` does not already `import AppKit`, add it at the top (it uses `@MainActor`/SwiftUI; add `import AppKit` only if `NSWorkspace` is unresolved at build time).

- [ ] **Step 2: Show approximate memory size in the memory Top row**

First check the available byte formatter: `grep -n "func gb\|func bytes\|func mb" Sources/MacPulse/Formatters.swift`.

In `Sources/MacPulse/Views/OverviewView.swift`, add a private helper (near the other private funcs, e.g. after `processRow(icon:items:isCPU:)`):

```swift
    /// Approximate resident size for a process, from its RAM percentage and total RAM.
    /// This is an estimate (percent of total), not exact RSS, but reads far better
    /// than a bare percentage for a non-technical user.
    private func memSizeText(_ p: ProcessItem) -> String {
        guard let total = state.system?.ramTotalBytes, total > 0 else {
            return String(format: "%.1f%%", p.memPercent)
        }
        let bytes = UInt64(Double(total) * p.memPercent / 100.0)
        return "\(Fmt.gb(bytes)) GB"
    }
```

If the grep shows a `Fmt.bytes(_:)` (or `Fmt.mb`) that already renders a scaled unit string, use that instead of `"\(Fmt.gb(bytes)) GB"` (it will read better for sub-GB values). Do not add a new formatter.

Then in `processRow(icon:items:isCPU:)`, change the value `Text` (currently ~lines 204-208) so memory rows use the size:

```swift
                    Text(isCPU
                         ? String(format: "%.0f%%", p.cpuPercent)
                         : memSizeText(p))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
```

- [ ] **Step 3: Add a safety hint helper**

In `OverviewView.swift`, add:

```swift
    /// Plain-language "is it safe to quit" hint and its colour.
    private func safetyHint(_ item: ProcessItem) -> (text: String, color: Color) {
        switch item.safety {
        case .safe:    return ("Safe to close", .secondary)
        case .caution: return ("Close only if you know it", .orange)
        case .system:  return ("System process, leave running", .secondary)
        }
    }
```

- [ ] **Step 4: Enrich the expanded per-process row**

Replace `processRow(_ proc: ProcessItem)` (~lines 215-234) with:

```swift
    private func processRow(_ proc: ProcessItem) -> some View {
        let hint = safetyHint(proc)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(proc.name).font(.caption).lineLimit(1)
                if let detail = proc.detail {
                    Text(detail).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
                Text(hint.text).font(.caption2).foregroundColor(hint.color).lineLimit(1)
            }
            Spacer()
            Text(String(format: "%.0f%%", sortByCPU ? proc.cpuPercent : proc.memPercent))
                .font(.caption.monospacedDigit()).foregroundColor(.secondary)
            Menu {
                Button("Quit") { state.endProcess(proc, force: false) }
                Button("Force Quit", role: .destructive) { state.endProcess(proc, force: true) }
                Divider()
                Button("Reveal in Finder") { state.revealInFinder(proc) }
                    .disabled(!state.canReveal(proc))
                Button("Open Activity Monitor") { state.openInActivityMonitor(proc) }
            } label: {
                Image(systemName: "xmark.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.vertical, 1)
    }
```

(The `VStack` holds at most three children, well under the ViewBuilder 10-child cap; the `Menu` content holds five including the `Divider`, also fine.)

- [ ] **Step 5: Add the same actions to spike rows**

In `spikeProcessRow(_:)` (~lines 166-186), replace the `Menu { ... } label: { ... }` block so it matches:

```swift
            Menu {
                Button("Quit") { state.endProcess(proc, force: false) }
                Button("Force Quit", role: .destructive) { state.endProcess(proc, force: true) }
                Divider()
                Button("Reveal in Finder") { state.revealInFinder(proc) }
                    .disabled(!state.canReveal(proc))
                Button("Open Activity Monitor") { state.openInActivityMonitor(proc) }
            } label: {
                Image(systemName: "xmark.circle")
            }
```

- [ ] **Step 6: Build the app**

Run: `make app`
Expected: clean build. If it fails with a ViewBuilder "extra argument" / "closure containing" error, wrap the offending group in `Group { ... }` (the 10-child cap has bitten this project before).

- [ ] **Step 7: Run and verify the UI**

Run: `make install && open /Applications/MacPulse.app`
Expected: memory Top row shows sizes (e.g. "Brave Browser 0.4 GB"); expanding "All processes" shows a detail line plus a coloured safety hint per row; the row menu lists Quit, Force Quit, Reveal in Finder (disabled for daemons with no path), Open Activity Monitor.

- [ ] **Step 8: Commit**

```bash
git add Sources/MacPulse/AppState.swift Sources/MacPulse/Views/OverviewView.swift
git commit -m "feat(overview): memory sizes, plain-language safety hints, reveal/activity actions"
```

---

### Task 4: EventLog pure formatter (tested) plus I-O writer

**Files:**
- Create: `Sources/MacPulse/EventLog.swift`
- Modify: `Tests/TestRunner/main.swift` (new EventLog section)
- Modify: `scripts/test.sh` (add `EventLog.swift`)

**Interfaces:**
- Produces: `enum EventKind: String { case cpu = "CPU", mem = "MEM" }`
- Produces: `EventLog.formatLine(kind:percent:name:at:) -> String` (pure).
- Produces: `EventLog.append(kind:percent:name:at:)` (I-O), `EventLog.fileURL: URL`, `EventLog.fileExists: Bool`.

- [ ] **Step 1: Add EventLog to the test compile list**

In `scripts/test.sh`, after the `ProcessNamer.swift` line added in Task 1:

```sh
    Sources/MacPulse/ProcessNamer.swift \
    Sources/MacPulse/EventLog.swift \
    Tests/TestRunner/main.swift \
```

- [ ] **Step 2: Write the failing EventLog formatter tests**

Append to `Tests/TestRunner/main.swift`:

```swift
// MARK: - EventLog

print("EventLog")

do {
    // A fixed instant: 2026-07-07 12:55:04 UTC. formatLine renders in UTC so the
    // test is timezone-stable.
    let date = Date(timeIntervalSince1970: 1_783_601_704)
    let cpu = EventLog.formatLine(kind: .cpu, percent: 87, name: "node", at: date)
    expectEq(cpu, "2026-07-07 12:55:04  CPU 87%  node", "cpu line format")
    let mem = EventLog.formatLine(kind: .mem, percent: 76, name: "Safari web page", at: date)
    expectEq(mem, "2026-07-07 12:55:04  MEM 76%  Safari web page", "mem line format")
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `make test`
Expected: FAIL to compile with "cannot find 'EventLog' in scope".

- [ ] **Step 4: Create `EventLog.swift`**

```swift
import Foundation

/// What kind of resource crossed a threshold.
enum EventKind: String {
    case cpu = "CPU"
    case mem = "MEM"
}

/// Rolling on-disk record of high-CPU / high-memory events, plus a pure line
/// formatter. The formatter takes an explicit `Date` and renders in UTC so it is
/// timezone-stable and unit-testable (the CPUHistory no-internal-clock convention).
/// File writes are best-effort convenience, never load-bearing.
enum EventLog {

    static let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MacPulse", isDirectory: true)
        return dir.appendingPathComponent("events.log")
    }()

    static var fileExists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    private static let maxLines = 2000

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// Pure: "2026-07-07 12:55:04  CPU 87%  node".
    static func formatLine(kind: EventKind, percent: Int, name: String, at date: Date) -> String {
        "\(formatter.string(from: date))  \(kind.rawValue) \(percent)%  \(name)"
    }

    /// Best-effort append of one event line, then trim to the last `maxLines`.
    /// Silently no-ops on any I-O error (logs to stderr for debugging).
    static func append(kind: EventKind, percent: Int, name: String, at date: Date) {
        let line = formatLine(kind: kind, percent: percent, name: name, at: date)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            let existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            var lines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if lines.last == "" { lines.removeLast() }   // drop trailing empty from the final newline
            lines.append(line)
            if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
            try (lines.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(Data("MacPulse: EventLog write failed: \(error)\n".utf8))
        }
    }
}
```

- [ ] **Step 5: Run to verify the formatter tests pass**

Run: `make test`
Expected: PASS, 0 failed (EventLog section green).

- [ ] **Step 6: Commit**

```bash
git add Sources/MacPulse/EventLog.swift Tests/TestRunner/main.swift scripts/test.sh
git commit -m "feat(eventlog): rolling event log with pure, tested line formatter"
```

---

### Task 5: Wire EventLog into triggers plus the "Open log file" button

**Files:**
- Modify: `Sources/MacPulse/AppState.swift` (`maybeCaptureSpike` ~166-185, `refreshSystem` ~147-160; add a memory-trigger cooldown near `isCapturingSpike` ~line 67)
- Modify: `Sources/MacPulse/Views/OverviewView.swift` (add an "Open log file" control at the bottom of the body ~line 111, before `.padding(12)`)

**Interfaces:**
- Consumes: `EventLog.append`, `EventLog.fileURL`, `EventLog.fileExists` (Task 4); `ProcessSnapshot.topRAM`, `SystemSnapshot.ramPercent/cpuPercent/date`.
- Produces: `AppState.openEventLog()`, `AppState.eventLogExists` (computed), a private `maybeLogMemoryEvent(_:)` with its own cooldown.

- [ ] **Step 1: Log CPU spikes to the event log**

In `Sources/MacPulse/AppState.swift`, inside `maybeCaptureSpike(_:)`, after `self.cpuHistory.recordSpike(...)` and before `self.isCapturingSpike = false` (around line 182), add a log write using the captured top process:

```swift
                if let top = procs.topCPU.first {
                    EventLog.append(kind: .cpu, percent: Int(cpu.rounded()),
                                    name: top.name, at: date)
                }
```

- [ ] **Step 2: Add a memory-event trigger**

Still in `AppState.swift`, add stored cooldown state next to `isCapturingSpike` (~line 67):

```swift
    private var lastMemoryEventAt: Date?
    private static let memoryEventThreshold = 85.0   // percent of RAM
    private static let memoryEventCooldown: TimeInterval = 300   // 5 minutes
```

In `refreshSystem()`, after `self.maybeCaptureSpike(snapshot)` (line 157), add:

```swift
                self.maybeLogMemoryEvent(snapshot)
```

Add the method right after `maybeCaptureSpike(_:)`:

```swift
    /// When RAM usage is high (and the cooldown has elapsed), record one memory
    /// event naming the current top-RAM process. Uses the already-sampled process
    /// list when the popover is open; otherwise runs one bounded `ps` scan.
    private func maybeLogMemoryEvent(_ snapshot: SystemSnapshot) {
        guard snapshot.ramPercent >= Self.memoryEventThreshold else { return }
        if let last = lastMemoryEventAt,
           snapshot.date.timeIntervalSince(last) < Self.memoryEventCooldown { return }
        lastMemoryEventAt = snapshot.date
        let monitor = self.monitor
        let date = snapshot.date
        let pct = Int(snapshot.ramPercent.rounded())
        let cached = processes.topRAM.first
        Task.detached(priority: .utility) {
            let name = cached?.name ?? monitor.sampleProcesses(top: 1).topRAM.first?.name
            guard let name else { return }
            EventLog.append(kind: .mem, percent: pct, name: name, at: date)
        }
    }
```

- [ ] **Step 3: Add `openEventLog` and `eventLogExists` to `AppState`**

Near the reveal/Activity actions from Task 3, add:

```swift
    var eventLogExists: Bool { EventLog.fileExists }

    /// Opens the event log in the user's default handler (Console.app / TextEdit).
    func openEventLog() {
        guard EventLog.fileExists else { return }
        NSWorkspace.shared.open(EventLog.fileURL)
    }
```

- [ ] **Step 4: Add the "Open log file" button to the Overview**

In `Sources/MacPulse/Views/OverviewView.swift`, at the very end of the top-level `VStack` in `body` (just before the closing brace and `.padding(12)` at ~line 112-113), add:

```swift
            Divider()

            Button {
                state.openEventLog()
            } label: {
                Label("Open log file", systemImage: "doc.text")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(!state.eventLogExists)
            .help("Open MacPulse's high CPU / memory event log")
```

If adding this pushes the top-level `VStack` past 10 direct children and the build errors, wrap the new `Divider()` plus `Button` in a `Group { ... }` (counts as one child).

- [ ] **Step 5: Build**

Run: `make app`
Expected: clean build.

- [ ] **Step 6: Verify the log end to end**

Run:
```bash
make install && open /Applications/MacPulse.app
# Drive CPU over the spike threshold to force a log write:
for i in $(seq 1 12); do ( yes > /dev/null & ); done; sleep 20; pkill -x yes
cat ~/Library/Logs/MacPulse/events.log
```
Expected: `events.log` exists and contains a `CPU NN%  <name>` line; in the app, the "Open log file" button is enabled and opens the file. (If RAM is above 85%, a `MEM` line appears too.)

- [ ] **Step 7: Commit**

```bash
git add Sources/MacPulse/AppState.swift Sources/MacPulse/Views/OverviewView.swift
git commit -m "feat(eventlog): log CPU/memory events and add Open log file button"
```

---

## Notes for the implementer

- `Fmt.bytes` vs `Fmt.gb`: check `Sources/MacPulse/Formatters.swift` before Task 3 Step 2. Use whichever byte formatter already exists; do not add a new formatter.
- `import AppKit` in `AppState.swift`: only add if `NSWorkspace`/`FileManager` fail to resolve. `AppState` is `@MainActor` and already SwiftUI-adjacent, so AppKit may already be transitively available.
- Every build must pass `make test` (currently 146 assertions plus the ~16 added here) AND `make app` cleanly before its commit.
- Do not touch `legacy/`.
```
