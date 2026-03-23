// ClaudeBlobsRemote/BonjourBrowser.swift
import Foundation
import Network

/// Discovers ClaudeBlobs instances on the local network via Bonjour.
@MainActor
final class BonjourBrowser: ObservableObject {
    @Published var discoveredHosts: [NWBrowser.Result] = []
    private var browser: NWBrowser?

    func start() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_claudeblobs._tcp", domain: nil)
        browser = NWBrowser(for: descriptor, using: .tcp)

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                self?.discoveredHosts = Array(results)
            }
        }

        browser?.stateUpdateHandler = { state in
            // Log state changes for debugging
        }

        browser?.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}
