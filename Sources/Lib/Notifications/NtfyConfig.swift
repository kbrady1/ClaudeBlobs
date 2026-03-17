import Foundation
import Combine

final class NtfyConfig: ObservableObject {
    @Published var isEnabled: Bool = UserDefaults.standard.bool(forKey: "ntfyEnabled") {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "ntfyEnabled") }
    }
    @Published var endpoint: String = UserDefaults.standard.string(forKey: "ntfyEndpoint") ?? "https://ntfy.sh" {
        didSet { UserDefaults.standard.set(endpoint, forKey: "ntfyEndpoint") }
    }
    @Published var topic: String = UserDefaults.standard.string(forKey: "ntfyTopic") ?? "" {
        didSet { UserDefaults.standard.set(topic, forKey: "ntfyTopic") }
    }
    @Published var delaySeconds: Int = UserDefaults.standard.object(forKey: "ntfyDelay") as? Int ?? 30 {
        didSet { UserDefaults.standard.set(delaySeconds, forKey: "ntfyDelay") }
    }
    @Published var defaultPriority: String = UserDefaults.standard.string(forKey: "ntfyDefaultPriority") ?? "default" {
        didSet { UserDefaults.standard.set(defaultPriority, forKey: "ntfyDefaultPriority") }
    }
    @Published var permissionPriority: String = UserDefaults.standard.string(forKey: "ntfyPermissionPriority") ?? "high" {
        didSet { UserDefaults.standard.set(permissionPriority, forKey: "ntfyPermissionPriority") }
    }
    @Published var tags: String = UserDefaults.standard.string(forKey: "ntfyTags") ?? "robot" {
        didSet { UserDefaults.standard.set(tags, forKey: "ntfyTags") }
    }

    // Which states trigger notifications
    @Published var notifyOnPermission: Bool = UserDefaults.standard.object(forKey: "ntfyOnPermission") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notifyOnPermission, forKey: "ntfyOnPermission") }
    }
    @Published var notifyOnWaiting: Bool = UserDefaults.standard.object(forKey: "ntfyOnWaiting") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notifyOnWaiting, forKey: "ntfyOnWaiting") }
    }
    @Published var notifyOnDone: Bool = UserDefaults.standard.object(forKey: "ntfyOnDone") as? Bool ?? false {
        didSet { UserDefaults.standard.set(notifyOnDone, forKey: "ntfyOnDone") }
    }

    var isConfigured: Bool { isEnabled && !topic.isEmpty }
}
