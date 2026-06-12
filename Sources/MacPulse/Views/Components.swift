import SwiftUI
import AppKit

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundColor(.secondary)
            .kerning(0.8)
    }
}

struct MetricBar: View {
    let label: String
    let valueText: String
    let percent: Double
    let warnAt: Double
    let critAt: Double

    private var color: Color {
        if percent >= critAt { return .red }
        if percent >= warnAt { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: max(3, geo.size.width * min(percent, 100) / 100))
                }
            }
            .frame(height: 6)
        }
    }
}

struct StatusDotRow: View {
    let name: String
    let isOn: Bool?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isOn == true ? Color.green : (isOn == false ? Color.red : Color.gray))
                .frame(width: 7, height: 7)
            Text(name)
                .font(.caption)
            Spacer()
            Text(isOn == true ? "ON" : (isOn == false ? "OFF" : "—"))
                .font(.caption.weight(.semibold))
                .foregroundColor(isOn == true ? .green : (isOn == false ? .red : .secondary))
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var accent: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundColor(accent)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

enum Opener {
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens Finder with the item selected. Falls back to opening the parent dir.
    static func reveal(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}
