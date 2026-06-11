import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var state: AppState

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
            processRow(icon: "cpu", items: state.processes.topCPU, isCPU: true)
            processRow(icon: "memorychip", items: state.processes.topRAM, isCPU: false)

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
}
