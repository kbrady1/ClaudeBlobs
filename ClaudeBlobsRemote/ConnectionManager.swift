// ClaudeBlobsRemote/ConnectionManager.swift
import Foundation
import Network
import CryptoKit
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
    private var sessionDelegate: CertPinningDelegate?
    private var serverURL: URL?
    private var authToken: String?
    private var expectedCertPin: String?
    private var reconnectTimer: Timer?

    func connect(host: String, port: Int, token: String, certPin: String? = nil) {
        authToken = token
        expectedCertPin = certPin
        let urlString = "wss://\(host):\(port)"
        log.info("Connecting to \(urlString)")
        guard let url = URL(string: urlString) else {
            log.error("Invalid URL: \(urlString)")
            return
        }
        serverURL = url

        connectionState = .connecting

        let config = URLSessionConfiguration.default
        let delegate = CertPinningDelegate(expectedPin: certPin)
        sessionDelegate = delegate
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.maximumMessageSize = 16 * 1024 * 1024  // 16 MB — snapshots include icon PNG data
        log.info("WebSocket task created, resuming...")
        webSocketTask?.resume()

        // First message must be auth token
        struct AuthMessage: Encodable {
            let type = "auth"
            let token: String
        }
        let authJSON = try? JSONEncoder().encode(AuthMessage(token: token))
        let authMessage = authJSON.flatMap { String(data: $0, encoding: .utf8) } ?? ""
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
                self.connect(host: serverURL.host ?? "", port: serverURL.port ?? 8443, token: token, certPin: self.expectedCertPin)
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

// MARK: - TLS Certificate Pinning

/// URLSession delegate that validates the server's TLS certificate against
/// a SHA-256 pin received during QR code pairing.
final class CertPinningDelegate: NSObject, URLSessionDelegate {
    private let expectedPin: String?

    init(expectedPin: String?) {
        self.expectedPin = expectedPin
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Require a certificate pin — reject if none was configured
        guard let expectedPin, !expectedPin.isEmpty else {
            log.error("No certificate pin configured — rejecting connection")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Validate certificate pin
        if SecTrustGetCertificateCount(serverTrust) > 0,
           let serverCert = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
           let leafCert = serverCert.first {
            let derData = SecCertificateCopyData(leafCert) as Data
            let hash = SHA256.hash(data: derData)
            let pin = "sha256/" + Data(hash).base64EncodedString()

            if pin == expectedPin {
                log.info("Certificate pin matches")
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            } else {
                log.error("Certificate pin mismatch: expected=\(expectedPin) got=\(pin)")
            }
        } else {
            log.error("Failed to extract server certificate for pin validation")
        }

        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}
