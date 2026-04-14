import SwiftUI

/// Token entry screen shown when the user is not authenticated.
struct TokenEntryView: View {
    private let createAccountURL = URL(string: "https://meta.sr.ht/register")!
    private let personalAccessTokensURL = URL(string: "https://meta.sr.ht/oauth/personal-access-tokens")!

    @Environment(AppState.self) private var appState
    @State private var token = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter your SourceHut personal access token to connect.")
                        .themedRow()
                } header: {
                    Text("Welcome to Hutch")
                } footer: {
                    Text("Hutch stores your SourceHut personal access token securely in the iOS keychain.")
                }

                Section {
                    SecureField("Personal Access Token", text: $token)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .disabled(isConnecting)
                        .themedRow()
                } header: {
                    Text("Token")
                }

                if let errorMessage {
                    Section {
                        Label {
                            Text(errorMessage)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                        .foregroundStyle(.red)
                        .themedRow()
                    }
                }

                Section {
                    Button {
                        connect()
                    } label: {
                        HStack {
                            Text("Connect")
                            if isConnecting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(tokenTrimmed.isEmpty || isConnecting)
                    .themedRow()
                }

                Section {
                    Link(destination: createAccountURL) {
                        Label("Create SourceHut account", systemImage: "person.badge.plus")
                    }
                    .themedRow()

                    Link(destination: personalAccessTokensURL) {
                        Label("Create Personal Access Token", systemImage: "key")
                    }
                    .themedRow()
                } header: {
                    Text("Need an account?")
                } footer: {
                    Text("These links open SourceHut in your browser. After signing up, create a Personal Access Token there and paste it here.")
                }
            }
            .themedList()
            .navigationTitle("Hutch")
        }
    }

    private var tokenTrimmed: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func connect() {
        errorMessage = nil
        isConnecting = true
        Task {
            do {
                try await appState.connect(with: tokenTrimmed)
            } catch {
                errorMessage = error.userFacingMessage
            }
            isConnecting = false
        }
    }
}
