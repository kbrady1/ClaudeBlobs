import Foundation
import Network
import Combine
import AppKit

/// Embedded WebSocket server for remote control.
final class RemoteServer: ObservableObject {
    private var listener: NWListener?
    private var connections: [String: WebSocketConnection] = [:]
    private var heartbeatTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    let pairingManager: PairingManager
    private let agentStore: AgentStore
    private let port: UInt16

    @Published var isRunning = false
    @Published var connectedClientCount = 0

    init(agentStore: AgentStore, port: UInt16 = 8443) {
        self.agentStore = agentStore
        self.port = port
        self.pairingManager = PairingManager()
    }

    func start() {
        guard !isRunning else { return }

        let wsOptions = NWProtocolWebSocket.Options()
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        // No interface restriction — works over WiFi and Ethernet
        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            DebugLog.shared.log("RemoteServer: failed to create listener — \(error)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            DebugLog.shared.log("RemoteServer: listener state \(state)")
            DispatchQueue.main.async {
                self?.isRunning = (state == .ready)
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        // Configure Bonjour BEFORE starting
        BonjourPublisher.configure(on: listener!)

        listener?.start(queue: .global(qos: .userInitiated))

        // Subscribe to agent changes for broadcasting
        agentStore.$agents
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] agents in
                self?.broadcastSnapshot(agents)
            }
            .store(in: &cancellables)

        // Heartbeat timer
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.sendHeartbeats()
        }

        DebugLog.shared.log("RemoteServer: started on port \(port)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        cancellables.removeAll()
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        isRunning = false
        connectedClientCount = 0
        DebugLog.shared.log("RemoteServer: stopped")
    }

    private func handleNewConnection(_ nwConnection: NWConnection) {
        let connId = UUID().uuidString
        let connection = WebSocketConnection(id: connId, connection: nwConnection)

        nwConnection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state {
                self?.connections.removeValue(forKey: connId)
                DispatchQueue.main.async {
                    self?.connectedClientCount = self?.connections.count ?? 0
                }
            }
        }

        nwConnection.start(queue: .global(qos: .userInitiated))

        // Auth: one-shot receiveMessage on raw NWConnection (NOT WebSocketConnection.receive
        // which sets up a recursive loop). After auth, switch to recursive receive.
        nwConnection.receiveMessage { [weak self] content, _, _, error in
            guard let self, let data = content else {
                connection.cancel()
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  json["type"] == "auth",
                  let token = json["token"],
                  self.pairingManager.isValidToken(token)
            else {
                DebugLog.shared.log("RemoteServer: auth failed, dropping connection (\(connId))")
                connection.cancel()
                return
            }

            self.connections[connId] = connection
            DispatchQueue.main.async {
                self.connectedClientCount = self.connections.count
            }
            let snapshots = self.buildSnapshots(self.agentStore.agents)
            let snapshot = RemoteMessage.snapshot(agents: snapshots)
            connection.send(snapshot)
            connection.receive { data in
                self.handleIncomingData(data, from: connId)
            }
            DebugLog.shared.log("RemoteServer: client authenticated (\(connId))")
        }
    }

    private func handleIncomingData(_ data: Data, from connId: String) {
        guard let request = try? JSONDecoder().decode(CommandRequest.self, from: data) else {
            DebugLog.shared.log("RemoteServer: invalid command from \(connId)")
            return
        }

        Task {
            guard let agent = agentStore.agents.first(where: { $0.sessionId == request.sessionId }) else {
                DebugLog.shared.log("RemoteServer: agent \(request.sessionId) not found")
                return
            }

            if let error = RemoteRouter.validateCommand(request.command, agent: agent) {
                DebugLog.shared.log("RemoteServer: command rejected — \(error)")
                return
            }

            let result = try await CommandExecutor.execute(
                command: request.command,
                agent: agent,
                text: request.text
            )
            DebugLog.shared.log("RemoteServer: command \(request.command) for \(request.sessionId): \(result.success ? "ok" : result.error ?? "failed")")
        }
    }

    private func broadcastSnapshot(_ agents: [Agent]) {
        let snapshots = buildSnapshots(agents)
        let message = RemoteMessage.snapshot(agents: snapshots)
        for connection in connections.values {
            connection.send(message)
        }
    }

    private func buildSnapshots(_ agents: [Agent]) -> [AgentSnapshot] {
        agents.map { agent in
            let iconData: Data? = agentStore.hostAppIcons[agent.pid].flatMap { nsImage in
                guard let tiffData = nsImage.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
                return bitmap.representation(using: .png, properties: [:])
            }
            return AgentSnapshot(agent: agent, appIconPNG: iconData)
        }
    }

    private func sendHeartbeats() {
        for connection in connections.values {
            connection.sendPing()
        }
    }
}
