import SwiftUI

struct AccountSwitcherView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var showAddAccount = false
    @State private var isSwitching = false
    @State private var switchError: String?
    @State private var pendingRemoval: AccountEntry?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(appState.accounts) { account in
                        let isActive = account.id == appState.activeAccountID
                        Button {
                            guard !isActive else { return }
                            switchTo(account)
                        } label: {
                            HStack(spacing: 12) {
                                if isActive {
                                    Image(systemName: "person.crop.circle.fill")
                                        .foregroundStyle(.tint)
                                } else {
                                    Image(systemName: "person.crop.circle")
                                        .foregroundStyle(.secondary)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("~\(account.username)")
                                        .foregroundStyle(.primary)
                                    Text(isActive ? "Active Account" : "Tap to switch")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isActive {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .disabled(isSwitching)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            pendingRemoval = appState.accounts[index]
                        }
                    }
                    .themedRow()
                }

                Section {
                    Button {
                        showAddAccount = true
                    } label: {
                        Label("Add Account", systemImage: "plus.circle")
                    }
                    .disabled(isSwitching)
                    .themedRow()
                }
            }
            .themedList()
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
            .alert(
                "Remove Account?",
                isPresented: Binding(
                    get: { pendingRemoval != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingRemoval = nil
                        }
                    }
                )
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) {
                    guard let pendingRemoval else { return }
                    Task { await appState.removeAccount(id: pendingRemoval.id) }
                    self.pendingRemoval = nil
                }
            } message: {
                if let pendingRemoval {
                    Text("~\(pendingRemoval.username) and its isolated local cache will be removed from this device.")
                }
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
