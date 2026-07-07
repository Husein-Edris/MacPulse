import Foundation

/// One menu-bar readout: a short uppercase label ("CPU") shown above its value ("8%").
struct MenuMetric: Equatable {
    let label: String
    let value: String
}

/// How hard macOS is leaning on swap (paging memory to disk). Drives both the
/// Memory-row colour and the Tips rule, so the thresholds live in one place.
enum SwapLevel: Int, Comparable {
    case ok = 0, elevated = 1, heavy = 2
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum Fmt {
    static func gb(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }

    static func gb(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }

    /// Human-readable memory size: MB below 1 GB, GB above (e.g. "390 MB", "1.2 GB").
    static func memSize(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb < 1024 {
            return "\(Int(mb.rounded())) MB"
        }
        return String(format: "%.1f GB", mb / 1024)
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3_600
        let minutes = (Int(seconds) % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// The enabled menu-bar metrics in display order (CPU, RAM, SSD). Empty when all are off.
    /// Each renders as a small label stacked above its rounded percentage (Stats-app style).
    static func menuBarMetrics(cpuPercent: Double, ramPercent: Double, diskPercent: Double,
                               showCPU: Bool, showRAM: Bool, showDisk: Bool) -> [MenuMetric] {
        var metrics: [MenuMetric] = []
        if showCPU { metrics.append(MenuMetric(label: "CPU", value: String(format: "%.0f%%", cpuPercent))) }
        if showRAM { metrics.append(MenuMetric(label: "RAM", value: String(format: "%.0f%%", ramPercent))) }
        if showDisk { metrics.append(MenuMetric(label: "SSD", value: String(format: "%.0f%%", diskPercent))) }
        return metrics
    }

    /// Menu-bar sample cadence. Stretched on battery to cut idle wakeups.
    static func sampleInterval(onBattery: Bool) -> TimeInterval {
        onBattery ? 12 : 5
    }

    /// Classifies swap usage. A little swap is normal; sustained GBs of paging is
    /// the real signal that 16 GB is overcommitted and things will feel slow.
    static func swapLevel(usedGB: Double) -> SwapLevel {
        if usedGB >= 3 { return .heavy }
        if usedGB >= 1 { return .elevated }
        return .ok
    }

    static func ago(_ date: Date) -> String {
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 { return "\(diff)s ago" }
        if diff < 3_600 { return "\(diff / 60)m ago" }
        if diff < 86_400 { return "\(diff / 3_600)h ago" }
        return "\(diff / 86_400)d ago"
    }

    /// Countdown to a future reset, e.g. "2h 14m" or "1d 3h". "now" when past.
    static func until(_ date: Date, now: Date = Date()) -> String {
        let diff = Int(date.timeIntervalSince(now))
        if diff <= 0 { return "now" }
        if diff >= 86_400 { return "\(diff / 86_400)d \((diff % 86_400) / 3_600)h" }
        let h = diff / 3_600, m = (diff % 3_600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
