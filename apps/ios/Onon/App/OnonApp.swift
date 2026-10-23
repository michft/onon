import SwiftUI

@main
struct OnonApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task { await model.prepare() }
                .onOpenURL { url in
                    model.receivePairing(payload: url.absoluteString)
                }
        }
    }
}
