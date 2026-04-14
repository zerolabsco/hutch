import SwiftUI
import WebKit

struct TicketDetailView: View {
    let ownerUsername: String
    let trackerName: String
    let trackerId: Int
    let trackerRid: String
    let ticketId: Int

    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var viewModel: TicketDetailViewModel?

    // Sheet state
    @State private var showResolveSheet = false
    @State private var showAssignSheet = false
    @State private var showLabelsSheet = false
    @State private var isOpeningTracker = false

    // Comment composer mode
    @State private var commentMode: CommentMode = .write

    private var isOwnedByCurrentUser: Bool {
        guard let currentUser = appState.currentUser else { return false }
        return normalizedUsername(currentUser.username) == normalizedUsername(ownerUsername)
    }

    private enum CommentMode: String, CaseIterable {
        case write = "Write"
        case preview = "Preview"
    }

    var body: some View {
        Group {
            if let viewModel {
                detailContent(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading ticket…")
            }
        }
        .navigationTitle("#\(ticketId)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                SRHTShareButton(url: SRHTWebURL.ticket(ownerUsername: ownerUsername, trackerName: trackerName, ticketId: ticketId), target: .ticket) {
                    Image(systemName: "square.and.arrow.up")
                }

                if let viewModel, viewModel.ticket != nil {
                    actionsMenu(viewModel)
                }
            }
        }
        .task {
            if viewModel == nil {
                let vm = TicketDetailViewModel(
                    ownerUsername: ownerUsername,
                    trackerName: trackerName,
                    trackerId: trackerId,
                    trackerRid: trackerRid,
                    ticketId: ticketId,
                    client: appState.client
                )
                viewModel = vm
                await reloadDetail(vm)
            }
        }
    }

    // MARK: - Actions Menu

    @ViewBuilder
    private func actionsMenu(_ viewModel: TicketDetailViewModel) -> some View {
        Menu {
            if let ticketURL = SRHTWebURL.ticket(ownerUsername: ownerUsername, trackerName: trackerName, ticketId: ticketId) {
                Button {
                    openURL(ticketURL)
                } label: {
                    SwiftUI.Label("Open in Browser", systemImage: "safari")
                }

                Button {
                    appState.copyToPasteboard(ticketURL.absoluteString, label: "ticket URL")
                } label: {
                    SwiftUI.Label("Copy URL", systemImage: "doc.on.doc")
                }
            }

            Button {
                appState.copyToPasteboard(String(ticketId), label: "ticket ID")
            } label: {
                SwiftUI.Label("Copy Ticket ID", systemImage: "number")
            }

            Button {
                appState.copyToPasteboard(trackerRid, label: "tracker RID")
            } label: {
                SwiftUI.Label("Copy Tracker RID", systemImage: "number")
            }

            if isOwnedByCurrentUser {
                Divider()

            if let ticket = viewModel.ticket {
                if ticket.status == .resolved {
                    Button {
                        Task {
                            await viewModel.updateStatus(status: .reported)
                        }
                    } label: {
                        SwiftUI.Label("Reopen", systemImage: "arrow.uturn.backward")
                    }
                } else {
                    Button {
                        showResolveSheet = true
                    } label: {
                        SwiftUI.Label("Resolve", systemImage: "checkmark.circle")
                    }
                }
            }

            Button {
                showAssignSheet = true
            } label: {
                SwiftUI.Label("Manage Assignees", systemImage: "person.badge.plus")
            }

            Button {
                showLabelsSheet = true
                Task { await viewModel.loadTrackerLabels() }
            } label: {
                SwiftUI.Label("Manage Labels", systemImage: "tag")
            }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Ticket actions")
        .sheet(isPresented: $showResolveSheet) {
            ResolveSheet(viewModel: viewModel, isPresented: $showResolveSheet)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAssignSheet) {
            AssignSheet(viewModel: viewModel, isPresented: $showAssignSheet)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showLabelsSheet) {
            LabelsSheet(viewModel: viewModel, isPresented: $showLabelsSheet)
                .presentationDetents([.medium])
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private func detailContent(_ viewModel: TicketDetailViewModel) -> some View {
        @Bindable var vm = viewModel

        if viewModel.isLoading, viewModel.ticket == nil {
            SRHTLoadingStateView(message: "Loading ticket…")
        } else if let error = viewModel.error, viewModel.ticket == nil {
            SRHTErrorStateView(
                title: "Couldn't Load Ticket",
                message: error,
                retryAction: { await reloadDetail(viewModel) }
            )
        } else if let ticket = viewModel.ticket {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    ticketHeader(ticket, viewModel: viewModel)

                    Divider()
                        .padding(.vertical, 12)

                    // Description
                    if let description = ticket.description, !description.isEmpty {
                        MarkdownContentView(markdown: description)
                            .padding(.horizontal)
                            .padding(.bottom, 16)

                        Divider()
                            .padding(.bottom, 12)
                    }

                    // Event timeline
                    if !viewModel.events.isEmpty {
                        Text("Activity")
                            .font(.headline)
                            .padding(.horizontal)
                            .padding(.bottom, 8)

                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(viewModel.events) { event in
                                EventRow(
                                    event: event,
                                    ticketSubmitter: viewModel.ticket?.submitter.canonicalName,
                                    ticketAssignees: viewModel.ticket?.assignees.map { $0.canonicalName }
                                )
                                if event.id != viewModel.events.last?.id {
                                    Divider()
                                        .padding(.leading, 40)
                                }
                            }
                        }

                        Divider()
                            .padding(.vertical, 12)
                    }

                    if appState.isDebugModeEnabled {
                        Divider()
                            .padding(.vertical, 12)

                        debugSection(viewModel: viewModel, ticket: ticket)
                    }

                    commentInput(viewModel)
                }
            }
            .task(id: ticket.id) {
                RecentActivityStore.recordTicket(
                    ownerUsername: ownerUsername,
                    trackerName: trackerName,
                    ticketId: ticket.id,
                    title: ticket.title,
                    defaults: appState.accountDefaults
                )
            }
            .srhtErrorBanner(error: $vm.error)
            .refreshable {
                await reloadDetail(viewModel)
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func ticketHeader(_ ticket: TicketDetail, viewModel: TicketDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(ticket.title)
                    .font(.title3.weight(.semibold))

                Spacer(minLength: 12)

                if isOwnedByCurrentUser {
                    assignToMeButton(ticket: ticket, viewModel: viewModel)
                }
            }

            HStack(spacing: 8) {
                TicketStatusIcon(status: ticket.status)
                Text(ticket.status.displayName)
                    .font(.subheadline.weight(.medium))

                if ticket.status == .resolved, let resolution = ticket.resolution {
                    Text("(\(resolution.displayName))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 4) {
                Text("Opened by")
                    .foregroundStyle(.secondary)
                Text(ticket.submitter.canonicalName)
                    .fontWeight(.medium)
                Text(ticket.created.relativeDescription)
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)

            Button {
                openTracker()
            } label: {
                HStack(spacing: 6) {
                    Label("\(ownerUsername)/\(trackerName)", systemImage: "checklist")
                        .font(.caption.weight(.medium))
                    if isOpeningTracker {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isOpeningTracker)

            if !ticket.assignees.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(ticket.assignees.map(\.canonicalName).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !ticket.labels.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(ticket.labels) { label in
                        LabelPill(label: label)
                    }
                }
            }
        }
        .padding()
    }

    @ViewBuilder
    private func assignToMeButton(ticket: TicketDetail, viewModel: TicketDetailViewModel) -> some View {
        if let currentUser = appState.currentUser {
            let isAssignedToCurrentUser = ticket.assignees.contains {
                TicketDetailViewModel.matchesAssignee($0, user: currentUser)
            }

            if isAssignedToCurrentUser {
                Label("Assigned to you", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemFill), in: Capsule())
            } else {
                Button {
                    Task {
                        await viewModel.assignToCurrentUser(currentUser)
                    }
                } label: {
                    if viewModel.isPerformingAction {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 88)
                    } else {
                        Text("Assign to Me")
                            .font(.caption.weight(.semibold))
                            .frame(minWidth: 88)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.isPerformingAction)
            }
        }
    }

    // MARK: - Comment Input

    @ViewBuilder
    private func commentInput(_ viewModel: TicketDetailViewModel) -> some View {
        @Bindable var vm = viewModel

        VStack(alignment: .leading, spacing: 8) {
            Text("New Comment")
                .font(.headline)

            Picker("Mode", selection: $commentMode) {
                ForEach(CommentMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if commentMode == .write {
                TextField("Write your comment…", text: $vm.commentText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...8)
            } else {
                // Markdown preview
                if viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Nothing to preview")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    MarkdownContentView(markdown: viewModel.commentText)
                        .frame(minHeight: 80, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            HStack {
                Spacer()
                Button {
                    Task { await viewModel.submitComment() }
                } label: {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Post Comment")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSubmitting)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func debugSection(viewModel: TicketDetailViewModel, ticket: TicketDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Debug")
                .font(.headline)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                DebugTextBlock(
                    title: "Diagnostics",
                    content: """
                    ticketId: \(ticket.id)
                    trackerId: \(trackerId)
                    trackerRid: \(trackerRid)
                    status: \(ticket.status.rawValue)
                    events: \(viewModel.events.count)
                    url: \(SRHTWebURL.ticket(ownerUsername: ownerUsername, trackerName: trackerName, ticketId: ticket.id)?.absoluteString ?? "unavailable")
                    """
                )

                if let rawTicketResponse = viewModel.rawTicketResponse {
                    DebugTextBlock(title: "Raw Response", content: rawTicketResponse)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    private func normalizedUsername(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("~") ? String(trimmed.dropFirst()) : trimmed
    }

    private func openTracker() {
        guard !isOpeningTracker else { return }
        isOpeningTracker = true
        Task {
            defer { isOpeningTracker = false }
            do {
                let tracker = try await appState.resolveTracker(owner: ownerUsername, name: trackerName)
                appState.navigateToTracker(tracker)
            } catch {
                appState.presentTicketDeepLinkError()
            }
        }
    }

    private func reloadDetail(_ viewModel: TicketDetailViewModel) async {
        if appState.isDebugModeEnabled {
            await viewModel.loadTicketWithDebugCapture()
        } else {
            await viewModel.loadTicket()
        }
    }
}

// MARK: - Self-Sizing Markdown Web View

/// Renders markdown as HTML in a WKWebView that auto-sizes its height to
/// fit the rendered content. Reuses the same `markdownToHTML` converter and
/// styling as the README renderer.
private struct MarkdownContentView: View {
    let markdown: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var renderedHTML: String?

    var body: some View {
        Group {
            if let renderedHTML {
                HTMLWebView(
                    html: renderedHTML,
                    colorScheme: colorScheme,
                    style: .commentPreview
                )
            } else {
                SRHTLoadingStateView(message: "Preparing content…")
                    .frame(minHeight: 80)
            }
        }
        .task(id: markdown) {
            let html = await Task.detached(priority: .userInitiated) {
                markdownToHTML(markdown)
            }.value
            guard !Task.isCancelled else { return }
            renderedHTML = html
        }
    }
}

// MARK: - Event Row

private struct EventRow: View {
    let event: TicketEvent
    let ticketSubmitter: String?
    let ticketAssignees: [String]?
    @State private var isShowingSystemStatusInfo = false

    var body: some View {
        ForEach(event.changes) { change in
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon(for: change))
                    .foregroundStyle(color(for: change))
                    .frame(width: 24)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if kind(for: change) == .comment {
                            Text(change.author?.canonicalName ?? "")
                                .font(.subheadline.weight(.medium))
                        } else {
                            let descriptionText = description(for: change, in: event, ticketSubmitter: ticketSubmitter, ticketAssignees: ticketAssignees)
                            if descriptionText.hasPrefix("System") {
                                HStack(spacing: 4) {
                                    Text(descriptionText)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Button {
                                        isShowingSystemStatusInfo = true
                                    } label: {
                                        Image(systemName: "info.circle")
                                            .foregroundStyle(.gray)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                Text(descriptionText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(event.created.relativeDescription)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if kind(for: change) == .comment, let text = change.text {
                        MarkdownContentView(markdown: text)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .alert("System Status Change", isPresented: $isShowingSystemStatusInfo) {
                Button("OK", role: .cancel) {
                    // Alert dismissal is implicit; no additional action required.
                }
            } message: {
                Text("This status change was recorded automatically or without a named user attached to the event.")
            }
        }
    }

    private func description(for change: EventChange, in event: TicketEvent, ticketSubmitter: String? = nil, ticketAssignees: [String]? = nil) -> String {
        let eventKind = kind(for: change)
        let authorName: String

        if let commentAuthor = event.changes.first(where: {
            kind(for: $0) == .comment && $0.author != nil
        })?.author?.canonicalName {
            authorName = commentAuthor
        } else {
            switch eventKind {
            case .created:
                authorName = change.author?.canonicalName ?? ticketSubmitter ?? "Someone"
            case .statusChange:
                authorName = "System"
            case .labelAdded, .labelRemoved, .labelUpdated:
                authorName = change.labeler?.canonicalName ?? "Someone"
            case .assigned, .unassigned:
                authorName = change.assigner?.canonicalName ?? "Someone"
            case .comment:
                authorName = change.author?.canonicalName ?? "Someone"
            case .ticketMention, .userMention:
                authorName = change.author?.canonicalName
                    ?? change.assigner?.canonicalName
                    ?? change.labeler?.canonicalName
                    ?? "Someone"
            case .unknown:
                authorName = change.author?.canonicalName
                    ?? change.assigner?.canonicalName
                    ?? change.labeler?.canonicalName
                    ?? change.assignee?.canonicalName
                    ?? change.mentioned?.canonicalName
                    ?? ticketAssignees?.first
                    ?? "Someone"
            }
        }

        switch eventKind {
        case .statusChange:
            let oldStatus = change.oldStatus?.displayName ?? "unknown"
            let newStatus = change.newStatus?.displayName ?? "unknown"
            return "\(authorName) changed status from \(oldStatus) to \(newStatus)"
        case .labelUpdated, .labelAdded:
            let labelName = change.label?.name ?? "a label"
            let verb = eventKind == .labelAdded ? "added" : "updated"
            return "\(authorName) \(verb) label \"\(labelName)\""
        case .labelRemoved:
            let labelName = change.label?.name ?? "a label"
            return "\(authorName) removed label \"\(labelName)\""
        case .assigned:
            let assigneeName = change.assignee?.canonicalName ?? "someone"
            return "\(authorName) assigned \(assigneeName)"
        case .unassigned:
            let assigneeName = change.assignee?.canonicalName ?? "someone"
            return "\(authorName) unassigned \(assigneeName)"
        case .ticketMention:
            if let ticketId = change.mentioned?.id {
                return "\(authorName) mentioned ticket #\(ticketId)"
            }
            return "\(authorName) mentioned another ticket"
        case .userMention:
            let user = change.mentioned?.canonicalName ?? "someone"
            return "\(authorName) mentioned \(user)"
        case .created:
            return "\(authorName) opened this ticket"
        case .comment:
            return "\(authorName) commented"
        case .unknown:
            return "\(authorName) updated this ticket"
        }
    }

    private func icon(for change: EventChange) -> String {
        switch kind(for: change) {
        case .comment:
            "text.bubble"
        case .statusChange:
            "arrow.triangle.2.circlepath"
        case .labelAdded, .labelRemoved, .labelUpdated:
            "tag"
        case .assigned:
            "person.badge.plus"
        case .unassigned:
            "person.badge.minus"
        case .ticketMention, .userMention:
            "at"
        case .created:
            "plus.circle"
        case .unknown:
            "circle.fill"
        }
    }

    private func color(for change: EventChange) -> Color {
        switch kind(for: change) {
        case .comment:
            .blue
        case .statusChange:
            change.newStatus == .resolved ? .green : .orange
        case .labelAdded, .labelRemoved, .labelUpdated:
            .purple
        case .assigned, .unassigned:
            .cyan
        case .ticketMention, .userMention:
            .indigo
        case .created:
            .green
        case .unknown:
            .gray
        }
    }

    private func kind(for change: EventChange) -> EventKind {
        switch change.eventType {
        case "COMMENT", "Comment":
            .comment
        case "STATUS_CHANGE", "StatusChange":
            .statusChange
        case "LABEL_UPDATE", "LabelUpdate":
            .labelUpdated
        case "LABEL_ADDED", "LabelAdded":
            .labelAdded
        case "LABEL_REMOVED", "LabelRemoved":
            .labelRemoved
        case "ASSIGNMENT", "Assignment", "ASSIGNED_USER", "AssignedUser":
            .assigned
        case "UNASSIGNED_USER", "UnassignedUser":
            .unassigned
        case "TICKET_MENTION", "TicketMention":
            .ticketMention
        case "USER_MENTION", "UserMention":
            .userMention
        case "CREATED", "Created":
            .created
        default:
            .unknown
        }
    }

    private enum EventKind: Equatable {
        case comment
        case statusChange
        case labelUpdated
        case labelAdded
        case labelRemoved
        case assigned
        case unassigned
        case ticketMention
        case userMention
        case created
        case unknown
    }
}

// MARK: - Resolve Sheet

private struct ResolveSheet: View {
    let viewModel: TicketDetailViewModel
    @Binding var isPresented: Bool
    @State private var selectedResolution: TicketResolution = .fixed

    private static let resolutionOptions: [TicketResolution] = [
        .closed, .fixed, .implemented, .wontFix,
        .byDesign, .invalid, .duplicate, .notOurBug
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Resolution") {
                    Picker("Resolution", selection: $selectedResolution) {
                        ForEach(Self.resolutionOptions, id: \.self) { resolution in
                            Text(resolution.displayName).tag(resolution)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .themedRow()
                }
            }
            .themedList()
            .navigationTitle("Resolve Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mark Resolved") {
                        Task {
                            await viewModel.updateStatus(
                                status: .resolved,
                                resolution: selectedResolution
                            )
                            if viewModel.error == nil {
                                isPresented = false
                            }
                        }
                    }
                    .disabled(viewModel.isPerformingAction)
                }
            }
            .overlay {
                if viewModel.isPerformingAction {
                    ProgressView()
                }
            }
        }
    }
}

// MARK: - Assign Sheet

private struct AssignSheet: View {
    let viewModel: TicketDetailViewModel
    @Binding var isPresented: Bool
    @State private var username = ""

    var body: some View {
        NavigationStack {
            Form {
                // Current assignees with remove buttons
                if let ticket = viewModel.ticket, !ticket.assignees.isEmpty {
                    Section("Current Assignees") {
                        ForEach(ticket.assignees, id: \.canonicalName) { assignee in
                            HStack {
                                Text(assignee.canonicalName)
                                Spacer()
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.unassignUser(
                                            username: assignee.canonicalName
                                        )
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .themedRow()
                    }
                }

                Section("Add Assignee") {
                    TextField("Username or ~username", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .themedRow()

                    Button("Add Assignee") {
                        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        Task {
                            await viewModel.assignUser(username: name)
                            username = ""
                        }
                    }
                    .disabled(
                        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || viewModel.isPerformingAction
                    )
                    .themedRow()
                }
            }
            .themedList()
            .navigationTitle("Assignees")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
            .overlay {
                if viewModel.isPerformingAction {
                    ProgressView()
                }
            }
        }
    }
}

// MARK: - Labels Sheet

private struct LabelsSheet: View {
    let viewModel: TicketDetailViewModel
    @Binding var isPresented: Bool
    @State private var showCreateLabel = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.trackerLabels.isEmpty {
                    if viewModel.isPerformingAction {
                        ProgressView()
                    } else {
                        ContentUnavailableView(
                            "No Labels",
                            systemImage: "tag",
                            description: Text("This tracker has no labels defined.")
                        )
                    }
                } else {
                    List {
                        ForEach(viewModel.trackerLabels) { label in
                            LabelToggleRow(
                                label: label,
                                isApplied: viewModel.ticket?.labels.contains(where: { $0.id == label.id }) ?? false,
                                isLoading: viewModel.isPerformingAction
                            ) { shouldApply in
                                Task {
                                    if shouldApply {
                                        await viewModel.labelTicket(labelId: label.id)
                                    } else {
                                        await viewModel.unlabelTicket(labelId: label.id)
                                    }
                                }
                            }
                        }
                        .themedRow()
                    }
                    .themedList()
                }
            }
            .navigationTitle("Labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { isPresented = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateLabel = true
                    } label: {
                        SwiftUI.Label("New Label", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateLabel) {
                CreateLabelSheet(viewModel: viewModel, isPresented: $showCreateLabel)
                    .presentationDetents([.medium])
            }
        }
    }
}

// MARK: - Create Label Sheet

private struct CreateLabelSheet: View {
    let viewModel: TicketDetailViewModel
    @Binding var isPresented: Bool
    @State private var labelName = ""
    @State private var backgroundColor = Color.blue
    @State private var foregroundColor = Color.white

    var body: some View {
        NavigationStack {
            Form {
                Section("Label Details") {
                    TextField("Label name", text: $labelName)
                        .autocorrectionDisabled()
                        .themedRow()
                }

                Section("Colors") {
                    ColorPicker("Background color", selection: $backgroundColor, supportsOpacity: false)
                        .themedRow()
                    ColorPicker("Text color", selection: $foregroundColor, supportsOpacity: false)
                        .themedRow()
                }

                Section("Preview") {
                    HStack {
                        Spacer()
                        Text(labelName.isEmpty ? "Label" : labelName)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(backgroundColor)
                            .foregroundStyle(foregroundColor)
                            .clipShape(Capsule())
                        Spacer()
                    }
                    .themedRow()
                }
            }
            .themedList()
            .navigationTitle("New Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Label") {
                        Task {
                            await viewModel.createLabel(
                                name: labelName.trimmingCharacters(in: .whitespacesAndNewlines),
                                backgroundColor: backgroundColor.hexString,
                                foregroundColor: foregroundColor.hexString
                            )
                            if viewModel.error == nil {
                                isPresented = false
                            }
                        }
                    }
                    .disabled(
                        labelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || viewModel.isPerformingAction
                    )
                }
            }
            .overlay {
                if viewModel.isPerformingAction {
                    ProgressView()
                }
            }
        }
    }
}

private struct LabelToggleRow: View {
    let label: TicketLabel
    let isApplied: Bool
    let isLoading: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isApplied)
        } label: {
            HStack {
                LabelPill(label: label)
                Spacer()
                if isApplied {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
        .disabled(isLoading)
    }
}
