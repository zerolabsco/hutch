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

    static func loadActor(defaults: UserDefaults? = sharedDefaults()) -> String? {
        defaults?.string(forKey: actorKey)
    }

    static func isEnabled(defaults: UserDefaults? = sharedDefaults()) -> Bool {
        defaults?.object(forKey: enabledKey) == nil ? true : defaults?.bool(forKey: enabledKey) ?? true
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults? = sharedDefaults()) {
        defaults?.set(enabled, forKey: enabledKey)
        reloadWidgetTimelines()
    }

    static func saveActor(_ actor: String, defaults: UserDefaults? = sharedDefaults()) {
        defaults?.set(actor, forKey: actorKey)
        reloadWidgetTimelines()
    }

    static func clear(defaults: UserDefaults? = sharedDefaults()) {
        defaults?.removeObject(forKey: actorKey)
        reloadWidgetTimelines()
    }

    private static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: HutchAppGroup.identifier)
    }

    private static func reloadWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: ContributionGraphWidgetConfiguration.kind)
        #endif
    }
}
