import SwiftUI
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    // MARK: - Live data
    @Published var system: SystemSnapshot?
    /// Rolling in-memory CPU history (sparkline + threshold-triggered spike captures).
    @Published var cpuHistory = CPUHistory()
    @Published var processes = ProcessSnapshot(topCPU: [], topRAM: [])
    @Published var security: SecurityStatus?
    @Published var github: GitHubSnapshot?
    @Published var githubError: String?
    @Published var githubLoading = false
    @Published var hotspots: StorageHotspots?
    @Published var hotspotsScanning = false
    @Published var largeFiles: [LargeFile]?
    @Published var largeFilesScanning = false
    @Published var backup: BackupStatus?
    @Published var claudeUsage: ClaudeUsageSnapshot?
    @Published var claudeUsageLoading = false
    @Published var loginItemError: String?
    @Published var processActionError: String?

    // MARK: - Settings
    @Published var githubUser: String {
        didSet { UserDefaults.standard.set(githubUser, forKey: Keys.githubUser) }
    }
    // Which live metrics to show in the menu bar (Stats-app style). All independent.
    @Published var menuBarCPU: Bool {
        didSet { UserDefaults.standard.set(menuBarCPU, forKey: Keys.menuBarCPU) }
    }
    @Published var menuBarRAM: Bool {
        didSet { UserDefaults.standard.set(menuBarRAM, forKey: Keys.menuBarRAM) }
    }
    @Published var menuBarDisk: Bool {
        didSet { UserDefaults.standard.set(menuBarDisk, forKey: Keys.menuBarDisk) }
    }
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    /// Enabled menu-bar metrics (CPU/RAM/SSD) for the current sample; empty when all are toggled off.
    func menuBarMetrics(for snapshot: SystemSnapshot) -> [MenuMetric] {
        Fmt.menuBarMetrics(cpuPercent: snapshot.cpuPercent,
                           ramPercent: snapshot.ramPercent,
                           diskPercent: snapshot.diskPercent,
                           showCPU: menuBarCPU, showRAM: menuBarRAM, showDisk: menuBarDisk)
    }

    private enum Keys {
        static let githubUser = "githubUser"
        static let menuBarCPU = "showCPUInMenuBar"  // legacy key reused so the old preference carries over
        static let menuBarRAM = "menuBarRAM"
        static let menuBarDisk = "menuBarDisk"
        static let githubCache = "githubSnapshotCacheV2"
        static let claudeUsage = "claudeUsageCacheV1"
    }

    private let monitor = SystemMonitor()
    private let githubService = GitHubService()
    private var systemTimer: Timer?
    private var githubTimer: Timer?
    private var processTimer: Timer?
    private var isPopoverOpen = false
    private var isSampling = false
    private var isCapturingSpike = false
    private var lastMemoryEventAt: Date?
    private static let memoryEventThreshold = 85.0   // percent of RAM
    private static let memoryEventCooldown: TimeInterval = 300   // 5 minutes
    private var onBattery = PowerSource.onBattery
    private static let processInterval: TimeInterval = 5
    private var isApplyingLoginItem = false

    private static let githubInterval: TimeInterval = 900       // 15 min
    private static let securityStaleAfter: TimeInterval = 1_800 // 30 min
    private static let claudeUsageStaleAfter: TimeInterval = 30

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        githubUser = defaults.string(forKey: Keys.githubUser) ?? "Husein-Edris"
        menuBarCPU = defaults.object(forKey: Keys.menuBarCPU) as? Bool ?? true
        menuBarRAM = defaults.object(forKey: Keys.menuBarRAM) as? Bool ?? true
        menuBarDisk = defaults.object(forKey: Keys.menuBarDisk) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled

        if let data = defaults.data(forKey: Keys.githubCache),
           let cached = try? JSONDecoder().decode(GitHubSnapshot.self, from: data) {
            github = cached
        }

        if let data = defaults.data(forKey: Keys.claudeUsage),
           let cached = try? JSONDecoder().decode(ClaudeUsageSnapshot.self, from: data) {
            claudeUsage = cached
        }

        startTimers()
        refreshSystem()
        refreshProcesses()
        refreshSecurity(force: true)
        refreshGitHub()
        refreshBackup()
    }

    // MARK: - Refresh

    func refreshAll() {
        refreshSystem()
        if isPopoverOpen { refreshProcesses() }
        refreshSecurity(force: true)
        refreshGitHub(force: true)
        refreshBackup()
    }

    func refreshBackup() {
        Task.detached(priority: .utility) {
            let status = BackupService.load()
            await MainActor.run { self.backup = status }
        }
    }

    func popoverDidOpen() {
        isPopoverOpen = true
        refreshSystem()
        refreshProcesses()
        refreshSecurity()
        refreshGitHub()
        refreshBackup()

        processTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.processInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refreshProcesses() }
        }
        timer.tolerance = 1
        processTimer = timer
    }

    func popoverDidClose() {
        isPopoverOpen = false
        processTimer?.invalidate()
        processTimer = nil
    }

    /// Cheap kernel sample only (CPU/RAM/disk) — drives the menu bar. No subprocess.
    /// Guarded so overlapping calls (timer tick + popover open) never run the
    /// non-concurrency-safe SystemMonitor.sample() simultaneously.
    func refreshSystem() {
        guard !isSampling else { return }
        isSampling = true
        let monitor = self.monitor
        Task.detached(priority: .utility) {
            let snapshot = monitor.sample()
            await MainActor.run {
                self.system = snapshot
                self.cpuHistory.addSample(percent: snapshot.cpuPercent, at: snapshot.date)
                self.isSampling = false
                self.maybeCaptureSpike(snapshot)
                self.maybeLogMemoryEvent(snapshot)
            }
        }
    }

    /// When CPU crosses the spike threshold (and the cooldown has elapsed), run a
    /// one-off `ps` scan to record *what* spiked. Bounded by the threshold + cooldown
    /// in `CPUHistory`, and by `isCapturingSpike` so ticks never double-fire the scan.
    /// This is the only path that runs `ps` while the popover is closed.
    private func maybeCaptureSpike(_ snapshot: SystemSnapshot) {
        guard !isCapturingSpike,
              cpuHistory.shouldCaptureSpike(percent: snapshot.cpuPercent, at: snapshot.date)
        else { return }
        isCapturingSpike = true
        let monitor = self.monitor
        let date = snapshot.date
        let cpu = snapshot.cpuPercent
        Task.detached(priority: .utility) {
            let procs = monitor.sampleProcesses(top: 5)
            if let top = procs.topCPU.first {
                EventLog.append(kind: .cpu, percent: Int(cpu.rounded()),
                                name: top.name, at: date)
            }
            await MainActor.run {
                self.cpuHistory.recordSpike(SpikeEvent(
                    date: date,
                    cpuPercent: cpu,
                    processes: procs.topCPU
                ))
                self.isCapturingSpike = false
            }
        }
    }

    /// When RAM usage is high (and the cooldown has elapsed), record one memory
    /// event naming the current top-RAM process. Uses the already-sampled process
    /// list when the popover is open; otherwise runs one bounded `ps` scan.
    private func maybeLogMemoryEvent(_ snapshot: SystemSnapshot) {
        guard snapshot.ramPercent >= Self.memoryEventThreshold else { return }
        if let last = lastMemoryEventAt,
           snapshot.date.timeIntervalSince(last) < Self.memoryEventCooldown { return }
        lastMemoryEventAt = snapshot.date
        let monitor = self.monitor
        let date = snapshot.date
        let pct = Int(snapshot.ramPercent.rounded())
        let cached = processes.topRAM.first
        Task.detached(priority: .utility) {
            let name = cached?.name ?? monitor.sampleProcesses(top: 1).topRAM.first?.name
            guard let name else { return }
            EventLog.append(kind: .mem, percent: pct, name: name, at: date)
        }
    }

    /// Expensive `ps` process list — only runs while the popover is open.
    /// Safe to overlap with `refreshSystem()`: `sampleProcesses()` only shells out
    /// to `ps` and never touches `SystemMonitor.previousTicks`, so the non-concurrency-safe
    /// CPU-tick state (guarded separately by `isSampling`) is not shared with this path.
    func refreshProcesses() {
        let monitor = self.monitor
        Task.detached(priority: .utility) {
            let procs = monitor.sampleProcesses()
            await MainActor.run { self.processes = procs }
        }
    }

    /// Ends a process and refreshes the list. Surfaces a friendly message on failure.
    func endProcess(_ item: ProcessItem, force: Bool) {
        switch ProcessControl.terminate(pid: item.pid, force: force) {
        case .ok:
            processActionError = nil
            refreshProcesses()
        case .notPermitted:
            processActionError = "Couldn't end \(item.name) — it's owned by the system."
        case .notFound:
            processActionError = nil
            refreshProcesses()
        case .failed(let code):
            processActionError = "Couldn't end \(item.name) (error \(code))."
        }
    }

    /// Reveals the process's executable in Finder. No-op when the raw name is not a real path.
    func revealInFinder(_ item: ProcessItem) {
        guard canReveal(item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.rawName)])
    }

    /// Opens Activity Monitor so the user can inspect the process there.
    func openInActivityMonitor(_ item: ProcessItem) {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.open(url)
    }

    var eventLogExists: Bool { EventLog.fileExists }

    /// Opens the event log in the user's default handler (Console.app / TextEdit).
    func openEventLog() {
        guard EventLog.fileExists else { return }
        NSWorkspace.shared.open(EventLog.fileURL)
    }

    /// True when Reveal in Finder can act on this process (it has a real file path).
    func canReveal(_ item: ProcessItem) -> Bool {
        item.rawName.hasPrefix("/") && FileManager.default.fileExists(atPath: item.rawName)
    }

    func refreshSecurity(force: Bool = false) {
        if !force,
           let current = security,
           Date().timeIntervalSince(current.auditedAt) < Self.securityStaleAfter {
            return
        }
        Task.detached(priority: .utility) {
            let status = SecurityAuditor.audit()
            await MainActor.run { self.security = status }
        }
    }

    func refreshGitHub(force: Bool = false) {
        let user = githubUser.trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty, !githubLoading else { return }
        if !force,
           let cached = github,
           cached.user == user,
           Date().timeIntervalSince(cached.fetchedAt) < Self.githubInterval {
            return
        }
        githubLoading = true
        githubError = nil
        Task {
            let token = await Task.detached { GitHubAuth.token() }.value
            do {
                let snapshot = try await githubService.fetch(user: user, token: token)
                self.github = snapshot
                if let data = try? JSONEncoder().encode(snapshot.redactedForCache()) {
                    UserDefaults.standard.set(data, forKey: Keys.githubCache)
                }
            } catch {
                self.githubError = error.localizedDescription
            }
            self.githubLoading = false
        }
    }

    /// Parses local transcripts + fetches subscription limits. Tab-open-gated
    /// (skips when a recent snapshot exists) unless forced by the reload button.
    /// Only the resulting aggregates are cached — the OAuth token never is.
    func refreshClaudeUsage(force: Bool = false) {
        guard !claudeUsageLoading else { return }
        if !force, let snap = claudeUsage,
           Date().timeIntervalSince(snap.updatedAt) < Self.claudeUsageStaleAfter { return }
        claudeUsageLoading = true
        Task {
            let activity = await Task.detached(priority: .utility) {
                ClaudeUsageService.loadActivity()
            }.value
            let limits = await ClaudeUsageService.fetchLimits()
            let snapshot = ClaudeUsageSnapshot(activity: activity, limits: limits, updatedAt: Date())
            self.claudeUsage = snapshot
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: Keys.claudeUsage)
            }
            self.claudeUsageLoading = false
        }
    }

    func scanStorage() {
        guard !hotspotsScanning else { return }
        hotspotsScanning = true
        Task.detached(priority: .utility) {
            let result = StorageScanner.scan()
            await MainActor.run {
                self.hotspots = result
                self.hotspotsScanning = false
            }
        }
    }

    func scanLargeFiles() {
        guard !largeFilesScanning else { return }
        largeFilesScanning = true
        Task.detached(priority: .utility) {
            let result = FileScanner.scanLargeFiles()
            await MainActor.run {
                self.largeFiles = result
                self.largeFilesScanning = false
            }
        }
    }

    // MARK: - Derived

    var improvements: [Improvement] {
        var ctx = ImprovementContext()
        if let s = system {
            ctx.cpuPercent = s.cpuPercent
            ctx.ramPercent = s.ramPercent
            ctx.swapUsedGB = s.swapUsedGB
            ctx.diskPercent = s.diskPercent
            ctx.diskFreeGB = Double(s.diskFreeBytes) / 1_073_741_824
            ctx.uptimeDays = s.uptimeDays
        }
        if let top = processes.topCPU.first {
            ctx.topCPUProcessName = top.name
            ctx.topCPUProcessPct = top.cpuPercent
        }
        if let top = processes.topRAM.first {
            ctx.topRAMProcessName = top.name
            ctx.topRAMProcessPct = top.memPercent
        }
        ctx.security = security
        ctx.cachesMB = hotspots?.cachesMB
        ctx.trashMB = hotspots?.trashMB
        ctx.downloadsMB = hotspots?.downloadsMB
        return ImprovementsEngine.evaluate(ctx)
    }

    // MARK: - Private

    private func startTimers() {
        systemTimer?.invalidate()
        githubTimer?.invalidate()
        scheduleSystemTimer()

        let ghTimer = Timer.scheduledTimer(withTimeInterval: Self.githubInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refreshGitHub() }
        }
        ghTimer.tolerance = 60
        githubTimer = ghTimer
    }

    /// (Re)schedules the menu-bar sample timer at the current battery cadence and,
    /// on each tick, reschedules itself if the power source changed.
    private func scheduleSystemTimer() {
        systemTimer?.invalidate()
        let interval = Fmt.sampleInterval(onBattery: onBattery)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshSystem()
                let nowOnBattery = PowerSource.onBattery
                if nowOnBattery != self.onBattery {
                    self.onBattery = nowOnBattery
                    self.scheduleSystemTimer()
                }
            }
        }
        timer.tolerance = 2
        systemTimer = timer
    }

    private func applyLaunchAtLogin() {
        guard !isApplyingLoginItem else { return }
        isApplyingLoginItem = true
        defer { isApplyingLoginItem = false }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            // Registration only works when running from an installed .app bundle.
            loginItemError = "Couldn't update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
