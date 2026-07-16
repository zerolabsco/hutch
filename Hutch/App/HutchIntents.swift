import AppIntents
import Foundation

// MARK: - Navigation Intents

struct OpenWorkQueueIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Work Queue"
    static var description = IntentDescription("Opens Hutch to your Work Queue.")
    static var openAppWhenRun = true

    var route: HutchRoute { .workQueue(scope: .all) }

    @MainActor
    func perform() async throws -> some IntentResult {
        HutchIntentNavigator.shared.open(route)
        return .result()
    }
}

struct OpenRecentActivityIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Recent Activity"
    static var description = IntentDescription("Opens Hutch to recent activity.")
    static var openAppWhenRun = true

    var route: HutchRoute { .recentActivity }

    @MainActor
    func perform() async throws -> some IntentResult {
        HutchIntentNavigator.shared.open(route)
        return .result()
    }
}

struct OpenSystemStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Open System Status"
    static var description = IntentDescription("Opens Hutch to SourceHut system status.")
    static var openAppWhenRun = true

    var route: HutchRoute { .systemStatus }

    @MainActor
    func perform() async throws -> some IntentResult {
        HutchIntentNavigator.shared.open(route)
        return .result()
    }
}

struct OpenPinnedResourceIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Pinned Resource"
    static var description = IntentDescription("Opens a pinned Hutch resource.")
    static var openAppWhenRun = true

    @Parameter(title: "Pinned Resource")
    var pinnedResource: PinnedResourceEntity

    var route: HutchRoute { pinnedResource.route }

    @MainActor
    func perform() async throws -> some IntentResult {
        HutchIntentNavigator.shared.open(route)
        return .result()
    }
}

struct OpenProjectDashboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Project Dashboard"
    static var description = IntentDescription("Opens a pinned project dashboard in Hutch.")
    static var openAppWhenRun = true

    @Parameter(title: "Project")
    var project: ProjectEntity

    var route: HutchRoute {
        .projectDashboard(id: project.id, title: project.name)
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        HutchIntentNavigator.shared.open(route)
        return .result()
    }
}

enum HutchShortcutScope: String, AppEnum {
    case all

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Scope")
    static var caseDisplayRepresentations: [HutchShortcutScope: DisplayRepresentation] = [
        .all: "All"
    ]
}

struct OpenFailedBuildsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Failed Builds"
    static var description = IntentDescription("Opens Hutch to failed builds.")
    static var openAppWhenRun = true

    @Parameter(title: "Scope", default: .all)
    var scope: HutchShortcutScope

    var route: HutchRoute { .failedBuilds }

    @MainActor
    func perform() async throws -> some IntentResult {
        HutchIntentNavigator.shared.open(route)
        return .result()
    }
}

struct OpenAssignedTicketsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Assigned Tickets"
    static var description = IntentDescription("Opens Hutch to tickets assigned to you.")
    static var openAppWhenRun = true

    @Parameter(title: "Scope", default: .all)
    var scope: HutchShortcutScope

    var route: HutchRoute { .workQueue(scope: .assigned) }

    @MainActor
    func perform() async throws -> some IntentResult {
        HutchIntentNavigator.shared.open(route)
        return .result()
    }
}

struct SearchHutchIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Hutch"
    static var description = IntentDescription("Opens Hutch lookup with a search query.")
    static var openAppWhenRun = true

    @Parameter(title: "Query")
    var query: String

    var route: HutchRoute {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Routes to Lookup for now; repoint at a global content search when Hutch
        // gains one — tracked in ROADMAP.md § "App Intent gaps".
        return normalized.isEmpty ? .lookup : .search(query: normalized)
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        HutchIntentNavigator.shared.open(route)
        return .result()
    }
}

// An OpenSavedSearchIntent belongs here once Hutch has global saved-search
// persistence — tracked in ROADMAP.md § "App Intent gaps".

// MARK: - App Entities

