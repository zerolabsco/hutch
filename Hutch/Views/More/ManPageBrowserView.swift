import SwiftUI

/// Entry point for the man.sr.ht browser in the More tab.
/// Shows a pre-populated list of official sr.ht man pages.
struct ManPageBrowserView: View {
    private let officialDocs: [(title: String, url: URL)] = [
        ("sr.ht", URL(string: "https://man.sr.ht/sr.ht/")!),
        ("hub.sr.ht", URL(string: "https://man.sr.ht/hub.sr.ht/")!),
        ("git.sr.ht", URL(string: "https://man.sr.ht/git.sr.ht/")!),
        ("hg.sr.ht", URL(string: "https://man.sr.ht/hg.sr.ht/")!),
        ("lists.sr.ht", URL(string: "https://man.sr.ht/lists.sr.ht/")!),
        ("todo.sr.ht", URL(string: "https://man.sr.ht/todo.sr.ht/")!),
        ("builds.sr.ht", URL(string: "https://man.sr.ht/builds.sr.ht/")!),
        ("paste.sr.ht", URL(string: "https://man.sr.ht/paste.sr.ht/")!),
        ("man.sr.ht", URL(string: "https://man.sr.ht/man.sr.ht/")!),
        ("meta.sr.ht", URL(string: "https://man.sr.ht/meta.sr.ht/")!),
        ("srht.site", URL(string: "https://srht.site/")!)
    ]

    var body: some View {
        List {
            Section("Official Man Pages") {
                ForEach(officialDocs, id: \.title) { doc in
                    NavigationLink(value: MoreRoute.manPage(doc.url)) {
                        Text(doc.title)
                    }
                }
                .themedRow()
            }
        }
        .themedList()
        .navigationTitle("Man Pages")
        .navigationBarTitleDisplayMode(.inline)
    }
}
