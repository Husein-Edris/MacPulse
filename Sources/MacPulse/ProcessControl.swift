import Darwin

/// Ends a process with a direct kill(2) syscall — no subprocess. Root-owned
/// processes fail with EPERM (we don't escalate with sudo).
enum ProcessControl {
    enum Outcome: Equatable {
        case ok
        case notPermitted   // EPERM — owned by another user / system
        case notFound       // ESRCH — already gone
        case failed(Int32)  // other errno
    }

    static func terminate(pid: Int32, force: Bool) -> Outcome {
        let sig = force ? SIGKILL : SIGTERM
        if kill(pid, sig) == 0 { return .ok }
        switch errno {
        case EPERM: return .notPermitted
        case ESRCH: return .notFound
        default:    return .failed(errno)
        }
    }
}
