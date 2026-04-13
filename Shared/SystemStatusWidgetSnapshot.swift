import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum SystemStatusWidgetConfiguration {
    static let kind = "SystemStatusWidget"
}

struct SystemStatusWidgetSnapshot: Codable, Sendable {
    let services: [ServiceEntry]
    let hasDisruption: Bool
    let overallStatusText: String
    let bannerSummary: String
    let updatedAt: Date

    struct ServiceEntry: Codable, Sendable, Identifiable {
        let id: String
        let name: String
        let status: String
        let requiresAttention: Bool
    }

    static let unavailable = SystemStatusWidgetSnapshot(
        services: [],
        hasDisruption: false,
        overallStatusText: "Unavailable",
        bannerSummary: "",
        updatedAt: .now
    )
}

enum SystemStatusWidgetSnapshotStore {
    private static let snapshotKey = "systemStatus.widgetSnapshot"

    static func load(
        accountID: String? = ActiveAccountContextStore.load(),
        defaults: UserDefaults? = sharedDefaults()
    ) -> SystemStatusWidgetSnapshot? {
        guard let defaults,
              let data = defaults.data(forKey: scopedKey(for: accountID)) else {
            return nil
        }
        return try? JSONDecoder().decode(SystemStatusWidgetSnapshot.self, from: data)
    }

    static func save(
        _ snapshot: SystemStatusWidgetSnapshot,
        accountID: String? = ActiveAccountContextStore.load(),
        defaults: UserDefaults? = sharedDefaults()
    ) {
        guard let defaults,
              let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: scopedKey(for: accountID))
        reloadWidgetTimelines()
    }

    static func clear(
        accountID: String? = ActiveAccountContextStore.load(),
        defaults: UserDefaults? = sharedDefaults()
    ) {
        defaults?.removeObject(forKey: scopedKey(for: accountID))
        reloadWidgetTimelines()
    }

    private static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: HutchAppGroup.identifier)
    }

    private static func scopedKey(for accountID: String?) -> String {
        guard let accountID, !accountID.isEmpty else { return snapshotKey }
        return "\(snapshotKey).\(accountID)"
    }

    private static func reloadWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: SystemStatusWidgetConfiguration.kind)
        #endif
    }
}
