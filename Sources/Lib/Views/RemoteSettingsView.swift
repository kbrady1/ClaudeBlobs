import SwiftUI
import CoreImage.CIFilterBuiltins

struct RemoteSettingsView: View {
    @ObservedObject var server: RemoteServer
    @State private var isEnabled = UserDefaults.standard.bool(forKey: "remoteControlEnabled")
    @State private var showingNewPairingCode = false
    @State private var pendingPayload: PairingManager.QRPayload?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Remote Control")
                .font(.headline)

            Toggle("Enable Remote Access", isOn: $isEnabled)
                .onChange(of: isEnabled) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "remoteControlEnabled")
                    if newValue {
                        server.start()
                    } else {
                        server.stop()
                    }
                }

            if isEnabled {
                Divider()

                HStack {
                    Circle()
                        .fill(server.isRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(server.isRunning ? "Server running" : "Server stopped")
                        .font(.caption)
                    Spacer()
                    if server.connectedClientCount > 0 {
                        Text("\(server.connectedClientCount) connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if showingNewPairingCode {
                    qrCodeSection
                } else {
                    Button("Generate Pairing Code") {
                        let token = PairingManager.generateToken()
                        pendingPayload = PairingManager.QRPayload(
                            token: token,
                            certPin: "sha256/placeholder",
                            port: 8443
                        )
                        showingNewPairingCode = true
                    }
                }

                if !server.pairingManager.pairedDevices.isEmpty {
                    Divider()
                    Text("Paired Devices")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(server.pairingManager.pairedDevices) { device in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.name)
                                    .font(.caption)
                                Text(device.pairedAt, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Unpair") {
                                server.pairingManager.removePairedDevice(token: device.token)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(width: 300)
    }

    @ViewBuilder
    private var qrCodeSection: some View {
        VStack(spacing: 8) {
            Text("Scan with ClaudeBlobs Remote on your iPhone")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let payload = pendingPayload,
               let ciImage = PairingManager.generateQRCode(payload: payload) {
                let transform = CGAffineTransform(scaleX: 8, y: 8)
                let scaled = ciImage.transformed(by: transform)
                let rep = NSCIImageRep(ciImage: scaled)
                let nsImage = NSImage(size: rep.size)

                Image(nsImage: {
                    nsImage.addRepresentation(rep)
                    return nsImage
                }())
                .interpolation(.none)
                .resizable()
                .frame(width: 200, height: 200)
            }

            Button("Done") {
                if let payload = pendingPayload {
                    server.pairingManager.addPairedDevice(name: "iPhone", token: payload.token)
                }
                pendingPayload = nil
                showingNewPairingCode = false
            }
        }
    }
}
