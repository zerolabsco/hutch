import Foundation

@Observable
@MainActor
final class MoreViewModel {
    private let repository: SystemStatusRepository

    private(set) var systemStatusSnapshot: SystemStatusSnapshot?
    private(set) var isLoadingSystemStatus = false
    private(set) var isShowingStaleSystemStatus = false
    private(set) var systemStatusErrorMessage: String?

    init(repository: SystemStatusRepository) {
        self.repository = repository
    }

    func loadIfNeeded() async {
        guard systemStatusSnapshot == nil, !isLoadingSystemStatus else { return }
        await loadSystemStatus()
    }

    func loadSystemStatus(forceRefresh: Bool = false) async {
        isLoadingSystemStatus = true
        defer { isLoadingSystemStatus = false }
        isShowingStaleSystemStatus = false
        systemStatusErrorMessage = nil

        do {
            let result = try await repository.snapshotResult(forceRefresh: forceRefresh)
            systemStatusSnapshot = result.value
            isShowingStaleSystemStatus = result.isStale
            systemStatusErrorMessage = result.isStale ? result.refreshErrorMessage : nil
        } catch {
            if systemStatusSnapshot == nil {
                systemStatusErrorMessage = error.userFacingMessage
            }
        }
    }
}
