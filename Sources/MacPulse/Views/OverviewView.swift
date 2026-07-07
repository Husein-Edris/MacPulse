import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var state: AppState

    @State private var showAllProcesses = false
    @State private var sortByCPU = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let s = state.system {
                VStack(alignment: .leading, spacing: 4) {
                    MetricBar(
                        label: "CPU",
                        valueText: String(format: "%.1f%%  ·  %d cores", s.cpuPercent, s.coreCount),
                        percent: s.cpuPercent, warnAt: 50, critAt: 80
                    )
                    if state.cpuHistory.samples.count >= 2 {
                        HStack(spacing: 6) {
                            Sparkline(samples: state.cpuHistory.samples)
                                .frame(height: 24)
                            Text(String(format: "peak %.0f%%", state.cpuHistory.peakPercent))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                                .fixedSize()
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    MetricBar(
                        label: "Memory",
                        valueText: "\(Fmt.gb(s.ramUsedBytes)) / \(Fmt.gb(s.ramTotalBytes)) GB  (\(Int(s.ramPercent))%)",
                        percent: s.ramPercent, warnAt: 60, critAt: 80
                    )
                    if s.swapTotalBytes > 0 {
                        swapRow(s)
                    }
                }
                MetricBar(
                    label: "Storage",
                    valueText: "\(Fmt.gb(s.diskUsedBytes)) / \(Fmt.gb(s.diskTotalBytes)) GB  ·  \(Fmt.gb(s.diskFreeBytes)) free",
                    percent: s.diskPercent, warnAt: 70, critAt: 85
                )
                HStack {
                    Label(
                        String(format: "%.2f  %.2f  %.2f", s.load1, s.load5, s.load15),
                        systemImage: "gauge.medium"
                    )
                    Spacer()
                    Label("up \(Fmt.uptime(s.uptime))", systemImage: "clock")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            } else {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
                .padding(.vertical, 30)
            }

            Divider()

            SectionHeader(title: "Top processes")
            processRow(icon: "cpu", items: Array(state.processes.topCPU.prefix(3)), isCPU: true)
            processRow(icon: "memorychip", items: Array(state.processes.topRAM.prefix(3)), isCPU: false)

            DisclosureGroup(isExpanded: $showAllProcesses) {
                Group {
                    Picker("", selection: $sortByCPU) {
                        Text("CPU").tag(true)
                        Text("Memory").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    ForEach(sortByCPU ? state.processes.topCPU : state.processes.topRAM) { proc in
                        processRow(proc)
                    }

                    if let err = state.processActionError {
                        Text(err).font(.caption2).foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } label: {
                Text("All processes").font(.caption.weight(.medium))
            }

            spikesSection

            Group {
                Divider()

                SectionHeader(title: "Security")
                if let sec = state.security {
                    HStack(spacing: 16) {
                        VStack(spacing: 5) {
                            StatusDotRow(name: "Firewall", isOn: sec.firewall)
                            StatusDotRow(name: "FileVault", isOn: sec.fileVault)
                        }
                        VStack(spacing: 5) {
                            StatusDotRow(name: "SIP", isOn: sec.sip)
                            StatusDotRow(name: "Gatekeeper", isOn: sec.gatekeeper)
                        }
                    }
                } else {
                    Text("Checking…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                Button {
                    state.openEventLog()
                } label: {
                    Label("Open log file", systemImage: "doc.text")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(!state.eventLogExists)
                .help("Open MacPulse's high CPU / memory event log")
            }
        }
        .padding(12)
    }

    /// Swap line under the Memory bar. A little swap is normal; sustained GBs is the
    /// real "memory pressure" signal that the Memory % alone hides. Colour tracks level.
    private func swapRow(_ s: SystemSnapshot) -> some View {
        let level = Fmt.swapLevel(usedGB: s.swapUsedGB)
        let color: Color = level == .heavy ? .red : (level == .elevated ? .orange : .secondary)
        let note = level == .heavy ? "heavy paging" : (level == .elevated ? "some paging" : "healthy")
        return HStack(spacing: 5) {
            Image(systemName: "arrow.left.arrow.right.circle").font(.caption2)
            Text("Swap \(Fmt.gb(s.swapUsedBytes)) / \(Fmt.gb(s.swapTotalBytes)) GB")
                .font(.caption2.monospacedDigit())
            Spacer()
            Text(note).font(.caption2)
        }
        .foregroundColor(color)
    }

    /// Recent CPU spikes (threshold crossings), each with the top processes captured
    /// at that moment and a quit action per process. Hidden until a spike is captured.
    @ViewBuilder
    private var spikesSection: some View {
        let spikes = state.cpuHistory.recentSpikes
        if !spikes.isEmpty {
            Divider()
            SectionHeader(title: "Recent CPU spikes")
            ForEach(Array(spikes.prefix(3))) { spike in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .frame(width: 14)
                        Text(String(format: "%.0f%% CPU", spike.cpuPercent))
                            .font(.caption.weight(.medium).monospacedDigit())
                        Spacer()
                        Text(Fmt.ago(spike.date))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    ForEach(Array(spike.processes.prefix(5))) { proc in
                        spikeProcessRow(proc)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// One process inside a spike: name, its CPU%, and a quit menu that reuses the
    /// shared kill confirmation. Note: a process from an older spike may have exited
    /// (handled gracefully), so the action is most meaningful on the latest spike.
    private func spikeProcessRow(_ proc: ProcessItem) -> some View {
        HStack(spacing: 8) {
            Text(proc.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text(String(format: "%.0f%%", proc.cpuPercent))
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
            Menu {
                Button("Quit") { state.endProcess(proc, force: false) }
                Button("Force Quit", role: .destructive) { state.endProcess(proc, force: true) }
                Divider()
                Button("Reveal in Finder") { state.revealInFinder(proc) }
                    .disabled(!state.canReveal(proc))
                Button("Open Activity Monitor") { state.openInActivityMonitor(proc) }
            } label: {
                Image(systemName: "xmark.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
        }
        .padding(.leading, 20)
    }

    @ViewBuilder
    private func processRow(icon: String, items: [ProcessItem], isCPU: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 14)
            if items.isEmpty {
                Text("—").font(.caption).foregroundColor(.secondary)
            }
            ForEach(items) { p in
                HStack(spacing: 3) {
                    Text(p.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(isCPU
                         ? String(format: "%.0f%%", p.cpuPercent)
                         : memSizeText(p))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Approximate resident size for a process, from its RAM percentage and total RAM.
    /// This is an estimate (percent of total), not exact RSS, but reads far better
    /// than a bare percentage for a non-technical user.
    private func memSizeText(_ p: ProcessItem) -> String {
        guard let total = state.system?.ramTotalBytes, total > 0 else {
            return String(format: "%.1f%%", p.memPercent)
        }
        let bytes = UInt64(Double(total) * p.memPercent / 100.0)
        return Fmt.memSize(bytes)
    }

    /// Plain-language "is it safe to quit" hint and its colour.
    private func safetyHint(_ item: ProcessItem) -> (text: String, color: Color) {
        switch item.safety {
        case .safe:    return ("Safe to close", .secondary)
        case .caution: return ("Close only if you know it", .orange)
        case .system:  return ("System process, leave running", .secondary)
        }
    }

    private func processRow(_ proc: ProcessItem) -> some View {
        let hint = safetyHint(proc)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(proc.name).font(.caption).lineLimit(1)
                if let detail = proc.detail {
                    Text(detail).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
                Text(hint.text).font(.caption2).foregroundColor(hint.color).lineLimit(1)
            }
            Spacer()
            Text(String(format: "%.0f%%", sortByCPU ? proc.cpuPercent : proc.memPercent))
                .font(.caption.monospacedDigit()).foregroundColor(.secondary)
            Menu {
                Button("Quit") { state.endProcess(proc, force: false) }
                Button("Force Quit", role: .destructive) { state.endProcess(proc, force: true) }
                Divider()
                Button("Reveal in Finder") { state.revealInFinder(proc) }
                    .disabled(!state.canReveal(proc))
                Button("Open Activity Monitor") { state.openInActivityMonitor(proc) }
            } label: {
                Image(systemName: "xmark.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.vertical, 1)
    }
}
