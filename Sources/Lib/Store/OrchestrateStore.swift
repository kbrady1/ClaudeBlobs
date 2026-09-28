import Foundation
import Combine

/// Publishes which sessions an `/orchestrate` run is currently driving.
///
/// Two sources, refreshed together: the cross-run registry at
/// `~/.superset/orchestrate/registry.json`, and the `state.json` each run in it
/// points at. The registry directory is watched for changes, but a run's state
/// file lives in the orchestrator's own Superset workspace — outside any
/// directory worth watching — so a timer carries the rest. The daemon rewrites
/// both every few seconds, so a poll is in step with the source anyway.
final class OrchestrateStore: ObservableObject {
    @Published private(set) var snapshot: OrchestrateSnapshot = .empty

    private let registryURL: URL
    private let loader: (URL) -> OrchestrateSnapshot
    private var watcher: StatusFileWatcher?
    private var refreshTimer: Timer?

    /// How often to re-read the registry and the state files it points at.
    static let refreshInterval: TimeInterval = 5

    /// `isProcessAlive` is injected so tests can describe a live daemon without
    /// needing a real process, the same way `OrchestrateRegistry.load` does.
    init(
        registryURL: URL = OrchestrateSnapshot.defaultRegistryURL,
        enableWatcher: Bool = true,
        isProcessAlive: @escaping (Int) -> Bool = { kill(Int32($0), 0) == 0 || errno == EPERM },
        loader: ((URL) -> OrchestrateSnapshot)? = nil
    ) {
        let loader = loader ?? { OrchestrateRegistry.load(registryURL: $0, isProcessAlive: isProcessAlive) }
        self.registryURL = registryURL
        self.loader = loader

        if enableWatcher {
            let watcher = StatusFileWatcher(directoryURL: registryURL.deletingLastPathComponent()) { [weak self] in
                self?.reload()
            }
            self.watcher = watcher
            watcher.start()

            refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
                self?.reload()
            }
        }
        reload()
    }

    deinit {
        watcher?.stop()
        refreshTimer?.invalidate()
    }

    func reload() {
        let next = loader(registryURL)
        guard next != snapshot else { return }
        snapshot = next
    }

    /// The unit driving this session, if an orchestrator owns it.
    func unit(for agent: Agent) -> OrchestrateUnit? {
        snapshot.unit(forTerminal: agent.supersetTerminal)
    }
}
