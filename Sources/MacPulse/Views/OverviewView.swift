import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var state: AppState

    @State private var showAllProcesses = false
    @State private var sortByCPU = true
    @State private var killTarget: ProcessItem?
    @State private var forceKill = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let s = state.system {
                MetricBar(
                    label: "CPU",
                    valueText: String(format: "%.1f%%  ·  %d cores", s.cpuPercent, s.coreCount),
                    percent: s.cpuPercent, warnAt: 50, critAt: 80
                )
                MetricBar(
                    label: "Memory",
                    valueText: "\(Fmt.gb(s.ramUsedBytes)) / \(Fmt.gb(s.ramTotalBytes)) GB  (\(Int(s.ramPercent))%)",
                    percent: s.ramPercent, warnAt: 60, critAt: 80
                )
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
            .confirmationDialog(
                "End \(killTarget?.name ?? "process")?",
                isPresented: Binding(get: { killTarget != nil }, set: { if !$0 { killTarget = nil } }),
                presenting: killTarget
            ) { proc in
                Button(forceKill ? "Force Quit" : "Quit", role: .destructive) {
                    state.endProcess(proc, force: forceKill)
                    killTarget = nil
                }
                Button("Cancel", role: .cancel) { killTarget = nil }
            }

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
        }
        .padding(12)
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
                         : String(format: "%.1f%%", p.memPercent))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func processRow(_ proc: ProcessItem) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(proc.name).font(.caption).lineLimit(1)
                Text("pid \(proc.pid)").font(.caption2.monospacedDigit()).foregroundColor(.secondary)
            }
            Spacer()
            Text(String(format: "%.0f%%", sortByCPU ? proc.cpuPercent : proc.memPercent))
                .font(.caption.monospacedDigit()).foregroundColor(.secondary)
            Menu {
                Button("Quit") { forceKill = false; killTarget = proc }
                Button("Force Quit", role: .destructive) { forceKill = true; killTarget = proc }
            } label: {
                Image(systemName: "xmark.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.vertical, 1)
    }
}
