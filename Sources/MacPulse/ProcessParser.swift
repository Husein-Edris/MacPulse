import Foundation

/// One running process. `id` is the pid so SwiftUI lists keep stable identity across refreshes.
struct ProcessItem: Identifiable, Equatable {
    let pid: Int32
    let name: String
    let cpuPercent: Double
    let memPercent: Double
    var id: Int32 { pid }
}

struct ProcessSnapshot {
    let topCPU: [ProcessItem]
    let topRAM: [ProcessItem]
}

/// Pure parser for `ps -Aceo pid,pcpu,pmem,comm -r` output, separated from the
/// subprocess call so it is unit-testable. `comm` may contain spaces
/// (e.g. "Google Chrome Helper"), so the command is the trailing remainder.
enum ProcessParser {
    static func parse(_ output: String) -> [ProcessItem] {
        var items: [ProcessItem] = []
        for line in output.split(separator: "\n").dropFirst() {       // drop the header row
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4,
                  let pid = Int32(parts[0]), pid > 0,
                  let cpu = Double(parts[1]),
                  let mem = Double(parts[2]) else { continue }
            let name = parts[3].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            items.append(ProcessItem(pid: pid, name: name, cpuPercent: cpu, memPercent: mem))
        }
        return items
    }
}
