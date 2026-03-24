// ClaudeBlobsRemote/App.swift
import SwiftUI
import Network
import Combine
import os

private let log = Logger(subsystem: "com.claudeblobs.remote", category: "App")

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
                        .onAppear {
                            log.info("AgentListView appeared, isPaired=\(pairingStore.isPaired)")
                            connectIfNeeded()
                        }
                        .onChange(of: bonjourBrowser.discoveredHosts) { _, hosts in
                            log.info("discoveredHosts changed: \(hosts.count) host(s), connectionState=\(String(describing: connectionManager.connectionState))")
                            if !hosts.isEmpty, connectionManager.connectionState == .disconnected {
                                resolveAndConnect(hosts: hosts)
                            }
                        }
                } else {
                    PairingView(pairingStore: pairingStore)
                        .onChange(of: pairingStore.isPaired) { _, isPaired in
                            log.info("isPaired changed to \(isPaired)")
                            if isPaired { connectIfNeeded() }
                        }
                }
            }
        }
    }

    private func connectIfNeeded() {
        log.info("connectIfNeeded: isPaired=\(pairingStore.isPaired) token=\(pairingStore.token != nil) port=\(String(describing: pairingStore.serverPort)) state=\(String(describing: connectionManager.connectionState))")

        guard pairingStore.isPaired,
              connectionManager.connectionState == .disconnected
        else {
            log.info("connectIfNeeded: guard failed, skipping")
            return
        }

        log.info("Starting Bonjour browser...")
        bonjourBrowser.start()

        if !bonjourBrowser.discoveredHosts.isEmpty {
            log.info("Hosts already discovered, resolving immediately")
            resolveAndConnect(hosts: bonjourBrowser.discoveredHosts)
        } else {
            log.info("No hosts yet, waiting for Bonjour discovery...")
        }
    }

    private func resolveAndConnect(hosts: [NWBrowser.Result]) {
        guard let token = pairingStore.token,
              let port = pairingStore.serverPort,
              let result = hosts.first
        else {
            log.error("resolveAndConnect: missing token=\(pairingStore.token != nil) port=\(String(describing: pairingStore.serverPort)) hosts=\(hosts.count)")
            return
        }

        log.info("Resolving endpoint: \(String(describing: result.endpoint)) on port \(port)")

        // Prefer IPv4 to avoid IPv6 link-local scope IDs (%en0) which break URL parsing
        let params = NWParameters.tcp
        params.preferNoProxies = true
        if let ipOptions = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4
        }

        let connection = NWConnection(to: result.endpoint, using: params)
        connection.stateUpdateHandler = { state in
            log.info("Resolution connection state: \(String(describing: state))")
            if case .ready = state {
                if let path = connection.currentPath,
                   let endpoint = path.remoteEndpoint,
                   case let .hostPort(host, _) = endpoint {
                    let hostString: String
                    switch host {
                    case .ipv4(let addr):
                        // Strip %interface suffix (e.g. "192.168.1.250%en0" -> "192.168.1.250")
                        let raw = "\(addr)"
                        hostString = raw.split(separator: "%").first.map(String.init) ?? raw
                    case .ipv6(let addr):
                        // Percent-encode the scope ID for URL safety
                        let raw = "\(addr)"
                        hostString = "[\(raw.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? raw)]"
                    @unknown default:
                        hostString = "localhost"
                    }
                    log.info("Resolved to IP: \(hostString), connecting WebSocket on port \(port)")
                    let pin = pairingStore.certPin
                    Task { @MainActor in
                        connectionManager.connect(host: hostString, port: port, token: token, certPin: pin)
                    }
                } else {
                    log.error("Connection ready but could not extract remote endpoint")
                }
                connection.cancel()
            } else if case let .failed(error) = state {
                log.error("Resolution connection failed: \(error.localizedDescription)")
                connection.cancel()
            } else if case .cancelled = state {
                log.info("Resolution connection cancelled")
            }
        }
        connection.start(queue: .global())
    }
}
