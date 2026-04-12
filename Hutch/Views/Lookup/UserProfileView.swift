import SwiftUI

struct UserProfileView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(AppStorageKeys.contributionGraphsEnabled) private var contributionGraphsEnabled = true

    let user: User
    @State private var profileViewModel: UserProfileViewModel?

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    var body: some View {
        List {
            if let avatarURL = user.avatar.flatMap(URL.init(string:)) {
                Section {
                    HStack {
                        Spacer()
                        AsyncImage(url: avatarURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure, .empty:
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.secondary)
                                    .padding(20)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                LabeledContent("Username", value: user.username)
                LabeledContent("Canonical Name", value: user.canonicalName)
                if let userType = user.userType {
                    LabeledContent("User Type", value: userType)
                }
                if let pronouns = user.pronouns {
                    LabeledContent("Pronouns", value: pronouns)
                }
                if let suspensionNotice = user.suspensionNotice {
                    LabeledContent("Suspension Notice", value: suspensionNotice)
                }
            }

            Section {
                LabeledContent("Email", value: user.email)
                if let urlString = user.url, let url = URL(string: urlString) {
                    LabeledContent("URL") {
                        Link(urlString, destination: url)
                    }
                }
                if let location = user.location {
                    LabeledContent("Location", value: location)
                }
            }

            if let bio = user.bio {
                Section("Bio") {
                    Text(bio)
                }
            }

            if user.created != nil || user.updated != nil {
                Section {
                    if let created = user.created {
                        LabeledContent("Joined", value: formattedTimestamp(created))
                    }
                    if let updated = user.updated {
                        LabeledContent("Updated", value: formattedTimestamp(updated))
                    }
                }
            }

            if let viewModel = profileViewModel {
                if contributionGraphsEnabled {
                    Section {
                        ContributionProfileCard(
                            actor: viewModel.actor,
                            weeks: viewModel.contributionCalendar.map {
                                ContributionCalendarLayout.weekColumns(from: $0.days)
                            } ?? [],
                            stats: viewModel.contributionStats,
                            isLoading: viewModel.isLoadingContributions,
                            error: viewModel.contributionsError ?? viewModel.contributionStatusText,
                            isIndexedButEmpty: viewModel.isContributionActivityIndexedButEmpty
                        )
                    }
                }

                Section {
                    if viewModel.isLoadingRepositories && viewModel.repositories.isEmpty {
                        ProgressView()
                    } else if viewModel.repositories.isEmpty {
                        Text("No public repositories.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.repositories.prefix(4)) { repo in
                            NavigationLink {
                                RepositoryDetailView(repository: repo)
                            } label: {
                                RepositoryRowView(repository: repo, buildStatus: .none)
                            }
                        }
                        if viewModel.repositories.count > 4 {
                            NavigationLink("See All") {
                                UserRepositoriesView(viewModel: viewModel)
                            }
                        }
                    }
                } header: {
                    Text("Repositories")
                }

                Section {
                    if viewModel.isLoadingTrackers && viewModel.trackers.isEmpty {
                        ProgressView()
                    } else if viewModel.trackers.isEmpty {
                        Text("No public trackers.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.trackers.prefix(4)) { tracker in
                            NavigationLink {
                                TicketListView(tracker: tracker)
                            } label: {
                                UserProfileTrackerRowView(tracker: tracker)
                            }
                        }
                        if viewModel.trackers.count > 4 {
                            NavigationLink("See All") {
                                UserTrackersView(viewModel: viewModel)
                            }
                        }
                    }
                } header: {
                    Text("Trackers")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(user.canonicalName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: user.canonicalName) {
            let owner = user.canonicalName.hasPrefix("~")
                ? String(user.canonicalName.dropFirst())
                : user.canonicalName
            let actor = user.canonicalName.hasPrefix("~") ? user.canonicalName : "~\(user.canonicalName)"

            let vm: UserProfileViewModel
            if let existingViewModel = profileViewModel,
               existingViewModel.actor == actor,
               existingViewModel.ownerUsername == owner {
                vm = existingViewModel
            } else {
                let newViewModel = UserProfileViewModel(
                    ownerUsername: owner,
                    actor: actor,
                    client: appState.client,
                    statsService: HutchStatsService(
                        configuration: appState.configuration,
                        currentActor: appState.currentUser?.canonicalName
                    )
                )
                profileViewModel = newViewModel
                vm = newViewModel
            }

            async let repos: () = vm.loadRepositories()
            async let trackers: () = vm.loadTrackers()
            if contributionGraphsEnabled {
                async let contributions: () = vm.loadContributions()
                _ = await (repos, trackers, contributions)
            } else {
                _ = await (repos, trackers)
            }
        }
    }

    private func formattedTimestamp(_ value: String) -> String {
        guard let date = Self.iso8601Formatter.date(from: value) else {
            return value
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct UserProfileTrackerRowView: View {
    let tracker: TrackerSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tracker.name)
                    .font(.subheadline.weight(.medium))

                Spacer()

                VisibilityBadge(visibility: tracker.visibility)
            }

            if let owner = tracker.owner.canonicalName.split(separator: "~").last {
                Text("~\(owner)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let description = tracker.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(tracker.updated.relativeDescription)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
