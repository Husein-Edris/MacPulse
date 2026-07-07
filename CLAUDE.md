# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

MacPulse — a native SwiftUI menu bar app (macOS 13+) showing system health
(with live CPU/RAM/disk readouts in the menu bar), a GitHub dashboard, a backup
monitor, and rule-based improvement tips. Zero third-party dependencies; ~560 KB
app bundle. The README covers features and user-facing docs; this file covers
what will bite you when editing.

## Commands

```bash
make test      # compile + run the assert-based test suite (~30s)
make app       # release build → dist/MacPulse.app (signed ad-hoc, hardened runtime)
make run       # build and launch from dist/
make install   # build and copy to /Applications (or ~/Applications)
make clean
```

There is no "run a single test" — the suite is one binary (`Tests/TestRunner/main.swift`)
that runs in a few seconds. To iterate on one area, comment out other sections locally.

## The build gotcha (read this first)

**This machine has Command Line Tools only — no Xcode.** CLT's SwiftPM fails with
`xcrun: unable to lookup item 'PlatformPath'`, and XCTest is unavailable. Therefore:

- `swift build` / `swift test` DO NOT WORK here. The Makefile drives `swiftc` directly
  (`scripts/bundle.sh`, `scripts/test.sh`). `Package.swift` exists only for machines
  with full Xcode.
- Tests use a homegrown assert runner (`expect`/`expectEq` in `Tests/TestRunner/main.swift`),
  not XCTest. `scripts/test.sh` compiles ONLY the pure-logic sources (currently
  `GitHubParser`, `ProcessParser`, `FileScanner`, `BackupStatus`, `ImprovementsEngine`,
  `SecurityAudit`, `Shell`, `Formatters`) — if you add a new logic file that tests
  reference, add it to the file list in `scripts/test.sh`.
- Swift is 5.8 / SDK 13.3: no `@Observable` macro (use `ObservableObject`), no bare
  `/regex/` literals (code uses `NSRegularExpression`), ViewBuilder still caps at
  10 children (wrap in `Group` — this has already broken the build once).

## Architecture

One-way flow: services sample/fetch → `AppState` (single `@MainActor ObservableObject`)
publishes → SwiftUI views render. Views never call services directly.

- **Pure logic vs I/O is a hard boundary.** `GitHubParser`, `ImprovementsEngine`, and
  the `Fmt` helpers are pure functions with no networking/filesystem — that's what
  makes them testable without XCTest. Keep new logic on the pure side and inject data.
- **`AppState` owns all timers and caching policy**: the cheap kernel sample
  (`refreshSystem()`, CPU/RAM/disk for the menu bar) is **battery-aware** —
  `Fmt.sampleInterval(onBattery:)` returns 5s on AC, 12s on battery, and
  `scheduleSystemTimer()` self-reschedules when the power source flips. The expensive
  `ps` process scan is **popover-gated**: `RootView` `.onAppear`/`.onDisappear` call
  `AppState.popoverDidOpen/Close`, which start/stop a separate `processTimer`, so it
  only runs while the popover is open. GitHub refreshes every 15 min (cached in
  UserDefaults so the UI has data on relaunch), security audit every 30 min, storage
  and large-file scans only on user demand. Blocking work runs in `Task.detached`,
  results assigned back on `@MainActor`.
- **`SystemMonitor` reads the kernel directly** (`host_statistics`, `vm_statistics64`,
  `sysctl`) — RAM uses Activity Monitor's formula (internal − purgeable + wired +
  compressed), disk uses `volumeAvailableCapacityForImportantUsage` to match Finder.
  Don't replace these with `df`/`top` parsing; values would stop matching macOS UI.
  `PowerSource` (IOKit) supplies the AC-vs-battery flag that drives the sample interval.
- **CPU % needs two tick samples** — `SystemMonitor` keeps `previousTicks` state and
  double-samples on first call. It is NOT safe to call `sample()` concurrently, so
  `refreshSystem()` is guarded by an `isSampling` flag to prevent overlapping runs.
- **Process control is pure-parse + syscall.** `SystemMonitor.sampleProcesses` runs
  `ps -Aeo pid,pcpu,pmem,comm -r -ww` (full executable paths, NOT `-c` short names);
  the pure, tested `ProcessParser` parses it and calls the pure, tested `ProcessNamer`
  to turn each raw path into a human-readable name plus a plain-language `detail` and a
  `ProcessSafety` verdict (`ProcessItem` carries `name`/`rawName`/`detail`/`safety`/`pid`).
  `ProcessControl.terminate(pid:force:)` calls the `kill(2)` syscall directly (SIGTERM,
  or SIGKILL when forced) and maps `EPERM` to a friendly `notPermitted` failure so
  root-owned processes fail gracefully, never escalating to sudo.
