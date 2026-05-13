import AppKit

struct SupersetLinker {
    static let bundleId = "com.superset.desktop"

    static func activate(_ agent: Agent) {
        guard let workspace = agent.supersetWorkspace else {
            DebugLog.shared.log("SupersetLinker: no workspace ID, falling back to app activation")
            activateHost()
            return
        }

        var components = URLComponents()
        components.scheme = "superset"
        components.host = "v2-workspace"
        components.path = "/\(workspace)"
        if let terminal = agent.supersetTerminal {
            components.queryItems = [URLQueryItem(name: "terminalId", value: terminal)]
        }

        if let url = components.url {
            NSWorkspace.shared.open(url)
            DebugLog.shared.log("SupersetLinker: opened \(url)")
        }

        activateHost()
    }

    private static func activateHost() {
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleId
        }) {
            app.unhide()
            app.activate()
            DebugLog.shared.log("SupersetLinker: activated Superset app")
        }
    }
}
