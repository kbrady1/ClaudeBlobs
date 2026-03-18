import Darwin
import Foundation

enum ProcessTree {
    /// Returns the parent PID of the given process using sysctl (no subprocess spawning).
    static func parentPid(of pid: Int32) -> Int32 {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return -1 }
        return info.kp_eproc.e_ppid
    }

    /// Returns the controlling TTY of the given process as `/dev/ttysNNN`, or nil.
    static func controllingTTY(of pid: Int32) -> String? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let tdev = info.kp_eproc.e_tdev
        guard tdev != -1 && tdev != 0 else { return nil }
        let minor = Int(tdev & 0xFFFFFF)
        let path = "/dev/ttys\(String(format: "%03d", minor))"
        return path
    }

    /// Walks up the process tree (max 5 levels) looking for a valid controlling TTY.
    static func resolveTTY(of pid: Int32) -> String? {
        var current = pid
        for _ in 0..<5 {
            if let tty = controllingTTY(of: current) {
                return tty
            }
            let parent = parentPid(of: current)
            if parent <= 1 { break }
            current = parent
        }
        return nil
    }

    /// Walks up the process tree from `pid`, calling `check` on each ancestor.
    /// Returns the first PID for which `check` returns true, or nil.
    static func findAncestor(of pid: Int32, maxDepth: Int = 20, where check: (Int32) -> Bool) -> Int32? {
        var current = pid
        for _ in 0..<maxDepth {
            let parent = parentPid(of: current)
            if parent <= 1 { break }
            if check(parent) { return parent }
            current = parent
        }
        return nil
    }
}
