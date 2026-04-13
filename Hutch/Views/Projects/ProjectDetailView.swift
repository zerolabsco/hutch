import SwiftUI

struct ProjectDetailView: View {
    let project: Project

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
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
        return ProjectPinStore.isPinned(projectID: displayedProject.id, for: currentUserKey, defaults: appState.accountDefaults)
    }

    var body: some View {
        List {
            headerSection
            repositoriesSection
            trackersSection
            mailingListsSection
            linksSection
            emptyResourcesSection
        }
        .themedList()
        .navigationTitle(displayedProject.displayName)
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
                Text(displayedProject.displayName)
                    .font(.headline)

                if let description = displayedProject.displayDescription {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !displayedProject.displayTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(displayedProject.displayTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                }

                LabeledContent("Project", value: displayedProject.visibility.displayName)
                LabeledContent("Updated", value: displayedProject.updated.relativeDescription)
                if let summary = displayedProject.resourceSummary {
                    LabeledContent("Linked", value: summary)
                }
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
                    Button {
                        openURL(link.url)
                    } label: {
                        HStack(spacing: 12) {
                            Label(link.title, systemImage: link.systemImage)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
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
                            do {
                                try await appState.openProjectSource(source)
                                dismiss()
                            } catch {
                                self.error = "Couldn’t open repository. \(error.userFacingMessage)"
                            }
                        }
                    } label: {
                        ProjectResourceRow(
                            title: source.displayName,
                            subtitle: source.ownerDisplayName,
                            detail: source.displayDescription,
                            systemImage: "book.closed"
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
                            do {
                                try await appState.openProjectTracker(tracker)
                                dismiss()
                            } catch {
                                self.error = "Couldn’t open tracker. \(error.userFacingMessage)"
                            }
                        }
                    } label: {
                        ProjectResourceRow(
                            title: tracker.displayName,
                            subtitle: tracker.ownerDisplayName,
                            detail: tracker.displayDescription,
                            systemImage: "checklist"
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
                            title: mailingList.displayName,
                            subtitle: mailingList.ownerDisplayName,
                            detail: mailingList.displayDescription,
                            systemImage: "list.bullet"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyResourcesSection: some View {
        if !displayedProject.hasLinkedResources, displayedProject.websiteURL == nil {
            Section {
                ContentUnavailableView(
                    "No Linked Resources",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("This project doesn’t currently expose repositories, trackers, mailing lists, or external links.")
                )
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
            self.error = "Couldn’t load project. \(error.userFacingMessage)"
        }
    }

    private func togglePinnedState() {
        guard let currentUserKey else { return }
        ProjectPinStore.togglePin(projectID: displayedProject.id, for: currentUserKey, defaults: appState.accountDefaults)
        pinChangeCount += 1
    }

    private func projectLinks(for project: Project) -> [ProjectLink] {
        var links: [ProjectLink] = []

        if let url = project.websiteURL {
            links.append(ProjectLink(id: "website", title: project.website ?? url.absoluteString, systemImage: "globe", url: url))
        }

        if let source = project.sources.first,
           let url = source.webURL {
            links.append(ProjectLink(id: "primary-repo", title: "\(source.ownerUsername)/\(source.displayName)", systemImage: "book.closed", url: url))
        }

        if let tracker = project.trackers.first,
           let url = tracker.webURL {
            links.append(ProjectLink(id: "primary-tracker", title: "\(tracker.ownerUsername)/\(tracker.displayName)", systemImage: "checklist", url: url))
        }

        if let mailingList = project.mailingLists.first,
           let url = SRHTWebURL.mailingList(ownerUsername: mailingList.ownerUsername, listName: mailingList.name) {
            links.append(ProjectLink(id: "primary-list", title: "\(mailingList.ownerUsername)/\(mailingList.displayName)", systemImage: "list.bullet", url: url))
        }

        return links
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
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 18, alignment: .leading)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

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

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}
