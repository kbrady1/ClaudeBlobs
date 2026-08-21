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
        case select(Int)                 // move the highlight to a 1-based row and press Enter
        case typeInto(Int, String)       // move to the "Type something" row, type, then Enter
        case text(String)                // type into the current input and press Enter
        case submit                      // Enter on the final review step
    }

    /// One answer per pending question, in order.
    enum Selection: Equatable {
        case option(Int)                       // 1-based option
        case typed(optionIndex: Int, text: String)  // choose "Type something" (1-based), then type
        /// Choose "Chat about this" (1-based) and send a general reply instead of answers.
        case chat(optionIndex: Int, text: String)
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
                // "Type something" is an inline field: move there, type, then Enter.
                // Enter on the empty row declines the whole question set.
                steps.append(.typeInto(n, text))
            case .chat(let n, let text):
                // Leaves the question flow entirely; no review step follows.
                return [.select(n), .text(text)]
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
            try? await Task.sleep(nanoseconds: 1_500_000_000)
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
            return await selectVerified(option, in: agent)
        case (.superset?, .typeInto(let row, let text)):
            if case .failure(let error) = await moveHighlight(to: row, in: agent) { return .failure(error) }
            return await typeText(text)
        case (.superset?, .text(let text)):
            return await typeText(text)
        case (.superset?, .submit):
            // The review step highlights "Submit answers" (row 1); make sure of it.
            return await selectVerified(1, in: agent)
        case (.cmux?, .select(let option)):
            for _ in 0..<max(0, option - 1) {
                guard CommandExecutor.sendKey("down", agent: agent) else { return .failure(MessengerError.failed("cmux send-key down failed")) }
            }
            return cmuxResult(CommandExecutor.sendKey("enter", agent: agent), "send-key enter")
        case (.cmux?, .typeInto(let row, let text)):
            for _ in 0..<max(0, row - 1) {
                guard CommandExecutor.sendKey("down", agent: agent) else { return .failure(MessengerError.failed("cmux send-key down failed")) }
            }
            guard CommandExecutor.sendText(text, agent: agent) else { return .failure(MessengerError.failed("cmux send failed")) }
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

    /// Moves the highlight to `option` by reading the screen and nudging, then
    /// presses Return. Blind arrow counts drift right after the focus switch.
    private static func selectVerified(_ option: Int, in agent: Agent) async -> Result<Void, Error> {
        if case .failure(let error) = await moveHighlight(to: option, in: agent) { return .failure(error) }
        return await pressKeys([36])
    }

    private static func moveHighlight(to option: Int, in agent: Agent) async -> Result<Void, Error> {
        for attempt in 0..<4 {
            guard let current = highlightedRow(in: agent) else {
                // No menu visible: fall back to a blind move on the first try.
                if attempt == 0 {
                    let moves = Array(repeating: 125, count: max(0, option - 1))
                    if !moves.isEmpty, case .failure(let error) = await pressKeys(moves) { return .failure(error) }
                    continue
                }
                break
            }
            if current == option { break }
            let delta = option - current
            let moves = Array(repeating: delta > 0 ? 125 : 126, count: abs(delta))
            if case .failure(let error) = await pressKeys(moves) { return .failure(error) }
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
        return .success(())
    }

    /// Row number of the "❯ N." highlight on the terminal screen, if a menu is showing.
    static func highlightedRow(in agent: Agent) -> Int? {
        guard let screen = readScreen(agent) else { return nil }
        return highlightedRow(inScreen: screen)
    }

    static func highlightedRow(inScreen screen: String) -> Int? {
        let lines = screen.split(separator: "\n")
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("❯") else { continue }
            let rest = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            let digits = rest.prefix { $0.isNumber }
            if let n = Int(digits), rest.dropFirst(digits.count).hasPrefix(".") { return n }
        }
        return nil
    }

    private static func readScreen(_ agent: Agent) -> String? {
        guard let workspace = agent.supersetWorkspace, let terminal = agent.supersetTerminal else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "exec superset terminals read --workspace \(shellQuote(workspace)) --terminal \(shellQuote(terminal))"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["text"] as? String
    }

    /// Key codes: 125 = ↓, 126 = ↑, 36 = Return. Sent to the frontmost app.
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
