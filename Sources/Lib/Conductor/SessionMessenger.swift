import Foundation
import AppKit
import ApplicationServices

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

    /// One committed action in an AskUserQuestion answer sequence.
    enum AnswerStep: Equatable {
        case select(Int)     // move the highlight to a 1-based option and press Enter
        case text(String)    // type text and press Enter
        case submit          // press Enter on the final review step
    }

    /// One answer per pending question, in order.
    enum Selection: Equatable {
        case option(Int)                       // 1-based option
        case typed(optionIndex: Int, text: String)  // choose "Type something" (1-based), then type
    }

    /// The highlight starts on option 1, ↓ moves it, Enter commits the
    /// question and advances. A multi-question prompt ends on a review step
    /// ("Submit answers" highlighted) that needs one more Enter. Text is only
    /// ever typed inside a question's "Type something" field — never on the
    /// review step, where letters move the highlight (e.g. onto Cancel).
    static func answerSteps(selections: [Selection]) -> [AnswerStep] {
        var steps: [AnswerStep] = []
        for selection in selections {
            switch selection {
            case .option(let n): steps.append(.select(n))
            case .typed(let n, let text):
                steps.append(.select(n))
                steps.append(.text(text))
            }
        }
        if selections.count > 1 && !steps.isEmpty { steps.append(.submit) }
        return steps
    }

    static func answer(selections: [Selection], to agent: Agent) async -> Result<Void, Error> {
        let steps = answerSteps(selections: selections)
        guard !steps.isEmpty else { return .failure(MessengerError.failed("Nothing to send")) }
        if channel(for: agent) == .superset {
            // The superset CLI pastes text, and the question menu ignores pasted
            // input. Focus the terminal and press real keys instead.
            guard isAccessibilityTrusted(prompt: true) else { return .failure(MessengerError.accessibilityDenied) }
            SupersetLinker.activate(agent)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        for (index, step) in steps.enumerated() {
            if index > 0 { try? await Task.sleep(nanoseconds: 450_000_000) }
            if case .failure(let error) = await perform(step, in: agent) { return .failure(error) }
        }
        return .success(())
    }

    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func perform(_ step: AnswerStep, in agent: Agent) async -> Result<Void, Error> {
        switch (channel(for: agent), step) {
        case (.superset?, .select(let option)):
            return await pressKeys(Array(repeating: 125, count: max(0, option - 1)) + [36])
        case (.superset?, .text(let text)):
            return await typeText(text)
        case (.superset?, .submit):
            return await pressKeys([36])
        case (.cmux?, .select(let option)):
            for _ in 0..<max(0, option - 1) {
                guard CommandExecutor.sendKey("down", agent: agent) else { return .failure(MessengerError.failed("cmux send-key down failed")) }
            }
            return cmuxResult(CommandExecutor.sendKey("enter", agent: agent), "send-key enter")
        case (.cmux?, .text(let text)):
            guard CommandExecutor.sendText(text, agent: agent) else { return .failure(MessengerError.failed("cmux send failed")) }
            return cmuxResult(CommandExecutor.sendKey("enter", agent: agent), "send-key enter")
        case (.cmux?, .submit):
            return cmuxResult(CommandExecutor.sendKey("enter", agent: agent), "send-key enter")
        case (nil, _):
            return .failure(MessengerError.noChannel)
        }
    }

    /// Key codes: 125 = ↓, 36 = Return. Sent to the frontmost app.
    private static func pressKeys(_ codes: [Int]) async -> Result<Void, Error> {
        let body = codes.map { "key code \($0)\ndelay 0.15" }.joined(separator: "\n")
        let ok = await AppleScriptRunner.run("tell application \"System Events\"\n\(body)\nend tell")
        return ok ? .success(()) : .failure(MessengerError.failed("Key press failed"))
    }

    private static func typeText(_ text: String) async -> Result<Void, Error> {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let ok = await AppleScriptRunner.run("tell application \"System Events\"\nkeystroke \"\(escaped)\"\ndelay 0.15\nkey code 36\nend tell")
        return ok ? .success(()) : .failure(MessengerError.failed("Typing failed"))
    }

    private static func cmuxResult(_ ok: Bool, _ what: String) -> Result<Void, Error> {
        ok ? .success(()) : .failure(MessengerError.failed("cmux \(what) failed"))
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
    case accessibilityDenied
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noChannel: return "This session has no superset or cmux channel to send to"
        case .accessibilityDenied: return "Allow ClaudeBlobs under System Settings → Privacy & Security → Accessibility, then retry"
        case .failed(let message): return String(message.prefix(200))
        }
    }
}