struct PinnedResourceEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Pinned Resource")
    static var defaultQuery = PinnedResourceQuery()

    let id: String
    let name: String
    let subtitle: String
    let route: HutchRoute

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }
}

struct PinnedResourceQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [PinnedResourceEntity.ID]) async throws -> [PinnedResourceEntity] {
        HutchIntentEntityStore.pinnedResources().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [PinnedResourceEntity] {
        HutchIntentEntityStore.pinnedResources()
    }
}

struct ProjectEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Project")
    static var defaultQuery = ProjectEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ProjectEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [ProjectEntity.ID]) async throws -> [ProjectEntity] {
        HutchIntentEntityStore.projects().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ProjectEntity] {
        HutchIntentEntityStore.projects()
    }
}

private enum HutchIntentEntityStore {
    static func pinnedResources() -> [PinnedResourceEntity] {
        pins().compactMap { makePinnedResource(from: $0) }
    }

    static func projects() -> [ProjectEntity] {
        pins().compactMap { pin in
            guard pin.kind == .project else { return nil }
            return ProjectEntity(id: pin.value, name: pin.title)
        }
    }

    private static func pins() -> [HomePinRecord] {
        guard let userKey = ContributionWidgetContextStore.loadActor(),
              !userKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return []
        }

        return HomePinStore.loadPins(for: userKey, defaults: activeAccountDefaults)
    }

    private static var activeAccountDefaults: UserDefaults {
        let activeID = UserDefaults.standard.string(forKey: AppStorageKeys.activeAccountID) ?? ""
        guard !activeID.isEmpty else { return .standard }
        return AccountDefaultsStore.userDefaults(for: activeID)
    }

    private static func makePinnedResource(from pin: HomePinRecord) -> PinnedResourceEntity? {
        guard let route = route(for: pin) else { return nil }
        return PinnedResourceEntity(
            id: pin.id,
            name: pin.title,
            subtitle: pin.subtitle,
            route: route
        )
    }

    private static func route(for pin: HomePinRecord) -> HutchRoute? {
        switch pin.kind {
        case .project:
            return .projectDashboard(id: pin.value, title: pin.title)
        case .repository:
            guard let owner = pin.ownerUsername else { return nil }
            return .repository(
                service: pin.service ?? .git,
                owner: formattedOwner(owner),
                repo: pin.value
            )
        case .tracker:
            guard let owner = pin.ownerUsername else { return nil }
            return .tracker(owner: formattedOwner(owner), tracker: pin.value)
        case .mailingList:
            guard let owner = pin.ownerUsername else { return nil }
            return .mailingList(owner: formattedOwner(owner), list: pin.value)
        case .user:
            guard let owner = pin.ownerUsername else { return nil }
            return .userProfile(owner: formattedOwner(owner))
        }
    }

    private static func formattedOwner(_ owner: String) -> String {
        owner.hasPrefix("~") ? owner : "~\(owner)"
    }
}

// MARK: - Existing Read-Only Summary Intents

struct CheckSystemStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check SourceHut Status"
    static var description = IntentDescription("Returns the current SourceHut system status.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let snapshot = SystemStatusWidgetSnapshotStore.load() else {
            return .result(value: "System status is unavailable. Open Hutch to refresh.")
        }

        if snapshot.hasDisruption {
            let disrupted = snapshot.services
                .filter { $0.requiresAttention }
                .map { "\($0.name): \($0.status)" }
                .joined(separator: ", ")
            return .result(value: "SourceHut disruption detected: \(disrupted)")
        }

        return .result(value: "All SourceHut services operational.")
    }
}

