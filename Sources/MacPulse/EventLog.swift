import Foundation

/// What kind of resource crossed a threshold.
enum EventKind: String {
    case cpu = "CPU"
    case mem = "MEM"
}

/// Rolling on-disk record of high-CPU / high-memory events, plus a pure line
/// formatter. The formatter takes an explicit `Date` and renders in UTC so it is
/// timezone-stable and unit-testable (the CPUHistory no-internal-clock convention).
/// File writes are best-effort convenience, never load-bearing.
enum EventLog {

    static let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MacPulse", isDirectory: true)
        return dir.appendingPathComponent("events.log")
    }()

    static var fileExists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    private static let maxLines = 2000
    private static let writeQueue = DispatchQueue(label: "com.macpulse.eventlog")

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// Pure: "2026-07-07 12:55:04  CPU 87%  node".
    static func formatLine(kind: EventKind, percent: Int, name: String, at date: Date) -> String {
        "\(formatter.string(from: date))  \(kind.rawValue) \(percent)%  \(name)"
    }

    /// Best-effort append of one event line, then trim to the last `maxLines`.
    /// Silently no-ops on any I-O error (logs to stderr for debugging).
    static func append(kind: EventKind, percent: Int, name: String, at date: Date) {
        writeQueue.sync {
            let line = formatLine(kind: kind, percent: percent, name: name, at: date)
            let fm = FileManager.default
            do {
                try fm.createDirectory(at: fileURL.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                let existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
                var lines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                if lines.last == "" { lines.removeLast() }   // drop trailing empty from the final newline
                lines.append(line)
                if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
                try (lines.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                FileHandle.standardError.write(Data("MacPulse: EventLog write failed: \(error)\n".utf8))
            }
        }
    }
}
