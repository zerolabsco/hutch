import SwiftUI

private struct TrackerQueryResponse: Decodable, Sendable {
    let tracker: TrackerSummary?
}

private struct TrackerACLQueryResponse: Decodable, Sendable {
    let tracker: TrackerACLQueryPayload?
}

private struct TrackerACLQueryPayload: Decodable, Sendable {
    let defaultACL: DefaultTrackerACL
    let acls: TrackerACLPage
}

private struct TrackerACLPage: Decodable, Sendable {
    let results: [TrackerACL]
    let cursor: String?
}

private struct TrackerLabelQueryResponse: Decodable, Sendable {
    let tracker: TrackerLabelQueryPayload?
}

private struct TrackerLabelQueryPayload: Decodable, Sendable {
    let labels: TrackerLabelPage
}

private struct TrackerLabelPage: Decodable, Sendable {
    let results: [TicketLabel]
    let cursor: String?
}

private struct UpdateTrackerResponse: Decodable, Sendable {
    let updateTracker: TrackerSummary
}

private struct DeleteTrackerResponse: Decodable, Sendable {
    let deleteTracker: DeletedTracker
}

private struct DeletedTracker: Decodable, Sendable {
    let id: Int
}

private struct UpdateUserACLResponse: Decodable, Sendable {
    let updateUserACL: TrackerACL
}

private struct UpdateTrackerACLResponse: Decodable, Sendable {
    let updateTrackerACL: DefaultTrackerACL
}

private struct DeleteTrackerACLResponse: Decodable, Sendable {
    let deleteACL: TrackerACL
}

private struct CreateTrackerLabelResponse: Decodable, Sendable {
    let createLabel: TicketLabel
}

private struct UpdateTrackerLabelResponse: Decodable, Sendable {
    let updateLabel: TicketLabel
}

private struct DeleteTrackerLabelResponse: Decodable, Sendable {
    let deleteLabel: TicketLabel
}

private struct TrackerUserLookupResponse: Decodable, Sendable {
    let user: UserIdPayload?
}

private struct UserIdPayload: Decodable, Sendable {
    let id: Int
}

@Observable
@MainActor
final class TrackerManagementViewModel {
    private(set) var tracker: TrackerSummary
    private(set) var acls: [TrackerACL] = []
    private(set) var defaultACL = DefaultTrackerACL(
        browse: true,
        submit: true,
        comment: true,
        edit: false,
        triage: false
    )
    private(set) var labels: [TicketLabel] = []

    private(set) var isSavingTracker = false
    private(set) var isDeletingTracker = false
    private(set) var isLoadingACLs = false
    private(set) var isSavingACL = false
    private(set) var isDeletingACL = false
    private(set) var isLoadingLabels = false
    private(set) var isSavingLabel = false
    private(set) var isDeletingLabel = false

    var error: String?
    var didDeleteTracker = false

    private let client: SRHTClient

    init(tracker: TrackerSummary, client: SRHTClient) {
        self.tracker = tracker
        self.client = client
    }

    private static let trackerQuery = """
    query tracker($rid: ID!) {
        tracker(rid: $rid) {
            id
            rid
            name
            description
            visibility
            updated
            owner { canonicalName }
        }
    }
    """

    private static let trackerACLsQuery = """
    query trackerACLs($rid: ID!, $cursor: Cursor) {
        tracker(rid: $rid) {
            defaultACL {
                browse
                submit
                comment
                edit
                triage
            }
            acls(cursor: $cursor) {
                results {
                    id
                    created
                    entity { canonicalName }
                    browse
                    submit
                    comment
                    edit
                    triage
                }
                cursor
            }
        }
    }
    """

    private static let trackerLabelsQuery = """
    query trackerLabels($rid: ID!, $cursor: Cursor) {
        tracker(rid: $rid) {
            labels(cursor: $cursor) {
                results {
                    id
                    name
                    backgroundColor
                    foregroundColor
                }
                cursor
            }
        }
    }
    """

    private static let updateTrackerMutation = """
    mutation updateTracker($id: Int!, $input: TrackerInput!) {
        updateTracker(id: $id, input: $input) {
            id
            rid
            name
            description
            visibility
            updated
            owner { canonicalName }
        }
    }
    """

