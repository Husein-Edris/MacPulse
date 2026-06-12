import SwiftUI
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    // MARK: - Live data
    @Published var system: SystemSnapshot?
    @Published var processes = ProcessSnapshot(topCPU: [], topRAM: [])
    @Published var security: SecurityStatus?
    @Published var github: GitHubSnapshot?
    @Published var githubError: String?
    @Published var githubLoading = false
    @Published var hotspots: StorageHotspots?
    @Published var hotspotsScanning = false
    @Published var backup: BackupStatus?
    @Published var loginItemError: String?

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
        static let githubCache = "githubSnapshotCache"
    }

    private let monitor = SystemMonitor()
    private let githubService = GitHubService()
    private var systemTimer: Timer?
    private var githubTimer: Timer?
    private var processTimer: Timer?
    private var isPopoverOpen = false
    private var onBattery = PowerSource.onBattery
    private static let processInterval: TimeInterval = 5
    private var isApplyingLoginItem = false

    private static let githubInterval: TimeInterval = 900       // 15 min
    private static let securityStaleAfter: TimeInterval = 1_800 // 30 min

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
    func refreshSystem() {
        let monitor = self.monitor
        Task.detached(priority: .utility) {
            let snapshot = monitor.sample()
            await MainActor.run { self.system = snapshot }
        }
    }

    /// Expensive `ps` process list — only runs while the popover is open.
    func refreshProcesses() {
        let monitor = self.monitor
        Task.detached(priority: .utility) {
            let procs = monitor.sampleProcesses()
            await MainActor.run { self.processes = procs }
        }
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
            do {
                let snapshot = try await githubService.fetch(user: user)
                self.github = snapshot
                if let data = try? JSONEncoder().encode(snapshot) {
                    UserDefaults.standard.set(data, forKey: Keys.githubCache)
                }
            } catch {
                self.githubError = error.localizedDescription
            }
            self.githubLoading = false
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

    // MARK: - Derived

    var improvements: [Improvement] {
        var ctx = ImprovementContext()
        if let s = system {
            ctx.cpuPercent = s.cpuPercent
            ctx.ramPercent = s.ramPercent
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
