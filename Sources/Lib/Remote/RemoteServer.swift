import Foundation
import Network
import Combine
import AppKit
import SwiftUI

/// Embedded WebSocket server for remote control.
final class RemoteServer: ObservableObject {
    private var listener: NWListener?
    private var connections: [String: WebSocketConnection] = [:]
    private var heartbeatTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Serial queue protecting `connections` and `failedAuthAttempts` from data races.
    /// All reads/writes to those dictionaries MUST go through this queue.
    private let syncQueue = DispatchQueue(label: "com.claudeblobs.remote.sync")

    let pairingManager: PairingManager
    private let agentStore: AgentStore
    private let port: UInt16

    /// Rate limiting: track failed auth attempts per remote IP.
    private var failedAuthAttempts: [String: [Date]] = [:]
    private static let maxFailedAttempts = 5
    private static let lockoutDuration: TimeInterval = 60
    private static let maxConnections = 3

    @Published var isRunning = false
    @Published var connectedClientCount = 0

    init(agentStore: AgentStore, port: UInt16 = 8443, pairingManager: PairingManager? = nil) {
        self.agentStore = agentStore
        self.port = port
        self.pairingManager = pairingManager ?? PairingManager()
    }

    func start() {
        guard !isRunning else { return }

        pairingManager.removeExpiredDevices()

        let wsOptions = NWProtocolWebSocket.Options()

        // Configure TLS with self-signed certificate
        let tlsOptions = NWProtocolTLS.Options()
        if let identity = pairingManager.tlsIdentity {
            sec_protocol_options_set_local_identity(
                tlsOptions.securityProtocolOptions,
                sec_identity_create(identity)!
            )
            sec_protocol_options_set_min_tls_protocol_version(
                tlsOptions.securityProtocolOptions,
                .TLSv12
            )
        } else {
            DebugLog.shared.log("RemoteServer: WARNING — no TLS identity, falling back to plaintext")
        }

        let params = pairingManager.tlsIdentity != nil
            ? NWParameters(tls: tlsOptions)
            : NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            DebugLog.shared.log("RemoteServer: failed to create listener — \(error)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            DebugLog.shared.log("RemoteServer: listener state \(String(describing: state))")
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

        DebugLog.shared.log("RemoteServer: started on port \(self.port)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        cancellables.removeAll()
        syncQueue.sync {
            connections.values.forEach { $0.cancel() }
            connections.removeAll()
            failedAuthAttempts.removeAll()
        }
        isRunning = false
        connectedClientCount = 0
        DebugLog.shared.log("RemoteServer: stopped")
    }

    private func handleNewConnection(_ nwConnection: NWConnection) {
        let connId = UUID().uuidString
        let connection = WebSocketConnection(id: connId, connection: nwConnection)
        let remoteIP = Self.remoteIP(from: nwConnection)

        // Rate limiting check (before auth, no connection-count gate — that
        // happens post-auth after pruning dead connections and evicting dupes)
        let rateLimited: Bool = syncQueue.sync {
            if let ip = remoteIP, isRateLimited(ip: ip) { return true }
            return false
        }
        if rateLimited {
            DebugLog.shared.log("RemoteServer [AUDIT]: rate-limited ip=\(remoteIP ?? "unknown"), rejecting conn=\(connId)")
            nwConnection.cancel()
            return
        }

        nwConnection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .cancelled, .failed:
                self.syncQueue.async {
                    self.connections.removeValue(forKey: connId)
                    let count = self.connections.count
                    DispatchQueue.main.async {
                        self.connectedClientCount = count
                    }
                }
            default:
                break
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
                self.syncQueue.async {
                    if let ip = remoteIP {
                        self.recordFailedAuth(ip: ip)
                    }
                }
                DebugLog.shared.log("RemoteServer [AUDIT]: auth failed conn=\(connId) ip=\(remoteIP ?? "unknown")")
                connection.cancel()
                return
            }

            // Prune dead connections, evict any existing connection from the
            // same device (same token), then check the limit — all atomically.
            connection.authToken = token
            let (accepted, evicted) = self.syncQueue.sync { () -> (Bool, [WebSocketConnection]) in
                // 1. Prune connections that are no longer alive
                let dead = self.connections.filter { !$0.value.isAlive }
                for id in dead.keys { self.connections.removeValue(forKey: id) }

                // 2. Evict existing connections with the same token (device reconnected)
                let dupes = self.connections.filter { $0.value.authToken == token }
                for id in dupes.keys { self.connections.removeValue(forKey: id) }

                // 3. Check limit after cleanup
                guard self.connections.count < Self.maxConnections else { return (false, []) }
                self.connections[connId] = connection
                return (true, Array(dupes.values))
            }
            // Cancel evicted connections outside the lock
            for dupe in evicted {
                DebugLog.shared.log("RemoteServer: evicting stale connection \(dupe.id) (same token)")
                dupe.cancel()
            }
            guard accepted else {
                DebugLog.shared.log("RemoteServer [AUDIT]: max connections reached post-auth, rejecting conn=\(connId)")
                connection.cancel()
                return
            }

            DispatchQueue.main.async {
                self.connectedClientCount = self.syncQueue.sync { self.connections.count }
            }
            let snapshots = self.buildSnapshots(self.agentStore.agents)
            let snapshot = RemoteMessage.snapshot(agents: snapshots)
            connection.send(snapshot)
            connection.receive { data in
                self.handleIncomingData(data, from: connId)
            }
            DebugLog.shared.log("RemoteServer [AUDIT]: auth success conn=\(connId) ip=\(remoteIP ?? "unknown")")
        }
    }

