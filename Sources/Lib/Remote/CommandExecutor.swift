// Sources/Lib/Remote/CommandExecutor.swift
import Foundation

/// Translates remote commands into cmux CLI invocations.
/// Commands are only valid for agents with cmux session info.
enum CommandExecutor {

    /// Build the cmux CLI argument arrays for a command.
    /// Returns an array of argument arrays — each is one cmux invocation.
    static func buildCommands(
        command: CommandType,
        cmuxSurface: String,
        cmuxSocketPath: String,
        text: String?
    ) -> [[String]] {
        let base = ["cmux", "--socket", cmuxSocketPath]

        switch command {
        case .approve:
            return [
                base + ["send-key", "--surface", cmuxSurface, "y"],
                base + ["send-key", "--surface", cmuxSurface, "Enter"],
            ]
        case .deny:
            return [
                base + ["send-key", "--surface", cmuxSurface, "Escape"]
            ]
        case .respond:
            guard let text, !text.isEmpty else { return [] }
            return [
                base + ["send", "--surface", cmuxSurface, text],
                base + ["send-key", "--surface", cmuxSurface, "Enter"],
            ]
        case .interrupt:
            return [
                base + ["send-key", "--surface", cmuxSurface, "C-c"]
            ]
        }
    }

    /// Execute a command against a cmux agent. Runs each sub-command sequentially.
    static func execute(
        command: CommandType,
        agent: Agent,
        text: String?
    ) async throws -> CommandResponse {
        guard let surface = agent.cmuxSurface else {
            return CommandResponse(success: false, error: "Agent has no cmux surface")
        }
        let socketPath = agent.cmuxSocketPath ?? "/tmp/cmux.sock"

        // Validate agent state for the command
        switch command {
        case .approve, .deny:
            guard agent.status == .permission else {
                return CommandResponse(success: false, error: "Agent is not in permission state")
            }
        case .respond:
            guard agent.status == .waiting || agent.status == .permission else {
                return CommandResponse(success: false, error: "Agent is not waiting for input")
            }
        case .interrupt:
            break // always allowed for cmux agents
        }

        let commands = buildCommands(
            command: command,
            cmuxSurface: surface,
            cmuxSocketPath: socketPath,
            text: text
        )
        guard !commands.isEmpty else {
            return CommandResponse(success: false, error: "No text provided for respond command")
        }

        for args in commands {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = args
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return CommandResponse(success: false, error: "cmux command failed with status \(process.terminationStatus)")
            }
        }

        return CommandResponse(success: true)
    }
}
