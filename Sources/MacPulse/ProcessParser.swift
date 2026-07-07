import Foundation

/// One running process. `id` is the pid so SwiftUI lists keep stable identity across refreshes.
struct ProcessItem: Identifiable, Equatable {
    let pid: Int32
    let name: String          // friendly, human-readable
    let cpuPercent: Double
    let memPercent: Double
    let rawName: String       // original ps string (full path or bare name)
    let detail: String?       // "a browser tab", "building the search index"
    let safety: ProcessSafety
    var id: Int32 { pid }

    init(pid: Int32, name: String, cpuPercent: Double, memPercent: Double,
         rawName: String = "", detail: String? = nil, safety: ProcessSafety = .caution) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memPercent = memPercent
        self.rawName = rawName
        self.detail = detail
        self.safety = safety
    }
}

struct ProcessSnapshot {
    let topCPU: [ProcessItem]
    let topRAM: [ProcessItem]
}

/// Pure parser for `ps -Aeo pid,pcpu,pmem,comm -r -ww` output, separated from the
/// subprocess call so it is unit-testable. `comm` is the full executable path and
/// may contain spaces (e.g. "/Applications/Google Chrome.app/..."), so the command
/// is the trailing remainder. Each row is named via `ProcessNamer`.
enum ProcessParser {
    static func parse(_ output: String) -> [ProcessItem] {
        var items: [ProcessItem] = []
        for line in output.split(separator: "\n").dropFirst() {       // drop the header row
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4,
                  let pid = Int32(parts[0]), pid > 0,
                  let cpu = Double(parts[1]),
                  let mem = Double(parts[2]) else { continue }
            let raw = parts[3].trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { continue }
            let label = ProcessNamer.label(for: raw)
            items.append(ProcessItem(pid: pid, name: label.name, cpuPercent: cpu,
                                     memPercent: mem, rawName: raw,
                                     detail: label.detail, safety: label.safety))
        }
        return items
    }
}
