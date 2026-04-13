import SwiftUI

struct RecentSearchSuggestions: View {
    let title: String
    let entries: [ScopedSearchHistoryEntry]
    let onSelect: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        if !entries.isEmpty {
            Section(title) {
                ForEach(entries) { entry in
                    Button {
                        onSelect(entry.query)
                    } label: {
                        Label(entry.query, systemImage: "clock.arrow.circlepath")
                    }
                }

                Button("Clear Recent Searches", role: .destructive) {
                    onClear()
                }
            }
        }
    }
}