    // MARK: - Rate Limiting

    private func isRateLimited(ip: String) -> Bool {
        let now = Date()
        guard let attempts = failedAuthAttempts[ip] else { return false }
        let recent = attempts.filter { now.timeIntervalSince($0) < Self.lockoutDuration }
        return recent.count >= Self.maxFailedAttempts
    }

    private func recordFailedAuth(ip: String) {
        let now = Date()
        var attempts = failedAuthAttempts[ip, default: []]
        attempts.append(now)
        // Only keep attempts within the lockout window
        attempts = attempts.filter { now.timeIntervalSince($0) < Self.lockoutDuration }
        failedAuthAttempts[ip] = attempts
    }

    private static func remoteIP(from connection: NWConnection) -> String? {
        if case let .hostPort(host, _) = connection.endpoint {
            return "\(host)"
        }
        return nil
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

            // Validate optionIndex bounds for selectOption commands
            if request.command == .selectOption, let optionIndex = request.optionIndex {
                if let surface = agent.cmuxSurface {
                    let socketPath = agent.cmuxSocketPath ?? "/tmp/cmux.sock"
                    if let screen = CommandExecutor.readScreen(surface: surface, workspace: agent.cmuxWorkspace, socketPath: socketPath) {
                        let options = CommandExecutor.parsePermissionOptions(from: screen)
                        if optionIndex < 0 || optionIndex >= options.count {
                            DebugLog.shared.log("RemoteServer: optionIndex \(optionIndex) out of bounds (0..<\(options.count))")
                            return
                        }
                    }
                }
            }

            let result = try await CommandExecutor.execute(
                command: request.command,
                agent: agent,
                text: request.text,
                optionIndex: request.optionIndex
            )
            DebugLog.shared.log("RemoteServer [AUDIT]: command=\(request.command.rawValue) session=\(request.sessionId.prefix(8)) from=\(connId) result=\(result.success ? "ok" : result.error ?? "failed")")
        }
    }

    private func broadcastSnapshot(_ agents: [Agent]) {
        let snapshots = buildSnapshots(agents)
        let message = RemoteMessage.snapshot(agents: snapshots)
        let activeConnections = syncQueue.sync { Array(connections.values) }
        let statuses = agents.map { "\($0.sessionId.prefix(8)):\($0.status.rawValue)" }.joined(separator: ", ")
        DebugLog.shared.log("RemoteServer: broadcasting to \(activeConnections.count) client(s): [\(statuses)]")
        for connection in activeConnections {
            connection.send(message)
        }
    }

    private func buildSnapshots(_ agents: [Agent]) -> [AgentSnapshot] {
        agents.map { originalAgent in
            // Sanitize agent data for network transmission:
            // - Strip rawLastMessage (can contain sensitive full output)
            // - Truncate cwd to basename (hides full filesystem paths)
            var agent = originalAgent
            agent.rawLastMessage = nil
            if let cwd = agent.cwd {
                agent.cwd = (cwd as NSString).lastPathComponent
            }
            let iconData: Data? = agentStore.hostAppIcons[agent.pid].flatMap { nsImage in
                // Resize to 64x64 before encoding — full-size icons blow up the WebSocket frame
                let targetSize = NSSize(width: 64, height: 64)
                let resized = NSImage(size: targetSize)
                resized.lockFocus()
                nsImage.draw(in: NSRect(origin: .zero, size: targetSize),
                            from: NSRect(origin: .zero, size: nsImage.size),
                            operation: .copy, fraction: 1.0)
                resized.unlockFocus()
                guard let tiffData = resized.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
                return bitmap.representation(using: .png, properties: [:])
            }
            // Resolve the status color from the current theme, matching macOS sprite logic
            let theme = ColorTheme(rawValue: UserDefaults.standard.string(forKey: "selectedTheme") ?? "") ?? .trafficLight
            let effectiveStatus: AgentStatus
            if agent.status == .waiting && agent.isDone {
                // Done agents use the starting color (green), matching AgentSpriteView.backgroundColor
                effectiveStatus = .starting
            } else {
                effectiveStatus = agent.status
            }
            let color = theme.color(for: effectiveStatus)
            let hex = Self.colorToHex(color)

            // Parse permission options from screen if agent is waiting for permission
            var permissionOptions: [String]? = nil
            if agent.status == .permission, let surface = agent.cmuxSurface {
                let socketPath = agent.cmuxSocketPath ?? "/tmp/cmux.sock"
                if let screen = CommandExecutor.readScreen(surface: surface, workspace: agent.cmuxWorkspace, socketPath: socketPath) {
                    let options = CommandExecutor.parsePermissionOptions(from: screen)
                    if !options.isEmpty {
                        permissionOptions = options
                    }
                }
            }

            return AgentSnapshot(agent: agent, appIconPNG: iconData, statusColorHex: hex, permissionOptions: permissionOptions)
        }
    }

    private static func colorToHex(_ color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func sendHeartbeats() {
        let activeConnections = syncQueue.sync { Array(connections.values) }
        for connection in activeConnections {
            connection.sendPing()
        }
    }
}
