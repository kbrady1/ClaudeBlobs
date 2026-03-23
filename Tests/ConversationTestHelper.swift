import Foundation
@testable import ClaudeBlobsLib

/// A single step in a simulated conversation — one hook event with its JSON input.
struct ConversationStep {
    let hookScript: String
    let input: [String: Any]
    let environment: [String: String]?

    init(_ hookScript: String, input: [String: Any], environment: [String: String]? = nil) {
        self.hookScript = hookScript
        self.input = input
        self.environment = environment
    }
}

/// Expected state of a status file after a conversation step.
struct StatusAssertion {
    let fileId: String  // session or agent ID (filename without .json)
    let exists: Bool
    let status: String?
    let lastToolUse: String?
    let parentSessionId: String?
    let waitReason: String?
    let agentType: String?

    init(
        _ fileId: String,
        exists: Bool = true,
        status: String? = nil,
        lastToolUse: String? = nil,
        parentSessionId: String? = nil,
        waitReason: String? = nil,
        agentType: String? = nil
    ) {
        self.fileId = fileId
        self.exists = exists
        self.status = status
        self.lastToolUse = lastToolUse
        self.parentSessionId = parentSessionId
        self.waitReason = waitReason
        self.agentType = agentType
    }
}

/// Replays a sequence of hook events and provides helpers to inspect the resulting state.
class ConversationTestHelper {
    let hookHelper: HookTestHelper

    init() throws {
        hookHelper = try HookTestHelper()
    }

    /// Replay all steps in order.
    func replay(_ steps: [ConversationStep]) throws {
        for step in steps {
            try runStep(step)
        }
    }

    /// Replay steps, checking assertions at specified checkpoints.
    /// Key = step index (0-based, checked AFTER that step runs).
    func replayWithCheckpoints(
        _ steps: [ConversationStep],
        checkpoints: [Int: [StatusAssertion]]
    ) throws {
        for (i, step) in steps.enumerated() {
            try runStep(step)
            if let assertions = checkpoints[i] {
                try verify(assertions, afterStep: i)
            }
        }
    }

    /// Read a specific status file by ID (session or agent ID).
    func readStatus(_ fileId: String) throws -> [String: Any]? {
        let file = hookHelper.statusDir.appendingPathComponent("\(fileId).json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Check if a status file exists.
    func statusFileExists(_ fileId: String) -> Bool {
        let file = hookHelper.statusDir.appendingPathComponent("\(fileId).json")
        return FileManager.default.fileExists(atPath: file.path)
    }

    /// Read all status files and return as [filename-without-ext: parsed JSON].
    func allStatuses() throws -> [String: [String: Any]] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: hookHelper.statusDir, includingPropertiesForKeys: nil
        ) else { return [:] }
        var result: [String: [String: Any]] = [:]
        for file in files where file.pathExtension == "json" {
            let key = file.deletingPathExtension().lastPathComponent
            if let data = try? Data(contentsOf: file),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                result[key] = json
            }
        }
        return result
    }

    /// Load status files into an AgentStore and return agents + child mappings.
    /// Uses a fake isProcessAlive that returns true for all PIDs.
    func loadStore() -> AgentStore {
        let source = AgentStatusSource(provider: .claudeCode, directoryURL: hookHelper.statusDir)
        let store = AgentStore(
            statusSources: [source],
            enableWatcher: false,
            isProcessAlive: { _ in true }
        )
        store.reload()
        return store
    }

    /// Backdate a status file's `statusChangedAt` so race guards treat it as stale.
    func backdateStatus(_ fileId: String, bySeconds seconds: Int = 3) throws {
        let file = hookHelper.statusDir.appendingPathComponent("\(fileId).json")
        let data = try Data(contentsOf: file)
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let ts = json["statusChangedAt"] as? Int {
            json["statusChangedAt"] = ts - (seconds * 1000)
        }
        let updated = try JSONSerialization.data(withJSONObject: json)
        try updated.write(to: file)
    }

    // MARK: - Private

    private func runStep(_ step: ConversationStep) throws {
        // Determine the session ID from the input
        let sessionId = step.input["session_id"] as? String ?? "test-session"

        // Check if this is a subagent-specific hook (start/stop use agent_id for file naming)
        if step.hookScript.contains("subagent") {
            let agentId = step.input["agent_id"] as? String ?? ""
            try hookHelper.runSubagentHook(
                step.hookScript,
                sessionId: sessionId,
                subagentId: agentId,
                input: step.input,
                environment: step.environment
            )
        } else {
            try hookHelper.runHook(
                step.hookScript,
                sessionId: sessionId,
                input: step.input,
                environment: step.environment
            )
        }
    }

    private func verify(_ assertions: [StatusAssertion], afterStep step: Int) throws {
        for a in assertions {
            let exists = statusFileExists(a.fileId)
            guard exists == a.exists else {
                throw ConversationTestError.assertionFailed(
                    "Step \(step): expected file '\(a.fileId).json' exists=\(a.exists), got \(exists)"
                )
            }
            guard a.exists else { continue }

            guard let json = try readStatus(a.fileId) else {
                throw ConversationTestError.assertionFailed(
                    "Step \(step): could not read '\(a.fileId).json'"
                )
            }

            if let expected = a.status {
                let actual = json["status"] as? String
                guard actual == expected else {
                    throw ConversationTestError.assertionFailed(
                        "Step \(step): '\(a.fileId)' status expected '\(expected)', got '\(actual ?? "nil")'"
                    )
                }
            }
            if let expected = a.lastToolUse {
                let actual = json["lastToolUse"] as? String ?? ""
                guard actual.hasPrefix(expected) else {
                    throw ConversationTestError.assertionFailed(
                        "Step \(step): '\(a.fileId)' lastToolUse expected prefix '\(expected)', got '\(actual)'"
                    )
                }
            }
            if let expected = a.parentSessionId {
                let actual = json["parentSessionId"] as? String
                guard actual == expected else {
                    throw ConversationTestError.assertionFailed(
                        "Step \(step): '\(a.fileId)' parentSessionId expected '\(expected)', got '\(actual ?? "nil")'"
                    )
                }
            }
            if let expected = a.waitReason {
                let actual = json["waitReason"] as? String
                guard actual == expected else {
                    throw ConversationTestError.assertionFailed(
                        "Step \(step): '\(a.fileId)' waitReason expected '\(expected)', got '\(actual ?? "nil")'"
                    )
                }
            }
            if let expected = a.agentType {
                let actual = json["agentType"] as? String
                guard actual == expected else {
                    throw ConversationTestError.assertionFailed(
                        "Step \(step): '\(a.fileId)' agentType expected '\(expected)', got '\(actual ?? "nil")'"
                    )
                }
            }
        }
    }
}

enum ConversationTestError: Error, CustomStringConvertible {
    case assertionFailed(String)

    var description: String {
        switch self {
        case .assertionFailed(let msg): return msg
        }
    }
}
