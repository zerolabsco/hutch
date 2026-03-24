import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum HutchAppGroup {
    static let identifier = "group.net.cleberg.Hutch"
}

enum NeedsAttentionWidgetConfiguration {
    static let kind = "NeedsAttentionWidget"
}

struct NeedsAttentionSnapshot: Codable, Sendable {
    let unreadInboxThreads: Int?
    let assignedOpenTickets: Int?
    let failedBuilds: Int?
    let updatedAt: Date

    static let unavailable = NeedsAttentionSnapshot(
        unreadInboxThreads: nil,
        assignedOpenTickets: nil,
        failedBuilds: nil,
        updatedAt: .now
    )

    var hasAnyData: Bool {
        unreadInboxThreads != nil || assignedOpenTickets != nil || failedBuilds != nil
    }

    var allCountsAreZero: Bool {
        let counts = [unreadInboxThreads, assignedOpenTickets, failedBuilds].compactMap { $0 }
        return !counts.isEmpty && counts.allSatisfy { $0 == 0 }
    }
}

enum NeedsAttentionSnapshotStore {
    private static let snapshotKey = "needsAttention.snapshot"

    static func load(defaults: UserDefaults? = sharedDefaults()) -> NeedsAttentionSnapshot? {
        guard let defaults,
              let data = defaults.data(forKey: snapshotKey) else {
            return nil
        }

        return try? JSONDecoder().decode(NeedsAttentionSnapshot.self, from: data)
    }

    static func save(_ snapshot: NeedsAttentionSnapshot, defaults: UserDefaults? = sharedDefaults()) {
        guard let defaults,
              let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        defaults.set(data, forKey: snapshotKey)
        reloadWidgetTimelines()
    }

    static func update(
        unreadInboxThreads: Int? = nil,
        assignedOpenTickets: Int? = nil,
        failedBuilds: Int? = nil,
        defaults: UserDefaults? = sharedDefaults()
    ) {
        let existing = load(defaults: defaults)
        let snapshot = NeedsAttentionSnapshot(
            unreadInboxThreads: unreadInboxThreads ?? existing?.unreadInboxThreads,
            assignedOpenTickets: assignedOpenTickets ?? existing?.assignedOpenTickets,
            failedBuilds: failedBuilds ?? existing?.failedBuilds,
            updatedAt: .now
        )
        save(snapshot, defaults: defaults)
    }

    static func adjustUnreadInboxThreads(
        by delta: Int,
        defaults: UserDefaults? = sharedDefaults()
    ) {
        guard let existing = load(defaults: defaults),
              let unreadInboxThreads = existing.unreadInboxThreads else {
            return
        }

        save(
            NeedsAttentionSnapshot(
                unreadInboxThreads: max(0, unreadInboxThreads + delta),
                assignedOpenTickets: existing.assignedOpenTickets,
                failedBuilds: existing.failedBuilds,
                updatedAt: .now
            ),
            defaults: defaults
        )
    }

    static func clear(defaults: UserDefaults? = sharedDefaults()) {
        defaults?.removeObject(forKey: snapshotKey)
        reloadWidgetTimelines()
    }

    private static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: HutchAppGroup.identifier)
    }

    private static func reloadWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: NeedsAttentionWidgetConfiguration.kind)
        #endif
    }
}
