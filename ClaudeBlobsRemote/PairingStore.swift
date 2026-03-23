// ClaudeBlobsRemote/PairingStore.swift
import Foundation
import AVFoundation

/// Stores pairing credentials and manages QR code scanning.
@MainActor
final class PairingStore: ObservableObject {
    @Published var isPaired = false
    @Published var token: String?
    @Published var certPin: String?
    @Published var serverPort: Int?

    private let tokenKey = "com.claudeblobs.remote.token"
    private let certPinKey = "com.claudeblobs.remote.certPin"
    private let portKey = "com.claudeblobs.remote.port"

    init() {
        loadFromKeychain()
    }

    func handleQRPayload(_ data: Data) {
        struct QRPayload: Codable {
            let token: String
            let certPin: String
            let port: Int
        }

        guard let payload = try? JSONDecoder().decode(QRPayload.self, from: data) else { return }

        token = payload.token
        certPin = payload.certPin
        serverPort = payload.port
        isPaired = true
        saveToKeychain()
    }

    func unpair() {
        token = nil
        certPin = nil
        serverPort = nil
        isPaired = false
        clearKeychain()
    }

    private func saveToKeychain() {
        setKeychainItem(key: tokenKey, value: token)
        setKeychainItem(key: certPinKey, value: certPin)
        if let serverPort {
            setKeychainItem(key: portKey, value: String(serverPort))
        }
    }

    private func loadFromKeychain() {
        token = getKeychainItem(key: tokenKey)
        certPin = getKeychainItem(key: certPinKey)
        if let portStr = getKeychainItem(key: portKey) {
            serverPort = Int(portStr)
        }
        isPaired = token != nil
    }

    private func clearKeychain() {
        deleteKeychainItem(key: tokenKey)
        deleteKeychainItem(key: certPinKey)
        deleteKeychainItem(key: portKey)
    }

    // MARK: - Keychain helpers

    private func setKeychainItem(key: String, value: String?) {
        guard let value, let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private func getKeychainItem(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychainItem(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
