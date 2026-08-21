import SwiftUI

/// `description` doubles as the inference hint.
struct AgentTag: Codable, Identifiable, Equatable, Hashable {
    /// Slug; also the token the inference model replies with.
    let id: String
    var name: String
    var description: String
    var colorHex: String

    var color: Color { Color(hex: colorHex) ?? .gray }

    static func slug(from name: String) -> String {
        let lowered = name.lowercased()
        let allowed = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            return "-"
        }
        var slug = String(allowed)
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static let presets: [AgentTag] = [
        AgentTag(
            id: "core-task",
            name: "Core task",
            description: "The main feature or bug the user is building. Infer when the first prompt asks for substantial implementation work in the product (new feature, refactor, migration, multi-step change).",
            colorHex: "#3987E5"
        ),
        AgentTag(
            id: "side-task",
            name: "Side task",
            description: "Small, quick, or exploratory work that is not the main deliverable. Infer when the prompt is a one-off fix, a script, a config tweak, or a question about how something works.",
            colorHex: "#9085E9"
        ),
        AgentTag(
            id: "code-review",
            name: "Code review",
            description: "Reviewing someone else's change. Infer when the prompt mentions a pull request, PR URL, diff, branch review, /code-review, or asks to review or critique code.",
            colorHex: "#199E70"
        ),
        AgentTag(
            id: "research",
            name: "Research",
            description: "Investigation with no code change expected. Infer when the prompt asks to explain, compare, investigate, find out, summarize, or read documentation or logs.",
            colorHex: "#C98500"
        ),
        AgentTag(
            id: "eng-request",
            name: "Eng request",
            description: "An on-call or support ticket. Infer when the prompt references an eng-request, host-request, Notion ticket, ER-/ENG- id, customer issue, or /eng-request and /host-request skills.",
            colorHex: "#E66767"
        ),
        AgentTag(
            id: "orchestrator",
            name: "Orchestrator",
            description: "A session that coordinates other agents instead of doing the work itself. Infer when the prompt asks to spawn, delegate to, watch, or manage other agents, workspaces, workflows, or a queue.",
            colorHex: "#D55181"
        ),
    ]

    /// Validated for CVD separation on a dark surface.
    static let palette: [String] = [
        "#3987E5", "#D95926", "#199E70", "#C98500", "#D55181", "#008300",
        "#9085E9", "#E66767", "#898781",
    ]
}

enum TagSource: String, Codable {
    case confirmed
    case inferred
}

struct TagAssignment: Codable, Equatable, Hashable {
    let tagId: String
    var source: TagSource
}

extension Color {
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt64(text, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
