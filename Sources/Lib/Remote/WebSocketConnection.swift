import Foundation
import Network

/// Manages a single WebSocket client connection.
final class WebSocketConnection: Identifiable {
    let id: String
    let nwConnection: NWConnection
    private var isAlive = true

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

    /// Send a ping frame for heartbeat.
    func sendPing() {
        guard isAlive else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .ping)
        let context = NWConnection.ContentContext(identifier: "ping", metadata: [metadata])
        nwConnection.send(
            content: nil,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { _ in }
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
