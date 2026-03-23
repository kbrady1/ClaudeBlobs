// Tests/PairingManagerTests.swift
import Testing
import Foundation
@testable import ClaudeBlobsLib

@Suite("PairingManager")
struct PairingManagerTests {

    @Test func generateTokenProduces256BitToken() {
        let token = PairingManager.generateToken()
        let data = Data(base64Encoded: token)
        #expect(data != nil)
        #expect(data!.count == 32)
    }

    @Test func generateTokenIsRandom() {
        let t1 = PairingManager.generateToken()
        let t2 = PairingManager.generateToken()
        #expect(t1 != t2)
    }

    @Test func qrPayloadContainsRequiredFields() throws {
        let payload = PairingManager.QRPayload(
            token: "dGVzdHRva2Vu",
            certPin: "sha256/abc123",
            port: 8443
        )
        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["token"] as? String == "dGVzdHRva2Vu")
        #expect(json["certPin"] as? String == "sha256/abc123")
        #expect(json["port"] as? Int == 8443)
    }

    @Test func pairedDeviceTracking() {
        let manager = PairingManager(keychainPrefix: "test-\(UUID().uuidString)")
        let token = PairingManager.generateToken()
        #expect(manager.isValidToken(token) == false)
        manager.addPairedDevice(name: "iPhone", token: token)
        #expect(manager.isValidToken(token) == true)
        #expect(manager.pairedDevices.count == 1)
        manager.removePairedDevice(token: token)
        #expect(manager.isValidToken(token) == false)
        #expect(manager.pairedDevices.isEmpty)
    }
}
