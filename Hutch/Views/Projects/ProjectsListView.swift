import SwiftUI

@Observable
@MainActor
final class ProjectsListViewModel {
    private(set) var projects: [Project] = []
    private(set) var isLoading = false
    var error: String?
    var searchText = ""

    private let service: ProjectService

    init(service: ProjectService) {
        self.service = service
    }

    var filteredProjects: [Project] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return projects }

        return projects.filter {
            $0.name.lowercased().contains(query) ||
            ($0.description?.lowercased().contains(query) ?? false) ||
            $0.tags.contains(where: { $0.lowercased().contains(query) })
        }
    }

    func loadProjects() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            projects = try await service.fetchProjects()
        } catch {
            if projects.isEmpty {
                self.error = error.userFacingMessage
            } else {
                self.error = "Couldn’t refresh projects. \(error.userFacingMessage)"
            }
        }
    }
}

struct ProjectsListView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: ProjectsListViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading projects…")
            }
        }
        .navigationTitle("Projects")
        .task {
            if viewModel == nil {
                let vm = ProjectsListViewModel(service: ProjectService(client: appState.client))
                viewModel = vm
                await vm.loadProjects()
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: ProjectsListViewModel) -> some View {
        List {
            ForEach(viewModel.filteredProjects) { project in
                NavigationLink {
                    ProjectDetailView(project: project)
                } label: {
                    ProjectListRow(project: project)
                }
                .buttonStyle(.plain)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
            .themedRow()
        }
        .themedList()
        .listStyle(.plain)
        .searchable(
            text: Binding(
                get: { viewModel.searchText },
                set: { viewModel.searchText = $0 }
            ),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search projects"
        )
        .overlay {
            if viewModel.isLoading, viewModel.projects.isEmpty {
                SRHTLoadingStateView(message: "Loading projects…")
            } else if let error = viewModel.error, viewModel.projects.isEmpty {
                SRHTErrorStateView(
                    title: "Couldn't Load Projects",
                    message: error,
                    retryAction: { await viewModel.loadProjects() }
                )
            } else if !viewModel.projects.isEmpty, viewModel.filteredProjects.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            } else if viewModel.projects.isEmpty {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "square.stack.3d.up",
                    description: Text("Projects from your SourceHut account will appear here when available.")
                )
            }
        }
        .srhtErrorBanner(
            error: Binding(
                get: { viewModel.error },
                set: { viewModel.error = $0 }
            )
        )
        .refreshable {
            await viewModel.loadProjects()
        }
        .connectivityOverlay(hasContent: !viewModel.projects.isEmpty) {
            await viewModel.loadProjects()
        }
    }
}

private struct ProjectListRow: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let description = project.displayDescription {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                VisibilityBadge(visibility: project.visibility)
            }

            Text(project.metadataLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !project.displayTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(project.displayTags.prefix(4), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
                .scrollDisabled(true)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}
