import Foundation

// MARK: - Enums

/// Status of a build job.
enum JobStatus: String, Codable, Sendable {
    case pending = "PENDING"
    case queued = "QUEUED"
    case running = "RUNNING"
    case success = "SUCCESS"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
    case timeout = "TIMEOUT"

    /// Whether the job can be cancelled.
    var isCancellable: Bool {
        switch self {
        case .pending, .queued, .running: true
        default: false
        }
    }
}

/// Status of a single build task within a job.
enum TaskStatus: String, Codable, Sendable {
    case pending = "PENDING"
    case running = "RUNNING"
    case success = "SUCCESS"
    case failed = "FAILED"
    case skipped = "SKIPPED"
}

// MARK: - Build Task

/// A single task within a build job.
struct BuildTask: Codable, Sendable, Identifiable {
    private(set) var ordinal: Int?
    let name: String
    let status: TaskStatus
    let log: BuildLog?

    var id: String {
        if let ordinal {
            return "\(ordinal):\(name)"
        }
        return [name, log?.fullURL, status.rawValue]
            .compactMap { $0 }
            .joined(separator: "::")
    }

    var logCacheKey: String {
        id
    }

    func withOrdinal(_ ordinal: Int) -> BuildTask {
        var task = self
        task.ordinal = ordinal
        return task
    }

    private enum CodingKeys: String, CodingKey {
        case name, status, log
    }
}

// MARK: - Job Summary (for list view)

/// Lightweight job model matching the fields returned by the jobs list query.
struct JobSummary: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let created: Date
    let updated: Date
    let status: JobStatus
    let note: String?
    let tags: [String]
    let visibility: Visibility?
    let image: String?
    let tasks: [JobTaskSummary]

    /// Number of completed (success) tasks.
    var completedTaskCount: Int {
        tasks.filter { $0.status == .success }.count
    }

    /// Display label: note if available, otherwise tags joined.
    var displayLabel: String {
        if let note, !note.isEmpty {
            return note
        }
        if !tags.isEmpty {
            return tags.joined(separator: ", ")
        }
        return "Job #\(id)"
    }
}

/// Minimal task info for the list query.
struct JobTaskSummary: Codable, Sendable, Hashable {
    let name: String
    let status: TaskStatus
}

// MARK: - Job Detail (for detail view)

/// Full job model with all fields for the detail view.
struct JobDetail: Codable, Sendable {
    let id: Int
    let created: Date
    let updated: Date
    let status: JobStatus
    let note: String?
    let tags: [String]
    let visibility: Visibility?
    let image: String?
    let manifest: String?
    var tasks: [BuildTask]
    let log: BuildLog?
    let owner: Entity
}

/// The log associated with a build job.
struct BuildLog: Codable, Sendable {
    let fullURL: String
}

// MARK: - Job Group

/// A group of related build jobs.
struct JobGroup: Codable, Sendable, Identifiable {
    let id: Int
    let created: Date
    let note: String?
    let jobs: [JobSummary]
}
