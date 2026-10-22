import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.isReady {
                TabView {
                    RecordingView()
                        .tabItem { Label("Record", systemImage: "location.fill") }
                    RecordingsView()
                        .tabItem { Label("Saved", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                }
            } else {
                ProgressView("Opening recordings…")
            }
        }
        .alert("Onon", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK") { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .sheet(isPresented: Binding(
            get: { model.pendingPairing != nil },
            set: { if !$0 { model.cancelPairing() } }
        )) {
            if let candidate = model.pendingPairing {
                VStack(spacing: 20) {
                    Text(ServerConfiguration.serverURL == nil ? "Pair with this laptop?" : "Replace paired laptop?")
                        .font(.title2.bold())
                    Text(candidate.serverURL.absoluteString)
                        .font(.headline)
                        .textSelection(.enabled)
                    Text("Completed recordings, including precise GPS locations, will upload automatically to this laptop after approval. Only approve a laptop you trust.")
                    Button("Pair and enable uploads") { Task { await model.confirmPairing() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isSyncing || model.isPairing)
                    Button("Cancel", role: .cancel) { model.cancelPairing() }
                }
                .padding()
                .presentationDetents([.medium, .large])
            }
        }
    }
}
