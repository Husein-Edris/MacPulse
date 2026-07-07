# Practical Overview: human-readable processes, safe cleanup, event log

Date: 2026-07-07
Status: approved (design), not yet implemented

## Problem

The Overview tab is meant to answer one non-technical question: "what is hogging
my Mac, and how do I deal with it?" Today it fails that for two reasons:

1. Process names are cryptic. `ps -c ... comm` emits truncated accounting names
   (`assistant_ser`, `com.apple.WebKit.WebContent`, `com.apple.W...`), which mean
   nothing to a human. This affects both the CPU and the Memory lists.
2. There is no plain-language guidance on what a heavy process is, whether it is
   safe to close, or how to act on it beyond a bare Quit menu. There is also no
   persisted record of "what spiked" to look back at.

## Goals

- Show human-readable names for the top CPU and memory processes.
- For a heavy process, explain in one line what it is and whether it is safe to
  quit, and offer safe actions (Quit, Force Quit, Reveal in Finder, Open in
  Activity Monitor).
- Persist a rolling event log of high-CPU / high-memory events and expose an
  "Open log file" button.

## Non-goals

- No cache/junk deletion, no memory "purge", no `sudo` escalation. Root-owned
  quits continue to fail gracefully (friendly `notPermitted` message), exactly as
  today.
- No new networking. Everything here is local (a `ps` call, string logic, one
  local log file).

## Architecture

Follows the existing one-way flow and the hard pure-logic / I-O boundary:

- Pure, unit-tested: `ProcessNamer` (new), the event-log line formatter.
- I/O: the `ps` invocation change in `SystemMonitor`, `EventLog` file writes,
  and the AppKit buttons (`NSWorkspace`).

### 1. Friendly names: `ProcessNamer` (pure, tested)

New pure module `Sources/MacPulse/ProcessNamer.swift`. Input is the raw
executable string from `ps`; output is a label:

```swift
enum ProcessSafety { case safe, caution, system }   // safe to quit? / leave alone

struct ProcessLabel: Equatable {
    let name: String        // "Brave Browser", "Spotlight indexing", "cmux"
    let detail: String?     // "a browser tab", "background indexing"
    let safety: ProcessSafety
}

enum ProcessNamer {
    static func label(for raw: String) -> ProcessLabel
}
```

Resolution order (all pure string logic, no syscalls):

1. Path contains `.app/`: use the OUTERMOST `.app` component's name as the app
   display name. `/Applications/Brave Browser.app/.../Helpers/Brave Browser
   Helper (Renderer).app/Contents/MacOS/Brave Browser Helper (Renderer)` resolves
   to "Brave Browser". Helper/renderer executables (name contains "Helper",
   "(Renderer)", "(GPU)", etc.) append a "(tab)" / "(helper)" hint and keep
   `safety: .safe`.
2. Curated dictionary keyed by executable basename or reverse-DNS id, for
   daemons and helpers that have no user-facing `.app`. Supplies `name`,
   `detail`, and `safety`. Seed entries (extendable):
   - `WindowServer` -> "macOS display engine", detail "draws everything on
     screen", `.system`
   - `kernel_task` -> "macOS CPU manager", detail "protects the CPU from
     overheating", `.system`
   - `mds`, `mds_stores`, `mdworker` -> "Spotlight indexing", detail "building
     search index", `.caution`
   - `com.apple.WebKit.WebContent` -> "Safari web page", detail "a browser tab",
     `.safe`
   - `com.apple.WebKit.GPU`, `com.apple.WebKit.Networking` -> "Safari (helper)",
     `.safe`
   - `assistantd`, `assistant_service` -> "Siri / Suggestions", `.caution`
   - `photoanalysisd` -> "Photos analysis", `.caution`
   - `backupd` -> "Time Machine backup", `.caution`
3. Fallback: cleaned basename (strip a leading `com.apple.` and similar
   reverse-DNS prefix, keep the last component), `detail: nil`,
   `safety: .caution`.

`ProcessItem` gains the derived fields so downstream views and the spike history
render friendly text with no extra lookups:

```swift
struct ProcessItem: Identifiable, Equatable {
    let pid: Int32
    let name: String         // now the friendly name
    let rawName: String      // original ps string, kept for the log + debugging
    let detail: String?
    let safety: ProcessSafety
    let cpuPercent: Double
    let memPercent: Double
    var id: Int32 { pid }
}
```

### 2. I/O change: `SystemMonitor.sampleProcesses`

Switch the `ps` command from `["-Aceo", "pid,pcpu,pmem,comm", "-r"]` to
`["-Aeo", "pid,pcpu,pmem,comm", "-r", "-ww"]`. Dropping `-c` makes `comm` the
full executable path; `-ww` disables width truncation so long paths survive the
pipe. Verified against live output:

```
15779  99.5  2.7 /Applications/Brave Browser.app/.../MacOS/Brave Browser Helper (Renderer)
 2835  88.0  1.2 /Applications/cmux.app/Contents/MacOS/cmux
16329  83.3  0.2 /usr/local/Cellar/python@3.14/.../Python.app/Contents/MacOS/Python
12472  75.1  0.0 tar
```