struct CheckBuildsIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Hutch Builds"
    static var description = IntentDescription("Returns a summary of your recent build status.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let snapshot = NeedsAttentionSnapshotStore.load() else {
            return .result(value: "Build status unavailable. Open Hutch to refresh.")
        }

        var parts: [String] = []

        if let failed = snapshot.failedBuilds {
            if failed > 0 {
                parts.append("\(failed) failed build\(failed == 1 ? "" : "s")")
            } else {
                parts.append("No failed builds")
            }
        }

        if let unread = snapshot.unreadInboxThreads, unread > 0 {
            parts.append("\(unread) unread thread\(unread == 1 ? "" : "s")")
        }

        if let assigned = snapshot.assignedOpenTickets, assigned > 0 {
            parts.append("\(assigned) assigned ticket\(assigned == 1 ? "" : "s")")
        }

        if parts.isEmpty {
            return .result(value: "No recent data. Open Hutch to refresh.")
        }

        return .result(value: parts.joined(separator: ". ") + ".")
    }
}

// MARK: - Shortcuts Provider

struct HutchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenWorkQueueIntent(),
            phrases: [
                "Open my work queue in \(.applicationName)",
                "Show work in \(.applicationName)"
            ],
            shortTitle: "Work Queue",
            systemImageName: "tray.full"
        )

        AppShortcut(
            intent: OpenRecentActivityIntent(),
            phrases: [
                "Open recent activity in \(.applicationName)",
                "Show activity in \(.applicationName)"
            ],
            shortTitle: "Recent Activity",
            systemImageName: "clock.arrow.circlepath"
        )

        AppShortcut(
            intent: OpenSystemStatusIntent(),
            phrases: [
                "Open system status in \(.applicationName)",
                "Show SourceHut status in \(.applicationName)"
            ],
            shortTitle: "System Status",
            systemImageName: "server.rack"
        )

        AppShortcut(
            intent: OpenPinnedResourceIntent(),
            phrases: [
                "Open \(\.$pinnedResource) in \(.applicationName)",
                "Show my pinned \(\.$pinnedResource) in \(.applicationName)"
            ],
            shortTitle: "Pinned Resource",
            systemImageName: "pin"
        )

        AppShortcut(
            intent: OpenProjectDashboardIntent(),
            phrases: [
                "Open \(\.$project) dashboard in \(.applicationName)",
                "Show project \(\.$project) in \(.applicationName)"
            ],
            shortTitle: "Project Dashboard",
            systemImageName: "square.stack.3d.up"
        )

        AppShortcut(
            intent: OpenFailedBuildsIntent(),
            phrases: [
                "Open failed builds in \(.applicationName)",
                "Show failed builds in \(.applicationName)"
            ],
            shortTitle: "Failed Builds",
            systemImageName: "exclamationmark.triangle"
        )

        AppShortcut(
            intent: OpenAssignedTicketsIntent(),
            phrases: [
                "Open assigned tickets in \(.applicationName)",
                "Show my assigned tickets in \(.applicationName)"
            ],
            shortTitle: "Assigned Tickets",
            systemImageName: "person.crop.circle.badge.checkmark"
        )

        AppShortcut(
            intent: SearchHutchIntent(),
            phrases: [
                "Search \(.applicationName)",
                "Look up something in \(.applicationName)"
            ],
            shortTitle: "Search Hutch",
            systemImageName: "magnifyingglass"
        )

        AppShortcut(
            intent: CheckSystemStatusIntent(),
            phrases: [
                "Check \(.applicationName) status",
                "Is SourceHut up in \(.applicationName)"
            ],
            shortTitle: "Check Status",
            systemImageName: "server.rack"
        )

        AppShortcut(
            intent: CheckBuildsIntent(),
            phrases: [
                "Check my \(.applicationName) builds",
                "Build status in \(.applicationName)"
            ],
            shortTitle: "Check Builds",
            systemImageName: "hammer"
        )
    }
}

// MARK: - Intent Navigator

@MainActor
@Observable
final class HutchIntentNavigator {
    static let shared = HutchIntentNavigator()
    var pendingRoute: HutchRoute?

    private init() {
        /* Singleton; external code uses `shared`. */
    }

    func open(_ route: HutchRoute) {
        pendingRoute = route
    }
}