    private static let deleteTrackerMutation = """
    mutation deleteTracker($id: Int!) {
        deleteTracker(id: $id) {
            id
        }
    }
    """

    private static let updateUserACLMutation = """
    mutation updateUserACL($trackerId: Int!, $userId: Int!, $input: ACLInput!) {
        updateUserACL(trackerId: $trackerId, userId: $userId, input: $input) {
            id
            created
            entity { canonicalName }
            browse
            submit
            comment
            edit
            triage
        }
    }
    """

    private static let updateTrackerACLMutation = """
    mutation updateTrackerACL($trackerId: Int!, $input: ACLInput!) {
        updateTrackerACL(trackerId: $trackerId, input: $input) {
            browse
            submit
            comment
            edit
            triage
        }
    }
    """

    private static let deleteACLMutation = """
    mutation deleteACL($id: Int!) {
        deleteACL(id: $id) {
            id
            created
            entity { canonicalName }
            browse
            submit
            comment
            edit
            triage
        }
    }
    """

    private static let createLabelMutation = """
    mutation createLabel($trackerId: Int!, $name: String!, $foregroundColor: String!, $backgroundColor: String!) {
        createLabel(trackerId: $trackerId, name: $name, foregroundColor: $foregroundColor, backgroundColor: $backgroundColor) {
            id
            name
            backgroundColor
            foregroundColor
        }
    }
    """

    private static let updateLabelMutation = """
    mutation updateLabel($id: Int!, $input: UpdateLabelInput!) {
        updateLabel(id: $id, input: $input) {
            id
            name
            backgroundColor
            foregroundColor
        }
    }
    """

    private static let deleteLabelMutation = """
    mutation deleteLabel($id: Int!) {
        deleteLabel(id: $id) {
            id
            name
            backgroundColor
            foregroundColor
        }
    }
    """

    private static let userLookupQuery = """
    query userLookup($username: String!) {
        user(username: $username) {
            id
        }
    }
    """

    func refreshTracker() async {
        do {
            let result = try await client.execute(
                service: .todo,
                query: Self.trackerQuery,
                variables: ["rid": tracker.rid],
                responseType: TrackerQueryResponse.self
            )
            if let tracker = result.tracker {
                self.tracker = tracker
            }
        } catch {
            self.error = error.userFacingMessage
        }
    }

    func updateTracker(name: String, description: String, visibility: Visibility) async -> TrackerSummary? {
        guard !isSavingTracker else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            error = "Enter a tracker name."
            return nil
        }

        isSavingTracker = true
        error = nil
        defer { isSavingTracker = false }

        var input: [String: any Sendable] = [
            "name": trimmedName,
            "visibility": visibility.rawValue
        ]
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        input["description"] = trimmedDescription.isEmpty ? "" : trimmedDescription

