import Foundation

@Observable
@MainActor
final class SystemStatusViewModel {
    private let repository: SystemStatusRepository

    private(set) var snapshot: SystemStatusSnapshot?
    private(set) var recentIncidents: [StatusIncident] = []
    private(set) var isLoading = false
    private(set) var isShowingStaleData = false
    private(set) var staleDataMessage: String?
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
        staleDataMessage = nil
        isShowingStaleData = false

        async let snapshotTask = repository.snapshotResult(forceRefresh: forceRefresh)
        async let incidentsTask = repository.recentIncidentsResult(forceRefresh: forceRefresh)

        var refreshWarnings: [String] = []

        do {
            let result = try await snapshotTask
            snapshot = result.value
            if result.isStale {
                isShowingStaleData = true
                staleDataMessage = "Showing the last saved system status snapshot."
                if let warning = result.refreshErrorMessage {
                    refreshWarnings.append(warning)
                }
            }
        } catch {
            if snapshot == nil {
                errorMessage = error.userFacingMessage
            }
        }

        do {
            let result = try await incidentsTask
            recentIncidents = result.value
            if result.isStale {
                isShowingStaleData = true
                staleDataMessage = staleDataMessage ?? "Showing the last saved incident history."
                if let warning = result.refreshErrorMessage {
                    refreshWarnings.append(warning)
                }
            }
        } catch {
            if errorMessage == nil && recentIncidents.isEmpty {
                errorMessage = error.userFacingMessage
            }
        }

        if hasContent, let firstWarning = refreshWarnings.first {
            errorMessage = "Showing cached system status. \(firstWarning)"
        }
    }
}
