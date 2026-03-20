import Foundation
import Combine
import SwiftUI

final class AgentStore: ObservableObject {
    @Published var agents: [Agent] = []
    @Published var snoozedSessionIds: Set<String> = []
    /// Parent session ID → child session IDs (sub-agents linked by PID ancestry)
    @Published var childSessionIds: [String: [String]] = [:]
    /// Cached host app icons per PID (resolved once per agent).
    @Published var hostAppIcons: [Int: NSImage] = [:]

    /// Tracks the last-seen status per session so we can unsnooze on change.
    private var lastSeenStatus: [String: AgentStatus] = [:]
    private var peekTimer: DispatchWorkItem?

    var ntfyScheduler: NtfyScheduler?
    var doneClassifierConfig: DoneClassifierConfig?

    private let doneClassifier = DoneClassifier()
    private var classifiedSessionIds: Set<String> = []
    private var aiWaitReasonOverrides: [String: String] = [:]

    private let statusDirectory: URL
    private var watcher: StatusFileWatcher?
    private let fileManager = FileManager.default
    private let isProcessAlive: (Int) -> Bool

    /// All session IDs that are children of another agent.
    private var subAgentIds: Set<String> {
        Set(childSessionIds.values.flatMap { $0 })
    }

    var collapsedAgents: [Agent] {
        let subs = subAgentIds
        var result = agents.filter {
            (!hideWorkingAgents || $0.status.visibleWhenCollapsed)
                && !snoozedSessionIds.contains($0.sessionId)
                && !subs.contains($0.sessionId)
        }
        if sortByPriority {
            result.sort {
                if $0.status.sortPriority != $1.status.sortPriority {
                    return $0.status.sortPriority < $1.status.sortPriority
                }
                // Within same priority: sort by when the agent entered this status
                let a = $0.statusChangedAt ?? $0.updatedAt
                let b = $1.statusChangedAt ?? $1.updatedAt
                return a > b
            }
        }
        return result
    }

    /// Top-level agents for expanded view (excludes sub-agents).
    var topLevelAgents: [Agent] {
        let subs = subAgentIds
        return agents.filter { !subs.contains($0.sessionId) }
    }

    /// Top-level agents sorted with snoozed ones at the end.
    var sortedTopLevelAgents: [Agent] {
        let snoozed = snoozedSessionIds
        let prioritySort = sortByPriority
        return topLevelAgents.sorted { a, b in
            let aSnooze = snoozed.contains(a.sessionId)
            let bSnooze = snoozed.contains(b.sessionId)
            if aSnooze != bSnooze { return !aSnooze }
            if prioritySort {
                if a.status.sortPriority != b.status.sortPriority {
                    return a.status.sortPriority < b.status.sortPriority
                }
                let aT = a.statusChangedAt ?? a.updatedAt
                let bT = b.statusChangedAt ?? b.updatedAt
                return aT > bT
            }
            return false
        }
    }

