import AppKit

struct TerminalLinker {
    static func activate(_ agent: Agent) {
        let pid = Int32(agent.pid)
        var currentPid = pid
        for _ in 0..<10 {
            let parentPid = parentProcess(of: currentPid)
            if parentPid <= 1 { break }
            if let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.processIdentifier == parentPid
            }) {
                app.activate()
                return
            }
            currentPid = parentPid
        }
    }

    private static func parentProcess(of pid: Int32) -> Int32 {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "ppid=", "-p", "\(pid)"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespaces) ?? ""
            return Int32(output) ?? -1
        } catch {
            return -1
        }
    }
}
