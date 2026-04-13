import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(AppStorageKeys.appTheme, store: .standard) private var appTheme: AppTheme = .system
    @AppStorage(AppStorageKeys.displayDensity, store: .standard) private var displayDensity: DisplayDensity = .standard
    @AppStorage(AppStorageKeys.swipeActionsEnabled, store: .standard) private var swipeActionsEnabled = true
    @AppStorage(AppStorageKeys.contributionGraphsEnabled, store: .standard) private var contributionGraphsEnabled = true
    @State private var pendingDestructiveAction: SettingsDestructiveAction?
    @State private var showAccountSwitcher = false

    var body: some View {
        Form {
            appearanceSection()
            behaviorSection()
            authenticationSection()
            aboutSection()
        }
        .themedList()
        .navigationTitle("Settings")
        .sheet(isPresented: $showAccountSwitcher) {
            AccountSwitcherView()
        }
        .alert(
            pendingDestructiveAction?.title ?? "",
            isPresented: Binding(
                get: { pendingDestructiveAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDestructiveAction = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {}
            Button(pendingDestructiveAction?.confirmationLabel ?? "Confirm", role: .destructive) {
                guard let action = pendingDestructiveAction else { return }
                pendingDestructiveAction = nil
                Task {
                    switch action {
                    case .resetAppData:
                        await appState.resetAppData()
                    case .signOut:
                        await appState.signOut()
                    }
                }
            }
        } message: {
            if let pendingDestructiveAction {
                Text(pendingDestructiveAction.message)
            }
        }
    }

    @ViewBuilder
    private func appearanceSection() -> some View {
        Section {
            Picker("Theme", selection: $appTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.label).tag(theme)
                }
            }
            Picker("Density", selection: $displayDensity) {
                ForEach(DisplayDensity.allCases) { density in
                    Text(density.label).tag(density)
                }
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Compact density reduces spacing throughout the app.")
        }
    }

    @ViewBuilder
    private func behaviorSection() -> some View {
        Section {
            Toggle("Swipe actions", isOn: $swipeActionsEnabled)
            Toggle("Contribution graphs", isOn: $contributionGraphsEnabled)
                .onChange(of: contributionGraphsEnabled) { _, newValue in
                    ContributionWidgetContextStore.setEnabled(newValue)
                }
        } header: {
            Text("Behavior")
        } footer: {
            Text("When enabled, swipe list rows to quickly take actions like resolving tickets, cancelling builds, and deleting pastes. Contribution graphs controls whether SourceHut activity heatmaps appear in lookup profiles.")
        }
    }

    @ViewBuilder
    private func authenticationSection() -> some View {
        Section {
            HStack {
                Image(systemName: "key.fill")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.currentUser?.canonicalName ?? "No active account")
                    Text("\(appState.accounts.count) saved account\(appState.accounts.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }

            Button {
                showAccountSwitcher = true
            } label: {
                Label("Manage Accounts", systemImage: "person.2")
            }

            HStack {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.secondary)
                Text("Tokens are stored separately per account in the iOS keychain")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }

            Button("Reset App Data", role: .destructive) {
                pendingDestructiveAction = .resetAppData
            }

            Button("Sign Out", role: .destructive) {
                pendingDestructiveAction = .signOut
            }
        } header: {
            Text("Authentication")
        } footer: {
            Text("Account switching keeps local caches and saved state isolated per account. Sign Out removes all saved accounts from this device. Reset App Data also clears local settings, cached responses, cookies, and embedded web data.")
        }
    }

    @ViewBuilder
    private func aboutSection() -> some View {
        Section("App") {
            NavigationLink {
                AboutView()
            } label: {
                SwiftUI.Label("About Hutch", systemImage: "info.circle")
            }
        }
    }
}

func settingsBioAttributedString(_ markdown: String) -> AttributedString {
    profileBioAttributedString(markdown)
}

private enum SettingsDestructiveAction {
    case resetAppData
    case signOut

    var title: String {
        switch self {
        case .resetAppData:
            "Reset App Data?"
        case .signOut:
            "Sign Out?"
        }
    }

    var confirmationLabel: String {
        switch self {
        case .resetAppData:
            "Reset App Data"
        case .signOut:
            "Sign Out"
        }
    }

    var message: String {
        switch self {
        case .resetAppData:
            "This signs you out and removes saved token data, local settings, cached responses, cookies, and embedded web content on this device."
        case .signOut:
            "This signs you out of Hutch and clears saved authentication state on this device."
        }
    }
}

private struct AboutView: View {
    @Environment(AppState.self) private var appState
    private let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "Hutch"
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        ?? "Unknown"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        ?? "Unknown"
    @State private var developerRevealCount = 0

    private var developerToolsVisible: Bool {
        appState.isDebugModeEnabled || developerRevealCount >= 5
    }

    private var developerRevealFooterText: String {
        developerRevealCount >= 5
            ? "Debug toggle unlocked. Scroll down to Developer to enable it."
            : "Tap the build number 5 times to reveal the debug toggle."
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appName)
                        .font(.title2.weight(.semibold))
                    Text("A native SourceHut client for iOS.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                LabeledContent("Version", value: version)
                    .onTapGesture {
                        developerRevealCount = min(developerRevealCount + 1, 5)
                    }
                LabeledContent("Build", value: build)
                    .onTapGesture {
                        developerRevealCount = min(developerRevealCount + 1, 5)
                    }
            } footer: {
                Text(developerRevealFooterText)
            }

            Section("Links") {
                Link(destination: URL(string: "https://sr.ht")!) {
                    SwiftUI.Label("SourceHut", systemImage: "link")
                }
                Link(destination: URL(string: "https://man.sr.ht")!) {
                    SwiftUI.Label("SourceHut Manuals", systemImage: "book")
                }
                Link(destination: URL(string: "https://sr.ht/~ccleberg/Hutch")!) {
                    SwiftUI.Label("Project Repository", systemImage: "folder")
                }
            }

            Section("Support") {
                Link(destination: URL(string: "mailto:hello@cleberg.net")!) {
                    SwiftUI.Label("Email Support", systemImage: "envelope")
                }
            }

            Section("Privacy") {
                Text("Hutch uses your SourceHut personal access token to make requests on your behalf. The token is stored locally in the iOS keychain.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Link(destination: URL(string: "https://zerolabs.sh/hutch/privacy-policy/")!) {
                    SwiftUI.Label("Privacy Policy", systemImage: "hand.raised")
                }
            }

            Section("Acknowledgements") {
                Text("Built for SourceHut users who want quick access to repositories, builds, and tickets on iOS.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if developerToolsVisible {
                Section {
                    Toggle("Debug Mode", isOn: Binding(
                        get: { appState.isDebugModeEnabled },
                        set: { appState.isDebugModeEnabled = $0 }
                    ))
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Shows raw API payloads and diagnostic details on builds and tickets screens. This stays hidden until explicitly enabled.")
                }
            }
        }
        .themedList()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
