import Foundation
import Combine

enum TagInference {
    static let maxPromptChars = 3000

    /// Tag descriptions are the hints; editing one changes inference.
    static func buildPrompt(tags: [AgentTag], cwd: String?, firstPrompt: String) -> String {
        var lines: [String] = []
        lines.append("You classify a coding-agent session into exactly one tag based on the user's first prompt.")
        lines.append("")
        lines.append("Tags (id: when to use it):")
        for tag in tags {
            let hint = tag.description.isEmpty ? tag.name : tag.description
            lines.append("- \(tag.id): \(hint)")
        }
        lines.append("")
        lines.append("Rules:")
        lines.append("- Reply with only one tag id from the list above, or the word none if no tag fits.")
        lines.append("- No explanation, no punctuation, no quotes.")
        lines.append("")
        if let cwd, !cwd.isEmpty {
            lines.append("Working directory: \(cwd)")
        }
        lines.append("First user prompt:")
        lines.append("<<<")
        lines.append(String(firstPrompt.prefix(maxPromptChars)))
        lines.append(">>>")
        return lines.joined(separator: "\n")
    }

    static func parseResponse(_ text: String, tags: [AgentTag]) -> String? {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let cleaned = firstLine
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
            .lowercased()
        guard !cleaned.isEmpty, cleaned != "none" else { return nil }
        if let exact = tags.first(where: { $0.id.lowercased() == cleaned }) { return exact.id }
        if let byName = tags.first(where: { $0.name.lowercased() == cleaned }) { return byName.id }
        if let bySlug = tags.first(where: { $0.id == AgentTag.slug(from: cleaned) }) { return bySlug.id }
        let contained = tags.filter { cleaned.contains($0.id.lowercased()) }
        return contained.count == 1 ? contained[0].id : nil
    }

    /// Login shell so PATH matches the terminal. Blocks; call off the main thread.
    static func runClaude(prompt: String, model: String = "haiku", timeout: TimeInterval = 120) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // A neutral cwd keeps the call free of any project CLAUDE.md or settings.
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("claudeblobs-infer")
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        process.currentDirectoryURL = scratch
        process.arguments = [
            "-lc",
            "exec claude -p --model \(model) --output-format text --no-session-persistence --tools \"\" --setting-sources \"\"",
        ]
        var env = ProcessInfo.processInfo.environment
        env["CLAUDEBLOBS_INFERENCE"] = "1"
        process.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        stdin.fileHandleForWriting.write(Data(prompt.utf8))
        try? stdin.fileHandleForWriting.close()

        // Drain on background readers to avoid pipe deadlocks.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outData = stdout.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let deadline = DispatchTime.now() + timeout
        if finished.wait(timeout: deadline) == .timedOut {
            process.terminate()
            throw TagInferenceError.timeout
        }
        group.wait()

        let output = String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            let err = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw TagInferenceError.failed(err.isEmpty ? output : err)
        }
        return output
    }
}

enum TagInferenceError: Error, LocalizedError {
    case timeout
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .timeout: return "Inference timed out"
        case .failed(let message): return message.isEmpty ? "Inference failed" : String(message.prefix(200))
        }
    }
}

