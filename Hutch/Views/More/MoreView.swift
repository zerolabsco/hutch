import SwiftUI

struct MoreView: View {
    @Environment(AppState.self) private var appState

    private let unsupportedLinks: [(title: String, url: URL)] = [
        ("chat.sr.ht", SRHTWebURL.chat)
    ]

    @State private var viewModel: MoreViewModel?
    @State private var showAccountSwitcher = false

    var body: some View {
        List {
            Section("Search") {
                NavigationLink(value: MoreRoute.lookup) {
                    Label("Look Up", systemImage: "magnifyingglass")
                }
                .themedRow()
            }

            Section("Other Services") {
                NavigationLink(value: MoreRoute.projects) {
                    Label("Projects", systemImage: "square.stack.3d.up")
                }
                .themedRow()

                NavigationLink(value: MoreRoute.lists) {
                    Label("Mailing Lists", systemImage: "list.bullet.rectangle")
                }
                .themedRow()

                NavigationLink(value: MoreRoute.manPageBrowser) {
                    Label("Man Pages", systemImage: "book")
                }
                .themedRow()

                NavigationLink(value: MoreRoute.pastes) {
                    Label("Pastes", systemImage: "doc.on.clipboard")
                }
                .themedRow()

                NavigationLink(value: MoreRoute.systemStatus) {
                    SystemStatusSummaryRow(
                        snapshot: viewModel?.systemStatusSnapshot,
                        isLoading: viewModel?.isLoadingSystemStatus ?? true,
                        errorMessage: viewModel?.systemStatusErrorMessage,
                        isShowingStaleData: viewModel?.isShowingStaleSystemStatus ?? false
                    )
                }
                .themedRow()
            }

            Section("Meta") {
                NavigationLink(value: MoreRoute.profile) {
                    Label("Profile", systemImage: "person.text.rectangle")
                }
                .themedRow()

                NavigationLink(value: MoreRoute.settings) {
                    Label("Settings", systemImage: "gear")
                }
                .themedRow()
            }

            Section {
                ForEach(unsupportedLinks, id: \.title) { item in
                    Link(destination: item.url) {
                        Label(item.title, systemImage: "safari")
                    }
                }
                .themedRow()
            } header: {
                Text("External Links")
            } footer: {
                Text("These SourceHut services are not supported in-app, as the SourceHut API does not support them, and will open in your browser.")
            }
        }
        .themedList()
        .navigationTitle("More")
        .refreshable {
            await ensureViewModel().loadSystemStatus(forceRefresh: true)
        }
        .task {
            await ensureViewModel().loadIfNeeded()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAccountSwitcher = true
                } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showAccountSwitcher) {
            AccountSwitcherView()
        }
    }

    @MainActor
    private func ensureViewModel() -> MoreViewModel {
        if let viewModel {
            return viewModel
        }

        let newViewModel = MoreViewModel(repository: appState.systemStatusRepository)
        viewModel = newViewModel
        return newViewModel
    }
}
