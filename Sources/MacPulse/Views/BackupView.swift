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

            Group {
                jobRow("projects-backup", loaded: pj?.loaded, exit: pj?.lastExit,
                       lastRun: pj?.lastRun, schedule: pj?.schedule)
                jobRow("claude-backup", loaded: cl?.loaded, exit: cl?.lastExit,
                       lastRun: cl?.lastRun, schedule: cl?.schedule)
            }

            Group {
                HStack(spacing: 8) {
                    StatTile(value: "\(pj?.covered ?? 0)/\(pj?.projectFolders ?? 0)", label: "covered")
                    StatTile(value: "\(pj?.failed ?? 0)", label: "failed",
                             accent: (pj?.failed ?? 0) > 0 ? .red : .green)
                    StatTile(value: drillText(b.drill?.status), label: "restore drill",
                             accent: drillColor(b.drill?.status))
                }
                HStack(spacing: 8) {
                    StatTile(value: "\(b.security?.high ?? 0)", label: "secret hits",
                             accent: (b.security?.high ?? 0) > 0 ? .red : .green)
                    StatTile(value: sizeText(pj?.sizeToday), label: "size today")
                    StatTile(value: "\(pj?.dbDumpsToday ?? 0)", label: "db dumps")
                }
                HStack(spacing: 8) {
                    StatTile(value: "\(pj?.archived ?? 0)", label: "archived today")
                    StatTile(value: "\(cl?.driveCopies ?? 0)", label: "claude copies")
                    StatTile(value: (pj?.ranToday == true) ? "yes" : "no", label: "ran today",
                             accent: (pj?.ranToday == true) ? .green : .orange)
                }
                if let detail = b.drill?.detail, !detail.isEmpty {
                    Text("Restore drill: \(detail)").font(.caption2).foregroundColor(.secondary)
                }
            }

            Divider()

            Group {
                SectionHeader(title: "Storage")
                kv("Drive backup", b.disk?.driveBackupUsed ?? "—")
                kv("SSD (full)", (b.disk?.ssdMounted == true)
                    ? "\(b.disk?.ssdFree ?? "—") free" : "not plugged in")
                kv("Mac free", b.disk?.macFree ?? "—")
            }

            Divider()
            Group {
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

    private func jobRow(_ name: String, loaded: Bool?, exit: Int?, lastRun: String?, schedule: String?) -> some View {
        let ok = (loaded == true) && (exit ?? 0) == 0
        return HStack(spacing: 8) {
            Circle()
                .fill(ok ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.caption.weight(.medium))
                Text(lastRun?.isEmpty == false ? lastRun! : "never run")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("exit \(exit ?? 0)")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor((exit ?? 0) == 0 ? .secondary : .red)
                if let schedule, !schedule.isEmpty {
                    Text(schedule)
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
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
