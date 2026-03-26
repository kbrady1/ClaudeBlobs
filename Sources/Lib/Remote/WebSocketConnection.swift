import Foundation
import Network
import os

/// Manages a single WebSocket client connection.
final class WebSocketConnection: Identifiable {
    let id: String
    let nwConnection: NWConnection
    /// The auth token this connection authenticated with, used for dedup/eviction.
    var authToken: String?
    private let _isAlive = OSAllocatedUnfairLock(initialState: true)

    var isAlive: Bool {
        get { _isAlive.withLock { $0 } }
        set { _isAlive.withLock { $0 = newValue } }
    }

    init(id: String, connection: NWConnection) {
        self.id = id
        self.nwConnection = connection
    }

    /// Send a RemoteMessage as JSON text frame.
    func send(_ message: RemoteMessage) {
        guard isAlive else { return }
        guard let data = try? JSONEncoder().encode(message) else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])

        nwConnection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { [weak self] error in
                if let error {
                    DebugLog.shared.log("WebSocketConnection[\(self?.id ?? "?")] send error: \(error)")
                    self?.isAlive = false
                }
            }
        )
    }

    /// Send a ping frame for heartbeat. Marks connection dead if send fails.
    func sendPing() {
        guard isAlive else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .ping)
        let context = NWConnection.ContentContext(identifier: "ping", metadata: [metadata])
        nwConnection.send(
            content: nil,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { [weak self] error in
                if let error {
                    DebugLog.shared.log("WebSocketConnection[\(self?.id ?? "?")] ping failed: \(error)")
                    self?.isAlive = false
                    self?.nwConnection.cancel()
                }
            }
        )
    }

    /// Start receiving messages. Calls handler for each received text frame.
    func receive(handler: @escaping (Data) -> Void) {
        guard isAlive else { return }
        nwConnection.receiveMessage { [weak self] content, context, _, error in
            guard let self, self.isAlive else { return }
            if let error {
                DebugLog.shared.log("WebSocketConnection[\(self.id)] receive error: \(error)")
                self.isAlive = false
                return
            }
            if let data = content {
                handler(data)
            }
            // Continue receiving
            self.receive(handler: handler)
        }
    }

    func cancel() {
        isAlive = false
        nwConnection.cancel()
    }
}
