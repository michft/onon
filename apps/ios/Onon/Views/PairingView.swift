import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            List {
                Section("Local server") {
                    if model.isPaired {
                        Label("Paired", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                        if let url = ServerConfiguration.serverURL { Text(url.absoluteString).font(.caption) }
                        Button("Refresh map details") { Task { await model.loadMapManifest() } }
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
                    Label("Download a detailed area before leaving Wi-Fi", systemImage: "map")
                }
            }
            .navigationTitle("Server")
            .sheet(isPresented: $showScanner) {
                NavigationStack {
                    QRCodeScannerView { payload in
                        showScanner = false
                        Task { await model.completePairing(payload: payload) }
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