`ProcessParser.parse` keeps its `maxSplits: 3` split (paths and app names may
contain spaces) and, for each row, calls `ProcessNamer.label(for:)` to fill the
friendly fields while retaining `rawName`. Parser stays pure; it just gains a
call into another pure module.

### 3. Overview UI

`Sources/MacPulse/Views/OverviewView.swift`:

- Top-3 CPU and Top-3 memory rows (`processRow(icon:items:isCPU:)`) show the
  friendly `name`. Memory rows show an approximate size next to the name derived
  from `memPercent * totalRAM` (e.g. "Brave Browser 390 MB") instead of a bare
  percentage; CPU rows keep the percentage.
- Expanded per-process rows (`processRow(_:)` in the "All processes" disclosure
  and `spikeProcessRow(_:)`) gain:
  - a one-line `detail` under the name when present,
  - a colored safety hint: `.safe` -> "Safe to close" (secondary/green),
    `.caution` -> "Close only if you know it" (orange), `.system` -> "System
    process, leave running" (secondary), and
  - an actions menu extended from {Quit, Force Quit} to also include Reveal in
    Finder and Open in Activity Monitor.
- New actions are thin `NSWorkspace` / `Shell` calls on `AppState`
  (`revealInFinder(_:)`, `openInActivityMonitor(_:)`), resolving the process path
  from `rawName`. Reveal is disabled when the path is not a real file (daemons
  with no `.app`).
- ViewBuilder 10-child cap: the added detail/safety lines wrap inside the
  existing per-row `VStack`, so no new top-level children are introduced. Verify
  the build (this cap has bitten the project before).

### 4. Event log + "Open log file"

New `Sources/MacPulse/EventLog.swift` (I/O writer) plus a pure line formatter:

- File: `~/Library/Logs/MacPulse/events.log` (macOS-idiomatic; Console.app reads
  it). Directory created on first write.
- Trigger: `AppState.maybeCaptureSpike` already fires on a threshold crossing
  with a cooldown. Extend that path to also append an event line, and add a
  parallel high-memory trigger (memory percent over a threshold, same cooldown
  style) so the log is not CPU-only.
- Line format (pure `EventLog.formatLine(...)`, tested):
  `2026-07-07 12:55:04  CPU 87%  node` and
  `2026-07-07 12:40:11  MEM 76%  Safari web page`. Timestamp is passed in (no
  clock inside the pure function), matching the `CPUHistory` no-internal-clock
  convention.
- Rolling cap: before/after append, trim the file to the last ~2000 lines so it
  never grows unbounded.
- Button: an "Open log file" control in the Overview footer row (near refresh /
  settings), calling `NSWorkspace.shared.open(url)`. Disabled until the file
  exists.

## Data flow

`SystemMonitor.sampleProcesses` (ps, I/O) -> `ProcessParser.parse` +
`ProcessNamer.label` (pure) -> `ProcessSnapshot` -> `AppState.processes`
(@MainActor) -> `OverviewView` rows. On a threshold crossing,
`AppState.maybeCaptureSpike` -> `EventLog.append` (I/O) writes a line formatted by
the pure `EventLog.formatLine`.

## Error handling

- `ps` failure: unchanged (returns an empty snapshot).
- `ProcessNamer`: total function, always returns a label; unknown input hits the
  fallback branch.
- `EventLog` write failure (permissions, disk): swallowed silently after logging
  to stderr; the log is a convenience, never load-bearing. The "Open log file"
  button stays disabled if the file is absent.
- Quit of a root-owned process: unchanged `notPermitted` friendly message.

## Testing

Added to `Tests/TestRunner/main.swift`:

- `ProcessNamer`: real app path -> app name; nested helper/renderer -> parent app
  + hint; known daemon basename -> dictionary label + safety; unknown ->
  cleaned-fallback with `.caution`; `com.apple.`-prefixed id -> cleaned.
- `EventLog.formatLine`: CPU and MEM lines format as specified for a fixed date.

`scripts/test.sh` compile list gains `ProcessNamer.swift` and `EventLog.swift`.
`EventLog.swift` imports only Foundation (no AppKit), so it compiles into the
test binary; tests call the pure `EventLog.formatLine(...)` only. The file
writer/rotation (`EventLog.append`) is exercised by running the app, not by the
unit runner.

Not unit-tested (I/O / AppKit, verified by running `make app` and using the app):
the `ps` change, `EventLog` file writes/rotation, and the new buttons.

## Build / verification notes

- CLT only, no Xcode: use the Makefile (`make test`, `make app`, `make install`),
  never `swift build` / `swift test`.
- After `make install`, launch `/Applications/MacPulse.app` (opening
  `dist/MacPulse.app` activates the old installed copy with the same bundle id).
- Swift 5.8 constraints: `ObservableObject` (no `@Observable`),
  `NSRegularExpression` (no bare regex literals), ViewBuilder 10-child cap.

## Rollout / files

New: `ProcessNamer.swift`, `EventLog.swift`,
`docs/superpowers/specs/2026-07-07-practical-overview-process-names-design.md`.
Changed: `ProcessParser.swift`, `SystemMonitor.swift`, `AppState.swift`,
`Views/OverviewView.swift`, `Tests/TestRunner/main.swift`, `scripts/test.sh`.
