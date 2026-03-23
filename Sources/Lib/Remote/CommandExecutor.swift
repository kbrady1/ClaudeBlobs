// Sources/Lib/Remote/CommandExecutor.swift
import Foundation

/// Translates remote commands into cmux CLI invocations.
/// Commands are only valid for agents with cmux session info.
enum CommandExecutor {

    private static let cmuxPath = "/Applications/cmux.app/Contents/Resources/bin/cmux"

    /// Build cmux args for surface-targeted commands.
    private static func cmuxBase(socketPath: String) -> [String] {
        [cmuxPath, "--socket", socketPath]
    }

    private static func surfaceArgs(_ surface: String, workspace: String?) -> [String] {
        var args = ["--surface", surface]
        if let workspace { args += ["--workspace", workspace] }
        return args
    }

    /// Read the current screen content of a cmux surface.
    static func readScreen(surface: String, workspace: String?, socketPath: String) -> String? {
        let args = cmuxBase(socketPath: socketPath) + ["read-screen"] + surfaceArgs(surface, workspace: workspace)
        return runProcess(args)
    }

    /// Parse permission options from a Claude Code permission prompt screen.
    /// Looks for lines like "❯ 1. Yes, and tell Claude..." or "  2. Yes, allow all..."
    static func parsePermissionOptions(from screenText: String) -> [String] {
        var options: [String] = []
        for line in screenText.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match "❯ N. <text>" or "N. <text>" where N is a digit
            // Also handle lines starting with just the number
            let stripped = trimmed
                .replacingOccurrences(of: "❯ ", with: "")
                .replacingOccurrences(of: "❯", with: "")
                .trimmingCharacters(in: .whitespaces)

            // Check if it starts with "N. " pattern
            if let firstChar = stripped.first, firstChar.isNumber,
               stripped.count > 2, stripped.dropFirst().first == "." {
                let text = String(stripped.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    options.append(text)
                }
            }
        }
        return options
    }

    /// Find which option index the cursor (❯) is currently on (0-based).
    static func currentCursorIndex(from screenText: String) -> Int {
        var index = 0
        for line in screenText.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("❯") {
                return index
            }
            // Count numbered options to track position
            let stripped = trimmed.replacingOccurrences(of: "❯ ", with: "").replacingOccurrences(of: "❯", with: "").trimmingCharacters(in: .whitespaces)
            if let firstChar = stripped.first, firstChar.isNumber,
               stripped.count > 2, stripped.dropFirst().first == "." {
                let text = String(stripped.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { index += 1 }
            }
        }
        return 0
    }

    /// Execute a command against a cmux agent.
    static func execute(
        command: CommandType,
        agent: Agent,
        text: String?,
        optionIndex: Int? = nil
    ) async throws -> CommandResponse {
        guard let surface = agent.cmuxSurface else {
            return CommandResponse(success: false, error: "Agent has no cmux surface")
        }
        let socketPath = agent.cmuxSocketPath ?? "/tmp/cmux.sock"
        let sArgs = surfaceArgs(surface, workspace: agent.cmuxWorkspace)
        let base = cmuxBase(socketPath: socketPath)

        // Validate agent state
        switch command {
        case .approve, .deny, .selectOption:
            guard agent.status == .permission else {
                return CommandResponse(success: false, error: "Agent is not in permission state")
            }
        case .respond:
            guard agent.status != .working && agent.status != .compacting else {
                return CommandResponse(success: false, error: "Agent is currently working")
            }
        case .interrupt:
            break
        }

        // Build and run command sequences
        var commands: [[String]] = []

        switch command {
        case .selectOption:
            guard let targetIndex = optionIndex else {
                return CommandResponse(success: false, error: "No option index provided")
            }

            // Type the 1-based option number — Claude's permission menu accepts number keys
            let optionNumber = "\(targetIndex + 1)"
            commands.append(base + ["send"] + sArgs + [optionNumber])

        case .approve:
            // Legacy: select first option
            commands.append(base + ["send-key"] + sArgs + ["enter"])

        case .deny:
            commands.append(base + ["send-key"] + sArgs + ["escape"])

        case .respond:
            guard let text, !text.isEmpty else {
                return CommandResponse(success: false, error: "No text provided")
            }
            commands.append(base + ["send"] + sArgs + [text])
            commands.append(base + ["send-key"] + sArgs + ["enter"])

        case .interrupt:
            commands.append(base + ["send-key"] + sArgs + ["ctrl+c"])
        }

        // Execute sequentially
        for args in commands {
            let result = runProcessWithStatus(args)
            guard result.status == 0 else {
                let detail = "cmux failed (status \(result.status)): args=\(args) stderr=\(result.stderr)"
                DebugLog.shared.log("CommandExecutor: \(detail)")
                return CommandResponse(success: false, error: detail)
            }
            // Small delay between keystrokes for UI to update
            if commands.count > 1 {
                try await Task.sleep(for: .milliseconds(100))
            }
        }

        return CommandResponse(success: true)
    }

    // MARK: - Process helpers

    private static func runProcess(_ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func runProcessWithStatus(_ args: [String]) -> (status: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())
        process.standardOutput = FileHandle.nullDevice
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}
