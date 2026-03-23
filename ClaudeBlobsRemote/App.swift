// ClaudeBlobsRemote/App.swift
import SwiftUI
import Network
import Combine

@main
struct ClaudeBlobsRemoteApp: App {
    @StateObject private var pairingStore = PairingStore()
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var bonjourBrowser = BonjourBrowser()

    var body: some Scene {
        WindowGroup {
            Group {
                if pairingStore.isPaired {
                    AgentListView(connectionManager: connectionManager, onUnpair: {
                            connectionManager.disconnect()
                            bonjourBrowser.stop()
                            pairingStore.unpair()
                        })
                        .onAppear { connectIfNeeded() }
                        .onChange(of: bonjourBrowser.discoveredHosts) { _, hosts in
                            // React to Bonjour discovery instead of using a fixed delay
                            if !hosts.isEmpty, connectionManager.connectionState == .disconnected {
                                resolveAndConnect(hosts: hosts)
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
              connectionManager.connectionState == .disconnected
        else { return }

        bonjourBrowser.start()

        // If hosts are already discovered (e.g., from a previous browse), connect immediately
        if !bonjourBrowser.discoveredHosts.isEmpty {
            resolveAndConnect(hosts: bonjourBrowser.discoveredHosts)
        }
        // Otherwise, onChange(of: discoveredHosts) will fire when they appear
    }

    private func resolveAndConnect(hosts: [NWBrowser.Result]) {
        guard let token = pairingStore.token,
              let port = pairingStore.serverPort,
              let result = hosts.first
        else { return }

        // Resolve the Bonjour endpoint to an IP address
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
                    @unknown default: hostString = "localhost"
                    }
                    Task { @MainActor in
                        connectionManager.connect(host: hostString, port: port, token: token)
                    }
                }
                connection.cancel()
            } else if case .failed = state {
                connection.cancel()
            }
        }
        connection.start(queue: .global())
    }
}
