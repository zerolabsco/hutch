import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(AppStorageKeys.appTheme) private var appTheme: AppTheme = .system
    @AppStorage(AppStorageKeys.displayDensity) private var displayDensity: DisplayDensity = .standard
    @AppStorage(AppStorageKeys.swipeActionsEnabled) private var swipeActionsEnabled = true
    @AppStorage(AppStorageKeys.contributionGraphsEnabled) private var contributionGraphsEnabled = true
    @State private var pendingDestructiveAction: SettingsDestructiveAction?

    var body: some View {
        Form {
            appearanceSection()
            behaviorSection()
            authenticationSection()
            aboutSection()
        }
        .themedList()
        .navigationTitle("Settings")
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
                Text("Personal access token in use")
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
            Text("Hutch stores your SourceHut token in the iOS keychain. Reset App Data removes saved token data, local settings, cached responses, cookies, and embedded web data on this device.")
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
    private let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "Hutch"
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        ?? "Unknown"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        ?? "Unknown"

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
                LabeledContent("Build", value: build)
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
        }
        .themedList()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
