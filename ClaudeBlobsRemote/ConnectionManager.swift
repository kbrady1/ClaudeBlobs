// ClaudeBlobsRemote/ConnectionManager.swift
import Foundation
import Network
import os

private let log = Logger(subsystem: "com.claudeblobs.remote", category: "Connection")

/// Manages the WebSocket connection to the ClaudeBlobs server.
@MainActor
final class ConnectionManager: ObservableObject {
    @Published var agents: [Agent] = []
    @Published var agentIconData: [String: Data] = [:]  // sessionId -> PNG data
    @Published var agentColorHex: [String: String] = [:]  // sessionId -> hex color
    @Published var agentPermissionOptions: [String: [String]] = [:]  // sessionId -> options
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
        let urlString = "ws://\(host):\(port)"
        log.info("Connecting to \(urlString)")
        guard let url = URL(string: urlString) else {
            log.error("Invalid URL: \(urlString)")
            return
        }
        serverURL = url

        connectionState = .connecting

        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config)

        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.maximumMessageSize = 16 * 1024 * 1024  // 16 MB — snapshots include icon PNG data
        log.info("WebSocket task created, resuming...")
        webSocketTask?.resume()

        // First message must be auth token
        let authMessage = "{\"type\":\"auth\",\"token\":\"\(token)\"}"
        log.info("Sending auth message...")
        webSocketTask?.send(.string(authMessage)) { [weak self] error in
            if let error {
                log.error("Auth send failed: \(error.localizedDescription)")
                Task { @MainActor in
                    self?.lastError = "Auth failed: \(error.localizedDescription)"
                    self?.connectionState = .disconnected
                }
                return
            }
            log.info("Auth sent successfully, now connected")
            Task { @MainActor in
                self?.connectionState = .connected
                self?.receiveMessage()
                self?.startHeartbeatMonitor()
            }
        }
    }

    func disconnect() {
        log.info("Disconnecting")
        reconnectTimer?.invalidate()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
    }

    // MARK: - Commands (sent over WebSocket, same channel as state)

    func sendCommand(_ command: CommandType, sessionId: String, text: String? = nil, optionIndex: Int? = nil) async {
        let request = CommandRequest(command: command, sessionId: sessionId, text: text, optionIndex: optionIndex)
        guard let data = try? JSONEncoder().encode(request),
              let jsonString = String(data: data, encoding: .utf8)
        else { return }

        log.info("Sending command: \(command.rawValue) for \(sessionId)")
        do {
            try await webSocketTask?.send(.string(jsonString))
        } catch {
            log.error("Command send failed: \(error.localizedDescription)")
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
                        log.info("Received text frame (\(text.count) chars)")
                        if let data = text.data(using: .utf8) {
                            self?.handleMessage(data)
                        }
                    case .data(let data):
                        log.info("Received data frame (\(data.count) bytes)")
                        self?.handleMessage(data)
                    @unknown default:
                        log.warning("Received unknown frame type")
                    }
                    self?.receiveMessage()

                case .failure(let error):
                    log.error("WebSocket receive error: \(error.localizedDescription)")
                    self?.connectionState = .disconnected
                    self?.lastError = error.localizedDescription
                    self?.scheduleReconnect()
                }
            }
        }
    }

    private func handleMessage(_ data: Data) {
        do {
            let message = try JSONDecoder().decode(RemoteMessage.self, from: data)
            switch message {
            case .snapshot(let snapshots):
                log.info("Received snapshot with \(snapshots.count) agent(s)")
                self.agents = snapshots.map(\.agent).sorted { $0.status.sortPriority < $1.status.sortPriority }
                var icons: [String: Data] = [:]
                var colors: [String: String] = [:]
                var perms: [String: [String]] = [:]
                for snapshot in snapshots {
                    let sid = snapshot.agent.sessionId
                    if let iconData = snapshot.appIconPNG { icons[sid] = iconData }
                    if let hex = snapshot.statusColorHex { colors[sid] = hex }
                    if let opts = snapshot.permissionOptions { perms[sid] = opts }
                }
                self.agentIconData = icons
                self.agentColorHex = colors
                self.agentPermissionOptions = perms
            case .agentUpdated(let snapshot):
                let agent = snapshot.agent
                log.info("Agent updated: \(agent.sessionId) status=\(agent.status.rawValue)")
                if let index = agents.firstIndex(where: { $0.sessionId == agent.sessionId }) {
                    agents[index] = agent
                } else {
                    agents.append(agent)
                }
                agents.sort { $0.status.sortPriority < $1.status.sortPriority }
                if let iconData = snapshot.appIconPNG {
                    agentIconData[agent.sessionId] = iconData
                }
                if let hex = snapshot.statusColorHex {
                    agentColorHex[agent.sessionId] = hex
                }
                if let opts = snapshot.permissionOptions {
                    agentPermissionOptions[agent.sessionId] = opts
                } else {
                    agentPermissionOptions.removeValue(forKey: agent.sessionId)
                }
            case .agentRemoved(let sessionId):
                log.info("Agent removed: \(sessionId)")
                agents.removeAll { $0.sessionId == sessionId }
                agentIconData.removeValue(forKey: sessionId)
            case .heartbeat:
                log.debug("Heartbeat received")
            }
        } catch {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
            log.error("Failed to decode message: \(error.localizedDescription)\nData: \(preview)")
        }
    }

    private func scheduleReconnect() {
        log.info("Scheduling reconnect in 5s")
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, let serverURL = self.serverURL, let token = self.authToken else { return }
                log.info("Reconnecting...")
                self.connect(host: serverURL.host ?? "", port: serverURL.port ?? 8443, token: token)
            }
        }
    }

    private func startHeartbeatMonitor() {
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.webSocketTask?.sendPing { error in
                if let error {
                    log.warning("Ping failed: \(error.localizedDescription)")
                    Task { @MainActor in
                        self.connectionState = .disconnected
                        self.scheduleReconnect()
                    }
                }
            }
        }
    }
}
