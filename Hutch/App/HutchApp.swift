import SwiftUI

@main
struct HutchApp: App {
    @State private var appState = AppState()
    @State private var networkMonitor = NetworkMonitor()
    @AppStorage(AppStorageKeys.appTheme) private var appTheme: AppTheme = .system
    @AppStorage(AppStorageKeys.displayDensity) private var displayDensity: DisplayDensity = .standard

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(networkMonitor)
                .environment(\.displayDensity, displayDensity)
                .environment(\.defaultMinListRowHeight, displayDensity == .compact ? 36 : 44)
                .preferredColorScheme(appTheme.colorScheme)
                .onOpenURL { url in
                    if let link = DeepLink(url: url) {
                        appState.pendingDeepLink = link
                    }
                }
                .onChange(of: HutchIntentNavigator.shared.pendingDestination) { _, destination in
                    guard let destination else { return }
                    HutchIntentNavigator.shared.pendingDestination = nil
                    let link: DeepLink
                    switch destination {
                    case .home: link = .home
                    case .inbox: link = .home
                    case .builds: link = .buildsTab
                    case .repositories: link = .repositoriesTab
                    case .trackers: link = .trackersTab
                    case .systemStatus: link = .systemStatus
                    case .lookup: link = .lookup
                    }
                    appState.pendingDeepLink = link
                }
        }
    }
}
