import SwiftUI

struct WorkView: View {
    private enum Scope: String, CaseIterable, Identifiable {
        case all = "All"
        case unread = "Unread"
        case assigned = "Assigned"

        var id: String { rawValue }
    }

    @AppStorage(AppStorageKeys.swipeActionsEnabled, store: .standard) private var swipeActionsEnabled = true
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: HomeViewModel?
    @State private var scope: Scope = .all

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading Work…")
            }
        }
        .navigationTitle("Work")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let currentUser = appState.currentUser else { return }
            await ensureViewModel(currentUser: currentUser).loadDashboard()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, let viewModel, viewModel.needsRefresh() else { return }
            Task {
                await viewModel.loadDashboard()
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: HomeViewModel) -> some View {
        List {
            headerSection(viewModel)
            scopeSection

            switch scope {
            case .all:
                allScopeContent(viewModel)
            case .unread:
                unreadSection(viewModel, compactWhenEmpty: true)
            case .assigned:
                assignedSection(viewModel)
            }
        }
        .themedList()
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadDashboard()
        }
        .connectivityOverlay(hasContent: hasWorkContent(viewModel)) {
            await viewModel.loadDashboard()
        }
    }

    private func headerSection(_ viewModel: HomeViewModel) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(title(viewModel))
                    .font(.headline)
                if workCount(viewModel) > 0 {
                    Text(summary(viewModel))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func allScopeContent(_ viewModel: HomeViewModel) -> some View {
        if unreadCount(viewModel) > 0 {
            unreadSection(viewModel, compactWhenEmpty: false)
        }

        assignedSection(viewModel)

        if workCount(viewModel) == 0 {
            Section {
                WorkCompactMessageRow(text: "Nothing to do", systemImage: "checkmark.circle")
            }
        }
    }

    private var scopeSection: some View {
        Section {
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    @ViewBuilder
    private func unreadSection(_ viewModel: HomeViewModel, compactWhenEmpty: Bool) -> some View {
        Section {
            if isLoadingUnread(viewModel) {
                WorkLoadingRow(label: "Loading unread threads")
            } else if viewModel.unreadInboxThreads.isEmpty {
                if compactWhenEmpty {
                    WorkCompactMessageRow(text: "No unread threads", systemImage: "tray")
                }
            } else {
                ForEach(viewModel.unreadInboxThreads) { thread in
                    NavigationLink {
                        ThreadDetailView(
                            thread: thread,
                            onViewed: { viewModel.markInboxThreadRead(thread) },
                            onMarkRead: { viewModel.markInboxThreadRead(thread) },
                            onMarkUnread: { viewModel.markInboxThreadUnread(thread) }
                        )
                    } label: {
                        WorkThreadRow(thread: thread)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if swipeActionsEnabled {
                            Button {
                                viewModel.markInboxThreadRead(thread)
                            } label: {
                                Label("Mark Read", systemImage: "envelope.open")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        } header: {
            Text("Unread Threads")
        } footer: {
            NavigationLink {
                MailingListListView()
            } label: {
                Label("Open mailing list workspace", systemImage: "list.bullet")
                    .font(.subheadline.weight(.medium))
            }
        }
    }

    @ViewBuilder
    private func assignedSection(_ viewModel: HomeViewModel) -> some View {
        Section {
            if viewModel.isLoadingAssignedTickets && viewModel.assignedTickets.isEmpty {
                WorkLoadingRow(label: "Loading assigned tickets")
            } else if viewModel.assignedTickets.isEmpty {
                WorkCompactMessageRow(text: "No assigned tickets", systemImage: "person.crop.circle.badge.checkmark")
            } else {
                ForEach(viewModel.assignedTickets) { ticket in
                    NavigationLink {
                        TicketDetailView(
                            ownerUsername: ticket.ownerUsername,
                            trackerName: ticket.trackerName,
                            trackerId: ticket.trackerId,
                            trackerRid: ticket.trackerRid,
                            ticketId: ticket.ticket.id
                        )
                    } label: {
                        WorkAssignedTicketRow(ticket: ticket)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if swipeActionsEnabled {
                            if ticket.ticket.status.isOpen {
                                Button {
                                    Task { await viewModel.resolveTicket(ticket) }
                                } label: {
                                    Label("Resolve", systemImage: "checkmark.circle")
                                }
                                .tint(.green)
                            } else {
                                Button {
                                    Task { await viewModel.reopenTicket(ticket) }
                                } label: {
                                    Label("Reopen", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if swipeActionsEnabled {
                            Button {
                                Task { await viewModel.unassignFromMe(ticket) }
                            } label: {
                                Label("Unassign", systemImage: "person.badge.minus")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
        } header: {
            Text("Assigned Tickets")
        } footer: {
            NavigationLink {
                TrackerListView()
            } label: {
                Label("Open tracker workspace", systemImage: "checklist")
                    .font(.subheadline.weight(.medium))
            }
        }
    }

    private func title(_ viewModel: HomeViewModel) -> String {
        let count = workCount(viewModel)
        if count == 0 {
            return "Queue clear"
        }
        return "\(count) item\(count == 1 ? "" : "s") need attention"
    }

    private func summary(_ viewModel: HomeViewModel) -> String {
        "\(unreadCount(viewModel)) unread • \(viewModel.assignedTickets.count) assigned"
    }

    private func workCount(_ viewModel: HomeViewModel) -> Int {
        unreadCount(viewModel) + viewModel.assignedTickets.count
    }

    private func unreadCount(_ viewModel: HomeViewModel) -> Int {
        viewModel.unreadInboxThreadCount ?? viewModel.unreadInboxThreads.count
    }

    private func isLoadingUnread(_ viewModel: HomeViewModel) -> Bool {
        viewModel.unreadInboxThreadCount == nil && viewModel.unreadInboxThreads.isEmpty
    }

    private func hasWorkContent(_ viewModel: HomeViewModel) -> Bool {
        workCount(viewModel) > 0
    }

    @MainActor
    private func ensureViewModel(currentUser: User) -> HomeViewModel {
        if let viewModel {
            return viewModel
        }

        let newViewModel = HomeViewModel(
            currentUser: currentUser,
            client: appState.client,
            systemStatusRepository: appState.systemStatusRepository,
            defaults: appState.accountDefaults,
            accountID: appState.activeAccountID
        )
        viewModel = newViewModel
        return newViewModel
    }
}

private struct WorkThreadRow: View {
    let thread: InboxThreadSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(thread.isUnread ? .blue : .clear)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)

                Text(thread.displaySubject)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
            }

            Text(thread.listDisplayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(thread.metadataLine)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

private struct WorkAssignedTicketRow: View {
    let ticket: HomeAssignedTicket

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("#\(ticket.ticket.id)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text(ticket.ticket.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text(ticket.ticket.status.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ticket.ticket.status.isOpen ? .orange : .secondary)
            }

            Text("\(ticket.ownerCanonicalName)/\(ticket.trackerName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(ticket.ticket.created.relativeDescription)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

private struct WorkCompactMessageRow: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 2)
    }
}

private struct WorkLoadingRow: View {
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
