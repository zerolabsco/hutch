import Foundation

@Observable
@MainActor
final class PasteListViewModel {
    private(set) var pastes: [Paste] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isRefreshing = false
    private(set) var isCreatingPaste = false
    var error: String?

    private var cursor: String?
    private var hasMore = true
    private let service: PasteService

    init(service: PasteService) {
        self.service = service
    }

    func loadPastes() async {
        if pastes.isEmpty, let cached = service.loadCachedPastes() {
            pastes = cached.results
            cursor = cached.cursor
            hasMore = cached.cursor != nil
        }

        if pastes.isEmpty {
            isLoading = true
        } else {
            isRefreshing = true
        }
        error = nil
        cursor = nil
        hasMore = true

        do {
            let page = try await service.listPastes(cursor: nil, useCache: true)
            pastes = page.results
            cursor = page.cursor
            hasMore = page.cursor != nil
        } catch {
            if pastes.isEmpty {
                self.error = error.localizedDescription
            }
        }

        isLoading = false
        isRefreshing = false
    }

    func loadMoreIfNeeded(currentItem: Paste) async {
        guard let last = pastes.last,
              last.id == currentItem.id,
              hasMore,
              !isLoadingMore else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await service.listPastes(cursor: cursor, useCache: false)
            pastes.append(contentsOf: page.results)
            cursor = page.cursor
            hasMore = page.cursor != nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createPaste(files: [PasteUploadDraft], visibility: Visibility) async -> Paste? {
        guard !isCreatingPaste else { return nil }

        let normalizedFiles = files.filter {
            !$0.contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !normalizedFiles.isEmpty else {
            error = "Add at least one file with text content."
            return nil
        }

        isCreatingPaste = true
        error = nil
        defer { isCreatingPaste = false }

        do {
            let paste = try await service.createPaste(files: normalizedFiles, visibility: visibility)
            upsertPaste(paste)
            return paste
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func upsertPaste(_ paste: Paste) {
        if let index = pastes.firstIndex(where: { $0.id == paste.id }) {
            pastes[index] = paste
        } else {
            pastes.insert(paste, at: 0)
        }
    }

    func removePaste(id: String) {
        pastes.removeAll { $0.id == id }
    }
}
