import Foundation

// MARK: - Response types (file-private to avoid @MainActor Decodable issues)

private struct TodoPreferencesResponse: Decodable, Sendable {
    let preferences: TodoPreferences
}

private struct TodoPreferences: Decodable, Sendable {
    let notifySelf: Bool
}

private struct ListsPreferencesResponse: Decodable, Sendable {
    let preferences: ListsPreferences
}

private struct ListsPreferences: Decodable, Sendable {
    let copySelf: Bool
}

// MARK: - View Model

/// Email preferences for todo.sr.ht and lists.sr.ht.
///
/// The two services each expose `preferences`/`updatePreferences` under the same
/// names but with different fields — `notifySelf` on todo, `copySelf` on lists —
/// and there is no shared preferences service, so both are handled side by side.
@Observable
@MainActor
final class NotificationPreferencesViewModel {

    private(set) var notifySelf = false
    private(set) var copySelf = false
    private(set) var isLoading = false
    private(set) var isSavingNotifySelf = false
    private(set) var isSavingCopySelf = false
    private(set) var hasLoaded = false
    var error: String?

    private let client: SRHTClient

    init(client: SRHTClient) {
        self.client = client
    }

    private static let todoPreferencesQuery = """
    query todoPreferences {
        preferences { notifySelf }
    }
    """

    private static let listsPreferencesQuery = """
    query listsPreferences {
        preferences { copySelf }
    }
    """

    private static let updateNotifySelfMutation = """
    mutation updateTodoPreferences($notifySelf: Boolean!) {
        preferences: updatePreferences(preferences: { notifySelf: $notifySelf }) {
            notifySelf
        }
    }
    """

    private static let updateCopySelfMutation = """
    mutation updateListsPreferences($copySelf: Boolean!) {
        preferences: updatePreferences(preferences: { copySelf: $copySelf }) {
            copySelf
        }
    }
    """

    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await load()
    }

    func load() async {
        isLoading = true
        error = nil
        defer {
            isLoading = false
            hasLoaded = true
        }

        // The two services are independent; one being unreachable should not hide
        // the other's setting.
        async let todo = fetchNotifySelf()
        async let lists = fetchCopySelf()

        let (todoResult, listsResult) = await (todo, lists)

        if let todoResult {
            notifySelf = todoResult
        }
        if let listsResult {
            copySelf = listsResult
        }

        if todoResult == nil && listsResult == nil {
            error = "Couldn't load your email preferences."
        }
    }

    /// The fetches stay in their own methods so the response types are only ever
    /// decoded on the main actor. The module defaults to MainActor isolation, so
    /// decoding straight from an `async let` would use a main-actor-isolated
    /// Decodable conformance from a nonisolated context.
    private func fetchNotifySelf() async -> Bool? {
        let response = try? await client.execute(
            service: .todo,
            query: Self.todoPreferencesQuery,
            responseType: TodoPreferencesResponse.self
        )
        return response?.preferences.notifySelf
    }

    private func fetchCopySelf() async -> Bool? {
        let response = try? await client.execute(
            service: .lists,
            query: Self.listsPreferencesQuery,
            responseType: ListsPreferencesResponse.self
        )
        return response?.preferences.copySelf
    }

    func setNotifySelf(_ newValue: Bool) async {
        guard !isSavingNotifySelf else { return }
        isSavingNotifySelf = true
        error = nil
        defer { isSavingNotifySelf = false }

        let previous = notifySelf
        notifySelf = newValue

        do {
            let response = try await client.execute(
                service: .todo,
                query: Self.updateNotifySelfMutation,
                variables: ["notifySelf": newValue],
                responseType: TodoPreferencesResponse.self
            )
            notifySelf = response.preferences.notifySelf
        } catch {
            notifySelf = previous
            self.error = "Couldn't update ticket email preference. \(error.userFacingMessage)"
        }
    }

    func setCopySelf(_ newValue: Bool) async {
        guard !isSavingCopySelf else { return }
        isSavingCopySelf = true
        error = nil
        defer { isSavingCopySelf = false }

        let previous = copySelf
        copySelf = newValue

        do {
            let response = try await client.execute(
                service: .lists,
                query: Self.updateCopySelfMutation,
                variables: ["copySelf": newValue],
                responseType: ListsPreferencesResponse.self
            )
            copySelf = response.preferences.copySelf
        } catch {
            copySelf = previous
            self.error = "Couldn't update mailing list email preference. \(error.userFacingMessage)"
        }
    }
}
