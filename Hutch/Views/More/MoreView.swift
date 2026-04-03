import SwiftUI

struct MoreView: View {
    @Environment(AppState.self) private var appState

    private let unsupportedLinks: [(title: String, url: URL)] = [
        ("chat.sr.ht", URL(string: "https://chat.sr.ht")!),
        ("srht.site", URL(string: "https://srht.site")!)
    ]

    @State private var showAccountSwitcher = false

    var body: some View {
        List {
            Section {
                NavigationLink(value: MoreRoute.lookup) {
                    Label("Look Up", systemImage: "magnifyingglass")
                }

                NavigationLink(value: MoreRoute.lists) {
                    Label("Mailing Lists", systemImage: "list.bullet.rectangle")
                }
                
                NavigationLink(value: MoreRoute.manPageBrowser) {
                    Label("Man Pages", systemImage: "book")
                }

                NavigationLink(value: MoreRoute.pastes) {
                    Label("Pastes", systemImage: "doc.on.clipboard")
                }

                NavigationLink(value: MoreRoute.settings) {
                    Label("Settings", systemImage: "gear")
                }
            }

            Section {
                ForEach(unsupportedLinks, id: \.title) { item in
                    Link(destination: item.url) {
                        Label(item.title, systemImage: "safari")
                    }
                }
            } header: {
                Text("External Links")
            } footer: {
                Text("These SourceHut services are not supported in-app, as the SourceHut API does not support them, and will open in your browser.")
            }
        }
        .navigationTitle("More")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAccountSwitcher = true
                } label: {
                    Image(systemName: "person.crop.circle")
                }
            }
        }
        .sheet(isPresented: $showAccountSwitcher) {
            AccountSwitcherView()
        }
    }
}
