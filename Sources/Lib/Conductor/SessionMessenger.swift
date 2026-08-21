import Foundation

enum SessionMessenger {
    enum Channel: String {
        case superset, cmux
    }

    static func channel(for agent: Agent) -> Channel? {
        if agent.isSupersetSession, agent.supersetTerminal != nil { return .superset }
        if agent.isCmuxSession { return .cmux }
        return nil
    }

    static func canMessage(_ agent: Agent) -> Bool { channel(for: agent) != nil }

    static func send(text: String, to agent: Agent) async -> Result<Void, Error> {
        switch channel(for: agent) {
        case .superset?:
            return runSuperset(args: ["terminals", "send",
                                      "--workspace", agent.supersetWorkspace ?? "",
                                      "--terminal", agent.supersetTerminal ?? "",
                                      "--text", text])
        case .cmux?:
            do {
                let response = try await CommandExecutor.execute(command: .respond, agent: agent, text: text)
                return response.success ? .success(()) : .failure(MessengerError.failed(response.error ?? "cmux send failed"))
            } catch {
                return .failure(error)
            }
        case nil:
            return .failure(MessengerError.noChannel)
        }
    }

    /// Claude shows questions one at a time, so the sends are spaced 600ms apart.
    static func answer(choices: [Int], freeText: String?, freeTextOption: Int?, to agent: Agent) async -> Result<Void, Error> {
        var steps: [String] = choices.map(String.init)
        if let freeText, !freeText.isEmpty {
            if let freeTextOption { steps.append(String(freeTextOption)) }
            steps.append(freeText)
        }
        guard !steps.isEmpty else { return .failure(MessengerError.failed("Nothing to send")) }
        for (index, step) in steps.enumerated() {
            if index > 0 { try? await Task.sleep(nanoseconds: 600_000_000) }
            if case .failure(let error) = await send(text: step, to: agent) { return .failure(error) }
        }
        return .success(())
    }

    static func approve(_ agent: Agent) async -> Result<Void, Error> {
        switch channel(for: agent) {
        case .superset?:
            // Claude's permission menu acts on the number key itself, so stage "1" without Enter.
            return runSuperset(args: ["terminals", "send",
                                      "--workspace", agent.supersetWorkspace ?? "",
                                      "--terminal", agent.supersetTerminal ?? "",
                                      "--text", "1", "--no-submit"])
        case .cmux?:
            do {
                let response = try await CommandExecutor.execute(command: .selectOption, agent: agent, text: nil, optionIndex: 0)
                return response.success ? .success(()) : .failure(MessengerError.failed(response.error ?? "cmux approve failed"))
            } catch {
                return .failure(error)
            }
        case nil:
            return .failure(MessengerError.noChannel)
        }
    }

    /// Runs the `superset` CLI through a login shell so PATH matches the terminal.
    private static func runSuperset(args: [String]) -> Result<Void, Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let quoted = args.map { Self.shellQuote($0) }.joined(separator: " ")
        process.arguments = ["-lc", "exec superset \(quoted)"]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .failure(error)
        }
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            DebugLog.shared.log("SessionMessenger: superset failed (\(process.terminationStatus)): \(message)")
            return .failure(MessengerError.failed(message.isEmpty ? "superset exited \(process.terminationStatus)" : message))
        }
        return .success(())
    }

    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum MessengerError: Error, LocalizedError {
    case noChannel
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noChannel: return "This session has no superset or cmux channel to send to"
        case .failed(let message): return String(message.prefix(200))
        }
    }
}
