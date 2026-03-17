import Foundation
import Combine
import SwiftUI

final class AgentStore: ObservableObject {
    @Published var agents: [Agent] = []
    @Published var snoozedSessionIds: Set<String> = []

    /// Tracks the last-seen status per session so we can unsnooze on change.
    private var lastSeenStatus: [String: AgentStatus] = [:]

    var ntfyScheduler: NtfyScheduler?

    private let statusDirectory: URL
    private var watcher: StatusFileWatcher?
    private let fileManager = FileManager.default
    private let isProcessAlive: (Int) -> Bool

    var collapsedAgents: [Agent] {
        agents.filter {
            (showAllAgents || $0.status.visibleWhenCollapsed) && !snoozedSessionIds.contains($0.sessionId)
        }
    }

    func snooze(_ agent: Agent) {
        snoozedSessionIds.insert(agent.sessionId)
        ntfyScheduler?.cancelPending(for: agent.sessionId)
    }

    func dismiss(_ agent: Agent) {
        ntfyScheduler?.reset(for: agent.sessionId)
        try? fileManager.removeItem(
            at: statusDirectory.appendingPathComponent("\(agent.sessionId).json")
        )
        reload()
    }

    func dismissAll() {
        for agent in agents {
            snoozedSessionIds.insert(agent.sessionId)
        }
    }

    @Published var showAllAgents: Bool = UserDefaults.standard.bool(forKey: "showAllAgents") {
        didSet { UserDefaults.standard.set(showAllAgents, forKey: "showAllAgents") }
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
                ntfyScheduler?.reset(for: agent.sessionId)
                try? fileManager.removeItem(
                    at: statusDirectory.appendingPathComponent("\(agent.sessionId).json")
                )
            }
            return alive
        }

        // Deduplicate by PID — resumed sessions create a new session ID
        // for the same process. Keep the most recently updated entry and
        // remove the stale status file.
        var bestByPid: [Int: Agent] = [:]
        for agent in loaded {
            if let existing = bestByPid[agent.pid] {
                if agent.updatedAt > existing.updatedAt {
                    try? fileManager.removeItem(
                        at: statusDirectory.appendingPathComponent("\(existing.sessionId).json")
                    )
                    bestByPid[agent.pid] = agent
                } else {
                    try? fileManager.removeItem(
                        at: statusDirectory.appendingPathComponent("\(agent.sessionId).json")
                    )
                }
            } else {
                bestByPid[agent.pid] = agent
            }
        }
        loaded = Array(bestByPid.values)

        // Sort by age: oldest agents first (stable left-to-right order)
        loaded.sort { ($0.createdAt ?? $0.updatedAt) < ($1.createdAt ?? $1.updatedAt) }

        // Unsnooze agents whose status changed
        for agent in loaded {
            if let previous = lastSeenStatus[agent.sessionId], previous != agent.status {
                snoozedSessionIds.remove(agent.sessionId)
            }
            lastSeenStatus[agent.sessionId] = agent.status
        }

        // Schedule or cancel notifications based on agent state
        for agent in loaded {
            let isSnoozed = snoozedSessionIds.contains(agent.sessionId)
            let notifiable = agent.status == .permission
                || (agent.status == .waiting && !agent.isDone)
                || (agent.status == .waiting && agent.isDone)
            if notifiable {
                ntfyScheduler?.scheduleIfNeeded(for: agent, isSnoozed: isSnoozed)
            } else {
                ntfyScheduler?.cancelPending(for: agent.sessionId)
            }
        }

        // Clean up snoozed/notification entries for sessions that no longer exist
        let activeIds = Set(loaded.map(\.sessionId))
        snoozedSessionIds = snoozedSessionIds.intersection(activeIds)
        ntfyScheduler?.cleanupGone(activeIds: activeIds)

        if loaded != agents {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                agents = loaded
            }
        }
    }

    deinit { watcher?.stop() }
}
