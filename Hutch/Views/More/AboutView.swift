import StoreKit
import SwiftUI

struct AboutView: View {
    @Environment(AppState.self) private var appState
    private let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "Hutch"
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        ?? "Unknown"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        ?? "Unknown"
    @State private var developerRevealCount = 0
    @State private var storeViewModel = TipStoreViewModel()

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
                .themedRow()

                LabeledContent("Version", value: version)
                    .onTapGesture {
                        developerRevealCount = min(developerRevealCount + 1, 5)
                    }
                    .themedRow()
                LabeledContent("Build", value: build)
                    .onTapGesture {
                        developerRevealCount = min(developerRevealCount + 1, 5)
                    }
                    .themedRow()
            } footer: {
                Text(developerRevealFooterText)
            }

            Section("Links") {
                Link(destination: URL(string: "https://sr.ht")!) {
                    SwiftUI.Label("SourceHut", systemImage: "link")
                }
                .themedRow()
                Link(destination: URL(string: "https://man.sr.ht")!) {
                    SwiftUI.Label("SourceHut Manuals", systemImage: "book")
                }
                .themedRow()
                Link(destination: URL(string: "https://sr.ht/~ccleberg/Hutch")!) {
                    SwiftUI.Label("Project Repository", systemImage: "folder")
                }
                .themedRow()
            }

            Section("Support") {
                Link(destination: URL(string: "mailto:hello@cleberg.net")!) {
                    SwiftUI.Label("Email Support", systemImage: "envelope")
                }
                .themedRow()
            }

            Section("Privacy") {
                Text("Hutch uses your SourceHut personal access token to make requests on your behalf. The token is stored locally in the iOS keychain.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .themedRow()

                Link(destination: URL(string: "https://zerolabs.sh/hutch/privacy-policy/")!) {
                    SwiftUI.Label("Privacy Policy", systemImage: "hand.raised")
                }
                .themedRow()
            }

            Section("Acknowledgements") {
                Text("Built for SourceHut users who want quick access to repositories, builds, and tickets on iOS.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .themedRow()
            }

            Section {
                if storeViewModel.isLoading {
                    ProgressView()
                        .themedRow()
                } else if storeViewModel.products.isEmpty {
                    Text("Tips unavailable")
                        .foregroundStyle(.secondary)
                        .themedRow()
                } else {
                    ForEach(storeViewModel.products, id: \.id) { product in
                        Button {
                            Task {
                                await storeViewModel.purchase(product)
                            }
                        } label: {
                            HStack {
                                Text(product.displayName)
                                Spacer()
                                Text(product.displayPrice)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .themedRow()
                    }
                }
            } header: {
                Text("Support Development")
            } footer: {
                Text("Tips help cover the costs of development and App Store distribution. They are one-time purchases and do not unlock any features.")
            }

            if developerToolsVisible {
                Section {
                    Toggle("Debug Mode", isOn: Binding(
                        get: { appState.isDebugModeEnabled },
                        set: { appState.isDebugModeEnabled = $0 }
                    ))
                    .themedRow()
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
        .task {
            await storeViewModel.loadProducts()
        }
    }
}
