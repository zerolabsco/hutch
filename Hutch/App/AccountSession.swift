import Foundation

struct AccountSession: Sendable {
    let account: AccountEntry
    let user: User
    let client: SRHTClient
    let defaults: UserDefaults
    let systemStatusRepository: SystemStatusRepository

    var id: String {
        account.id
    }
}

enum AccountDefaultsStore {
    private static let suitePrefix = "net.cleberg.Hutch.account"

    static func userDefaults(for accountID: String) -> UserDefaults {
        let suiteName = suiteName(for: accountID)
        return UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func clear(accountID: String) {
        let suiteName = suiteName(for: accountID)
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removePersistentDomain(forName: suiteName)
    }

    private static func suiteName(for accountID: String) -> String {
        "\(suitePrefix).\(accountID)"
    }
}
