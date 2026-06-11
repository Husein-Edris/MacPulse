# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

MacPulse — a native SwiftUI menu bar app (macOS 13+) showing system health, a
GitHub dashboard, a local LinkedIn profile analyzer, and rule-based improvement
tips. Zero third-party dependencies; ~450 KB app bundle. The README covers
features and user-facing docs; this file covers what will bite you when editing.

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
  not XCTest. `scripts/test.sh` compiles ONLY the pure-logic sources — if you add a new
  logic file that tests reference, add it to the file list in `scripts/test.sh`.
- Swift is 5.8 / SDK 13.3: no `@Observable` macro (use `ObservableObject`), no bare
  `/regex/` literals (code uses `NSRegularExpression`), ViewBuilder still caps at
  10 children (wrap in `Group` — this has already broken the build once).

## Architecture

One-way flow: services sample/fetch → `AppState` (single `@MainActor ObservableObject`)
publishes → SwiftUI views render. Views never call services directly.

- **Pure logic vs I/O is a hard boundary.** `GitHubParser`, `LinkedInAnalyzer`,
  `ImprovementsEngine` are pure functions with no networking/filesystem — that's what
  makes them testable without XCTest. Keep new logic on the pure side and inject data.
- **`AppState` owns all timers and caching policy**: system sample every 5s
  (tolerance 2s), GitHub every 15 min (cached in UserDefaults so the UI has data on
  relaunch), security audit every 30 min, storage scan only on user demand.
  Blocking work runs in `Task.detached`, results assigned back on `@MainActor`.
- **`SystemMonitor` reads the kernel directly** (`host_statistics`, `vm_statistics64`,
  `sysctl`) — RAM uses Activity Monitor's formula (internal − purgeable + wired +
  compressed), disk uses `volumeAvailableCapacityForImportantUsage` to match Finder.
  Don't replace these with `df`/`top` parsing; values would stop matching macOS UI.
- **CPU % needs two tick samples** — `SystemMonitor` keeps `previousTicks` state and
  double-samples on first call. It is NOT safe to call `sample()` concurrently.
- **GitHub data is unauthenticated by design** (security: nothing to leak). The
  contributions total relies on a tooltip-sum fallback because GitHub's HTML fragment
  no longer ships the "N contributions in the last year" headline. If GitHub changes
  the `data-date`/`data-level` markup, `GitHubParser.parseContributions` is the only
  place to fix.
- **LinkedIn is local-only** — no API exists; scraping violates LinkedIn ToS. Profile
  data is user-entered, stored in UserDefaults, analyzed offline. Don't "improve" this
  with scraping.

## Conventions

- No third-party dependencies — that's a feature (size, security, supply chain).
- System binaries are called with absolute paths and array args via `Shell.run`
  (never a shell string — no injection surface).
- LinkedIn scoring sections must sum to exactly 100 (`testFullProfileScoresMaximum`
  guards this — rebalance other sections when adding one).
- `legacy/` holds the retired Bash dashboard this app replaced. Don't touch it.
- `logs/` is leftover data from the legacy scripts, gitignored.
