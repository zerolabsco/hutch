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
            self.error = "Failed to load projects"
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
        @Bindable var vm = viewModel

        List {
            ForEach(viewModel.filteredProjects) { project in
                NavigationLink {
                    ProjectDetailView(project: project)
                } label: {
                    ProjectListRow(project: project)
                }
            }
        }
        .themedList()
        .listStyle(.plain)
        .searchable(
            text: $vm.searchText,
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
                    description: Text("Your SourceHut projects will appear here.")
                )
            }
        }
        .srhtErrorBanner(error: $vm.error)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(project.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Spacer()

                Text(project.updated.relativeDescription)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let description = project.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let summary = project.resourceSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
