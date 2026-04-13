import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum ContributionGraphWidgetConfiguration {
    static let kind = "ContributionGraphWidget"
}

enum ContributionWidgetContextStore {
    private static let actorKey = "contributionWidget.actor"
    private static let enabledKey = "contributionWidget.enabled"

    static func loadActor(
        accountID: String? = ActiveAccountContextStore.load(),
        defaults: UserDefaults? = sharedDefaults()
    ) -> String? {
        defaults?.string(forKey: scopedActorKey(for: accountID))
    }

    static func isEnabled(defaults: UserDefaults? = sharedDefaults()) -> Bool {
        defaults?.object(forKey: enabledKey) == nil ? true : defaults?.bool(forKey: enabledKey) ?? true
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults? = sharedDefaults()) {
        defaults?.set(enabled, forKey: enabledKey)
        reloadWidgetTimelines()
    }

    static func saveActor(
        _ actor: String,
        accountID: String? = ActiveAccountContextStore.load(),
        defaults: UserDefaults? = sharedDefaults()
    ) {
        defaults?.set(actor, forKey: scopedActorKey(for: accountID))
        reloadWidgetTimelines()
    }

    static func clear(
        accountID: String? = ActiveAccountContextStore.load(),
        defaults: UserDefaults? = sharedDefaults()
    ) {
        defaults?.removeObject(forKey: scopedActorKey(for: accountID))
        reloadWidgetTimelines()
    }

    private static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: HutchAppGroup.identifier)
    }

    private static func scopedActorKey(for accountID: String?) -> String {
        guard let accountID, !accountID.isEmpty else { return actorKey }
        return "\(actorKey).\(accountID)"
    }

    private static func reloadWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: ContributionGraphWidgetConfiguration.kind)
        #endif
    }
}
