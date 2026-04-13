import Foundation

@Observable
@MainActor
final class RepositoryACLViewModel {
    let repository: RepositorySummary

    private let service: any RepositoryACLServicing

    private(set) var entries: [RepositoryACLEntry] = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var updatingEntryIDs: Set<Int> = []
    private(set) var deletingEntryIDs: Set<Int> = []
    private(set) var isCreatingEntry = false

    var addUsername = ""
    var addMode: AccessMode = .ro
    var error: String?

    init(
        repository: RepositorySummary,
        service: any RepositoryACLServicing
    ) {
        self.repository = repository
        self.service = service
    }

    var visibleEntries: [RepositoryACLEntry] {
        sort(entries.filter { normalizedIdentity($0.entity.canonicalName) != normalizedIdentity(repository.owner.canonicalName) })
    }

    var hasEntries: Bool {
        !visibleEntries.isEmpty
    }

    var addValidationMessage: String? {
        Self.validateEntityInput(
            addUsername,
            ownerCanonicalName: repository.owner.canonicalName,
            existingEntities: visibleEntries.map(\.entity.canonicalName)
        )
    }

    var canSubmitNewEntry: Bool {
        addValidationMessage == nil && !isCreatingEntry
    }

    func load() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            entries = try await service.fetchACLs(repositoryRid: repository.rid)
            loadError = nil
        } catch {
            let message = error.userFacingMessage
            if entries.isEmpty {
                loadError = message
            } else {
                self.error = message
            }
        }
    }

    func addEntry() async -> Bool {
        guard let entity = validatedNewEntity() else {
            error = addValidationMessage ?? "Enter a valid username."
            return false
        }

        isCreatingEntry = true
        defer { isCreatingEntry = false }
        error = nil

        do {
            let entry = try await service.upsertACL(
                repositoryId: repository.id,
                entity: entity,
                mode: addMode
            )
            merge(entry)
            addUsername = ""
            addMode = .ro
            await refreshAfterMutation()
            return true
        } catch {
            self.error = error.userFacingMessage
            return false
        }
    }

    func updatePermission(for entry: RepositoryACLEntry, to mode: AccessMode) async {
        guard entry.mode != mode else { return }

        updatingEntryIDs.insert(entry.id)
        defer { updatingEntryIDs.remove(entry.id) }
        error = nil

        do {
            let updatedEntry = try await service.upsertACL(
                repositoryId: repository.id,
                entity: entry.entity.canonicalName,
                mode: mode
            )
            merge(updatedEntry)
            await refreshAfterMutation()
        } catch {
            self.error = error.userFacingMessage
        }
    }

    func removeEntry(_ entry: RepositoryACLEntry) async {
        deletingEntryIDs.insert(entry.id)
        defer { deletingEntryIDs.remove(entry.id) }
        error = nil

        do {
            try await service.deleteACL(entryId: entry.id)
            entries.removeAll { $0.id == entry.id }
            await refreshAfterMutation()
        } catch {
            self.error = error.userFacingMessage
        }
    }

    func isUpdating(_ entry: RepositoryACLEntry) -> Bool {
        updatingEntryIDs.contains(entry.id)
    }

    func isDeleting(_ entry: RepositoryACLEntry) -> Bool {
        deletingEntryIDs.contains(entry.id)
    }

    static func canonicalEntity(from input: String) -> String? {
        guard validateEntityInput(input, ownerCanonicalName: nil, existingEntities: []) == nil else {
            return nil
        }

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = trimmed.hasPrefix("~") ? String(trimmed.dropFirst()) : trimmed
        return "~\(username)"
    }

    static func validateEntityInput(
        _ input: String,
        ownerCanonicalName: String?,
        existingEntities: [String]
    ) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Enter a username." }
        guard !trimmed.contains(where: \.isWhitespace) else { return "Usernames cannot contain spaces." }

        let username = trimmed.hasPrefix("~") ? String(trimmed.dropFirst()) : trimmed
        guard !username.isEmpty else { return "Enter a username." }
        guard username.first != "~", !username.contains("~") else { return "Enter a valid username." }
        guard username.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil else {
            return "Enter a valid username."
        }

        if let ownerCanonicalName, normalizedIdentity(ownerCanonicalName) == normalizedIdentity(username) {
            return "The repository owner already has access."
        }

        if existingEntities.contains(where: { normalizedIdentity($0) == normalizedIdentity(username) }) {
            return "That user already has access."
        }

        return nil
    }
}

private extension RepositoryACLViewModel {
    func validatedNewEntity() -> String? {
        guard addValidationMessage == nil else { return nil }
        return Self.canonicalEntity(from: addUsername)
    }

    func refreshAfterMutation() async {
        do {
            entries = try await service.fetchACLs(repositoryRid: repository.rid)
            loadError = nil
        } catch {
            self.error = "Saved, but couldn't refresh access list: \(error.userFacingMessage)"
        }
    }

    func merge(_ entry: RepositoryACLEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        entries = sort(entries)
    }

    func sort(_ entries: [RepositoryACLEntry]) -> [RepositoryACLEntry] {
        entries.sorted {
            $0.entity.canonicalName.localizedCaseInsensitiveCompare($1.entity.canonicalName) == .orderedAscending
        }
    }

    static func normalizedIdentity(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("~") ? String(trimmed.dropFirst()).lowercased() : trimmed.lowercased()
    }

    func normalizedIdentity(_ value: String) -> String {
        Self.normalizedIdentity(value)
    }
}
