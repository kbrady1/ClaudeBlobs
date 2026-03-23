// ClaudeBlobsRemote/App.swift
import SwiftUI

@main
struct ClaudeBlobsRemoteApp: App {
    @StateObject private var pairingStore = PairingStore()
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var bonjourBrowser = BonjourBrowser()

    var body: some Scene {
        WindowGroup {
            Group {
                if pairingStore.isPaired {
                    AgentListView(connectionManager: connectionManager)
                        .onAppear { connectIfNeeded() }
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Unpair") {
                                    connectionManager.disconnect()
                                    pairingStore.unpair()
                                }
                                .font(.caption)
                            }
                        }
                } else {
                    PairingView(pairingStore: pairingStore)
                        .onChange(of: pairingStore.isPaired) { _, isPaired in
                            if isPaired { connectIfNeeded() }
                        }
                }
            }
        }
    }

    private func connectIfNeeded() {
        guard pairingStore.isPaired,
              let token = pairingStore.token,
              let port = pairingStore.serverPort,
              connectionManager.connectionState == .disconnected
        else { return }

        // Start Bonjour discovery to find the Mac's IP
        bonjourBrowser.start()

        // For v1, connect to first discovered host
        // In production, match against cert pin from pairing
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if let result = bonjourBrowser.discoveredHosts.first,
               case let .service(name, _, _, _) = result.endpoint {
                // Resolve the Bonjour endpoint to connect
                let connection = NWConnection(to: result.endpoint, using: .tcp)
                connection.stateUpdateHandler = { state in
                    if case .ready = state {
                        if let path = connection.currentPath,
                           let endpoint = path.remoteEndpoint,
                           case let .hostPort(host, _) = endpoint {
                            let hostString: String
                            switch host {
                            case .ipv4(let addr): hostString = "\(addr)"
                            case .ipv6(let addr): hostString = "\(addr)"
                            default: hostString = name
                            @unknown default: hostString = name
                            }
                            Task { @MainActor in
                                connectionManager.connect(host: hostString, port: port, token: token)
                            }
                        }
                        connection.cancel()
                    }
                }
                connection.start(queue: .global())
            }
        }
    }
}
