import Foundation
import Combine
import SwiftUI

struct AgentStatusSource: Equatable {
    let provider: AgentProvider
    let directoryURL: URL
}

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

    private let statusSources: [AgentStatusSource]
    private var watchers: [StatusFileWatcher] = []
    private let fileManager = FileManager.default
    private let isProcessAlive: (Int) -> Bool

    /// All session IDs that are children of another agent.
    private var subAgentIds: Set<String> {
        Set(childSessionIds.values.flatMap { $0 })
    }

    var collapsedAgents: [Agent] {
        let subs = subAgentIds
        var result = agents.filter {
            let effective = effectiveStatus(of: $0)
            return (!hideWorkingAgents || effective.visibleWhenCollapsed)
                && !snoozedSessionIds.contains($0.id)
                && !subs.contains($0.id)
        }
        if sortByPriority {
            result.sort {
                let p0 = sortKey(for: $0)
                let p1 = sortKey(for: $1)
                if p0 != p1 {
                    return p0 < p1
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
        return agents.filter { !subs.contains($0.id) }
    }

    /// Top-level agents sorted with snoozed ones at the end.
    var sortedTopLevelAgents: [Agent] {
        let snoozed = snoozedSessionIds
        let prioritySort = sortByPriority
        return topLevelAgents.sorted { a, b in
            let aSnooze = snoozed.contains(a.id)
            let bSnooze = snoozed.contains(b.id)
            if aSnooze != bSnooze { return !aSnooze }
            if prioritySort {
                let aP = sortKey(for: a)
                let bP = sortKey(for: b)
                if aP != bP {
                    return aP < bP
                }
                let aT = a.statusChangedAt ?? a.updatedAt
                let bT = b.statusChangedAt ?? b.updatedAt
                return aT > bT
            }
            return false
        }
    }

    /// Returns the effective status for sorting/filtering (considers child sub-agents).
    private func effectiveStatus(of agent: Agent) -> AgentStatus {
        Agent.effectiveStatus(of: agent, children: children(of: agent.id))
    }

    /// Sort key: effective priority, with done agents demoted within the waiting tier.
    /// Waiting (not done) = 1, Waiting (done) = 1.5 (between waiting and starting).
    private func sortKey(for agent: Agent) -> Double {
        let base = Double(effectiveStatus(of: agent).sortPriority)
        if effectiveStatus(of: agent) == .waiting && agent.isDone { return base + 0.5 }
        return base
    }

    /// Returns child Agent objects for a given parent session ID.
    func children(of id: String) -> [Agent] {
        guard let ids = childSessionIds[id] else { return [] }
        return ids.compactMap { childId in agents.first { $0.id == childId } }
    }

    func snooze(_ agent: Agent) {
        snoozedSessionIds.insert(agent.id)
        ntfyScheduler?.cancelPending(for: agent.id)
    }

    func dismiss(_ agent: Agent) {
        ntfyScheduler?.reset(for: agent.id)
        if let statusDirectory = statusDirectory(for: agent.provider) {
            try? fileManager.removeItem(
                at: statusDirectory.appendingPathComponent("\(agent.sessionId).json")
            )
        }
        reload()
    }

    func dismissAll() {
        for agent in agents {
            snoozedSessionIds.insert(agent.id)
        }
    }

    // MARK: - Custom Names

    @Published var customNames: [String: String] = {
        (UserDefaults.standard.dictionary(forKey: "customAgentNames") as? [String: String]) ?? [:]
    }()

    func setCustomName(_ name: String, for agent: Agent) {
        customNames[agent.sessionId] = name
        UserDefaults.standard.set(customNames, forKey: "customAgentNames")
    }

    func clearCustomName(for agent: Agent) {
        customNames.removeValue(forKey: agent.sessionId)
        UserDefaults.standard.set(customNames, forKey: "customAgentNames")
    }

    func displayName(for agent: Agent) -> String {
        customNames[agent.sessionId] ?? agent.directoryLabel
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
        statusSources: [AgentStatusSource]? = nil,
        enableWatcher: Bool = true,
        isProcessAlive: @escaping (Int) -> Bool = { pid in kill(Int32(pid), 0) == 0 }
    ) {
        if let statusSources {
            self.statusSources = statusSources
        } else if let statusDirectory {
            self.statusSources = [AgentStatusSource(provider: .claudeCode, directoryURL: statusDirectory)]
        } else {
            self.statusSources = AgentProvider.allCases.map {
                AgentStatusSource(provider: $0, directoryURL: $0.statusDirectory)
            }
        }
        self.isProcessAlive = isProcessAlive

        if enableWatcher {
            for source in self.statusSources {
                let watcher = StatusFileWatcher(directoryURL: source.directoryURL) { [weak self] in
                    self?.reload()
                }
                watchers.append(watcher)
                watcher.start()
            }
        }

        reload()
    }

    func reload() {
        let decoder = JSONDecoder()
        var loaded: [Agent] = []
        var hadReadableSource = false

        for source in statusSources {
            guard let files = try? fileManager.contentsOfDirectory(
                at: source.directoryURL, includingPropertiesForKeys: nil
            ) else {
                continue
            }
            hadReadableSource = true

            for file in files where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file),
                      var agent = try? decoder.decode(Agent.self, from: data) else {
                    continue
                }
                agent.provider = source.provider
                loaded.append(agent)
            }
        }

        guard hadReadableSource else {
            agents = []
            return
        }

        // Clean up stale PIDs
        loaded = loaded.filter { agent in
            let alive = isProcessAlive(agent.pid)
            if !alive {
                ntfyScheduler?.reset(for: agent.id)
                if let statusDirectory = statusDirectory(for: agent.provider) {
                    try? fileManager.removeItem(
                        at: statusDirectory.appendingPathComponent("\(agent.sessionId).json")
                    )
                }
            }
            return alive
        }

        // Deduplicate by PID — resumed sessions create a new session ID
        // for the same process. Keep the most recently updated entry and
        // remove the stale status file. Skip sub-agents (pid 0) since
        // multiple sub-agents legitimately share that sentinel value.
        var bestByPid: [String: Agent] = [:]
        var pidZeroAgents: [Agent] = []
        for agent in loaded {
            if agent.pid == 0 {
                pidZeroAgents.append(agent)
                continue
            }
            let key = "\(agent.provider.rawValue):\(agent.pid)"
            if let existing = bestByPid[key] {
                if agent.updatedAt > existing.updatedAt {
                    if let statusDirectory = statusDirectory(for: existing.provider) {
                        try? fileManager.removeItem(
                            at: statusDirectory.appendingPathComponent("\(existing.sessionId).json")
                        )
                    }
                    bestByPid[key] = agent
                } else {
                    if let statusDirectory = statusDirectory(for: agent.provider) {
                        try? fileManager.removeItem(
                            at: statusDirectory.appendingPathComponent("\(agent.sessionId).json")
                        )
                    }
                }
            } else {
                bestByPid[key] = agent
            }
        }
        loaded = Array(bestByPid.values) + pidZeroAgents

        // Sort by age: oldest agents first (stable left-to-right order)
        loaded.sort { ($0.createdAt ?? $0.updatedAt) < ($1.createdAt ?? $1.updatedAt) }

        // Unsnooze agents whose status changed and trigger peek
        var changedIds: Set<String> = []
        for agent in loaded {
            if let previous = lastSeenStatus[agent.id], previous != agent.status {
                snoozedSessionIds.remove(agent.id)
                changedIds.insert(agent.id)
            }
            lastSeenStatus[agent.id] = agent.status
        }

        // Pop in briefly when status changes and hideWhileCollapsed is on
        if !changedIds.isEmpty && hideWhileCollapsed {
            triggerPeek(for: changedIds)
        }

        // Schedule or cancel notifications based on agent state
        for agent in loaded {
            let isSnoozed = snoozedSessionIds.contains(agent.id)
            let notifiable = agent.status == .permission
                || (agent.status == .waiting && !agent.isDone)
                || (agent.status == .waiting && agent.isDone)
            if notifiable {
                ntfyScheduler?.scheduleIfNeeded(for: agent, isSnoozed: isSnoozed)
            } else {
                ntfyScheduler?.cancelPending(for: agent.id)
            }
        }

        // Clean up snoozed/notification entries for sessions that no longer exist
        let activeIds = Set(loaded.map(\.id))
        let activeSessionIds = Set(loaded.map(\.sessionId))
        snoozedSessionIds = snoozedSessionIds.intersection(activeIds)
        ntfyScheduler?.cleanupGone(activeIds: activeIds)

        // Prune custom names for sessions that no longer exist
        let staleNames = customNames.keys.filter { !activeSessionIds.contains($0) }
        if !staleNames.isEmpty {
            for key in staleNames { customNames.removeValue(forKey: key) }
            UserDefaults.standard.set(customNames, forKey: "customAgentNames")
        }

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
                    guard let self, let result = await self.doneClassifier.classify(message: message) else {
                        DebugLog.shared.log("DoneClassifier: no result for \(sessionId), keeping regex=\(regexResult ?? "nil")")
                        return
                    }
                    let changed = result != regexResult
                    DebugLog.shared.log("DoneClassifier: \(sessionId) ai=\(result) regex=\(regexResult ?? "nil") changed=\(changed)")
                    await MainActor.run { [self] in
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
                let parentKey = "\(agent.provider.rawValue):\(parentId)"
                newChildren[parentKey, default: []].append(agent.id)
            }
        }

        if loaded != agents || newChildren != childSessionIds {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                agents = loaded
                childSessionIds = newChildren
            }
        }
    }

    private func statusDirectory(for provider: AgentProvider) -> URL? {
        statusSources.first(where: { $0.provider == provider })?.directoryURL
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

    deinit {
        for watcher in watchers {
            watcher.stop()
        }
    }
}
