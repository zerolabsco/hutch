import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum ContributionGraphWidgetConfiguration {
    static let kind = "ContributionGraphWidget"
}

enum ContributionWidgetContextStore {
    private static let actorKey = "contributionWidget.actor"

    static func loadActor(defaults: UserDefaults? = sharedDefaults()) -> String? {
        defaults?.string(forKey: actorKey)
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
