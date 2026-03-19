import SwiftUI

struct ProjectDetailView: View {
    let project: Project
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            headerSection
            repositoriesSection
            trackersSection
            mailingListsSection
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(project.name)
                    .font(.headline)

                if let description = project.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let website = project.website, let url = URL(string: website) {
                    Link(destination: url) {
                        Label(website, systemImage: "link")
                            .font(.subheadline)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var repositoriesSection: some View {
        if !project.sources.isEmpty {
            Section("Repositories") {
                ForEach(project.sources) { source in
                    Button {
                        Task {
                            try? await appState.openProjectSource(source)
                            dismiss()
                        }
                    } label: {
                        ProjectResourceRow(
                            title: source.name,
                            subtitle: source.owner.canonicalName,
                            detail: source.description
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var trackersSection: some View {
        if !project.trackers.isEmpty {
            Section("Trackers") {
                ForEach(project.trackers) { tracker in
                    Button {
                        Task {
                            try? await appState.openProjectTracker(tracker)
                            dismiss()
                        }
                    } label: {
                        ProjectResourceRow(
                            title: tracker.name,
                            subtitle: tracker.owner.canonicalName,
                            detail: tracker.description
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var mailingListsSection: some View {
        if !project.mailingLists.isEmpty {
            Section("Mailing Lists") {
                ForEach(project.mailingLists) { mailingList in
                    Button {
                        appState.openMailingList(mailingList.inboxReference)
                        dismiss()
                    } label: {
                        ProjectResourceRow(
                            title: mailingList.name,
                            subtitle: mailingList.owner.canonicalName,
                            detail: mailingList.description
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ProjectResourceRow: View {
    let title: String
    let subtitle: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.medium))

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
