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
    @Published var analysis: LinkedInAnalysis?
    @Published var loginItemError: String?

    @Published var profile: LinkedInProfile {
        didSet {
            saveProfile()
            analysis = profile.isEmpty ? nil : LinkedInAnalyzer.analyze(profile)
        }
    }

    // MARK: - Settings
    @Published var githubUser: String {
        didSet { UserDefaults.standard.set(githubUser, forKey: Keys.githubUser) }
    }
    @Published var showCPUInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showCPUInMenuBar, forKey: Keys.showCPU) }
    }
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    private enum Keys {
        static let githubUser = "githubUser"
        static let showCPU = "showCPUInMenuBar"
        static let profile = "linkedinProfile"
        static let githubCache = "githubSnapshotCache"
    }

    private let monitor = SystemMonitor()
    private let githubService = GitHubService()
    private var systemTimer: Timer?
    private var githubTimer: Timer?
    private var isApplyingLoginItem = false

    private static let systemInterval: TimeInterval = 5
    private static let githubInterval: TimeInterval = 900       // 15 min
    private static let securityStaleAfter: TimeInterval = 1_800 // 30 min

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        githubUser = defaults.string(forKey: Keys.githubUser) ?? "Husein-Edris"
        showCPUInMenuBar = defaults.object(forKey: Keys.showCPU) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled

        if let data = defaults.data(forKey: Keys.profile),
           let saved = try? JSONDecoder().decode(LinkedInProfile.self, from: data) {
            profile = saved
        } else {
            profile = LinkedInProfile()
        }
        if let data = defaults.data(forKey: Keys.githubCache),
           let cached = try? JSONDecoder().decode(GitHubSnapshot.self, from: data) {
            github = cached
        }
        if !profile.isEmpty {
            analysis = LinkedInAnalyzer.analyze(profile)
        }

        startTimers()
        refreshSystem()
        refreshSecurity(force: true)
        refreshGitHub()
    }

    // MARK: - Refresh

    func refreshAll() {
        refreshSystem()
        refreshSecurity(force: true)
        refreshGitHub(force: true)
    }

    func popoverOpened() {
        refreshSystem()
        refreshSecurity()
        refreshGitHub()
    }

    func refreshSystem() {
        let monitor = self.monitor
        Task.detached(priority: .utility) {
            let snapshot = monitor.sample()
            let procs = monitor.sampleProcesses()
            await MainActor.run {
                self.system = snapshot
                self.processes = procs
            }
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

        let sysTimer = Timer.scheduledTimer(withTimeInterval: Self.systemInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refreshSystem() }
        }
        sysTimer.tolerance = 2
        systemTimer = sysTimer

        let ghTimer = Timer.scheduledTimer(withTimeInterval: Self.githubInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refreshGitHub() }
        }
        ghTimer.tolerance = 60
        githubTimer = ghTimer
    }

    private func saveProfile() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: Keys.profile)
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
