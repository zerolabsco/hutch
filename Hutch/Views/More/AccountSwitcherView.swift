import SwiftUI

struct AccountSwitcherView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var showAddAccount = false
    @State private var isSwitching = false
    @State private var switchError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(appState.accounts) { account in
                        Button {
                            guard account.id != appState.activeAccountID else { return }
                            switchTo(account)
                        } label: {
                            HStack {
                                Text("~\(account.username)")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if account.id == appState.activeAccountID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .disabled(isSwitching)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let account = appState.accounts[index]
                            Task { await appState.removeAccount(id: account.id) }
                        }
                    }
                }

                Section {
                    Button {
                        showAddAccount = true
                    } label: {
                        Label("Add Account", systemImage: "plus.circle")
                    }
                    .disabled(isSwitching)
                }
            }
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if isSwitching {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        ProgressView("Switching…")
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .alert("Switch Failed", isPresented: Binding(
                get: { switchError != nil },
                set: { if !$0 { switchError = nil } }
            )) {
                Button("OK") { switchError = nil }
            } message: {
                Text(switchError ?? "")
            }
            .sheet(isPresented: $showAddAccount) {
                AddAccountView()
            }
        }
    }

    private func switchTo(_ account: AccountEntry) {
        isSwitching = true
        Task {
            do {
                try await appState.switchAccount(to: account.id)
                dismiss()
            } catch {
                switchError = error.localizedDescription
            }
            isSwitching = false
        }
    }
}
