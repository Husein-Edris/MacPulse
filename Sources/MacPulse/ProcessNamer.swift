import Foundation

/// How risky it is to quit a process, in plain terms.
enum ProcessSafety: Equatable {
    case safe      // a user app or browser tab; closing it just closes that thing
    case caution   // a background helper; usually fine but may interrupt something
    case system    // core macOS; leave it running
}

/// The human-readable identity of a process, derived from its raw `ps` string.
struct ProcessLabel: Equatable {
    let name: String
    let detail: String?
    let safety: ProcessSafety
}

/// Pure mapping from a raw `ps comm` value (a full executable path, or a bare
/// name / reverse-DNS id for kernel and helper processes) to a friendly label.
/// No syscalls, no I-O, so it is unit-testable without XCTest.
enum ProcessNamer {

    /// Curated dictionary for daemons and helpers that have no user-facing `.app`.
    /// Keyed by the executable basename or a reverse-DNS id (matched case-sensitively).
    private static let known: [String: ProcessLabel] = [
        "WindowServer":     ProcessLabel(name: "macOS display engine", detail: "draws everything on screen", safety: .system),
        "kernel_task":      ProcessLabel(name: "macOS CPU manager", detail: "protects the CPU from overheating", safety: .system),
        "launchd":          ProcessLabel(name: "macOS service manager", detail: "starts background services", safety: .system),
        "mds":              ProcessLabel(name: "Spotlight indexing", detail: "building the search index", safety: .caution),
        "mds_stores":       ProcessLabel(name: "Spotlight indexing", detail: "building the search index", safety: .caution),
        "mdworker":         ProcessLabel(name: "Spotlight indexing", detail: "building the search index", safety: .caution),
        "mdworker_shared":  ProcessLabel(name: "Spotlight indexing", detail: "building the search index", safety: .caution),
        "assistantd":       ProcessLabel(name: "Siri and Suggestions", detail: "on-device assistant", safety: .caution),
        "assistant_service":ProcessLabel(name: "Siri and Suggestions", detail: "on-device assistant", safety: .caution),
        "photoanalysisd":   ProcessLabel(name: "Photos analysis", detail: "scanning your photo library", safety: .caution),
        "backupd":          ProcessLabel(name: "Time Machine backup", detail: "backing up your Mac", safety: .caution),
        "com.apple.WebKit.WebContent":   ProcessLabel(name: "Safari web page", detail: "a browser tab", safety: .safe),
        "com.apple.WebKit.GPU":          ProcessLabel(name: "Safari (helper)", detail: "browser graphics", safety: .safe),
        "com.apple.WebKit.Networking":   ProcessLabel(name: "Safari (helper)", detail: "browser networking", safety: .safe),
    ]

    static func label(for raw: String) -> ProcessLabel {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        // 1. A real app: use the outermost ".app" component's base name.
        if let app = outermostAppName(in: trimmed) {
            if isBrowserRenderer(trimmed) {
                return ProcessLabel(name: app, detail: "a browser tab", safety: .safe)
            }
            if isHelper(trimmed) {
                return ProcessLabel(name: app, detail: "a helper process", safety: .safe)
            }
            return ProcessLabel(name: app, detail: nil, safety: .safe)
        }

        // 2. Known daemon / helper by basename or reverse-DNS id.
        let base = (trimmed as NSString).lastPathComponent
        if let hit = known[trimmed] ?? known[base] {
            return hit
        }

        // 3. Fallback: cleaned basename, caution.
        return ProcessLabel(name: cleaned(base), detail: nil, safety: .caution)
    }

    /// The name (without ".app") of the FIRST ".app" bundle in the path, or nil.
    private static func outermostAppName(in path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            if component.hasSuffix(".app") {
                return String(component.dropLast(4))   // strip ".app"
            }
        }
        return nil
    }

    private static func isBrowserRenderer(_ path: String) -> Bool {
        let p = path.lowercased()
        return p.contains("(renderer)") || p.contains("webcontent")
    }

    private static func isHelper(_ path: String) -> Bool {
        path.lowercased().contains("helper")
    }

    /// Strip a leading reverse-DNS prefix (com.apple., com.google., ...) so the
    /// fallback shows the meaningful tail rather than the vendor id.
    private static func cleaned(_ base: String) -> String {
        let parts = base.split(separator: ".")
        if parts.count >= 3, parts[0] == "com" || parts[0] == "org" || parts[0] == "io" {
            return String(parts.last ?? Substring(base))
        }
        return base
    }
}