        do {
            let result = try await client.execute(
                service: .todo,
                query: Self.updateTrackerMutation,
                variables: [
                    "id": tracker.id,
                    "input": input
                ],
                responseType: UpdateTrackerResponse.self
            )
            tracker = result.updateTracker
            return result.updateTracker
        } catch {
            self.error = "Couldn’t update the tracker. \(error.userFacingMessage)"
            return nil
        }
    }

    func deleteTracker() async -> Bool {
        guard !isDeletingTracker else { return false }
        isDeletingTracker = true
        error = nil
        defer { isDeletingTracker = false }

        do {
            _ = try await client.execute(
                service: .todo,
                query: Self.deleteTrackerMutation,
                variables: ["id": tracker.id],
                responseType: DeleteTrackerResponse.self
            )
            didDeleteTracker = true
            return true
        } catch {
            self.error = "Couldn’t delete the tracker. \(error.userFacingMessage)"
            return false
        }
    }

    func loadACLs() async {
        guard !isLoadingACLs else { return }
        isLoadingACLs = true
        error = nil
        defer { isLoadingACLs = false }

        do {
            let result = try await client.execute(
                service: .todo,
                query: Self.trackerACLsQuery,
                variables: ["rid": tracker.rid],
                responseType: TrackerACLQueryResponse.self
            )
            defaultACL = result.tracker?.defaultACL ?? defaultACL
            acls = result.tracker?.acls.results ?? []
        } catch {
            self.error = error.userFacingMessage
        }
    }

    func updateDefaultACL(_ permissions: TrackerACLPermissions) async -> Bool {
        guard !isSavingACL else { return false }
        isSavingACL = true
        error = nil
        defer { isSavingACL = false }

        do {
            let result = try await client.execute(
                service: .todo,
                query: Self.updateTrackerACLMutation,
                variables: [
                    "trackerId": tracker.id,
                    "input": permissions.graphQLInput
                ],
                responseType: UpdateTrackerACLResponse.self
            )
            defaultACL = result.updateTrackerACL
            await loadACLs()
            return true
        } catch {
            self.error = error.userFacingMessage
            return false
        }
    }

    func addOrUpdateACL(username: String, permissions: TrackerACLPermissions) async -> Bool {
        guard !isSavingACL else { return false }
        let normalizedUsername = Self.normalizedUsername(username)
        guard !normalizedUsername.isEmpty else {
            error = "Enter a SourceHut username."
            return false
        }

        isSavingACL = true
        error = nil
        defer { isSavingACL = false }

        do {
            let userResult = try await client.execute(
                service: .todo,
                query: Self.userLookupQuery,
                variables: ["username": normalizedUsername],
                responseType: TrackerUserLookupResponse.self
            )
            guard let userId = userResult.user?.id else {
                error = "That user couldn’t be found."
                return false
            }

            let result = try await client.execute(
                service: .todo,
                query: Self.updateUserACLMutation,
                variables: [
                    "trackerId": tracker.id,
                    "userId": userId,
                    "input": permissions.graphQLInput
                ],
                responseType: UpdateUserACLResponse.self
            )
            if let index = acls.firstIndex(where: { $0.id == result.updateUserACL.id }) {
                acls[index] = result.updateUserACL
            } else {
                acls.append(result.updateUserACL)
                acls.sort { $0.entity.canonicalName.localizedCaseInsensitiveCompare($1.entity.canonicalName) == .orderedAscending }
            }
            await loadACLs()
            return true
        } catch {
            self.error = error.userFacingMessage
            return false
        }
    }

    func deleteACL(_ entry: TrackerACL) async {
        guard !isDeletingACL else { return }
        isDeletingACL = true
        error = nil
        defer { isDeletingACL = false }

        do {
            _ = try await client.execute(
                service: .todo,
                query: Self.deleteACLMutation,
                variables: ["id": entry.id],
                responseType: DeleteTrackerACLResponse.self
            )
            acls.removeAll { $0.id == entry.id }
            await loadACLs()
        } catch {
            self.error = error.userFacingMessage
        }
    }

    func loadLabels() async {
        guard !isLoadingLabels else { return }
        isLoadingLabels = true
        error = nil
        defer { isLoadingLabels = false }

        do {
            let result = try await client.execute(
                service: .todo,
                query: Self.trackerLabelsQuery,
                variables: ["rid": tracker.rid],
                responseType: TrackerLabelQueryResponse.self
            )
            labels = result.tracker?.labels.results ?? []
        } catch {
            self.error = error.userFacingMessage
        }
    }

    func createLabel(name: String, foregroundColor: String, backgroundColor: String) async -> Bool {
        guard !isSavingLabel else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            error = "Enter a label name."
            return false
        }
        guard Self.isValidHexColor(foregroundColor), Self.isValidHexColor(backgroundColor) else {
            error = "Label colors must use #RRGGBB format."
            return false
        }

        isSavingLabel = true
        error = nil
        defer { isSavingLabel = false }

        do {
            _ = try await client.execute(
                service: .todo,
                query: Self.createLabelMutation,
                variables: [
                    "trackerId": tracker.id,
                    "name": trimmedName,
                    "foregroundColor": foregroundColor,
                    "backgroundColor": backgroundColor
                ],
                responseType: CreateTrackerLabelResponse.self
            )
            await loadLabels()
            return true
        } catch {
            self.error = error.userFacingMessage
            return false
        }
    }

    func updateLabel(
        _ label: TicketLabel,
        name: String,
        foregroundColor: String,
        backgroundColor: String
    ) async -> Bool {
        guard !isSavingLabel else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            error = "Enter a label name."
            return false
        }
        guard Self.isValidHexColor(foregroundColor), Self.isValidHexColor(backgroundColor) else {
            error = "Label colors must use #RRGGBB format."
            return false
        }

        isSavingLabel = true
        error = nil
        defer { isSavingLabel = false }

        var input: [String: any Sendable] = [:]
        if trimmedName != label.name {
            input["name"] = trimmedName
        }
        if foregroundColor.caseInsensitiveCompare(label.foregroundColor) != .orderedSame {
            input["foregroundColor"] = foregroundColor
        }
        if backgroundColor.caseInsensitiveCompare(label.backgroundColor) != .orderedSame {
            input["backgroundColor"] = backgroundColor
        }

        guard !input.isEmpty else { return true }

        do {
            _ = try await client.execute(
                service: .todo,
                query: Self.updateLabelMutation,
                variables: [
                    "id": label.id,
                    "input": input
                ],
                responseType: UpdateTrackerLabelResponse.self
            )
            await loadLabels()
            return true
        } catch {
            self.error = error.userFacingMessage
            return false
        }
    }

    func deleteLabel(_ label: TicketLabel) async {
        guard !isDeletingLabel else { return }
        isDeletingLabel = true
        error = nil
        defer { isDeletingLabel = false }

        do {
            _ = try await client.execute(
                service: .todo,
                query: Self.deleteLabelMutation,
                variables: ["id": label.id],
                responseType: DeleteTrackerLabelResponse.self
            )
            labels.removeAll { $0.id == label.id }
            await loadLabels()
        } catch {
            self.error = error.userFacingMessage
        }
    }

    static func normalizedUsername(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasPrefix("~") ? String(trimmed.dropFirst()) : trimmed
    }

    static func isValidHexColor(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 7, trimmed.first == "#" else { return false }
        return trimmed.dropFirst().allSatisfy { $0.isHexDigit }
    }
}

