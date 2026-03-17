import Darwin

enum ProcessTree {
    /// Returns the parent PID of the given process using sysctl (no subprocess spawning).
    static func parentPid(of pid: Int32) -> Int32 {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return -1 }
        return info.kp_eproc.e_ppid
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
