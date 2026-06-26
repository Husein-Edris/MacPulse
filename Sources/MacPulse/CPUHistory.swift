import Foundation

/// One CPU% reading at a point in time. Pure value type backing the sparkline.
struct CPUSample: Equatable {
    let date: Date
    let percent: Double
}

/// A recorded CPU spike: when it happened, how high overall CPU was, and the top
/// processes at that moment (captured via a one-off `ps` scan when the spike fired,
/// already CPU-sorted, up to a handful). `topProcess` is the single worst offender.
struct SpikeEvent: Identifiable, Equatable {
    let date: Date
    let cpuPercent: Double
    let processes: [ProcessItem]
    var id: Date { date }
    var topProcess: ProcessItem? { processes.first }
}

/// Pure ring buffer plus spike-trigger policy for recent CPU history.
///
/// No timers, no subprocesses, no clock reads: every decision takes an explicit
/// `Date`, so the whole thing is unit-testable without XCTest. `AppState` feeds it
/// samples on each kernel tick and asks `shouldCaptureSpike` before paying for the
/// expensive `ps` scan, keeping that scan bounded by `spikeThreshold` and `spikeCooldown`.
struct CPUHistory: Equatable {
    private(set) var samples: [CPUSample] = []
    private(set) var spikes: [SpikeEvent] = []
    private(set) var lastSpikeCaptureAt: Date?

    /// How much wall-clock history to retain for the sparkline.
    let window: TimeInterval
    /// CPU% at or above which a spike capture is considered.
    let spikeThreshold: Double
    /// Minimum gap between spike captures, to bound the expensive `ps` calls.
    let spikeCooldown: TimeInterval
    /// Cap on retained spike events (oldest dropped first).
    let maxSpikes: Int

    init(window: TimeInterval = 900,        // 15 min
         spikeThreshold: Double = 80,
         spikeCooldown: TimeInterval = 60,
         maxSpikes: Int = 20) {
        self.window = window
        self.spikeThreshold = spikeThreshold
        self.spikeCooldown = spikeCooldown
        self.maxSpikes = maxSpikes
    }

    /// Append a CPU reading, dropping anything older than `window`.
    mutating func addSample(percent: Double, at date: Date) {
        samples.append(CPUSample(date: date, percent: percent))
        let cutoff = date.addingTimeInterval(-window)
        samples.removeAll { $0.date < cutoff }
    }

    /// True when `percent` is at/above threshold AND the cooldown since the last
    /// capture has elapsed. The caller runs `ps` only when this returns true.
    func shouldCaptureSpike(percent: Double, at date: Date) -> Bool {
        guard percent >= spikeThreshold else { return false }
        guard let last = lastSpikeCaptureAt else { return true }
        return date.timeIntervalSince(last) >= spikeCooldown
    }

    /// Record a captured spike (after the caller ran `ps`) and arm the cooldown.
    mutating func recordSpike(_ event: SpikeEvent) {
        spikes.append(event)
        lastSpikeCaptureAt = event.date
        if spikes.count > maxSpikes {
            spikes.removeFirst(spikes.count - maxSpikes)
        }
    }

    /// Most recent spikes first, for display.
    var recentSpikes: [SpikeEvent] { spikes.reversed() }

    /// Peak CPU% across the retained window (0 when empty), to label the sparkline.
    var peakPercent: Double { samples.map(\.percent).max() ?? 0 }
}
