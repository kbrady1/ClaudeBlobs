// Sources/Lib/Remote/PairingManager.swift
import Foundation
import Security
import CoreImage

/// Manages pairing tokens, TLS identity, and QR code generation.
/// Class (reference type) so mutations from views update the shared instance.
final class PairingManager {

    struct QRPayload: Codable {
        let token: String
        let certPin: String
        let port: Int
    }

    struct PairedDevice: Codable, Identifiable {
        let name: String
        let token: String
        let pairedAt: Date
        var id: String { token }
    }

    private let keychainPrefix: String

    var pairedDevices: [PairedDevice] {
        get {
            guard let data = getKeychainData(key: "\(keychainPrefix).pairedDevices"),
                  let devices = try? JSONDecoder().decode([PairedDevice].self, from: data)
            else { return [] }
            return devices
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            setKeychainData(key: "\(keychainPrefix).pairedDevices", data: data)
        }
    }

    private func setKeychainData(key: String, data: Data?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        guard let data else { return }
        var attrs = query
        attrs[kSecValueData as String] = data
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private func getKeychainData(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    init(keychainPrefix: String = "com.claudeblobs.remote") {
        self.keychainPrefix = keychainPrefix
    }

    static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    func isValidToken(_ token: String) -> Bool {
        pairedDevices.contains { $0.token == token }
    }

    func addPairedDevice(name: String, token: String) {
        var devices = pairedDevices
        devices.append(PairedDevice(name: name, token: token, pairedAt: Date()))
        pairedDevices = devices
    }

    func removePairedDevice(token: String) {
        var devices = pairedDevices
        devices.removeAll { $0.token == token }
        pairedDevices = devices
    }

    func removeAllDevices() {
        pairedDevices = []
    }

    static func generateQRCode(payload: QRPayload) -> CIImage? {
        guard let data = try? JSONEncoder().encode(payload),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        return filter.outputImage
    }
}