private extension TrackerACLPermissions {
    var graphQLInput: [String: any Sendable] {
        [
            "browse": browse,
            "submit": submit,
            "comment": comment,
            "edit": edit,
            "triage": triage
        ]
    }
}

struct TrackerEditorSheet: View {
    let title: String
    let confirmationTitle: String
    let isSaving: Bool
    let error: String?
    let initialName: String
    let initialDescription: String
    let initialVisibility: Visibility
    let onSave: (String, String, Visibility) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String
    @State private var visibility: Visibility

    init(
        title: String,
        confirmationTitle: String,
        isSaving: Bool,
        error: String?,
        initialName: String,
        initialDescription: String,
        initialVisibility: Visibility,
        onSave: @escaping (String, String, Visibility) async -> Bool
    ) {
        self.title = title
        self.confirmationTitle = confirmationTitle
        self.isSaving = isSaving
        self.error = error
        self.initialName = initialName
        self.initialDescription = initialDescription
        self.initialVisibility = initialVisibility
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _description = State(initialValue: initialDescription)
        _visibility = State(initialValue: initialVisibility)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tracker Details") {
                    TextField("Tracker name", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .themedRow()
                    TextField("Short description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                        .themedRow()
                    Picker("Visibility", selection: $visibility) {
                        Text("Public").tag(Visibility.public)
                        Text("Unlisted").tag(Visibility.unlisted)
                        Text("Private").tag(Visibility.private)
                    }
                    .themedRow()
                }

                if let error, !error.isEmpty {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .themedRow()
                    }
                }
            }
            .themedList()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let didSave = await onSave(name, description, visibility)
                            if didSave {
                                dismiss()
                            }
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(confirmationTitle)
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }
}

struct TrackerACLManagementSheet: View {
    let viewModel: TrackerManagementViewModel

    @Bindable private var bindableViewModel: TrackerManagementViewModel
    @State private var editingACL: TrackerACL?
    @State private var editingDefaultACL = false
    @State private var pendingDeletion: TrackerACL?
    @State private var showCreateACL = false

