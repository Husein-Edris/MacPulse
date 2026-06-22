import SwiftUI

struct BackupView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Backups")
            if let b = state.backup {
                content(b)
            } else {
                missing
            }
        }
        .padding(12)
    }

    // MARK: - Loaded

    private func content(_ b: BackupStatus) -> some View {
        let now = Date()
        let overall = BackupParser.effectiveOverall(b, now: now)
        let stale = BackupParser.isStale(b, now: now)
        let pj = b.backups?.projects
        let cl = b.backups?.claude

        return VStack(alignment: .leading, spacing: 12) {
            banner(overall: overall, stale: stale)

            brokenSummary(b, overall: overall)

            Group {
                jobRow("projects-backup", loaded: pj?.loaded, exit: pj?.lastExit,
                       lastRun: pj?.lastRun, schedule: pj?.schedule,
                       runState: pj?.runState, lastSuccess: pj?.lastSuccess, lastAttempt: pj?.lastAttempt)
                jobRow("claude-backup", loaded: cl?.loaded, exit: cl?.lastExit,
                       lastRun: cl?.lastRun, schedule: cl?.schedule,
                       runState: nil, lastSuccess: cl?.lastSuccess, lastAttempt: cl?.lastAttempt)
            }

            Group {
                HStack(spacing: 8) {
                    StatTile(value: "\(pj?.covered ?? 0)/\(pj?.projectFolders ?? 0)", label: "covered")
                    StatTile(value: "\(pj?.failed ?? 0)", label: "failed",
                             accent: (pj?.failed ?? 0) > 0 ? .red : .green)
                    StatTile(value: drillTileText(b.drill), label: "restore drill",
                             accent: drillTileColor(b.drill))
                }
                HStack(spacing: 8) {
                    StatTile(value: "\(pj?.neverBacked ?? 0)", label: "never backed",
                             accent: (pj?.neverBacked ?? 0) > 0 ? .red : .green)
                    StatTile(value: "\(pj?.dbFailed ?? 0)", label: "db failed",
                             accent: (pj?.dbFailed ?? 0) > 0 ? .red : .green)
                    StatTile(value: "\(b.security?.high ?? 0)", label: "secret hits",
                             accent: (b.security?.high ?? 0) > 0 ? .red : .green)
                }
                HStack(spacing: 8) {
                    StatTile(value: sizeText(pj?.sizeToday), label: "size today")
                    StatTile(value: "\(pj?.dbDumpsToday ?? 0)", label: "db dumps")
                    StatTile(value: "\(pj?.archived ?? 0)", label: "archived today")
                }
                HStack(spacing: 8) {
                    StatTile(value: "\(cl?.driveCopies ?? 0)", label: "claude copies")
                    StatTile(value: (pj?.ranToday == true) ? "yes" : "no", label: "ran today",
                             accent: (pj?.ranToday == true) ? .green : .orange)
                    StatTile(value: (cl?.ranToday == true) ? "yes" : "no", label: "claude ran",
                             accent: (cl?.ranToday == true) ? .green : .orange)
                }
                if let detail = drillDetail(b.drill) {
                    Text("Restore drill: \(detail)").font(.caption2).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            Group {
                SectionHeader(title: "Storage")
                kv("Drive backup", b.disk?.driveBackupUsed ?? "—")
                ssdRow(b.disk)
                kv("Mac free", b.disk?.macFree ?? "—")
            }

            failuresFeed(b)

            Group {
                Divider()
                SectionHeader(title: "Locations")
                if let pj = BackupLocations.projectsBackup { revealRow(pj) }
                if let cl = BackupLocations.claudeBackup { revealRow(cl) }
                revealRow(BackupLocations.ssd)
                HStack(spacing: 8) {
                    Button("projects log") { Opener.reveal(BackupLocations.projectsLog.path) }.font(.caption2)
                    Button("claude log") { Opener.reveal(BackupLocations.claudeLog.path) }.font(.caption2)
                    Spacer()
                }
            }

            Divider()

            HStack {
                Text(updatedText(b, now: now))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Open dashboard") {
                    Opener.open("https://backups.edrishusein.com/")
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Pieces

    private func banner(overall: String, stale: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: overallIcon(overall))
                .foregroundColor(overallColor(overall))
            VStack(alignment: .leading, spacing: 1) {
                Text(overallTitle(overall))
                    .font(.callout.weight(.semibold))
                if stale {
                    Text("Data is stale — the Mac may be off or the publish failed.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(overallColor(overall).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private func jobRow(_ name: String, loaded: Bool?, exit: Int?, lastRun: String?,
                        schedule: String?, runState: String?, lastSuccess: String?,
                        lastAttempt: String?) -> some View {
        let ok = (loaded == true) && (exit ?? 0) == 0
        // Prefer last_success when present; fall back to last_run, then "never run".
        let primary = (lastSuccess?.isEmpty == false) ? lastSuccess!
            : (lastRun?.isEmpty == false ? lastRun! : "never run")
        // Show an "attempt:" line only when the latest attempt differs from the success shown.
        let showAttempt = (lastAttempt?.isEmpty == false) && lastAttempt != lastSuccess
        return HStack(spacing: 8) {
            Circle()
                .fill(ok ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.caption.weight(.medium))
                Text(primary)
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                if showAttempt {
                    Text("attempt: \(lastAttempt!)")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.orange)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(runStateLabel(runState, exit: exit))
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .foregroundColor(runStateColor(runState, exit: exit))
                if let schedule, !schedule.isEmpty {
                    Text(schedule)
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// "What's broken" — compact list of failing reasons under the banner.
    /// Hidden when everything is healthy (overall == "ok") or there's nothing to report.
    @ViewBuilder
    private func brokenSummary(_ b: BackupStatus, overall: String) -> some View {
        let reasons = (overall == "ok") ? [] : BackupParser.brokenReasons(b)
        if !reasons.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(reasons.enumerated()), id: \.offset) { _, reason in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: reason.isFailure ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(reason.isFailure ? .red : .orange)
                        Text(reason.text)
                            .font(.caption2)
                            .foregroundColor(reason.isFailure ? .red : .orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// SSD storage row: free/mounted text, plus an orange "X days old" when stale (>=14d).
    @ViewBuilder
    private func ssdRow(_ disk: BackupStatus.Disk?) -> some View {
        let mountedText = (disk?.ssdMounted == true)
            ? "\(disk?.ssdFree ?? "—") free" : "not plugged in"
        let staleDays = disk?.ssdStaleDays ?? -1
        HStack {
            Text("SSD (full)").font(.caption).foregroundColor(.secondary)
            Spacer()
            if staleDays >= BackupParser.ssdStaleThresholdDays {
                Text("\(staleDays) days old")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.orange)
            }
            Text(mountedText).font(.caption.monospacedDigit())
        }
    }

    /// Compact failures feed: up to 6 newest events, fail in red, warn in quieter orange.
    @ViewBuilder
    private func failuresFeed(_ b: BackupStatus) -> some View {
        let events = BackupParser.sortedEvents(b, limit: 6)
        if !events.isEmpty {
            Group {
                Divider()
                SectionHeader(title: "Recent failures")
                ForEach(Array(events.enumerated()), id: \.offset) { _, ev in
                    eventRow(ev)
                }
            }
        }
    }

    private func eventRow(_ ev: BackupStatus.Event) -> some View {
        let isFail = ev.level == "fail"
        let color: Color = isFail ? .red : .orange
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(ev.source ?? "—")
                .font(.caption2.weight(.medium))
                .foregroundColor(color)
            Text(truncate(ev.msg ?? "", 80))
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func revealRow(_ loc: BackupLocation) -> some View {
        HStack {
            Text(loc.label).font(.caption).foregroundColor(.secondary)
            Spacer()
            Button("Reveal") { Opener.reveal(loc.path) }
                .font(.caption2)
                .disabled(!loc.exists)
        }
    }

    private func kv(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
        }
    }

    private var missing: some View {
        VStack(spacing: 8) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("No backup status found.")
                .font(.caption)
            Text("Run the collector on this Mac, then reopen:")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("backup-automation/scripts/collect-status.sh")
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
            Button("Refresh") { state.refreshBackup() }
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Formatting helpers

    private func sizeText(_ s: String?) -> String {
        (s?.isEmpty == false) ? s! : "—"
    }
    private func truncate(_ s: String, _ max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max - 1)) + "…"
    }
    /// Restore-drill tile text. A stale (untested) drill is a warning even if it last passed —
    /// an untested backup is not a backup.
    private func drillText(_ status: String?) -> String {
        switch status {
        case "ok": return "Passed"
        case "fail": return "Failed"
        default: return "—"
        }
    }
    private func drillColor(_ status: String?) -> Color {
        switch status {
        case "ok": return .green
        case "fail": return .red
        default: return .primary
        }
    }
    /// Tile text/colour that treats a stale (untested) drill as a warning, not a pass.
    private func drillTileText(_ drill: BackupStatus.Drill?) -> String {
        if drill?.stale == true && drill?.status != "fail" { return "Stale" }
        return drillText(drill?.status)
    }
    private func drillTileColor(_ drill: BackupStatus.Drill?) -> Color {
        if drill?.stale == true && drill?.status != "fail" { return .orange }
        return drillColor(drill?.status)
    }
    /// Drill detail line, adding a stale warning and verified-files percentage when present.
    private func drillDetail(_ drill: BackupStatus.Drill?) -> String? {
        guard let drill else { return nil }
        var parts: [String] = []
        if drill.stale == true && drill.status != "fail" {
            parts.append("stale, not verified in 14+ days")
        }
        if let pct = drill.pct {
            if let files = drill.fileCount {
                parts.append("\(pct)% of \(files) files verified")
            } else {
                parts.append("\(pct)% files verified")
            }
        }
        if let detail = drill.detail, !detail.isEmpty {
            parts.append(detail)
        }
        let joined = parts.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }
    /// Per-job run-state label. Uses run_state when present, else derives from exit code.
    private func runStateLabel(_ runState: String?, exit: Int?) -> String {
        switch runState {
        case "running": return "running"
        case "hung": return "hung"
        case "failed": return "failed"
        case "idle": return "idle"
        case "ok": return "ok"
        default: return "exit \(exit ?? 0)"
        }
    }
    private func runStateColor(_ runState: String?, exit: Int?) -> Color {
        switch runState {
        case "ok", "idle": return .secondary
        case "running": return .blue
        case "hung", "failed": return .red
        default: return (exit ?? 0) == 0 ? .secondary : .red
        }
    }
    private func updatedText(_ b: BackupStatus, now: Date) -> String {
        guard let age = BackupParser.ageHours(b, now: now) else { return "never updated" }
        if age < 1 { return "updated \(Int(age * 60))m ago" }
        if age < 48 { return "updated \(Int(age))h ago" }
        return "updated \(Int(age / 24))d ago"
    }
    private func overallTitle(_ o: String) -> String {
        switch o {
        case "ok": return "All systems healthy"
        case "warn": return "Needs attention"
        default: return "Backups failing"
        }
    }
    private func overallIcon(_ o: String) -> String {
        switch o {
        case "ok": return "checkmark.circle.fill"
        case "warn": return "exclamationmark.triangle.fill"
        default: return "xmark.octagon.fill"
        }
    }
    private func overallColor(_ o: String) -> Color {
        switch o {
        case "ok": return .green
        case "warn": return .orange
        default: return .red
        }
    }
}
