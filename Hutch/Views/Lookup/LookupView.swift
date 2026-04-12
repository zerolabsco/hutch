import SwiftUI
import os

private let lookupLogger = Logger(subsystem: "net.cleberg.Hutch", category: "Lookup")

enum LookupType: String, CaseIterable, Identifiable, Codable, Sendable {
    case user = "User"
    case gitRepo = "Git Repo"
    case hgRepo = "Hg Repo"
    case mailingList = "Mailing List"
    case tracker = "Tracker"
    case buildJob = "Build Job"

    var id: String { rawValue }

    var placeholder: String {
        switch self {
        case .user:
            "~username"
        case .gitRepo, .hgRepo:
            "~username/repo-name"
        case .mailingList:
            "~username/list-name"
        case .tracker:
            "~username/tracker-name"
        case .buildJob:
            "Job ID (e.g. 123456)"
        }
    }

    var inputLabel: String {
        switch self {
        case .user:
            "Username"
        case .gitRepo, .hgRepo:
            "Repository"
        case .mailingList:
            "Mailing List"
        case .tracker:
            "Tracker"
        case .buildJob:
            "Build Job ID"
        }
    }
}

enum LookupResult: Identifiable {
    case user(User)
    case repository(RepositorySummary)
    case mailingList(InboxMailingListReference)
    case tracker(TrackerSummary)
    case buildJob(Int)

    var id: String {
        switch self {
        case .user(let user):
            "user:\(user.id)"
        case .repository(let repository):
            "repo:\(repository.id)"
        case .mailingList(let mailingList):
            "list:\(mailingList.id)"
        case .tracker(let tracker):
            "tracker:\(tracker.id)"
        case .buildJob(let jobId):
            "job:\(jobId)"
        }
    }
}

@Observable
@MainActor
final class LookupViewModel {
    var selectedType: LookupType = .user
    var inputText: String = ""
    private(set) var result: LookupResult?
    private(set) var isLooking = false
    private(set) var history: [LookupHistoryEntry]
    var error: String?

    private let client: SRHTClient
    private let appState: AppState
    private let defaults: UserDefaults

    var resultBinding: Binding<LookupResult?> {
        Binding(
            get: { self.result },
            set: { newValue in
                if newValue == nil {
                    self.result = nil
                }
            }
        )
    }

    init(client: SRHTClient, appState: AppState, defaults: UserDefaults = .standard) {
        self.client = client
        self.appState = appState
        self.defaults = defaults
        self.history = LookupHistoryStore.load(defaults: defaults)
    }

    func lookup() async {
        result = nil
        error = nil
        isLooking = true
        defer { isLooking = false }

        do {
            switch selectedType {
            case .user:
                result = try await lookupUser()
            case .gitRepo:
                result = try await lookupRepository(service: .git)
            case .hgRepo:
                result = try await lookupRepository(service: .hg)
            case .mailingList:
                result = try await lookupMailingList()
            case .tracker:
                result = try await lookupTracker()
            case .buildJob:
                result = try await lookupBuildJob()
            }
        } catch LookupError.invalidInput {
            return
        } catch {
            self.error = error.userFacingMessage
        }
    }

    func rerun(_ entry: LookupHistoryEntry) async {
        selectedType = entry.type
        inputText = entry.query
        await lookup()
    }

    func clearHistory() {
        LookupHistoryStore.clear(defaults: defaults)
        history = []
    }

    private func parseOwnerAndName() -> (owner: String, name: String)? {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("~") ? String(trimmed.dropFirst()) : trimmed
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: false)

        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            error = "Enter a value in the format ~username/name."
            return nil
        }

        return (String(parts[0]), String(parts[1]))
    }

    private func parseUsername() -> String? {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("~") ? String(trimmed.dropFirst()) : trimmed

        guard !normalized.isEmpty else {
            error = "Enter a username."
            return nil
        }

        return normalized
    }

    private func parseBuildJobId() -> Int? {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jobId = Int(trimmed) else {
            error = "Enter a numeric build job ID."
            return nil
        }

        return jobId
    }

    private func lookupUser() async throws -> LookupResult {
        guard let username = parseUsername() else { throw LookupError.invalidInput }
        recordHistory(type: .user, query: "~\(username)")

        struct Response: Decodable, Sendable {
            let user: User
        }

        let query = """
        query userLookup($username: String!) {
            user: userByName(username: $username) {
                id
                created
                updated
                canonicalName
                username
                email
                url
                location
                bio
                avatar
                pronouns
                userType
            }
        }
        """

        lookupLogger.debug("Looking up user profile for username: \(username, privacy: .public)")

        let result: Response
        do {
            result = try await client.execute(
                service: .meta,
                query: query,
                variables: ["username": username],
                responseType: Response.self
            )
        } catch {
            lookupLogger.error(
                """
                User lookup failed
                username: \(username, privacy: .public)
                query:
                \(query, privacy: .public)
                error:
                \(String(describing: error), privacy: .public)
                """
            )
            throw error
        }

        lookupLogger.debug("User lookup succeeded for username: \(username, privacy: .public)")

        return .user(result.user)
    }

    private func lookupRepository(service: SRHTService) async throws -> LookupResult {
        guard let (owner, name) = parseOwnerAndName() else { throw LookupError.invalidInput }
        let type: LookupType = service == .git ? .gitRepo : .hgRepo
        recordHistory(type: type, query: "~\(owner)/\(name)")

        let repository = try await appState.resolveRepository(owner: owner, name: name, service: service)
        let resolvedRepository = RepositorySummary(
            id: repository.id,
            rid: repository.rid,
            service: service,
            name: repository.name,
            description: repository.description,
            visibility: repository.visibility,
            updated: repository.updated,
            owner: repository.owner,
            head: repository.head
        )

        return .repository(resolvedRepository)
    }

    private func lookupMailingList() async throws -> LookupResult {
        guard let (owner, name) = parseOwnerAndName() else { throw LookupError.invalidInput }
        recordHistory(type: .mailingList, query: "~\(owner)/\(name)")

        struct Response: Decodable, Sendable {
            let user: UserWithList
        }

        struct UserWithList: Decodable, Sendable {
            let mailingList: InboxMailingListReference
        }

        let query = """
        query mailingListLookup($owner: String!, $name: String!) {
            user(username: $owner) {
                mailingList: list(name: $name) {
                    id rid name owner { canonicalName }
                }
            }
        }
        """

        let result = try await client.execute(
            service: .lists,
            query: query,
            variables: ["owner": owner, "name": name],
            responseType: Response.self
        )

        return .mailingList(result.user.mailingList)
    }

    private func lookupTracker() async throws -> LookupResult {
        guard let (owner, name) = parseOwnerAndName() else { throw LookupError.invalidInput }
        recordHistory(type: .tracker, query: "~\(owner)/\(name)")
        let tracker = try await appState.resolveTracker(owner: owner, name: name)
        return .tracker(tracker)
    }

    private func lookupBuildJob() async throws -> LookupResult {
        guard let jobId = parseBuildJobId() else { throw LookupError.invalidInput }
        recordHistory(type: .buildJob, query: String(jobId))

        struct Response: Decodable, Sendable {
            let job: JobIdOnly
        }

        struct JobIdOnly: Decodable, Sendable {
            let id: Int
        }

        let query = """
        query buildLookup($id: Int!) {
            job(id: $id) { id }
        }
        """

        _ = try await client.execute(
            service: .builds,
            query: query,
            variables: ["id": jobId],
            responseType: Response.self
        )

        return .buildJob(jobId)
    }

    private enum LookupError: Error {
        case invalidInput
    }

    private func recordHistory(type: LookupType, query: String) {
        LookupHistoryStore.record(type: type, query: query, defaults: defaults)
        history = LookupHistoryStore.load(defaults: defaults)
    }
}

