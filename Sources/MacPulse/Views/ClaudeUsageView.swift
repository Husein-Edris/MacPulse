import SwiftUI

struct ClaudeUsageView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let snap = state.claudeUsage {
                limitsSection(snap.limits)
                Divider()
                activitySection(snap.activity)
                Divider()
                projectsSection(snap.activity.projects)
            } else if state.claudeUsageLoading {
                Text("Reading Claude Code usage…").font(.caption).foregroundColor(.secondary)
            } else {
                Text("No usage data yet.").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(12)
        .onAppear { state.refreshClaudeUsage() }
    }

    private var header: some View {
        HStack {
            SectionHeader(title: "Claude Code")
            Spacer()
            if let snap = state.claudeUsage {
                Text("updated \(Fmt.ago(snap.updatedAt))")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Button { state.refreshClaudeUsage(force: true) } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(state.claudeUsageLoading)
            .help("Reload usage now")
        }
    }

    @ViewBuilder
    private func limitsSection(_ limits: ClaudeLimits?) -> some View {
        if let limits {
            VStack(alignment: .leading, spacing: 8) {
                limitRow("5-hour", limits.fiveHour)
                limitRow("7-day", limits.sevenDay)
                limitRow("Weekly", limits.weekly)
            }
        } else {
            Text("Limits unavailable — is Claude Code signed in?")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func limitRow(_ label: String, _ window: LimitWindow?) -> some View {
        if let window, let pct = window.percent {
            VStack(alignment: .leading, spacing: 2) {
                MetricBar(label: label, valueText: String(format: "%.0f%%", pct),
                          percent: pct, warnAt: 75, critAt: 90)
                if let resets = window.resetsAt {
                    Text("resets in \(Fmt.until(resets))")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
    }

    private func activitySection(_ a: ClaudeActivity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Activity")
            HStack(spacing: 8) {
                StatTile(value: "\(a.today.messages)", label: "today")
                StatTile(value: "\(a.last7.messages)", label: "7 days")
                StatTile(value: "\(a.last30.messages)", label: "30 days")
                StatTile(value: "\(a.allTime.messages)", label: "all-time")
            }
            HStack(spacing: 8) {
                StatTile(value: "\(a.allTime.sessions)", label: "sessions")
                StatTile(value: "\(a.allTime.toolCalls)", label: "tool calls")
                StatTile(value: tokens(a.allTime), label: "tokens")
            }
        }
    }

    private func projectsSection(_ projects: [ProjectActivity]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "By project")
            if projects.isEmpty {
                Text("No project activity found.").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(projects.prefix(8)) { p in
                    HStack {
                        Text(p.name).font(.caption).lineLimit(1)
                        Spacer()
                        Text("\(p.messages) msg").font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    /// Compact total-token count, e.g. "1.2M" / "340K".
    private func tokens(_ b: ActivityBucket) -> String {
        let total = b.inputTokens + b.outputTokens
        if total >= 1_000_000 { return String(format: "%.1fM", Double(total) / 1_000_000) }
        if total >= 1_000 { return "\(total / 1_000)K" }
        return "\(total)"
    }
}