    init(viewModel: TrackerManagementViewModel) {
        self.viewModel = viewModel
        self._bindableViewModel = Bindable(viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Default Access") {
                    TrackerPermissionSummary(permissions: viewModel.defaultACL.permissions)
                        .themedRow()
                    Button("Update Default ACL") {
                        editingDefaultACL = true
                    }
                    .disabled(viewModel.isSavingACL)
                    .themedRow()
                }

                Section {
                    if viewModel.isLoadingACLs {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .themedRow()
                    } else if viewModel.acls.isEmpty {
                        Text("No tracker-specific ACLs yet.")
                            .foregroundStyle(.secondary)
                            .themedRow()
                    } else {
                        ForEach(viewModel.acls) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.entity.canonicalName)
                                    .font(.subheadline.weight(.medium))
                                TrackerPermissionSummary(permissions: entry.permissions)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDeletion = entry
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    editingACL = entry
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                        .themedRow()
                    }
                } header: {
                    Text("User ACLs")
                } footer: {
                    Text("Each ACL must include all five permission flags.")
                }
            }
            .themedList()
            .navigationTitle("ACLs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateACL = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(viewModel.isSavingACL)
                }
            }
            .task {
                await viewModel.loadACLs()
            }
            .srhtErrorBanner(error: $bindableViewModel.error)
            .sheet(isPresented: $showCreateACL) {
                TrackerACLEditorSheet(
                    title: "Add ACL",
                    submitTitle: "Save",
                    isSaving: viewModel.isSavingACL,
                    error: viewModel.error,
                    initialUsername: "",
                    initialPermissions: viewModel.defaultACL.permissions
                ) { username, permissions in
                    await viewModel.addOrUpdateACL(username: username, permissions: permissions)
                }
            }
            .sheet(item: $editingACL) { entry in
                TrackerACLEditorSheet(
                    title: "Update ACL",
                    submitTitle: "Save",
                    isSaving: viewModel.isSavingACL,
                    error: viewModel.error,
                    initialUsername: entry.entity.canonicalName,
                    initialPermissions: entry.permissions
                ) { username, permissions in
                    await viewModel.addOrUpdateACL(username: username, permissions: permissions)
                }
            }
            .sheet(isPresented: $editingDefaultACL) {
                TrackerDefaultACLEditorSheet(
                    isSaving: viewModel.isSavingACL,
                    error: viewModel.error,
                    initialPermissions: viewModel.defaultACL.permissions
                ) { permissions in
                    await viewModel.updateDefaultACL(permissions)
                }
            }
            .alert("Remove Access?", isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletion = nil
                    }
                }
            )) {
                Button("Cancel", role: .cancel) {
                    // no-op: .cancel role handles alert dismissal
                }
                Button("Delete", role: .destructive) {
                    guard let pendingDeletion else { return }
                    Task {
                        await viewModel.deleteACL(pendingDeletion)
                        self.pendingDeletion = nil
                    }
                }
            } message: {
                if let pendingDeletion {
                    Text("\(pendingDeletion.entity.canonicalName) will fall back to the tracker default ACL.")
                }
            }
        }
    }
}

private struct TrackerPermissionSummary: View {
    let permissions: TrackerACLPermissions

    var body: some View {
        Text(summary)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var summary: String {
        let items = [
            permissions.browse ? "browse" : nil,
            permissions.submit ? "submit" : nil,
            permissions.comment ? "comment" : nil,
            permissions.edit ? "edit" : nil,
            permissions.triage ? "triage" : nil
        ].compactMap { $0 }
        return items.isEmpty ? "No permissions" : items.joined(separator: ", ")
    }
}

private struct TrackerACLEditorSheet: View {
    let title: String
    let submitTitle: String
    let isSaving: Bool
    let error: String?
    let initialUsername: String
    let initialPermissions: TrackerACLPermissions
    let onSave: (String, TrackerACLPermissions) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var username: String
    @State private var browse: Bool
    @State private var submit: Bool
    @State private var comment: Bool
    @State private var edit: Bool
    @State private var triage: Bool

