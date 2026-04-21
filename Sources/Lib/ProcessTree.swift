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

    /// Returns argv for the given PID via KERN_PROCARGS2, or nil if unavailable.
    /// Layout: [argc:Int32][argv[0] (exec path, NUL-padded)][argv[0]\0][argv[1]\0]...[envp...]
    static func argv(of pid: Int32) -> [String]? {
        var argMax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var mibMax: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mibMax, 2, &argMax, &size, nil, 0) == 0 else { return nil }

        var bufSize = Int(argMax)
        var buffer = [UInt8](repeating: 0, count: bufSize)
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        let ok = buffer.withUnsafeMutableBufferPointer { ptr -> Bool in
            sysctl(&mib, 3, ptr.baseAddress, &bufSize, nil, 0) == 0
        }
        guard ok, bufSize >= MemoryLayout<Int32>.size else { return nil }

        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc > 0 else { return nil }

        // Skip the argc header and the exec path (NUL-terminated, may be NUL-padded).
        var index = MemoryLayout<Int32>.size
        // Skip exec path terminator(s)
        while index < bufSize && buffer[index] != 0 { index += 1 }
        while index < bufSize && buffer[index] == 0 { index += 1 }

        var args: [String] = []
        args.reserveCapacity(Int(argc))
        var tokenStart = index
        while index < bufSize && args.count < Int(argc) {
            if buffer[index] == 0 {
                let slice = Array(buffer[tokenStart..<index])
                if let s = String(bytes: slice, encoding: .utf8) {
                    args.append(s)
                }
                tokenStart = index + 1
            }
            index += 1
        }
        return args
    }

    /// Returns true if the process was launched as a headless `claude -p` / `--print` invocation.
    /// These are sub-processes spawned by another agent (e.g. Maestro heal steps) rather than
    /// interactive user sessions, and should be hidden from the menu bar list.
    static func isHeadlessClaudeInvocation(pid: Int32) -> Bool {
        guard pid > 0, let argv = argv(of: pid), argv.count > 1 else { return false }
        // Skip argv[0] (binary path) — match -p / --print as standalone tokens only.
        return argv.dropFirst().contains { $0 == "-p" || $0 == "--print" }
    }
}