- **Overview event log.** `EventLog` (pure tested `formatLine` + off-main, serialized
  `append` under a `writeQueue`) records high-CPU/high-memory events to
  `~/Library/Logs/MacPulse/events.log`; `AppState` writes on the CPU-spike path and a
  high-memory path (RAM >= 85%, 5-min cooldown), and the Overview has an "Open log file"
  button. Timestamps are UTC by design. `ProcessNamer` and `EventLog` are both in the
  `scripts/test.sh` pure-logic list (only `EventLog.formatLine` is tested; `append` is I/O).
- **Large-file scan is I/O walk + pure ranker.** `FileScanner.scanLargeFiles` walks the
  home folder (skipping `~/Library`, hidden dirs, and symlinks) for files ≥100 MB;
  the pure, tested `LargeFileRanker` sorts and caps the results. Keep the ranking logic
  on the pure side.
- **GitHub data is unauthenticated by default** (security: nothing to leak). The
  contributions total relies on a tooltip-sum fallback because GitHub's HTML fragment
  no longer ships the "N contributions in the last year" headline. If GitHub changes
  the `data-date`/`data-level` markup, `GitHubParser.parseContributions` is the only
  place to fix.
- **Optional auth borrows the `gh` CLI token in memory only.** `GitHubAuth` shells out
  to `gh auth token`; the token is never written to disk. When signed in, MacPulse hits
  the authenticated events feed (private + public) for the Recent Commits list and
  private repo count. **Security boundary:** private commit details and the authenticated
  events feed are stripped via `redactedForCache()` before the snapshot is persisted —
  only public-safe aggregates reach UserDefaults. The cache key is `githubSnapshotCacheV2`
  (bumped from v1 so older caches with no redaction are discarded). Everything still works
  fully unauthenticated if `gh` isn't logged in.
- **Backups tab reads a local file, not the network.** `BackupService.load()` reads
  `~/Projects/backup-automation/web/data/status.json` (the same JSON that repo's
  `collect-status.sh` writes and its web dashboard renders); decoding + staleness live in
  the pure, tested `BackupParser`/`BackupStatus`. The public dashboard URL is login-gated and
  serves the raw JSON as 403, so the local file is the correct source. All `BackupStatus`
  fields are optional so a partial/older status.json still decodes; unknown keys are ignored.
  `BackupLocations` resolves the Google Drive `projects-backup`/`claude-backups` folders
  (via a CloudStorage glob — no hardcoded email), the SSD, and the launchd log paths so the
  Backups tab can reveal them in Finder (buttons disabled when a destination isn't mounted).
- **Claude tab reads local transcripts + one usage call.** `ClaudeUsageService.loadActivity()`
  walks `~/.claude/projects/**/*.jsonl` (assistant turns only) and the pure, tested
  `ClaudeUsageParser` aggregates per-day/per-project activity; `fetchLimits()` GETs
  `https://api.anthropic.com/api/oauth/usage` for the 5-hour/7-day/weekly utilization.
  **Security boundary:** the OAuth token is read in-memory from the keychain
  (`Claude Code-credentials`) via `ClaudeAuth` — never persisted; only the utilization
  %s and counts are cached (`claudeUsageCacheV1`). Refresh is tab-open-gated + manual
  reload, like the popover-gated `ps` scan. `ClaudeUsageParser` is in the
  `scripts/test.sh` pure-logic list.
- **Menu-bar readout** is `MenuBarLabel` in `MacPulseApp.swift`. `Fmt.menuBarMetrics(...)`
  (pure, tested) decides which `MenuMetric`s show; `MenuBarRenderer.image(...)` draws them
  Stats-style — a small label stacked above each value — as a **template** `NSImage` so the
  menu bar tints it for light/dark. Three independent `AppState` toggles drive it
  (`menuBarCPU/menuBarRAM/menuBarDisk`); the CPU one persists under the legacy
  `showCPUInMenuBar` key so existing installs keep their preference. `MenuBarRenderer` uses
  AppKit, so it's not in the `scripts/test.sh` pure-logic list — verify its output by
  rendering to a PNG (see the menu-bar preview approach), not via the unit runner.

## Conventions

- No third-party dependencies — that's a feature (size, security, supply chain).
- System binaries are called with absolute paths and array args via `Shell.run`
  (never a shell string — no injection surface).
- `legacy/` holds the retired Bash dashboard this app replaced. Don't touch it.
- `logs/` is leftover data from the legacy scripts, gitignored.

<!-- handover:status -->
**Current status:** Practical Overview (friendly process names, safe-quit hints + Reveal/Activity actions, MB/GB sizes, CPU/memory event log) shipped and pushed to origin/main (merge 741a45b). **Next:** see HANDOVER.md.
<!-- /handover:status -->
