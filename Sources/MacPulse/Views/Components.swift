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

/// Compact CPU% sparkline (area + line) over the retained history window.
/// Plots samples evenly spaced; colour tracks the window's peak so a recent
/// spike tints the whole trace. Drawn with `Path`, no per-point views.
struct Sparkline: View {
    let samples: [CPUSample]
    var warnAt: Double = 50
    var critAt: Double = 80

    private var peak: Double { samples.map(\.percent).max() ?? 0 }
    private var color: Color {
        if peak >= critAt { return .red }
        if peak >= warnAt { return .orange }
        return .green
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let n = samples.count
            if n >= 2 {
                let stepX = w / CGFloat(n - 1)
                let point: (Int, CPUSample) -> CGPoint = { i, s in
                    CGPoint(x: CGFloat(i) * stepX,
                            y: h - CGFloat(min(s.percent, 100) / 100) * h)
                }
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h))
                        for (i, s) in samples.enumerated() { p.addLine(to: point(i, s)) }
                        p.addLine(to: CGPoint(x: w, y: h))
                        p.closeSubpath()
                    }
                    .fill(color.opacity(0.15))

                    Path { p in
                        for (i, s) in samples.enumerated() {
                            let pt = point(i, s)
                            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            }
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
