import Foundation

struct SecurityStatus {
    /// nil = could not determine
    var firewall: Bool?
    var fileVault: Bool?
    var sip: Bool?
    var gatekeeper: Bool?
    var auditedAt: Date = Date()

    var allOn: Bool {
        [firewall, fileVault, sip, gatekeeper].allSatisfy { $0 == true }
    }
}

/// Queries the four macOS security subsystems via their first-party CLIs.
/// All status reads work without root; results are cached by AppState.
enum SecurityAuditor {
    static func audit() -> SecurityStatus {
        var status = SecurityStatus()
        if let out = Shell.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"]) {
            status.firewall = out.lowercased().contains("enabled")
        }
        if let out = Shell.run("/usr/bin/fdesetup", ["status"]) {
            status.fileVault = out.contains("On")
        }
        if let out = Shell.run("/usr/bin/csrutil", ["status"]) {
            status.sip = out.lowercased().contains("enabled")
        }
        if let out = Shell.run("/usr/sbin/spctl", ["--status"]) {
            status.gatekeeper = out.lowercased().contains("enabled")
        }
        return status
    }
}
