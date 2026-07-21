import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.isReady {
                TabView {
                    RecordingView()
                        .tabItem { Label("Record", systemImage: "location.fill") }
                    OfflineAreasView()
                        .tabItem { Label("Offline", systemImage: "square.and.arrow.down") }
                    RecordingsView()
                        .tabItem { Label("Saved", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                    PairingView()
                        .tabItem { Label("Server", systemImage: "laptopcomputer.and.iphone") }
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
    }
}
