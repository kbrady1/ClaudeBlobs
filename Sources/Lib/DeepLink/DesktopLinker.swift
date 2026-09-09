import AppKit

/// Deep links into Claude Desktop.
///
/// Claude Desktop registers the `claude://` scheme, and its URL handler offers
/// two routes we can reach with the ids in a status file:
///
/// - `claude://claude.ai/epitaxy/local_<uuid>` focuses a session Claude Desktop
///   already has. This is the one we want: it navigates, and changes nothing.
///   `/epitaxy` is Claude Desktop's own route for a Claude Code session, and
///   the route the app itself navigates to after a resume.
/// - `claude://resume?session=<cli-uuid>` imports a Claude Code CLI transcript
///   from `~/.claude/projects/` as a *new* desktop session. Useful only for a
///   session Claude Desktop has never seen; pointing it at a session Claude
///   Desktop is already running clones that session rather than focusing it.
///
/// Our status files carry only the CLI session id, so `DesktopSessionIndex`
/// resolves it to a `local_` id first and we fall back to the import.
///
/// `claude://code/continue?session=local_<uuid>` focuses a session too, but it
/// sits behind a server-side feature gate that is off for most accounts, so it
/// silently does nothing. The `/epitaxy` route is ungated.
///
/// Both routes are undocumented, so treat them as best effort. Anthropic can
/// change them, and the enterprise `disableDeepLinks` setting turns the whole
/// `claude://` scheme off. Every failure ends with Claude Desktop merely
/// activated, which is what `activateHost` does on its own.
struct DesktopLinker {
    static let bundleId = "com.anthropic.claudefordesktop"

    /// Which `claude://` route to use for an agent.
    enum Route: Equatable {
        /// Focus a session Claude Desktop already has.
        case focus(localSessionId: String)
        /// Import a CLI transcript Claude Desktop has never seen.
        case importTranscript(cliSessionId: String)

        var url: URL? {
            var components = URLComponents()
            components.scheme = "claude"
            switch self {
            case .focus(let localSessionId):
                components.host = "claude.ai"
                components.path = "/epitaxy/\(localSessionId)"
            case .importTranscript(let cliSessionId):
                components.host = "resume"
                components.queryItems = [URLQueryItem(name: "session", value: cliSessionId)]
            }
            return components.url
        }
    }

    /// Chooses the route for an agent, given the desktop session id already
    /// resolved for it (nil when Claude Desktop has no session for it). Pure,
    /// so tests can cover the choice without a Claude Desktop install.
    static func route(for agent: Agent, localSessionId: String?) -> Route? {
        // Only Claude Code writes the CLI session id these routes key off.
        guard agent.provider == .claudeCode else { return nil }
        if let localSessionId { return .focus(localSessionId: localSessionId) }
        // The import handler validates `session` against a strict UUID pattern.
        guard UUID(uuidString: agent.sessionId) != nil else { return nil }
        return .importTranscript(cliSessionId: agent.sessionId)
    }

    static func activate(_ agent: Agent) {
        let localSessionId = agent.provider == .claudeCode
            ? DesktopSessionIndex.localSessionId(forCLISession: agent.sessionId)
            : nil

        guard let route = route(for: agent, localSessionId: localSessionId),
              let url = route.url
        else {
            DebugLog.shared.log("DesktopLinker: no usable session id, falling back to app activation")
            activateHost()
            return
        }

        NSWorkspace.shared.open(url)
        DebugLog.shared.log("DesktopLinker: opened \(url)")

        activateHost()
    }

    /// Brings Claude Desktop forward, launching it if it is not running.
    static func activateHost() {
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleId
        }) {
            app.unhide()
            app.activate()
            DebugLog.shared.log("DesktopLinker: activated running Claude Desktop")
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
            DebugLog.shared.log("DesktopLinker: launched Claude Desktop at \(url)")
        } else {
            DebugLog.shared.log("DesktopLinker: Claude Desktop not found")
        }
    }
}
