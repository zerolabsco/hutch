import SwiftUI
import os

@main
struct HutchApp: App {
    private let deepLinkLogger = Logger(subsystem: "net.cleberg.Hutch", category: "DeepLink")
    @State private var appState = AppState()
    @State private var networkMonitor = NetworkMonitor()
    @AppStorage(AppStorageKeys.appTheme, store: .standard) private var appTheme: AppTheme = .system
    @AppStorage(AppStorageKeys.displayDensity, store: .standard) private var displayDensity: DisplayDensity = .standard

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(networkMonitor)
                .environment(\.displayDensity, displayDensity)
                .environment(\.isAMOLEDTheme, appTheme == .amoled)
                .environment(\.defaultMinListRowHeight, displayDensity == .compact ? 36 : 44)
                .background(appTheme == .amoled ? Color.black : Color.clear)
                .preferredColorScheme(appTheme.colorScheme)
                .onOpenURL { url in
                    deepLinkLogger.info("Received URL: \(url.absoluteString, privacy: .public)")
                    if let link = DeepLink(url: url) {
                        deepLinkLogger.info("Parsed deep link: \(String(describing: link), privacy: .public)")
                        appState.pendingDeepLink = link
                    } else {
                        deepLinkLogger.error("Rejected URL: \(url.absoluteString, privacy: .public)")
                    }
                }
                .onChange(of: HutchIntentNavigator.shared.pendingRoute) { _, route in
                    guard let route else { return }
                    HutchIntentNavigator.shared.pendingRoute = nil
                    appState.open(route)
                }
        }
    }
}