struct LookupView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: LookupViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                SRHTLoadingStateView(message: "Preparing lookup…")
            }
        }
        .navigationTitle("Look Up")
        .task {
            if viewModel == nil {
                viewModel = LookupViewModel(client: appState.client, appState: appState)
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: LookupViewModel) -> some View {
        @Bindable var vm = viewModel

        Form {
            Section {
                Picker("Type", selection: $vm.selectedType) {
                    ForEach(LookupType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)

                TextField(
                    vm.selectedType.inputLabel,
                    text: $vm.inputText,
                    prompt: Text(vm.selectedType.placeholder)
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    Task { await vm.lookup() }
                }
            }

            Section {
                HStack {
                    Button("Look Up") {
                        Task { await vm.lookup() }
                    }
                    .disabled(vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isLooking)

                    if vm.isLooking {
                        Spacer()
                        ProgressView()
                    }
                }
            }

            if !vm.history.isEmpty {
                Section("Recent Searches") {
                    ForEach(vm.history) { entry in
                        Button {
                            Task { await vm.rerun(entry) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.query)
                                        .foregroundStyle(.primary)
                                    Text(entry.type.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .disabled(vm.isLooking)
                    }

                    Button("Clear History", role: .destructive) {
                        vm.clearHistory()
                    }
                    .disabled(vm.isLooking)
                }
            }
        }
        .formStyle(.grouped)
        .srhtErrorBanner(error: $vm.error)
        .sheet(item: vm.resultBinding) { result in
            NavigationStack {
                lookupDestination(result)
            }
            .navigationDestination(for: MoreRoute.self) { route in
                switch route {
                case .lookup:
                    LookupView()
                case .lists:
                    MailingListListView()
                case .pastes:
                    PasteListView()
                case .profile:
                    ProfileView()
                case .systemStatus:
                    SystemStatusView()
                case .settings:
                    SettingsView()
                case .mailingList(let mailingList):
                    MailingListDetailView(mailingList: mailingList)
                case .thread(let thread):
                    ThreadDetailView(
                        thread: thread,
                        onViewed: {
                            InboxReadStateStore.markViewed(max(Date(), thread.lastActivityAt), for: thread.id)
                            NeedsAttentionSnapshotStore.adjustUnreadInboxThreads(by: -1)
                        },
                        onMarkRead: {
                            InboxReadStateStore.markViewed(max(Date(), thread.lastActivityAt), for: thread.id)
                            NeedsAttentionSnapshotStore.adjustUnreadInboxThreads(by: -1)
                        },
                        onMarkUnread: {
                            InboxReadStateStore.markUnread(for: thread.id)
                            NeedsAttentionSnapshotStore.adjustUnreadInboxThreads(by: 1)
                        }
                    )
                case .manPageBrowser:
                    ManPageBrowserView()
                case .manPage(let url):
                    ManPageDetailView(url: url)
                }
            }
            .environment(appState)
        }
    }

    @ViewBuilder
    private func lookupDestination(_ result: LookupResult) -> some View {
        switch result {
        case .user(let user):
            UserProfileView(user: user)
        case .repository(let repository):
            RepositoryDetailView(repository: repository)
        case .mailingList(let mailingList):
            MailingListDetailView(mailingList: mailingList)
        case .tracker(let tracker):
            TicketListView(tracker: tracker)
        case .buildJob(let jobId):
            BuildDetailView(jobId: jobId)
        }
    }
}
