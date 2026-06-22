# MacPulse — Claude Code Usage Tab (design)

Date: 2026-06-22
Status: approved (design); pending implementation plan

## Goal

Add a new "Claude" tab to MacPulse showing the user's Claude Code usage, with a
manual reload button. Three things, in priority order:

1. **Subscription limit %** — how much of the 5-hour, 7-day, and weekly plan
   limits is consumed, and when each resets. Requires a network call.
2. **Per-project breakdown** — which projects account for the most activity.
3. **Activity stats** — messages / sessions / tool calls over today / 7d / 30d /
   all-time. Token totals surfaced as a secondary stat (free from the same parse).

Plus a prominent **Reload** button ("updated Xs ago").

Not in scope: dollar-cost estimation as a headline (tokens are shown, cost is
not), editing or managing the Claude account, anything that writes to
`~/.claude`.

## Data sources (all verified)

### 1. Subscription limits — `GET https://api.anthropic.com/api/oauth/usage`

Confirmed present in the Claude Code CLI binary (`/api/oauth/usage`). Auth is the
OAuth bearer token plus `anthropic-beta: oauth-2025-04-20`. The response carries
windows named `five_hour`, `seven_day`, `seven_day_oauth_apps`, and `weekly`,
each with a `utilization` value (0–1) and a `resets_at` timestamp. (Exact JSON
shape to be confirmed against a live response during implementation; the parser
decodes defensively with all fields optional, like `BackupParser`.)

### 2 + 3. Activity & per-project — `~/.claude/projects/<encoded-project>/*.jsonl`

Each transcript line is a JSON object with `type` (`assistant`/`user`/…),
`timestamp`, `sessionId`, the model, and — on assistant messages — a `usage`
object (`input_tokens`, `output_tokens`, `cache_*`). The **folder name encodes
the project path** (e.g. `-Users-edrishusein-Projects-MacPulse`), so per-project
grouping is just per-folder. ~307 files on this machine; some are multi-MB.

`~/.claude/stats-cache.json` exists but lags (last computed weeks ago), so
activity is computed fresh from the JSONL rather than read from the cache.

### Token access

The OAuth token lives in the macOS keychain under service
`Claude Code-credentials` (`claudeAiOauth.accessToken`, with `expiresAt` and
`subscriptionType`). MacPulse reads it the same in-memory-only way it borrows the
`gh` token today:

```
Shell.run("/usr/bin/security", ["find-generic-password", "-s",
          "Claude Code-credentials", "-w"])
```

then JSON-parses out `claudeAiOauth.accessToken`. The token is **never written to
disk**. First read triggers the standard macOS keychain "allow access" dialog
once. If the token is missing or expired (401), the tab shows a graceful
"Claude Code not signed in" state — MacPulse never refreshes the token (that is
Claude Code's job). This mirrors `GitHubAuth`'s graceful-degradation pattern.

## Architecture

Follows MacPulse's existing one-way flow and the hard pure-logic / I-O boundary.

### Pure (added to `scripts/test.sh`, tested via the assert runner)

`ClaudeUsageParser.swift`:

- `parseLimits(_ data: Data) -> ClaudeLimits?` — decodes the `/api/oauth/usage`
  body into windows. Defensive decoding (all fields optional).
- `decodeRecord(_ line: String) -> UsageRecord?` — one JSONL line → a minimal
  record (`timestamp`, `type`, `sessionId`, `model`, optional token counts).
  Returns nil for blank/garbage lines.
- `aggregate(_ records: [UsageRecord], project: String, now: Date) -> [ProjectActivity]`
  / a top-level `aggregate(...)` that rolls per-project records into
  `ClaudeActivity` with today / 7d / 30d / all-time buckets (message count,
  session count, tool-call count, token totals) and a per-project list.

Models (in the parser file): `ClaudeLimits`, `LimitWindow { utilization, resetsAt }`,
`UsageRecord`, `ProjectActivity`, `ClaudeActivity`, and a `ClaudeUsageSnapshot`
combining limits + activity + `lastUpdated`.

### I/O

`ClaudeUsageService.swift`:

- `loadActivity() -> ClaudeActivity` — enumerates `~/.claude/projects/*/`,
  streams each `*.jsonl` line by line. For token counts it only JSON-decodes
  lines containing the substring `"usage"`; everything else is a cheap line/type
  scan. Feeds lines to the pure parser. Heavy — runs in `Task.detached`.
- `fetchLimits() -> ClaudeLimits?` — reads the keychain token, GETs the usage
  endpoint with the bearer + beta header, hands the body to `parseLimits`.
  Returns nil → "not signed in" state.

Token read may live in a small `ClaudeAuth.swift` (mirroring `GitHubAuth`) or be
folded into the service; decide during planning.

### State / UI

`AppState`:

- `claudeUsage: ClaudeUsageSnapshot?` (published; cached in UserDefaults so the
  tab has data on relaunch — **only** the utilization %s and counts are cached,
  never the token).
- `refreshClaudeUsage()` — runs `loadActivity()` + `fetchLimits()` off-main,
  assigns the snapshot on `@MainActor`, guarded against overlapping runs.
- **Tab-open gating** like the `ps` scan: `RootView` `.onAppear` for the Claude
  tab triggers a refresh (using the cached snapshot if recent); the reload button
  forces one. No timer (parsing 307 files is too heavy to poll).

`ClaudeUsageView.swift` (Views/):

- Limit gauges: 5-hour / 7-day / weekly, each a bar with `utilization` % and a
  reset countdown. "Not signed in" message when limits are unavailable.
- Activity summary: today / 7d / 30d / all-time messages, sessions, tool calls
  (tokens as secondary).
- Per-project list (top projects by activity), revealable like the process list.
- Reload button + "updated Xs ago".

`RootView`: add the tab (icon e.g. `sparkles`). Mind the 10-child ViewBuilder cap
— wrap in `Group` if the tab list grows past it.

## Constraints honored

- Zero third-party dependencies; system binaries via `Shell.run` (absolute path,
  array args).
- Swift 5.8 / SDK 13.3 — `ObservableObject` (no `@Observable`),
  `NSRegularExpression` (no bare regex), ViewBuilder 10-child cap.
- Build via `make test` / `make app` (CLT-only; `swift build`/`swift test` fail).
- New pure-logic file added to the `scripts/test.sh` source list.
- Security: OAuth token in memory only, never persisted; only public-to-user
  aggregates cached.

## Open questions

- Exact JSON field nesting of `/api/oauth/usage` (e.g. is it `{five_hour:
  {utilization, resets_at}}` or wrapped) — confirm against one live response
  early in implementation; defensive decoding limits the blast radius either way.
- Whether `seven_day_oauth_apps` / an Opus-specific weekly window should be shown
  separately or folded in — decide once the live shape is known.