    init(
        title: String,
        submitTitle: String,
        isSaving: Bool,
        error: String?,
        initialUsername: String,
        initialPermissions: TrackerACLPermissions,
        onSave: @escaping (String, TrackerACLPermissions) async -> Bool
    ) {
        self.title = title
        self.submitTitle = submitTitle
        self.isSaving = isSaving
        self.error = error
        self.initialUsername = initialUsername
        self.initialPermissions = initialPermissions
        self.onSave = onSave
        _username = State(initialValue: initialUsername)
        _browse = State(initialValue: initialPermissions.browse)
        _submit = State(initialValue: initialPermissions.submit)
        _comment = State(initialValue: initialPermissions.comment)
        _edit = State(initialValue: initialPermissions.edit)
        _triage = State(initialValue: initialPermissions.triage)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("User") {
                    TextField("Username or ~username", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .themedRow()
                }

                permissionSection

                if let error, !error.isEmpty {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .themedRow()
                    }
                }
            }
            .themedList()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let didSave = await onSave(username, permissions)
                            if didSave {
                                dismiss()
                            }
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(submitTitle)
                        }
                    }
                    .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }

    private var permissionSection: some View {
        Section("Permissions") {
            Toggle("Browse", isOn: $browse)
                .themedRow()
            Toggle("Submit", isOn: $submit)
                .themedRow()
            Toggle("Comment", isOn: $comment)
                .themedRow()
            Toggle("Edit", isOn: $edit)
                .themedRow()
            Toggle("Triage", isOn: $triage)
                .themedRow()
        }
    }

    private var permissions: TrackerACLPermissions {
        TrackerACLPermissions(
            browse: browse,
            submit: submit,
            comment: comment,
            edit: edit,
            triage: triage
        )
    }
}

private struct TrackerDefaultACLEditorSheet: View {
    let isSaving: Bool
    let error: String?
    let initialPermissions: TrackerACLPermissions
    let onSave: (TrackerACLPermissions) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var browse: Bool
    @State private var submit: Bool
    @State private var comment: Bool
    @State private var edit: Bool
    @State private var triage: Bool

    init(
        isSaving: Bool,
        error: String?,
        initialPermissions: TrackerACLPermissions,
        onSave: @escaping (TrackerACLPermissions) async -> Bool
    ) {
        self.isSaving = isSaving
        self.error = error
        self.initialPermissions = initialPermissions
        self.onSave = onSave
        _browse = State(initialValue: initialPermissions.browse)
        _submit = State(initialValue: initialPermissions.submit)
        _comment = State(initialValue: initialPermissions.comment)
        _edit = State(initialValue: initialPermissions.edit)
        _triage = State(initialValue: initialPermissions.triage)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Permissions") {
                    Toggle("Browse", isOn: $browse)
                        .themedRow()
                    Toggle("Submit", isOn: $submit)
                        .themedRow()
                    Toggle("Comment", isOn: $comment)
                        .themedRow()
                    Toggle("Edit", isOn: $edit)
                        .themedRow()
                    Toggle("Triage", isOn: $triage)
                        .themedRow()
                }

                if let error, !error.isEmpty {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .themedRow()
                    }
                }
            }
            .themedList()
            .navigationTitle("Default ACL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let didSave = await onSave(
                                TrackerACLPermissions(
                                    browse: browse,
                                    submit: submit,
                                    comment: comment,
                                    edit: edit,
                                    triage: triage
                                )
                            )
                            if didSave {
                                dismiss()
                            }
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
}

struct TrackerLabelManagementSheet: View {
    let viewModel: TrackerManagementViewModel

    @Bindable private var bindableViewModel: TrackerManagementViewModel
    @State private var showCreateLabel = false
    @State private var editingLabel: TicketLabel?
    @State private var pendingDeletion: TicketLabel?

