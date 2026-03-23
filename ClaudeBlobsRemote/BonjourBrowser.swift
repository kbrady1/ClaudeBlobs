// ClaudeBlobsRemote/BonjourBrowser.swift
import Foundation
import Network
import os

private let log = Logger(subsystem: "com.claudeblobs.remote", category: "Bonjour")

/// Discovers ClaudeBlobs instances on the local network via Bonjour.
@MainActor
final class BonjourBrowser: ObservableObject {
    @Published var discoveredHosts: [NWBrowser.Result] = []
    private var browser: NWBrowser?

    func start() {
        log.info("Starting Bonjour browse for _claudeblobs._tcp")
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_claudeblobs._tcp", domain: nil)
        browser = NWBrowser(for: descriptor, using: .tcp)

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            log.info("Bonjour results changed: \(results.count) host(s)")
            for result in results {
                log.info("  Found: \(String(describing: result.endpoint))")
            }
            for change in changes {
                log.info("  Change: \(String(describing: change))")
            }
            DispatchQueue.main.async {
                self?.discoveredHosts = Array(results)
            }
        }

        browser?.stateUpdateHandler = { state in
            log.info("Bonjour browser state: \(String(describing: state))")
        }

        browser?.start(queue: .main)
    }

    func stop() {
        log.info("Stopping Bonjour browser")
        browser?.cancel()
        browser = nil
    }
}
