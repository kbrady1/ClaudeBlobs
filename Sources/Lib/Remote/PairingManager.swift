// Sources/Lib/Remote/PairingManager.swift
import Foundation
import Security
import CoreImage
import CryptoKit

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

    /// The TLS identity (private key + certificate) used by the server.
    /// Created once and persisted in Keychain; reused across restarts.
    private(set) var tlsIdentity: SecIdentity?

    /// SHA-256 fingerprint of the server's TLS certificate, base64-encoded.
    /// Embedded in QR codes so the iOS client can pin the connection.
    private(set) var certificatePin: String?

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

    init(keychainPrefix: String = "com.claudeblobs.remote", enableTLS: Bool = true) {
        self.keychainPrefix = keychainPrefix
        if enableTLS {
            loadOrCreateTLSIdentity()
        }
    }

    // MARK: - TLS Identity

    /// Load existing TLS identity from Keychain, or create a new self-signed one.
    private func loadOrCreateTLSIdentity() {
        let label = "\(keychainPrefix).tls"

        // Try to load existing identity
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let identity = result {
            // swiftlint:disable:next force_cast
            tlsIdentity = (identity as! SecIdentity)
            certificatePin = computeCertificatePin(from: tlsIdentity!)
            DebugLog.shared.log("PairingManager: loaded existing TLS identity")
            return
        }

        // Generate new self-signed identity
        guard let identity = generateSelfSignedIdentity(label: label) else {
            DebugLog.shared.log("PairingManager: failed to generate TLS identity")
            return
        }
        tlsIdentity = identity
        certificatePin = computeCertificatePin(from: identity)
        DebugLog.shared.log("PairingManager: created new TLS identity, pin=\(certificatePin ?? "nil")")
    }

    /// Generate a self-signed identity using Security framework.
    private func generateSelfSignedIdentity(label: String) -> SecIdentity? {
        // Generate RSA key pair in Keychain
        let keyTag = "\(label).key".data(using: .utf8)!
        let keyParams: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecAttrLabel as String: label,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrLabel as String: label,
            ] as [String: Any],
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(keyParams as CFDictionary, &error) else {
            DebugLog.shared.log("PairingManager: key generation failed — \(String(describing: error))")
            return nil
        }

        // Create self-signed certificate using the private key
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let cert = createSelfSignedCert(publicKey: publicKey, privateKey: privateKey, label: label) else {
            DebugLog.shared.log("PairingManager: certificate generation failed")
            return nil
        }

        // Store certificate in Keychain
        let certAddQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: cert,
            kSecAttrLabel as String: label,
        ]
        SecItemDelete(certAddQuery as CFDictionary)
        let certStatus = SecItemAdd(certAddQuery as CFDictionary, nil)
        guard certStatus == errSecSuccess else {
            DebugLog.shared.log("PairingManager: failed to store certificate — \(certStatus)")
            return nil
        }

        // Retrieve identity (key + cert pair)
        let identityQuery: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var identityResult: AnyObject?
        guard SecItemCopyMatching(identityQuery as CFDictionary, &identityResult) == errSecSuccess else {
            DebugLog.shared.log("PairingManager: failed to retrieve identity after creation")
            return nil
        }
        // swiftlint:disable:next force_cast
        return (identityResult as! SecIdentity)
    }

    /// Create a self-signed X.509 certificate (DER-encoded) using Security framework.
    private func createSelfSignedCert(publicKey: SecKey, privateKey: SecKey, label: String) -> SecCertificate? {
        // Build a minimal self-signed X.509 v1 certificate in DER format.
        // Subject: CN=ClaudeBlobs Remote, valid for 10 years.
        guard let pubKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else { return nil }

        let cn = "ClaudeBlobs Remote"
        let now = Date()
        let expiry = Calendar.current.date(byAdding: .year, value: 10, to: now)!

        let tbs = buildTBSCertificate(cn: cn, publicKeyData: pubKeyData, notBefore: now, notAfter: expiry)
        let signature = signData(tbs, with: privateKey)
        guard let signature else { return nil }

        let certDER = wrapSignedCertificate(tbsCertificate: tbs, signature: signature)
        return SecCertificateCreateWithData(nil, certDER as CFData)
    }

    // MARK: - ASN.1 / DER helpers

    /// Build TBS (to-be-signed) certificate structure.
    private func buildTBSCertificate(cn: String, publicKeyData: Data, notBefore: Date, notAfter: Date) -> Data {
        var tbs = Data()

        // Version: v1 (default, no explicit version tag needed for v1)
        // Serial number
        let serial = buildDERInteger(data: Data([0x01]))

        // Signature algorithm: SHA256WithRSAEncryption
        let sigAlgOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B] // 1.2.840.113549.1.1.11
        let sigAlg = buildDERSequence(contents: buildDEROID(sigAlgOID) + buildDERNull())

        // Issuer: CN=<cn>
        let issuer = buildDistinguishedName(cn: cn)

        // Validity
        let validity = buildDERSequence(contents: buildDERUTCTime(notBefore) + buildDERUTCTime(notAfter))

        // Subject = Issuer (self-signed)
        let subject = issuer

        // SubjectPublicKeyInfo (RSA)
        let rsaOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01] // 1.2.840.113549.1.1.1
        let spkiAlg = buildDERSequence(contents: buildDEROID(rsaOID) + buildDERNull())
        let spki = buildDERSequence(contents: spkiAlg + buildDERBitString(publicKeyData))

        tbs = serial + sigAlg + issuer + validity + subject + spki
        return buildDERSequence(contents: tbs)
    }

    private func signData(_ data: Data, with privateKey: SecKey) -> Data? {
        var error: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, &error) else {
            return nil
        }
        return sig as Data
    }

    private func wrapSignedCertificate(tbsCertificate: Data, signature: Data) -> Data {
        let sigAlgOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]
        let sigAlg = buildDERSequence(contents: buildDEROID(sigAlgOID) + buildDERNull())
        let sigBits = buildDERBitString(signature)
        return buildDERSequence(contents: tbsCertificate + sigAlg + sigBits)
    }

    private func buildDERSequence(contents: Data) -> Data {
        return Data([0x30]) + derLength(contents.count) + contents
    }

    private func buildDERInteger(data: Data) -> Data {
        // Ensure positive by prepending 0x00 if high bit set
        var bytes = data
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0x00, at: 0)
        }
        return Data([0x02]) + derLength(bytes.count) + bytes
    }

    private func buildDEROID(_ oid: [UInt8]) -> Data {
        return Data([0x06, UInt8(oid.count)] + oid)
    }

    private func buildDERNull() -> Data {
        return Data([0x05, 0x00])
    }

    private func buildDERBitString(_ data: Data) -> Data {
        // Bit string: 0x03 + length + 0x00 (no unused bits) + data
        let contents = Data([0x00]) + data
        return Data([0x03]) + derLength(contents.count) + contents
    }

    private func buildDERUTCTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let str = formatter.string(from: date)
        let bytes = Array(str.utf8)
        return Data([0x17, UInt8(bytes.count)] + bytes)
    }

    private func buildDistinguishedName(cn: String) -> Data {
        // CN OID: 2.5.4.3
        let cnOID: [UInt8] = [0x55, 0x04, 0x03]
        let cnValue = Data([0x0C]) + derLength(cn.utf8.count) + Data(cn.utf8)  // UTF8String
        let attrTypeAndValue = buildDERSequence(contents: buildDEROID(cnOID) + cnValue)
        let rdn = Data([0x31]) + derLength(attrTypeAndValue.count) + attrTypeAndValue  // SET
        return buildDERSequence(contents: rdn)
    }

    private func derLength(_ length: Int) -> Data {
        if length < 0x80 {
            return Data([UInt8(length)])
        } else if length < 0x100 {
            return Data([0x81, UInt8(length)])
        } else {
            return Data([0x82, UInt8(length >> 8), UInt8(length & 0xFF)])
        }
    }

    // MARK: - Certificate Pin

    /// Compute SHA-256 fingerprint of the certificate's DER encoding, base64-encoded.
    private func computeCertificatePin(from identity: SecIdentity) -> String? {
        var cert: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess,
              let certificate = cert else { return nil }
        let derData = SecCertificateCopyData(certificate) as Data
        let hash = SHA256.hash(data: derData)
        return "sha256/" + Data(hash).base64EncodedString()
    }

    // MARK: - Tokens

    static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    /// Token lifetime: 72 hours.
    static let tokenLifetime: TimeInterval = 72 * 60 * 60

    func isValidToken(_ token: String) -> Bool {
        let now = Date()
        return pairedDevices.contains { device in
            device.token == token && now.timeIntervalSince(device.pairedAt) < Self.tokenLifetime
        }
    }

    /// Remove all expired devices.
    func removeExpiredDevices() {
        let now = Date()
        var devices = pairedDevices
        devices.removeAll { now.timeIntervalSince($0.pairedAt) >= Self.tokenLifetime }
        pairedDevices = devices
    }

    func addPairedDevice(name: String, token: String) {
        var devices = pairedDevices
        devices.append(PairedDevice(name: name, token: token, pairedAt: Date()))
        pairedDevices = devices
        DebugLog.shared.log("PairingManager [AUDIT]: device paired name=\(name)")
    }

    func removePairedDevice(token: String) {
        let name = pairedDevices.first { $0.token == token }?.name ?? "unknown"
        var devices = pairedDevices
        devices.removeAll { $0.token == token }
        pairedDevices = devices
        DebugLog.shared.log("PairingManager [AUDIT]: device unpaired name=\(name)")
    }

    func removeAllDevices() {
        let count = pairedDevices.count
        pairedDevices = []
        DebugLog.shared.log("PairingManager [AUDIT]: all devices removed count=\(count)")
    }

    static func generateQRCode(payload: QRPayload) -> CIImage? {
        guard let data = try? JSONEncoder().encode(payload),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        return filter.outputImage
    }
}
