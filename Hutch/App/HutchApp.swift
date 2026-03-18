import SwiftUI

@main
struct HutchApp: App {
    @State private var appState = AppState()
    @State private var networkMonitor = NetworkMonitor()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(networkMonitor)
                .onOpenURL { url in
                    if let link = DeepLink(url: url) {
                        appState.pendingDeepLink = link
                    }
                }
        }
    }
}
