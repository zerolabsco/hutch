import SwiftUI

struct ProjectDetailView: View {
    let project: Project

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var detailProject: Project?
    @State private var isLoading = false
    @State private var error: String?
    @State private var pinChangeCount = 0

    private var displayedProject: Project {
        detailProject ?? project
    }

    private var currentUserKey: String? {
        appState.currentUser?.canonicalName
    }

    private var isPinnedToHome: Bool {
        _ = pinChangeCount
        guard let currentUserKey else { return false }
        return ProjectPinStore.isPinned(projectID: displayedProject.id, for: currentUserKey)
    }

    var body: some View {
        List {
            headerSection
            linksSection
            repositoriesSection
            trackersSection
            mailingListsSection
        }
        .themedList()
        .navigationTitle(displayedProject.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading, detailProject == nil, !project.isFullyLoaded {
                SRHTLoadingStateView(message: "Loading project…")
            } else if let error, detailProject == nil, !project.isFullyLoaded {
                SRHTErrorStateView(
                    title: "Couldn't Load Project",
                    message: error,
                    retryAction: { await loadProjectIfNeeded(forceRefresh: true) }
                )
            }
        }
        .toolbar {
            if currentUserKey != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        togglePinnedState()
                    } label: {
                        Image(systemName: isPinnedToHome ? "pin.fill" : "pin")
                    }
                    .accessibilityLabel(isPinnedToHome ? "Unpin from Home" : "Pin to Home")
                }
            }
        }
        .task {
            await loadProjectIfNeeded()
        }
        .refreshable {
            await loadProjectIfNeeded(forceRefresh: true)
        }
        .srhtErrorBanner(error: $error)
    }

    @ViewBuilder
    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(displayedProject.name)
                    .font(.headline)

                if let description = displayedProject.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !displayedProject.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(displayedProject.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                }

                LabeledContent("Updated", value: displayedProject.updated.relativeDescription)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var linksSection: some View {
        let links = projectLinks(for: displayedProject)
        if !links.isEmpty {
            Section("Links") {
                ForEach(links) { link in
                    Link(destination: link.url) {
                        Label(link.title, systemImage: link.systemImage)
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var repositoriesSection: some View {
        if !displayedProject.sources.isEmpty {
            Section("Repositories") {
                ForEach(displayedProject.sources) { source in
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
        if !displayedProject.trackers.isEmpty {
            Section("Trackers") {
                ForEach(displayedProject.trackers) { tracker in
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
        if !displayedProject.mailingLists.isEmpty {
            Section("Mailing Lists") {
                ForEach(displayedProject.mailingLists) { mailingList in
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

    private func loadProjectIfNeeded(forceRefresh: Bool = false) async {
        guard forceRefresh || !project.isFullyLoaded else {
            detailProject = project
            return
        }
        guard !isLoading else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let service = ProjectService(client: appState.client)
            detailProject = try await service.fetchProjectDetail(rid: project.id)
        } catch {
            self.error = "Failed to load project"
        }
    }

    private func togglePinnedState() {
        guard let currentUserKey else { return }
        ProjectPinStore.togglePin(projectID: displayedProject.id, for: currentUserKey)
        pinChangeCount += 1
    }

    private func projectLinks(for project: Project) -> [ProjectLink] {
        var links: [ProjectLink] = []

        if let website = project.website?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: website),
           !website.isEmpty {
            links.append(ProjectLink(id: "website", title: website, systemImage: "globe", url: url))
        }

        if let source = project.sources.first,
           let url = sourceURL(for: source) {
            links.append(ProjectLink(id: "primary-repo", title: "\(source.ownerUsername)/\(source.name)", systemImage: "book.closed", url: url))
        }

        if let tracker = project.trackers.first,
           let url = SRHTWebURL.tracker(ownerUsername: tracker.ownerUsername, trackerName: tracker.name) {
            links.append(ProjectLink(id: "primary-tracker", title: "\(tracker.ownerUsername)/\(tracker.name)", systemImage: "checklist", url: url))
        }

        return links
    }

    private func sourceURL(for source: Project.SourceRepo) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "\(source.repoType.service.rawValue).sr.ht"
        components.percentEncodedPath = "/~\(source.ownerUsername)/\(source.name)"
        return components.url
    }
}

private struct ProjectLink: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let url: URL
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
