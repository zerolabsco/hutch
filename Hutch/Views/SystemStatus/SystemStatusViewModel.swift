import Foundation

@Observable
@MainActor
final class SystemStatusViewModel {
    private let repository: SystemStatusRepository

    private(set) var snapshot: SystemStatusSnapshot?
    private(set) var recentIncidents: [StatusIncident] = []
    private(set) var isLoading = false
    var errorMessage: String?

    init(repository: SystemStatusRepository) {
        self.repository = repository
    }

    var hasContent: Bool {
        snapshot != nil || !recentIncidents.isEmpty
    }

    func load(forceRefresh: Bool = false) async {
        if !hasContent {
            isLoading = true
        }
        defer { isLoading = false }

        errorMessage = nil

        async let snapshotTask = repository.snapshot(forceRefresh: forceRefresh)
        async let incidentsTask = repository.recentIncidents(forceRefresh: forceRefresh)

        do {
            snapshot = try await snapshotTask
        } catch {
            if snapshot == nil {
                errorMessage = error.userFacingMessage
            }
        }

        do {
            recentIncidents = try await incidentsTask
        } catch {
            if errorMessage == nil && recentIncidents.isEmpty {
                errorMessage = error.userFacingMessage
            }
        }
    }
}
