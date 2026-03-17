import Foundation
import Combine

final class NtfyScheduler: ObservableObject {
    @Published var notifiedSessionIds: Set<String> = []

    private var pendingWork: [String: DispatchWorkItem] = [:]
    /// Sessions that have sent a notification (blocks re-scheduling even after badge fades).
    private var sentSessionIds: Set<String> = []
    private let config: NtfyConfig

    init(config: NtfyConfig) {
        self.config = config
    }

    /// Schedule a delayed notification if conditions are met.
    func scheduleIfNeeded(for agent: Agent, isSnoozed: Bool) {
        guard config.isConfigured, !isSnoozed else { return }
        guard pendingWork[agent.sessionId] == nil,
              !notifiedSessionIds.contains(agent.sessionId),
              !sentSessionIds.contains(agent.sessionId) else { return }

        guard shouldNotify(for: agent) else { return }

        let sessionId = agent.sessionId
        let title = buildTitle(for: agent)
        let body = agent.speechBubbleText
        let priority = agent.status == .permission ? config.permissionPriority : config.defaultPriority
        let endpoint = config.endpoint
        let topic = config.topic
        let tags = config.tags

        let work = DispatchWorkItem { [weak self] in
            NtfyClient.send(
                endpoint: endpoint,
                topic: topic,
                message: body,
                title: title,
                priority: priority,
                tags: tags
            )
            DispatchQueue.main.async {
                self?.pendingWork.removeValue(forKey: sessionId)
                self?.notifiedSessionIds.insert(sessionId)
                self?.sentSessionIds.insert(sessionId)

                // Fade badge after 60 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                    self?.notifiedSessionIds.remove(sessionId)
                }
            }
        }

        pendingWork[sessionId] = work
        let delay = config.delaySeconds
        DebugLog.shared.log("NtfyScheduler: scheduled \(sessionId) in \(delay)s")
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + .seconds(delay),
            execute: work
        )
    }

    /// Cancel a pending notification without clearing the "already sent" flag.
    /// This prevents re-scheduling when an agent briefly transitions away and back.
    func cancelPending(for sessionId: String) {
        if let work = pendingWork.removeValue(forKey: sessionId) {
            work.cancel()
            DebugLog.shared.log("NtfyScheduler: cancelled pending \(sessionId)")
        }
    }

    /// Full cleanup: cancel pending and clear the "already sent" flag.
    /// Use when a session ends (PID stale, dismissed, file removed).
    func reset(for sessionId: String) {
        cancelPending(for: sessionId)
        notifiedSessionIds.remove(sessionId)
        sentSessionIds.remove(sessionId)
    }

    /// Clean up notification state for sessions that no longer exist.
    func cleanupGone(activeIds: Set<String>) {
        for id in notifiedSessionIds where !activeIds.contains(id) {
            reset(for: id)
        }
        for id in pendingWork.keys where !activeIds.contains(id) {
            reset(for: id)
        }
    }

    func cancelAll() {
        for (id, work) in pendingWork {
            work.cancel()
            DebugLog.shared.log("NtfyScheduler: cancelled \(id)")
        }
        pendingWork.removeAll()
        notifiedSessionIds.removeAll()
        sentSessionIds.removeAll()
    }

    private func shouldNotify(for agent: Agent) -> Bool {
        switch agent.status {
        case .permission:
            return config.notifyOnPermission
        case .waiting:
            return agent.isDone ? config.notifyOnDone : config.notifyOnWaiting
        default:
            return false
        }
    }

    private func buildTitle(for agent: Agent) -> String {
        let label = agent.directoryLabel
        switch agent.status {
        case .permission:
            return "\(label) \u{2014} Permission needed"
        case .waiting where agent.isDone:
            return "\(label) \u{2014} Done"
        case .waiting:
            return "\(label) \u{2014} Waiting for input"
        default:
            return label
        }
    }
}