    /// Returns child Agent objects for a given parent session ID.
    func children(of sessionId: String) -> [Agent] {
        guard let ids = childSessionIds[sessionId] else { return [] }
        return ids.compactMap { id in agents.first { $0.sessionId == id } }
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

    @Published var hideWorkingAgents: Bool = UserDefaults.standard.bool(forKey: "hideWorkingAgents") {
        didSet { UserDefaults.standard.set(hideWorkingAgents, forKey: "hideWorkingAgents") }
    }

    @Published var hideWhileCollapsed: Bool = UserDefaults.standard.bool(forKey: "hideWhileCollapsed") {
        didSet { UserDefaults.standard.set(hideWhileCollapsed, forKey: "hideWhileCollapsed") }
    }

    @Published var appIconVisibility: AppIconVisibility = AppIconVisibility(
        rawValue: UserDefaults.standard.string(forKey: "appIconVisibility") ?? ""
    ) ?? .expanded {
        didSet { UserDefaults.standard.set(appIconVisibility.rawValue, forKey: "appIconVisibility") }
    }

    @Published var screenPlacement: ScreenPlacement = ScreenPlacement(
        rawValue: UserDefaults.standard.string(forKey: "screenPlacement") ?? ""
    ) ?? .primaryOnly {
        didSet { UserDefaults.standard.set(screenPlacement.rawValue, forKey: "screenPlacement") }
    }

    @Published var sortByPriority: Bool = UserDefaults.standard.bool(forKey: "sortByPriority") {
        didSet { UserDefaults.standard.set(sortByPriority, forKey: "sortByPriority") }
    }

    @Published var isPeeking: Bool = false
    @Published var peekingIds: Set<String> = []

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
        // remove the stale status file. Skip sub-agents (pid 0) since
        // multiple sub-agents legitimately share that sentinel value.
        var bestByPid: [Int: Agent] = [:]
        var pidZeroAgents: [Agent] = []
        for agent in loaded {
            if agent.pid == 0 {
                pidZeroAgents.append(agent)
                continue
            }
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
        loaded = Array(bestByPid.values) + pidZeroAgents

        // Sort by age: oldest agents first (stable left-to-right order)
        loaded.sort { ($0.createdAt ?? $0.updatedAt) < ($1.createdAt ?? $1.updatedAt) }

        // Unsnooze agents whose status changed and trigger peek
        var changedIds: Set<String> = []
        for agent in loaded {
            if let previous = lastSeenStatus[agent.sessionId], previous != agent.status {
                snoozedSessionIds.remove(agent.sessionId)
                changedIds.insert(agent.sessionId)
            }
            lastSeenStatus[agent.sessionId] = agent.status
        }

        // Pop in briefly when status changes and hideWhileCollapsed is on
        if !changedIds.isEmpty && hideWhileCollapsed {
            triggerPeek(for: changedIds)
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

        // Clear AI classification state for agents that left waiting
        for agent in loaded {
            if agent.status != .waiting {
                classifiedSessionIds.remove(agent.sessionId)
                aiWaitReasonOverrides.removeValue(forKey: agent.sessionId)
            }
        }

        // Apply any AI overrides to waitReason
        for i in loaded.indices {
            if let override = aiWaitReasonOverrides[loaded[i].sessionId] {
                loaded[i].waitReason = override
            }
        }

        // Launch AI classification for waiting agents with rawLastMessage
        if doneClassifierConfig?.appleIntelligenceEnabled == true {
            for agent in loaded where agent.status == .waiting
                && agent.rawLastMessage != nil
                && !classifiedSessionIds.contains(agent.sessionId) {
                classifiedSessionIds.insert(agent.sessionId)
                let sessionId = agent.sessionId
                let message = agent.rawLastMessage!
                let regexResult = agent.waitReason
                DebugLog.shared.log("DoneClassifier: queuing classification for \(sessionId) (regex=\(regexResult ?? "nil"))")
                Task { [weak self] in
                    guard let result = await self?.doneClassifier.classify(message: message) else {
                        DebugLog.shared.log("DoneClassifier: no result for \(sessionId), keeping regex=\(regexResult ?? "nil")")
                        return
                    }
                    await MainActor.run {
                        guard let self else { return }
                        let changed = result != regexResult
                        DebugLog.shared.log("DoneClassifier: \(sessionId) ai=\(result) regex=\(regexResult ?? "nil") changed=\(changed)")
                        self.aiWaitReasonOverrides[sessionId] = result
                        if let idx = self.agents.firstIndex(where: { $0.sessionId == sessionId }) {
                            self.agents[idx].waitReason = result
                        }
                        self.objectWillChange.send()
                    }
                }
            }
        }

        // Resolve host app icons for new PIDs
        let activePids = Set(loaded.map(\.pid))
        for pid in activePids where pid != 0 && hostAppIcons[pid] == nil {
            hostAppIcons[pid] = HostAppResolver.resolve(pid: pid)?.icon
        }
        // Clean up icons for PIDs no longer present
        for pid in hostAppIcons.keys where !activePids.contains(pid) {
            hostAppIcons.removeValue(forKey: pid)
        }

        // Build parent-child relationships from parentSessionId
        var newChildren: [String: [String]] = [:]
        for agent in loaded {
            if let parentId = agent.parentSessionId {
                newChildren[parentId, default: []].append(agent.sessionId)
            }
        }

        if loaded != agents || newChildren != childSessionIds {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                agents = loaded
                childSessionIds = newChildren
            }
        }
    }

    func triggerPeek(for ids: Set<String>? = nil) {
        peekTimer?.cancel()
        isPeeking = true
        if let ids {
            peekingIds.formUnion(ids)
        }
        let item = DispatchWorkItem { [weak self] in
            self?.isPeeking = false
            self?.peekingIds = []
        }
        peekTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: item)
    }

    deinit { watcher?.stop() }
}