    init(viewModel: TrackerManagementViewModel) {
        self.viewModel = viewModel
        self._bindableViewModel = Bindable(viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Labels are managed here and reused throughout the tracker.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .themedRow()
                }

                if viewModel.isLoadingLabels {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .themedRow()
                } else if viewModel.labels.isEmpty {
                    ContentUnavailableView(
                        "No Labels",
                        systemImage: "tag",
                        description: Text("Create labels for triage and organization.")
                    )
                    .themedRow()
                } else {
                    ForEach(viewModel.labels) { label in
                        Button {
                            editingLabel = label
                        } label: {
                            TrackerLabelManagementRow(label: label)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                editingLabel = label
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)

                            Button(role: .destructive) {
                                pendingDeletion = label
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .themedRow()
                }
            }
            .themedList()
            .navigationTitle("Labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateLabel = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(viewModel.isSavingLabel)
                }
            }
            .task {
                await viewModel.loadLabels()
            }
            .srhtErrorBanner(error: $bindableViewModel.error)
            .sheet(isPresented: $showCreateLabel) {
                TrackerLabelEditorSheet(
                    title: "New Label",
                    submitTitle: "Create",
                    isSaving: viewModel.isSavingLabel,
                    error: viewModel.error,
                    initialLabel: nil
                ) { name, foreground, background in
                    await viewModel.createLabel(
                        name: name,
                        foregroundColor: foreground,
                        backgroundColor: background
                    )
                }
            }
            .sheet(item: $editingLabel) { label in
                TrackerLabelEditorSheet(
                    title: "Update Label",
                    submitTitle: "Save",
                    isSaving: viewModel.isSavingLabel,
                    error: viewModel.error,
                    initialLabel: label
                ) { name, foreground, background in
                    await viewModel.updateLabel(
                        label,
                        name: name,
                        foregroundColor: foreground,
                        backgroundColor: background
                    )
                }
            }
            .alert("Delete Label?", isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletion = nil
                    }
                }
            )) {
                Button("Cancel", role: .cancel) {
                    // no-op: .cancel role handles alert dismissal
                }
                Button("Delete", role: .destructive) {
                    guard let pendingDeletion else { return }
                    Task {
                        await viewModel.deleteLabel(pendingDeletion)
                        self.pendingDeletion = nil
                    }
                }
            } message: {
                if let pendingDeletion {
                    Text("“\(pendingDeletion.name)” will be removed from this tracker and from any tickets using it.")
                }
            }
        }
    }
}

private struct TrackerLabelManagementRow: View {
    let label: TicketLabel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                LabelPill(label: label)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                colorSwatch(hex: label.backgroundColor, title: "Background")
                colorSwatch(hex: label.foregroundColor, title: "Text")
            }
        }
        .padding(.vertical, 4)
    }

    private func colorSwatch(hex: String, title: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: hex) ?? .clear)
                .frame(width: 10, height: 10)
                .overlay {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                }

            Text("\(title): \(hex.uppercased())")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TrackerLabelEditorSheet: View {
    let title: String
    let submitTitle: String
    let isSaving: Bool
    let error: String?
    let initialLabel: TicketLabel?
    let onSave: (String, String, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var foregroundColor: Color
    @State private var backgroundColor: Color

    init(
        title: String,
        submitTitle: String,
        isSaving: Bool,
        error: String?,
        initialLabel: TicketLabel?,
        onSave: @escaping (String, String, String) async -> Bool
    ) {
        self.title = title
        self.submitTitle = submitTitle
        self.isSaving = isSaving
        self.error = error
        self.initialLabel = initialLabel
        self.onSave = onSave
        _name = State(initialValue: initialLabel?.name ?? "")
        _foregroundColor = State(initialValue: Color(hex: initialLabel?.foregroundColor ?? "#ffffff") ?? .white)
        _backgroundColor = State(initialValue: Color(hex: initialLabel?.backgroundColor ?? "#000000") ?? .black)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Label name", text: $name)
                        .themedRow()
                    ColorPicker("Foreground", selection: $foregroundColor, supportsOpacity: false)
                        .themedRow()
                    ColorPicker("Background", selection: $backgroundColor, supportsOpacity: false)
                        .themedRow()
                }

                Section("Preview") {
                    LabelPill(
                        label: TicketLabel(
                            id: initialLabel?.id ?? -1,
                            name: name.isEmpty ? "Preview" : name,
                            backgroundColor: backgroundColor.hexString,
                            foregroundColor: foregroundColor.hexString
                        )
                    )
                    .themedRow()
                }

                if let error, !error.isEmpty {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .themedRow()
                    }
                }
            }
            .themedList()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let didSave = await onSave(
                                name,
                                foregroundColor.hexString,
                                backgroundColor.hexString
                            )
                            if didSave {
                                dismiss()
                            }
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(submitTitle)
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }
}
