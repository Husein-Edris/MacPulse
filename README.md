# MacPulse

A native macOS menu bar app that keeps your machine's health and your GitHub presence one click away — with live CPU/memory/disk readouts right in the menu bar. Written in pure Swift/SwiftUI with **zero third-party dependencies** — the whole app weighs under 400 KB.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-brightgreen)
![Swift](https://img.shields.io/badge/Swift-5.8-orange)
![Dependencies](https://img.shields.io/badge/dependencies-0-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## What it shows

**Overview tab**
- CPU usage (live, read from the kernel via `host_statistics` — matches Activity Monitor)
- Memory used/total with pressure coloring (`vm_statistics64`, Activity Monitor formula)
- Storage used/free for the boot volume, purgeable-aware (matches Finder, not `df`)
- Load average, uptime, top 3 processes by CPU and by RAM
- Security audit: Firewall, FileVault, SIP, Gatekeeper — red dot when something is off

**GitHub tab**
- Contributions this year, current streak, days active this week, contributed-today flag
- Public repos, followers, last 5 public events (pushes, PRs, branches, issues)
- Public data only — no token, no login, nothing to leak

**Backups tab**
- Health of the local backup automation: overall status, the two launchd jobs (loaded state, last run, exit code), projects covered, failures, restore-drill result, tracked-secret hits, and Drive/SSD/Mac disk figures
- Reads the collector's local `status.json` directly — no network, no login, nothing leaves the Mac
- Shows a friendly empty state if the backup tooling isn't set up on this machine

**Tips tab**
- Rule-based improvement findings sorted by severity: disk almost full, RAM pressure, security features disabled, long uptime
- On-demand storage hotspot scan (Caches / Trash / Downloads sizes) with one-click reveal
- Deep links straight into the relevant System Settings pane

**Menu bar** — pick any of CPU %, memory %, and disk % to show live next to the clock (Stats-app style); toggle each in Settings. Plus a launch-at-login option.

## Install

```bash
git clone https://github.com/Husein-Edris/MacPulse.git
cd MacPulse
make install   # builds, signs, copies to /Applications
open /Applications/MacPulse.app
```

Requires macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`). No Xcode, no Homebrew, no package managers needed.

### Other targets

```bash
make test    # run the unit test suite (parsers, scoring, rules engine)
make app     # build dist/MacPulse.app without installing
make run     # build and launch from dist/
make clean
```

> Note: with Command Line Tools only, the Makefile drives `swiftc` directly because CLT's SwiftPM cannot resolve the platform path. On a machine with full Xcode, plain `swift build` also works via `Package.swift`.

## Design decisions

| Concern | Choice |
|---|---|
| Size | Single native binary, no bundled runtime — under 400 KB total vs. 100+ MB for an Electron equivalent |
| Energy | Kernel reads are microseconds; timers carry tolerance so the OS can coalesce wakeups; storage scans only run when you ask |
| Security | Hardened-runtime code signing; no tokens or credentials anywhere; GitHub fetches use an ephemeral session (no disk cache) |
| Privacy | The app makes exactly three HTTPS requests, all to github.com, all public endpoints |
| Practicality | Lives in the menu bar, one click to everything, launch-at-login toggle |

## Architecture

```
Sources/MacPulse/
├── MacPulseApp.swift      MenuBarExtra entry point
├── AppState.swift         Central ObservableObject: timers, caching, settings
├── SystemMonitor.swift    CPU/RAM/disk/uptime/processes (mach + sysctl)
├── SecurityAudit.swift    Firewall/FileVault/SIP/Gatekeeper via system CLIs
├── GitHubParser.swift     Pure parsing (unit-tested), separated from I/O
├── GitHubService.swift    Ephemeral URLSession fetches
├── BackupStatus.swift     Pure status.json model + parser (unit-tested)
├── BackupService.swift    Local status.json file read
├── MenuBarRenderer.swift  Stacked CPU/RAM/SSD menu-bar image (AppKit)
├── ImprovementsEngine.swift  Pure rules engine (unit-tested)
├── StorageScanner.swift   On-demand du-based hotspot sizing
└── Views/                 SwiftUI: Overview, GitHub, Backups, Tips, Settings
```

All business logic (parsing, scoring, rules) is pure functions with no I/O, covered by the test runner in `Tests/TestRunner`.

## History

MacPulse replaces a set of Bash monitoring scripts (terminal dashboard + cron-style daemon) that lived in this repo before; they're preserved in [`legacy/`](legacy/) with their original README.

## License

MIT
