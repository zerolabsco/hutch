import SwiftUI

struct UserTrackersView: View {
    let viewModel: UserProfileViewModel

    var body: some View {
        List {
            ForEach(viewModel.trackers) { tracker in
                NavigationLink {
                    TicketListView(tracker: tracker)
                } label: {
                    UserProfileTrackerRowView(tracker: tracker)
                }
            }
            .themedRow()
        }
        .themedList()
        .listStyle(.plain)
        .navigationTitle("Trackers")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isLoadingTrackers && viewModel.trackers.isEmpty {
                SRHTLoadingStateView(message: "Loading trackers…")
            }
        }
        .refreshable {
            await viewModel.loadTrackers()
        }
    }
}
