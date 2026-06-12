import Foundation
import Darwin

struct SystemSnapshot {
    let cpuPercent: Double
    let coreCount: Int
    let load1: Double
    let load5: Double
    let load15: Double
    let ramUsedBytes: UInt64
    let ramTotalBytes: UInt64
    let diskUsedBytes: Int64
    let diskTotalBytes: Int64
    let diskFreeBytes: Int64
    let uptime: TimeInterval
    let date: Date

    var ramPercent: Double {
        ramTotalBytes == 0 ? 0 : Double(ramUsedBytes) / Double(ramTotalBytes) * 100
    }
    var diskPercent: Double {
        diskTotalBytes == 0 ? 0 : Double(diskUsedBytes) / Double(diskTotalBytes) * 100
    }
    var uptimeDays: Double { uptime / 86_400 }
}


/// Reads system metrics straight from the kernel (mach / sysctl) — no daemons,
/// no log files, no polling subprocesses except one `ps` call for the process list.
final class SystemMonitor {
    private struct CPUTicks {
        let user: UInt64, system: UInt64, idle: UInt64, nice: UInt64
        var active: UInt64 { user &+ system &+ nice }
        var total: UInt64 { active &+ idle }
    }

    private var previousTicks: CPUTicks?

    // MARK: - Public sampling

    /// Blocking; call off the main thread. First call primes the CPU delta with a short double-sample.
    func sample() -> SystemSnapshot {
        let cpu = sampleCPUPercent()
        let (ramUsed, ramTotal) = sampleRAM()
        let (diskUsed, diskTotal, diskFree) = sampleDisk()
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)

        return SystemSnapshot(
            cpuPercent: cpu,
            coreCount: ProcessInfo.processInfo.processorCount,
            load1: loads[0], load5: loads[1], load15: loads[2],
            ramUsedBytes: ramUsed,
            ramTotalBytes: ramTotal,
            diskUsedBytes: diskUsed,
            diskTotalBytes: diskTotal,
            diskFreeBytes: diskFree,
            uptime: ProcessInfo.processInfo.systemUptime,
            date: Date()
        )
    }

    /// Blocking; one `ps` invocation, parsed and sorted in-process.
    func sampleProcesses(top n: Int = 10) -> ProcessSnapshot {
        guard let output = Shell.run("/bin/ps", ["-Aceo", "pid,pcpu,pmem,comm", "-r"]) else {
            return ProcessSnapshot(topCPU: [], topRAM: [])
        }
        let items = ProcessParser.parse(output)
        let byCPU = Array(items.prefix(n)) // ps -r is already CPU-sorted
        let byRAM = Array(items.sorted { $0.memPercent > $1.memPercent }.prefix(n))
        return ProcessSnapshot(topCPU: byCPU, topRAM: byRAM)
    }

    // MARK: - CPU

    private func readTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // cpu_ticks tuple order: (USER, SYSTEM, IDLE, NICE)
        return CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    private func sampleCPUPercent() -> Double {
        guard var previous = previousTicks ?? readTicks() else { return 0 }
        if previousTicks == nil {
            // Prime the delta so the very first reading is meaningful.
            usleep(200_000)
            previousTicks = previous
            guard let primed = readTicks() else { return 0 }
            defer { previousTicks = primed }
            previous = previousTicks ?? previous
        }
        guard let current = readTicks() else { return 0 }
        defer { previousTicks = current }

        let totalDelta = current.total &- previous.total
        guard totalDelta > 0 else { return 0 }
        let activeDelta = current.active &- previous.active
        return min(100, Double(activeDelta) / Double(totalDelta) * 100)
    }

    // MARK: - RAM

    private func sampleRAM() -> (used: UInt64, total: UInt64) {
        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &size, nil, 0)

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        // Matches Activity Monitor's "Memory Used":
        // app memory (internal - purgeable) + wired + compressed
        let appPages = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
        let usedPages = appPages &+ UInt64(stats.wire_count) &+ UInt64(stats.compressor_page_count)
        return (usedPages &* UInt64(pageSize), total)
    }

    // MARK: - Disk

    private func sampleDisk() -> (used: Int64, total: Int64, free: Int64) {
        let rootURL = URL(fileURLWithPath: "/")
        guard let values = try? rootURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]),
            let total = values.volumeTotalCapacity,
            let free = values.volumeAvailableCapacityForImportantUsage
        else { return (0, 0, 0) }
        // "Important usage" capacity accounts for purgeable space — matches Finder/About This Mac.
        return (Int64(total) - free, Int64(total), free)
    }
}
