import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

final class DoneClassifier {

    /// Classify whether an agent message indicates "done" or "question".
    /// Returns nil on any failure (timeout, unavailable, parse error) so the caller keeps the regex result.
    func classify(message: String) async -> String? {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *) else { return nil }
        return await classifyWithFoundationModels(message: message)
        #else
        return nil
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private func classifyWithFoundationModels(message: String) async -> String? {
        do {
            let session = LanguageModelSession(
                instructions: """
                Classify a coding AI agent's message as "done" or "question". Respond with exactly one word.

                IMPORTANT: Focus on the LAST FEW SENTENCES of the message. Ignore completion language at the beginning.

                Reply "question" if the message ends with ANY of these:
                - A question mark
                - A request for confirmation: "shall I", "should I", "want me to", "would you like", "sound good", "look right"
                - A suggestion to verify: "try running", "test it", "check if", "take a look", "let me know", "run it"
                - An offer to do more: "ready to", "like me to", "go ahead", "proceed"

                Reply "done" ONLY if the message does NOT end with any of the above AND the agent is reporting that work is finished.

                Default to "question" if unclear.
                """
            )

            DebugLog.shared.log("DoneClassifier: sending message (\(message.prefix(80))...)")
            let response = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    let result = try await session.respond(to: message)
                    return result.content
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(5))
                    throw CancellationError()
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }

            let result = parseResponse(response)
            DebugLog.shared.log("DoneClassifier: raw response=\(response.prefix(50)) parsed=\(result ?? "nil")")
            return result
        } catch {
            DebugLog.shared.log("DoneClassifier: error: \(error)")
            return nil
        }
    }
    #endif

    private func parseResponse(_ response: String) -> String? {
        let firstWord = response.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ")
            .first
            .map(String.init)

        switch firstWord {
        case "done": return "done"
        case "question": return "question"
        default: return nil
        }
    }
}
