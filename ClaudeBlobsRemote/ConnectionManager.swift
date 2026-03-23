// ClaudeBlobsRemote/ConnectionManager.swift
import Foundation
import Network

/// Manages the WebSocket connection to the ClaudeBlobs server.
@MainActor
final class ConnectionManager: ObservableObject {
    @Published var agents: [Agent] = []
    @Published var agentIconData: [String: Data] = [:]  // sessionId -> PNG data
    @Published var connectionState: ConnectionState = .disconnected
    @Published var lastError: String?

    enum ConnectionState {
        case disconnected, connecting, connected
    }

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var serverURL: URL?
    private var authToken: String?
    private var reconnectTimer: Timer?

    func connect(host: String, port: Int, token: String) {
        authToken = token
        // TODO: Switch to wss:// once server has TLS with self-signed cert.
        // For now, use plain ws:// since the server is plain TCP + WebSocket.
        // The auth token in the first message still provides authentication.
        let urlString = "ws://\(host):\(port)"
        guard let url = URL(string: urlString) else { return }
        serverURL = url

        connectionState = .connecting

        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config)

        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()

        // First message must be auth token
        let authMessage = "{\"type\":\"auth\",\"token\":\"\(token)\"}"
        webSocketTask?.send(.string(authMessage)) { [weak self] error in
            if let error {
                Task { @MainActor in
                    self?.lastError = "Auth failed: \(error.localizedDescription)"
                    self?.connectionState = .disconnected
                }
                return
            }
            Task { @MainActor in
                self?.connectionState = .connected
                self?.receiveMessage()
                self?.startHeartbeatMonitor()
            }
        }
    }

    func disconnect() {
        reconnectTimer?.invalidate()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
    }

    // MARK: - Commands (sent over WebSocket, same channel as state)

    func sendCommand(_ command: CommandType, sessionId: String, text: String? = nil) async {
        let request = CommandRequest(command: command, sessionId: sessionId, text: text)
        guard let data = try? JSONEncoder().encode(request),
              let jsonString = String(data: data, encoding: .utf8)
        else { return }

        do {
            try await webSocketTask?.send(.string(jsonString))
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - WebSocket Receiving

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        if let data = text.data(using: .utf8) {
                            self?.handleMessage(data)
                        }
                    case .data(let data):
                        self?.handleMessage(data)
                    @unknown default:
                        break
                    }
                    self?.receiveMessage()

                case .failure(let error):
                    self?.connectionState = .disconnected
                    self?.lastError = error.localizedDescription
                    self?.scheduleReconnect()
                }
            }
        }
    }

    private func handleMessage(_ data: Data) {
        guard let message = try? JSONDecoder().decode(RemoteMessage.self, from: data) else { return }

        switch message {
        case .snapshot(let snapshots):
            self.agents = snapshots.map(\.agent).sorted { $0.status.sortPriority < $1.status.sortPriority }
            var icons: [String: Data] = [:]
            for snapshot in snapshots {
                if let iconData = snapshot.appIconPNG {
                    icons[snapshot.agent.sessionId] = iconData
                }
            }
            self.agentIconData = icons
        case .agentUpdated(let snapshot):
            let agent = snapshot.agent
            if let index = agents.firstIndex(where: { $0.sessionId == agent.sessionId }) {
                agents[index] = agent
            } else {
                agents.append(agent)
            }
            agents.sort { $0.status.sortPriority < $1.status.sortPriority }
            if let iconData = snapshot.appIconPNG {
                agentIconData[agent.sessionId] = iconData
            }
        case .agentRemoved(let sessionId):
            agents.removeAll { $0.sessionId == sessionId }
            agentIconData.removeValue(forKey: sessionId)
        case .heartbeat:
            break
        }
    }

    private func scheduleReconnect() {
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, let serverURL = self.serverURL, let token = self.authToken else { return }
                self.connect(host: serverURL.host ?? "", port: serverURL.port ?? 8443, token: token)
            }
        }
    }

    private func startHeartbeatMonitor() {
        // Ping every 30s to detect dead connections
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.webSocketTask?.sendPing { error in
                if error != nil {
                    Task { @MainActor in
                        self.connectionState = .disconnected
                        self.scheduleReconnect()
                    }
                }
            }
        }
    }
}
