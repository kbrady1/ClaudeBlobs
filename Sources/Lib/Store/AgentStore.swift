import Foundation
import Combine

final class AgentStore: ObservableObject {
    @Published var agents: [Agent] = []

    private let statusDirectory: URL
    private var watcher: StatusFileWatcher?
    private let fileManager = FileManager.default
    private let isProcessAlive: (Int) -> Bool

    var collapsedAgents: [Agent] {
        agents.filter { $0.status.visibleWhenCollapsed }
    }

    var hasAgents: Bool { !agents.isEmpty }
    var hasActionableAgents: Bool { !collapsedAgents.isEmpty }

    init(
        statusDirectory: URL? = nil,
        enableWatcher: Bool = true,
        isProcessAlive: @escaping (Int) -> Bool = { pid in kill(Int32(pid), 0) == 0 }
    ) {
        self.statusDirectory = statusDirectory
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/agent-status")
        self.isProcessAlive = isProcessAlive

        if enableWatcher {
            let watcher = StatusFileWatcher(directoryURL: self.statusDirectory) { [weak self] in
                self?.reload()
            }
            self.watcher = watcher
            watcher.start()
        }

        reload()
    }

    func reload() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: statusDirectory, includingPropertiesForKeys: nil
        ) else {
            agents = []
            return
        }

        let decoder = JSONDecoder()
        var loaded: [Agent] = []

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let agent = try? decoder.decode(Agent.self, from: data) else {
                continue
            }
            loaded.append(agent)
        }

        // Clean up stale PIDs
        loaded = loaded.filter { agent in
            let alive = isProcessAlive(agent.pid)
            if !alive {
                try? fileManager.removeItem(
                    at: statusDirectory.appendingPathComponent("\(agent.sessionId).json")
                )
            }
            return alive
        }

        // Sort: permission > waiting > starting > working
        let priority: [AgentStatus: Int] = [
            .permission: 0, .waiting: 1, .starting: 2, .working: 3
        ]
        loaded.sort { (priority[$0.status] ?? 9) < (priority[$1.status] ?? 9) }

        if loaded != agents {
            agents = loaded
        }
    }

    deinit { watcher?.stop() }
}
