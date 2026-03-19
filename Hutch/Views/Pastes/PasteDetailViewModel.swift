import Foundation

@Observable
@MainActor
final class PasteDetailViewModel {
    private(set) var paste: Paste?
    private(set) var isLoading = false
    private(set) var isUpdatingVisibility = false
    private(set) var isDeleting = false
    private(set) var loadingFileHashes: Set<String> = []
    var error: String?

    var selectedFileHash: String?
    private(set) var fileContents: [String: String] = [:]

    private let pasteID: String
    private let service: PasteService

    init(pasteID: String, initialPaste: Paste? = nil, service: PasteService) {
        self.pasteID = pasteID
        self.paste = initialPaste
        self.service = service
        self.selectedFileHash = initialPaste?.files.first?.hash
    }

    var selectedFile: PasteFile? {
        let hash = selectedFileHash ?? paste?.files.first?.hash
        return paste?.files.first(where: { $0.hash == hash })
    }

    var selectedFileContents: String? {
        guard let selectedFile else { return nil }
        return fileContents[selectedFile.hash]
    }

    func loadPaste() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let loaded = try await service.loadPaste(id: pasteID)
            paste = loaded
            if selectedFileHash == nil {
                selectedFileHash = loaded?.files.first?.hash
            }
            await loadSelectedFileContentsIfNeeded()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func selectFile(hash: String) {
        selectedFileHash = hash
        Task {
            await loadSelectedFileContentsIfNeeded()
        }
    }

    func updateVisibility(_ visibility: Visibility) async -> Paste? {
        guard !isUpdatingVisibility else { return nil }
        guard let paste else { return nil }
        guard paste.visibility != visibility else { return paste }

        isUpdatingVisibility = true
        error = nil
        defer { isUpdatingVisibility = false }

        do {
            let updatedPaste = try await service.updateVisibility(id: paste.id, visibility: visibility)
            if let updatedPaste {
                self.paste = updatedPaste
                if selectedFileHash == nil {
                    selectedFileHash = updatedPaste.files.first?.hash
                }
            }
            return updatedPaste
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func deletePaste() async -> Bool {
        guard !isDeleting else { return false }
        isDeleting = true
        error = nil
        defer { isDeleting = false }

        do {
            _ = try await service.deletePaste(id: pasteID)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func loadSelectedFileContentsIfNeeded() async {
        guard let file = selectedFile, fileContents[file.hash] == nil else { return }
        guard let url = file.contents else { return }
        guard !loadingFileHashes.contains(file.hash) else { return }

        loadingFileHashes.insert(file.hash)
        defer { loadingFileHashes.remove(file.hash) }

        do {
            fileContents[file.hash] = try await service.loadContents(from: url)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