/// Fallback for sessions that predate `firstPrompt` in the status file.
enum TranscriptReader {
    static func projectDirectoryName(for cwd: String) -> String {
        String(cwd.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" { return Character(scalar) }
            return "-"
        })
    }

    static func transcriptURL(sessionId: String, cwd: String, projectsRoot: URL? = nil) -> URL {
        let root = projectsRoot
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        return root
            .appendingPathComponent(projectDirectoryName(for: cwd))
            .appendingPathComponent("\(sessionId).jsonl")
    }

    static func firstUserPrompt(sessionId: String, cwd: String, projectsRoot: URL? = nil) -> String? {
        firstUserPrompt(in: transcriptURL(sessionId: sessionId, cwd: cwd, projectsRoot: projectsRoot))
    }

    /// Skips sidechains, meta lines, and injected `<system-reminder>` / `<command-*>` content.
    static func firstUserPrompt(in url: URL, maxLines: Int = 200) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var buffer = Data()
        var linesSeen = 0
        while linesSeen < maxLines {
            let chunk = handle.readData(ofLength: 64 * 1024)
            if chunk.isEmpty {
                if let prompt = userPrompt(fromLine: buffer) { return prompt }
                return nil
            }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                linesSeen += 1
                if let prompt = userPrompt(fromLine: line) { return prompt }
                if linesSeen >= maxLines { return nil }
            }
        }
        return nil
    }

    static func userPrompt(fromLine line: Data) -> String? {
        guard !line.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              obj["type"] as? String == "user",
              obj["isSidechain"] as? Bool != true,
              obj["isMeta"] as? Bool != true,
              let message = obj["message"] as? [String: Any] else {
            return nil
        }
        var text: String?
        if let content = message["content"] as? String {
            text = content
        } else if let blocks = message["content"] as? [[String: Any]] {
            text = blocks.first { $0["type"] as? String == "text" }?["text"] as? String
        }
        guard let prompt = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prompt.isEmpty,
              !prompt.hasPrefix("<") else {
            return nil
        }
        return prompt
    }
}

final class TagInferenceCoordinator {
    typealias Runner = (String) throws -> String

    private let agentStore: AgentStore
    private let tagStore: TagStore
    private let runner: Runner
    private let queue: OperationQueue
    private var cancellables = Set<AnyCancellable>()

    init(
        agentStore: AgentStore,
        tagStore: TagStore,
        runner: @escaping Runner = { try TagInference.runClaude(prompt: $0) }
    ) {
        self.agentStore = agentStore
        self.tagStore = tagStore
        self.runner = runner
        self.queue = OperationQueue()
        self.queue.maxConcurrentOperationCount = 2
        self.queue.qualityOfService = .utility
    }

    func start() {
        agentStore.$agents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] agents in self?.scan(agents) }
            .store(in: &cancellables)
    }

    static func promptText(for agent: Agent) -> String? {
        if let prompt = agent.firstPrompt, !prompt.isEmpty { return prompt }
        guard let cwd = agent.cwd, agent.provider == .claudeCode else { return nil }
        return TranscriptReader.firstUserPrompt(sessionId: agent.sessionId, cwd: cwd)
    }

    func scan(_ agents: [Agent]) {
        guard !agents.isEmpty else { return }
        let topLevel = agents.filter { $0.parentSessionId == nil && $0.pid != 0 }
        tagStore.prune(liveSessionIds: Set(agents.map(\.sessionId)))
        for agent in topLevel where tagStore.needsInference(sessionId: agent.sessionId) {
            infer(agent)
        }
    }

    func infer(_ agent: Agent, force: Bool = false) {
        if force { tagStore.resetInference(sessionId: agent.sessionId) }
        guard !tagStore.inferringSessionIds.contains(agent.sessionId) else { return }
        let sessionId = agent.sessionId
        let tags = tagStore.tags
        tagStore.beginInference(sessionId: sessionId)
        let runner = self.runner
        queue.addOperation { [weak self] in
            // The transcript fallback reads a file; keep that off the main thread.
            guard let text = Self.promptText(for: agent) else {
                // Leave unattempted so a later scan retries.
                DispatchQueue.main.async { self?.tagStore.inferringSessionIds.remove(sessionId) }
                return
            }
            let prompt = TagInference.buildPrompt(tags: tags, cwd: agent.cwd, firstPrompt: text)
            DebugLog.shared.log("Tag inference started for \(sessionId)")
            do {
                let reply = try runner(prompt)
                let tagId = TagInference.parseResponse(reply, tags: tags)
                DispatchQueue.main.async {
                    DebugLog.shared.log("Tag inference for \(sessionId): \(reply.prefix(80)) → \(tagId ?? "none")")
                    self?.tagStore.finishInference(sessionId: sessionId, tagId: tagId)
                }
            } catch {
                DispatchQueue.main.async {
                    DebugLog.shared.log("Tag inference failed for \(sessionId): \(error.localizedDescription)")
                    self?.tagStore.failInference(sessionId: sessionId, error: error.localizedDescription)
                }
            }
        }
    }
}
