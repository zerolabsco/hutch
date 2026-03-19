import SwiftUI

struct MoreView: View {
    private let unsupportedLinks: [(title: String, url: URL)] = [
        ("chat.sr.ht", URL(string: "https://chat.sr.ht")!),
        ("man.sr.ht", URL(string: "https://man.sr.ht")!),
        ("srht.site", URL(string: "https://srht.site")!)
    ]

    var body: some View {
        List {
            Section {
                NavigationLink(value: MoreRoute.lists) {
                    Label("Lists", systemImage: "list.bullet.rectangle")
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
                Text("These SourceHut services are not supported in-app and open in your browser.")
            }
        }
        .navigationTitle("More")
    }
}
