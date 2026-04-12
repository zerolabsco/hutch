import Foundation

enum StatusLevel: String, Codable, Sendable {
    case operational
    case degraded
    case majorOutage
    case maintenance
    case unknown

    var displayName: String {
        switch self {
        case .operational:
            "Operational"
        case .degraded:
            "Degraded"
        case .majorOutage:
            "Major outage"
        case .maintenance:
            "Maintenance"
        case .unknown:
            "Unknown"
        }
    }

    var requiresAttention: Bool {
        switch self {
        case .degraded, .majorOutage, .maintenance:
            true
        case .operational, .unknown:
            false
        }
    }
}

struct StatusServiceState: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let slug: String?
    let status: StatusLevel
    let description: String?
}

struct StatusIncident: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let summary: String?
    let url: URL?
    let publishedAt: Date
    let updatedAt: Date?
    let isActive: Bool?
}

struct SystemStatusSnapshot: Hashable, Codable, Sendable {
    let services: [StatusServiceState]
    let activeIncidents: [StatusIncident]
    let lastUpdated: Date

    var disruptedServices: [StatusServiceState] {
        services.filter { $0.status.requiresAttention }
    }

    var hasDisruption: Bool {
        !disruptedServices.isEmpty
    }

    var overallStatusText: String {
        hasDisruption ? "Experiencing disruptions" : "All monitored services operational"
    }

    var bannerSummary: String {
        if disruptedServices.count == 1, let service = disruptedServices.first {
            return "\(service.name) disrupted"
        }
        if disruptedServices.count > 1 {
            return "\(disruptedServices.count) services disrupted"
        }
        return "SourceHut service disruption"
    }
}

struct SystemStatusPageData: Sendable {
    let snapshot: SystemStatusSnapshot
    let recentIncidents: [StatusIncident]
}
