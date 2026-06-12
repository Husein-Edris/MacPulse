# HANDOVER — MacPulse

## Goal
Turn the old Bash terminal monitor (`monitoring/`) into a functional, optimized, secure macOS desktop app showing system health (CPU/RAM/storage/improvements), GitHub stats, and LinkedIn profile analysis; rename the project properly and publish to GitHub. **This is done.** Any new session is for follow-ups/polish only.

## Status
- [x] Project renamed: `~/Projects/monitoring` → `~/Projects/MacPulse`
- [x] Native SwiftUI menu bar app built (Swift 5.8, macOS 13+, zero third-party deps, 436 KB)
- [x] 3 tabs: Overview (CPU/RAM/disk/processes/security audit), GitHub, Tips (improvements engine + storage scan). (LinkedIn analyzer removed 2026-06-12.)
- [x] Menu bar shows live CPU/RAM/disk readouts (Stats-app style), each toggleable in Settings (2026-06-12)
- [x] Settings: GitHub username, CPU-in-menu-bar toggle, launch-at-login (SMAppService)
- [x] Tests: 44/44 passing via custom runner (`make test`)
- [x] Signed (ad-hoc + hardened runtime), installed to `/Applications/MacPulse.app`, verified running in menu bar (⌁ icon + CPU %)
- [x] Published: https://github.com/Husein-Edris/MacPulse (public, branch `main`, commit `01e1a4c`)
- [ ] Nothing in-progress. Possible future: app icon (.icns), popover UI walkthrough/screenshots for README, GitHub release with .app zip, notarization (needs paid Apple ID)

## Key files & changes
- `Sources/MacPulse/AppState.swift` — central @MainActor ObservableObject; all timers (system 5s, GitHub 15min, security 30min) + UserDefaults caching/settings
- `Sources/MacPulse/SystemMonitor.swift` — kernel reads: host_statistics CPU ticks (needs 2 samples, keeps state, not concurrency-safe), vm_statistics64 RAM (Activity Monitor formula), volumeAvailableCapacityForImportantUsage disk (matches Finder), one `ps` call for processes
- `Sources/MacPulse/GitHubParser.swift` — pure, tested; contributions total uses tooltip-sum fallback (live GitHub HTML has NO "N contributions in the last year" headline — verified live)
- Menu-bar readout: `MenuBarLabel` in `MacPulseApp.swift` + pure `Fmt.menuBar(...)` + `AppState.menuBarCPU/RAM/Disk` toggles (CPU persists under legacy `showCPUInMenuBar` key)
- `Sources/MacPulse/ImprovementsEngine.swift` — pure rules (disk/RAM/CPU/uptime/security/cache sizes)
- `Sources/MacPulse/Views/*` — RootView (tabs+footer), Overview/GitHub/Tips/Settings, Components
- `scripts/bundle.sh`, `scripts/test.sh`, `Makefile` — swiftc-direct build (see constraints)
- `Packaging/Info.plist` — LSUIElement=true, bundle id `com.edrishusein.macpulse`
- `legacy/` — old bash scripts + old README, preserved, don't touch
- `CLAUDE.md` — rewritten for the Swift app (read it; it has the gotchas)

## Decisions & constraints (non-obvious)
- **No Xcode on this Mac, CLT only (Swift 5.8 / SDK 13.3).** `swift build`/`swift test` FAIL (`PlatformPath` xcrun error); XCTest unavailable. Build = `swiftc` direct via Makefile. Package.swift kept only for Xcode machines.
- Swift 5.8 limits: no `@Observable`, no bare regex literals (NSRegularExpression used), ViewBuilder 10-child cap (already broke build once — use `Group`).
- Tests = homegrown expect/expectEq runner compiling ONLY pure-logic files; new logic files must be added to `scripts/test.sh` file list.
- GitHub: deliberately unauthenticated (nothing to leak); ephemeral URLSession; 60 req/h rate limit is fine at 15-min refresh.
- Zero third-party deps is a feature (user asked for optimized size + security). Intel x86_64 Mac, macOS 15.7.
- User rules: no AI co-author in commits; `feat:`-style messages; never commit unless told (publishing was explicitly requested this session).

## Next steps
None required. If user asks for more, likely candidates in order of value:
1. App icon: generate PNG → `iconutil` → .icns, add CFBundleIconFile, rebuild
2. README screenshots of the popover (open via menu bar click; osascript needs accessibility permission — was denied)
3. `gh release create v1.0.0` with zipped dist/MacPulse.app
4. Sparkle-less auto-update is out of scope (no deps rule)

## Open questions / blockers
- osascript lacks assistive access → couldn't screenshot the open popover; user has visually working menu bar item (verified by screenshot of menu bar: ⌁ 8%)
- Another stats app already runs in the user's menu bar (SSD/CPU/RAM items) — MacPulse coexists; user may want to retire one

## How to verify
```bash
cd ~/Projects/MacPulse
make test                                  # 44 passed, 0 failed
make app                                   # → dist/MacPulse.app (436K), codesign verify passes
ps aux | grep -v grep | grep MacPulse.app  # running from /Applications
gh repo view Husein-Edris/MacPulse         # public repo, main branch
```
