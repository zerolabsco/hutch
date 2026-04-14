import SwiftUI

struct AddAccountView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Personal Access Token", text: $token)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .themedRow()
                } footer: {
                    Text("Generate a token at meta.sr.ht → OAuth2 clients.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .themedRow()
                    }
                }
            }
            .themedList()
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isConnecting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { connect() }
                        .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)
                }
            }
            .interactiveDismissDisabled(isConnecting)
        }
    }

    private func connect() {
        isConnecting = true
        errorMessage = nil
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                try await appState.addAccount(token: trimmed)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }
}
