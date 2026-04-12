import AppIntents
import Foundation

// MARK: - Open Hutch Intent

enum HutchDestination: String, AppEnum {
    case home
    case inbox
    case builds
    case repositories
    case trackers
    case systemStatus
    case lookup

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Hutch Section")

    static var caseDisplayRepresentations: [HutchDestination: DisplayRepresentation] = [
        .home: "Home",
        .inbox: "Inbox",
        .builds: "Builds",
        .repositories: "Repositories",
        .trackers: "Trackers",
        .systemStatus: "System Status",
        .lookup: "Look Up"
    ]
}

struct OpenHutchIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Hutch"
    static var description = IntentDescription("Opens Hutch to a specific section.")
    static var openAppWhenRun = true

    @Parameter(title: "Section", default: .home)
    var destination: HutchDestination

    @MainActor
    func perform() async throws -> some IntentResult {
        HutchIntentNavigator.shared.pendingDestination = destination
        return .result()
    }
}

// MARK: - Check System Status Intent

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

// MARK: - Check Builds Intent

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
            intent: OpenHutchIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Open \(.applicationName) \(\.$destination)",
                "Show my \(.applicationName) \(\.$destination)",
                "Go to \(\.$destination) in \(.applicationName)"
            ],
            shortTitle: "Open Hutch",
            systemImageName: "house"
        )

        AppShortcut(
            intent: CheckSystemStatusIntent(),
            phrases: [
                "Check \(.applicationName) status",
                "Is SourceHut up in \(.applicationName)",
                "SourceHut status in \(.applicationName)"
            ],
            shortTitle: "Check SourceHut Status",
            systemImageName: "server.rack"
        )

        AppShortcut(
            intent: CheckBuildsIntent(),
            phrases: [
                "Check my \(.applicationName) builds",
                "How are my builds in \(.applicationName)",
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
    var pendingDestination: HutchDestination?

    private init() {}
}
