# MacPulse

A native macOS menu bar app that keeps your machine, your GitHub presence, and your LinkedIn profile health in one click's reach. Written in pure Swift/SwiftUI with **zero third-party dependencies** — the whole app weighs about 450 KB.

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

**LinkedIn tab**
- Profile strength score (0–100, graded A–F) across 12 sections: photo, banner, headline, about, experience, skills, network size, featured, recommendations, activity, …
- Prioritized "biggest wins" tips
- LinkedIn has no public profile API and scraping breaks their ToS, so you enter your profile data once; analysis runs entirely offline and the data never leaves your Mac

**Tips tab**
- Rule-based improvement findings sorted by severity: disk almost full, RAM pressure, security features disabled, long uptime
- On-demand storage hotspot scan (Caches / Trash / Downloads sizes) with one-click reveal
- Deep links straight into the relevant System Settings pane

Optional: live CPU % next to the menu bar icon, and launch-at-login.

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
| Size | Single native binary, no bundled runtime — ~450 KB total vs. 100+ MB for an Electron equivalent |
| Energy | Kernel reads are microseconds; timers carry tolerance so the OS can coalesce wakeups; storage scans only run when you ask |
| Security | Hardened-runtime code signing; no tokens or credentials anywhere; GitHub fetches use an ephemeral session (no disk cache); LinkedIn analysis is fully offline |
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
├── LinkedInAnalyzer.swift Pure scoring engine (unit-tested)
├── ImprovementsEngine.swift  Pure rules engine (unit-tested)
├── StorageScanner.swift   On-demand du-based hotspot sizing
└── Views/                 SwiftUI: Overview, GitHub, LinkedIn, Tips, Settings
```

All business logic (parsing, scoring, rules) is pure functions with no I/O, covered by the test runner in `Tests/TestRunner`.

## History

MacPulse replaces a set of Bash monitoring scripts (terminal dashboard + cron-style daemon) that lived in this repo before; they're preserved in [`legacy/`](legacy/) with their original README.

## License

MIT
