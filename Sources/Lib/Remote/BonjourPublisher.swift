import Foundation
import Network

/// Configures Bonjour advertisement on an existing NWListener.
/// Does NOT create its own listener — avoids port conflict with RemoteServer.
enum BonjourPublisher {

    /// Configure Bonjour service discovery on the given listener.
    /// Call this before `listener.start()`.
    static func configure(on listener: NWListener) {
        listener.service = NWListener.Service(
            name: Host.current().localizedName ?? "ClaudeBlobs",
            type: "_claudeblobs._tcp"
        )
        DebugLog.shared.log("BonjourPublisher: configured _claudeblobs._tcp on listener")
    }
}
