import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showScanner = false
    @State private var scannedPayload: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Local server") {
                    if model.isPaired {
                        Label(model.serverReachable ? "Connected" : "Paired — server unreachable", systemImage: model.serverReachable ? "checkmark.circle.fill" : "wifi.slash")
                            .foregroundStyle(model.serverReachable ? .green : .orange)
                        if let url = ServerConfiguration.serverURL { Text(url.absoluteString).font(.caption) }
                        Button("Check server") { Task { await model.loadMapManifest(showError: true) } }
                        Button("Sync now") { Task { await model.syncNow() } }.disabled(model.isSyncing)
                        Button("Unpair device", role: .destructive) { model.unpair() }
                    } else {
                        Text("On the laptop, open the pairing page and show its one-time QR code.")
                        Button("Scan pairing QR") { showScanner = true }
                    }
                }
                Section("Field use") {
                    Label("Raw recordings stay on this iPhone after sync", systemImage: "internaldrive")
                    Label("Always location access enables lock-screen capture", systemImage: "lock.iphone")
                    Label("Bundled Sydney map works offline", systemImage: "map")
                }
            }
            .navigationTitle("Server")
            .sheet(isPresented: $showScanner, onDismiss: {
                guard let payload = scannedPayload else { return }
                scannedPayload = nil
                model.receivePairing(payload: payload)
            }) {
                NavigationStack {
                    QRCodeScannerView { payload in
                        scannedPayload = payload
                        showScanner = false
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Scan pairing code")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Cancel") { showScanner = false } }
                }
            }
        }
    }
}
