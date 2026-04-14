import Foundation

@Observable
@MainActor
final class PasteListViewModel {
    private(set) var pastes: [Paste] = [] {
        didSet { updateFilteredPastes() }
    }
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isRefreshing = false
    private(set) var isCreatingPaste = false
    var error: String?
    var searchText = "" {
        didSet { updateFilteredPastes() }
    }
    private(set) var filteredPastes: [Paste] = []

    private var cursor: String?
    private var hasMore = true
    private let service: PasteService

    init(service: PasteService) {
        self.service = service
    }

    private func updateFilteredPastes() {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let updated: [Paste]
        if q.isEmpty {
            updated = pastes
        } else {
            updated = pastes.filter {
                $0.files.contains {
                    ($0.filename?.lowercased().contains(q) == true) ||
                    $0.hash.lowercased().hasPrefix(q)
                }
            }
        }
        if updated != filteredPastes {
            filteredPastes = updated
        }
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
                self.error = error.userFacingMessage
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
            self.error = error.userFacingMessage
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
            self.error = error.userFacingMessage
            return nil
        }
    }

    func deletePaste(_ paste: Paste) async {
        do {
            _ = try await service.deletePaste(id: paste.id)
            removePaste(id: paste.id)
        } catch {
            self.error = error.userFacingMessage
        }
    }

    func cycleVisibility(for paste: Paste) async {
        let next: Visibility
        switch paste.visibility {
        case .publicVisibility:
            next = .unlisted
        case .unlisted:
            next = .privateVisibility
        case .privateVisibility:
            next = .publicVisibility
        }

        let original = pastes
        if let index = pastes.firstIndex(where: { $0.id == paste.id }) {
            pastes[index] = Paste(
                id: paste.id,
                created: paste.created,
                visibility: next,
                files: paste.files,
                user: paste.user
            )
        }

        do {
            if let updated = try await service.updateVisibility(id: paste.id, visibility: next) {
                upsertPaste(updated)
            }
        } catch {
            pastes = original
            self.error = error.userFacingMessage
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
