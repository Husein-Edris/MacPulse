import Foundation

enum ImprovementSeverity: Int, Comparable {
    case critical = 0, warning = 1, info = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct Improvement: Identifiable, Equatable {
    let id: String
    let severity: ImprovementSeverity
    let icon: String
    let title: String
    let detail: String
    var actionTitle: String?
    var actionURL: URL?
}

struct ImprovementContext {
    var cpuPercent: Double?
    var ramPercent: Double?
    var diskPercent: Double?
    var diskFreeGB: Double?
    var uptimeDays: Double?
    var topCPUProcessName: String?
    var topCPUProcessPct: Double?
    var topRAMProcessName: String?
    var topRAMProcessPct: Double?
    var security: SecurityStatus?
    var cachesMB: Double?
    var trashMB: Double?
    var downloadsMB: Double?
}

/// Rule-based "what should I improve on this Mac" engine. Pure function — testable.
enum ImprovementsEngine {
    private static let securitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")
    private static let storageSettingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.Storage")

    static func evaluate(_ ctx: ImprovementContext) -> [Improvement] {
        var items: [Improvement] = []

        // --- Storage ---
        if let disk = ctx.diskPercent {
            if disk >= 90 {
                items.append(Improvement(
                    id: "disk-critical", severity: .critical, icon: "internaldrive",
                    title: "Disk almost full (\(Int(disk))%)",
                    detail: "Only \(String(format: "%.1f", ctx.diskFreeGB ?? 0)) GB free. macOS slows down and updates can fail below 10% free space.",
                    actionTitle: "Open Storage Settings", actionURL: storageSettingsURL
                ))
            } else if disk >= 80 {
                items.append(Improvement(
                    id: "disk-warning", severity: .warning, icon: "internaldrive",
                    title: "Disk filling up (\(Int(disk))%)",
                    detail: "\(String(format: "%.1f", ctx.diskFreeGB ?? 0)) GB free. Worth reviewing large files before it becomes urgent.",
                    actionTitle: "Open Storage Settings", actionURL: storageSettingsURL
                ))
            }
        }
        if let caches = ctx.cachesMB, caches >= 2048 {
            items.append(Improvement(
                id: "caches", severity: .info, icon: "folder.badge.minus",
                title: "User caches: \(String(format: "%.1f", caches / 1024)) GB",
                detail: "~/Library/Caches can be cleared safely — apps rebuild what they need.",
                actionTitle: "Reveal in Finder",
                actionURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
            ))
        }
        if let trash = ctx.trashMB, trash >= 1024 {
            items.append(Improvement(
                id: "trash", severity: .info, icon: "trash",
                title: "Trash holds \(String(format: "%.1f", trash / 1024)) GB",
                detail: "Emptying the Trash reclaims this space immediately.",
                actionTitle: "Open Trash",
                actionURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            ))
        }
        if let downloads = ctx.downloadsMB, downloads >= 5120 {
            items.append(Improvement(
                id: "downloads", severity: .info, icon: "arrow.down.circle",
                title: "Downloads folder: \(String(format: "%.1f", downloads / 1024)) GB",
                detail: "Old installers and archives tend to pile up here.",
                actionTitle: "Open Downloads",
                actionURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            ))
        }

        // --- Memory ---
        if let ram = ctx.ramPercent, ram >= 85 {
            var detail = "Memory pressure is high — apps will start swapping to disk."
            if let name = ctx.topRAMProcessName, let pct = ctx.topRAMProcessPct {
                detail += " Biggest consumer: \(name) (\(String(format: "%.1f", pct))%)."
            }
            items.append(Improvement(
                id: "ram", severity: ram >= 95 ? .critical : .warning, icon: "memorychip",
                title: "RAM usage at \(Int(ram))%",
                detail: detail
            ))
        }

        // --- CPU ---
        if let cpu = ctx.cpuPercent, cpu >= 85 {
            var detail = "Sustained high CPU drains battery and heats the machine."
            if let name = ctx.topCPUProcessName, let pct = ctx.topCPUProcessPct {
                detail += " Top process: \(name) (\(Int(pct))%)."
            }
            items.append(Improvement(
                id: "cpu", severity: .warning, icon: "cpu",
                title: "CPU at \(Int(cpu))%",
                detail: detail
            ))
        }

        // --- Uptime ---
        if let uptime = ctx.uptimeDays, uptime >= 14 {
            items.append(Improvement(
                id: "uptime", severity: .info, icon: "arrow.triangle.2.circlepath",
                title: "No restart in \(Int(uptime)) days",
                detail: "A restart clears leaked memory and applies pending maintenance tasks."
            ))
        }

        // --- Security ---
        if let sec = ctx.security {
            if sec.firewall == false {
                items.append(Improvement(
                    id: "firewall", severity: .critical, icon: "flame",
                    title: "Firewall is off",
                    detail: "Incoming connections are unfiltered. Turn it on in Network settings.",
                    actionTitle: "Open Security Settings", actionURL: securitySettingsURL
                ))
            }
            if sec.fileVault == false {
                items.append(Improvement(
                    id: "filevault", severity: .critical, icon: "lock.open",
                    title: "FileVault is off",
                    detail: "Your disk is unencrypted — anyone with physical access can read it.",
                    actionTitle: "Open Security Settings", actionURL: securitySettingsURL
                ))
            }
            if sec.sip == false {
                items.append(Improvement(
                    id: "sip", severity: .critical, icon: "shield.slash",
                    title: "System Integrity Protection disabled",
                    detail: "Re-enable SIP from macOS Recovery (csrutil enable) unless you disabled it deliberately."
                ))
            }
            if sec.gatekeeper == false {
                items.append(Improvement(
                    id: "gatekeeper", severity: .warning, icon: "checkmark.shield",
                    title: "Gatekeeper disabled",
                    detail: "Unsigned apps can run without warning. Re-enable with: sudo spctl --master-enable."
                ))
            }
        }

        return items.sorted { $0.severity < $1.severity }
    }
}
