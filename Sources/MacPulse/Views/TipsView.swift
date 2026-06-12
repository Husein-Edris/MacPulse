import SwiftUI

struct TipsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let improvements = state.improvements

            HStack {
                SectionHeader(title: "Improvements")
                Spacer()
                Button {
                    state.scanStorage()
                } label: {
                    if state.hotspotsScanning {
                        ProgressView().controlSize(.mini)
                    } else {
                        Label(
                            state.hotspots == nil ? "Scan storage" : "Rescan",
                            systemImage: "magnifyingglass"
                        )
                        .font(.caption)
                    }
                }
                .help("Measure Caches, Trash and Downloads sizes")
            }

            if improvements.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title)
                        .foregroundColor(.green)
                    Text("All clear — nothing needs attention.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if state.hotspots == nil {
                        Text("Run a storage scan to also check Caches, Trash and Downloads.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            }

            ForEach(improvements) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.icon)
                        .foregroundColor(severityColor(item.severity))
                        .frame(width: 18)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                        Text(item.detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let actionTitle = item.actionTitle, let url = item.actionURL {
                            Button(actionTitle) { Opener.open(url) }
                                .font(.caption)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(
                    severityColor(item.severity).opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 8)
                )
            }

            if let hotspots = state.hotspots {
                Text("Storage scanned \(Fmt.ago(hotspots.scannedAt))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Group {
                SectionHeader(title: "Large files")
                Button(state.largeFilesScanning ? "Scanning…" : "Scan large files (≥100 MB)") {
                    state.scanLargeFiles()
                }
                .disabled(state.largeFilesScanning)
                .font(.caption)

                if let files = state.largeFiles {
                    if files.isEmpty {
                        Text("No files ≥100 MB found in your home folder.")
                            .font(.caption2).foregroundColor(.secondary)
                    } else {
                        ForEach(files) { f in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(f.name).font(.caption).lineLimit(1)
                                    Text(f.path).font(.caption2).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Text(String(format: "%.0f MB", f.sizeMB)).font(.caption.monospacedDigit())
                                Button("Reveal") { Opener.reveal(f.path) }.font(.caption2)
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }
            }
        }
        .padding(12)
    }

    private func severityColor(_ severity: ImprovementSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}
