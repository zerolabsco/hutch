import PhotosUI
import SwiftUI

private let profileBioMarkdownOptions = AttributedString.MarkdownParsingOptions(
    interpretedSyntax: .inlineOnlyPreservingWhitespace
)

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(AppStorageKeys.contributionGraphsEnabled) private var contributionGraphsEnabled = true
    @State private var viewModel: SettingsViewModel?
    @State private var contributionViewModel: UserProfileViewModel?
    @State private var pendingDestructiveAction: ProfileDestructiveAction?

    var body: some View {
        Group {
            if let viewModel {
                profileContent(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading profile…")
            }
        }
        .navigationTitle("Profile")
        .task {
            if viewModel == nil {
                let vm = SettingsViewModel(client: appState.client)
                viewModel = vm
                await vm.loadProfile()
            }
        }
        .task(id: contributionGraphsEnabled ? appState.currentUser?.canonicalName ?? "" : "contributions-disabled") {
            guard contributionGraphsEnabled, let currentUser = appState.currentUser else { return }

            let owner = currentUser.canonicalName.hasPrefix("~")
                ? String(currentUser.canonicalName.dropFirst())
                : currentUser.canonicalName
            let actor = currentUser.canonicalName.hasPrefix("~") ? currentUser.canonicalName : "~\(currentUser.canonicalName)"

            let vm: UserProfileViewModel
            if let existingViewModel = contributionViewModel,
               existingViewModel.actor == actor,
               existingViewModel.ownerUsername == owner {
                vm = existingViewModel
            } else {
                let newViewModel = UserProfileViewModel(
                    ownerUsername: owner,
                    actor: actor,
                    client: appState.client,
                    statsService: HutchStatsService(
                        configuration: appState.configuration,
                        currentActor: appState.currentUser?.canonicalName
                    )
                )
                contributionViewModel = newViewModel
                vm = newViewModel
            }

            await vm.loadContributions()
        }
    }

    @ViewBuilder
    private func profileContent(_ viewModel: SettingsViewModel) -> some View {
        @Bindable var vm = viewModel

        Form {
            if let profile = viewModel.profile {
                profileSection(profile, viewModel: viewModel)

                if contributionGraphsEnabled, let contributionViewModel {
                    Section {
                        ContributionProfileCard(
                            actor: contributionViewModel.actor,
                            weeks: contributionViewModel.contributionCalendar.map {
                                ContributionCalendarLayout.weekColumns(from: $0.days)
                            } ?? [],
                            stats: contributionViewModel.contributionStats,
                            isLoading: contributionViewModel.isLoadingContributions,
                            error: contributionViewModel.contributionsError ?? contributionViewModel.contributionStatusText,
                            isIndexedButEmpty: contributionViewModel.isContributionActivityIndexedButEmpty
                        )
                    }
                }

                sshKeysSection(viewModel)
                pgpKeysSection(viewModel)
                patSection(viewModel)
            }
        }
        .themedList()
        .overlay {
            if viewModel.isLoading, viewModel.profile == nil {
                SRHTLoadingStateView(message: "Loading profile…")
            } else if let error = viewModel.error, viewModel.profile == nil {
                SRHTErrorStateView(
                    title: "Couldn't Load Profile",
                    message: error,
                    retryAction: { await viewModel.loadProfile() }
                )
            }
        }
        .sheet(isPresented: $vm.isEditingProfile) {
            if let profile = viewModel.profile {
                EditProfileSheet(profile: profile, viewModel: viewModel)
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil && viewModel.profile != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.error = nil
                }
            }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            if let error = viewModel.error {
                Text(error)
            }
        }
        .alert(
            pendingDestructiveAction?.title ?? "",
            isPresented: Binding(
                get: { pendingDestructiveAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDestructiveAction = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {}
            Button(pendingDestructiveAction?.confirmationLabel ?? "Confirm", role: .destructive) {
                guard let action = pendingDestructiveAction else { return }
                pendingDestructiveAction = nil
                Task {
                    switch action {
                    case .deleteSSHKey(let key):
                        await viewModel.deleteSSHKey(key)
                    case .deletePGPKey(let key):
                        await viewModel.deletePGPKey(key)
                    }
                }
            }
        } message: {
            if let pendingDestructiveAction {
                Text(pendingDestructiveAction.message)
            }
        }
        .refreshable {
            await viewModel.loadProfile()
        }
    }

    @ViewBuilder
    private func profileSection(_ profile: UserProfile, viewModel: SettingsViewModel) -> some View {
        Section("Profile") {
            HStack(spacing: 12) {
                AsyncImage(url: profile.avatar.flatMap { URL(string: $0) }) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.canonicalName)
                        .font(.headline)
                    Text(profile.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let userType = profile.userType {
                        Text(userType.capitalized)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 4)

            if let bio = profile.bio, !bio.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bio")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProfileBioView(markdown: bio)
                }
            }

            if let location = profile.location, !location.isEmpty {
                LabeledContent("Location", value: location)
            }

            if let url = profile.url, !url.isEmpty {
                LabeledContent("URL", value: url)
            }

            if let status = profile.paymentStatus {
                LabeledContent("Payment", value: status.capitalized)
            }

            if let sub = profile.subscription {
                if let status = sub.status {
                    LabeledContent("Subscription", value: status.capitalized)
                }
                if let interval = sub.interval {
                    LabeledContent("Interval", value: interval.capitalized)
                }
            }

            Button("Edit Profile") {
                viewModel.isEditingProfile = true
            }

            SRHTShareButton(url: SRHTWebURL.profile(canonicalName: profile.canonicalName), target: .profile) {
                SwiftUI.Label("Share Profile", systemImage: "square.and.arrow.up")
            }
        }
    }

    @ViewBuilder
    private func sshKeysSection(_ viewModel: SettingsViewModel) -> some View {
        @Bindable var vm = viewModel

        Section {
            ForEach(viewModel.sshKeys) { key in
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.fingerprint)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack {
                        if let comment = key.comment, !comment.isEmpty {
                            Text(comment)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(key.created.relativeDescription)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if let lastUsed = key.lastUsed {
                        Text("Last used \(lastUsed.relativeDescription)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) {
                        pendingDestructiveAction = .deleteSSHKey(key)
                    }
                }
            }

            if viewModel.isAddingSSHKey {
                TextField("Paste SSH public key", text: $vm.newSSHKey, axis: .vertical)
                    .font(.caption.monospaced())
                    .lineLimit(3...6)

                HStack {
                    Button("Cancel") {
                        viewModel.isAddingSSHKey = false
                        viewModel.newSSHKey = ""
                    }
                    Spacer()
                    Button("Add") {
                        Task { await viewModel.addSSHKey() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.newSSHKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Button {
                    viewModel.isAddingSSHKey = true
                } label: {
                    SwiftUI.Label("Add SSH Key", systemImage: "key")
                }
            }
        } header: {
            Text("SSH Keys")
        } footer: {
            Text("\(viewModel.sshKeys.count) key\(viewModel.sshKeys.count == 1 ? "" : "s")")
        }
    }

    @ViewBuilder
    private func pgpKeysSection(_ viewModel: SettingsViewModel) -> some View {
        @Bindable var vm = viewModel

        Section {
            ForEach(viewModel.pgpKeys) { key in
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.fingerprint)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(key.created.relativeDescription)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) {
                        pendingDestructiveAction = .deletePGPKey(key)
                    }
                }
            }

            if viewModel.isAddingPGPKey {
                TextField("Paste PGP public key", text: $vm.newPGPKey, axis: .vertical)
                    .font(.caption.monospaced())
                    .lineLimit(3...6)

                HStack {
                    Button("Cancel") {
                        viewModel.isAddingPGPKey = false
                        viewModel.newPGPKey = ""
                    }
                    Spacer()
                    Button("Add") {
                        Task { await viewModel.addPGPKey() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.newPGPKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Button {
                    viewModel.isAddingPGPKey = true
                } label: {
                    SwiftUI.Label("Add PGP Key", systemImage: "key.fill")
                }
            }
        } header: {
            Text("PGP Keys")
        } footer: {
            Text("\(viewModel.pgpKeys.count) key\(viewModel.pgpKeys.count == 1 ? "" : "s")")
        }
    }

    @ViewBuilder
    private func patSection(_ viewModel: SettingsViewModel) -> some View {
        Section {
            if viewModel.isLoadingPATs {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if viewModel.personalAccessTokens.isEmpty {
                Button("Load Tokens") {
                    Task { await viewModel.loadPersonalAccessTokens() }
                }
            } else {
                ForEach(viewModel.personalAccessTokens) { token in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(token.comment ?? "Token #\(token.id)")
                                .font(.subheadline)
                            Spacer()
                        }

                        HStack(spacing: 12) {
                            Text("Issued \(token.issued.relativeDescription)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            if let expires = token.expires {
                                Text("Expires \(expires.relativeDescription)")
                                    .font(.caption2)
                                    .foregroundStyle(expires < Date.now ? .red : .secondary)
                            }
                        }

                        if let grants = token.grants, !grants.isEmpty {
                            Text(grants)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        } header: {
            Text("Personal Access Tokens")
        } footer: {
            if !viewModel.personalAccessTokens.isEmpty {
                Text("\(viewModel.personalAccessTokens.count) token\(viewModel.personalAccessTokens.count == 1 ? "" : "s")")
            }
        }
    }
}

private struct ProfileBioView: View {
    let markdown: String

    var body: some View {
        Text(profileBioAttributedString(markdown))
            .frame(maxWidth: .infinity, alignment: .leading)
            .tint(.accentColor)
            .textSelection(.enabled)
    }
}

func profileBioAttributedString(_ markdown: String) -> AttributedString {
    guard let attributed = try? AttributedString(
        markdown: markdown,
        options: profileBioMarkdownOptions
    ) else {
        return AttributedString(markdown)
    }
    return attributed
}

private struct EditProfileSheet: View {
    let profile: UserProfile
    let viewModel: SettingsViewModel

    @State private var email: String
    @State private var url: String
    @State private var location: String
    @State private var bio: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarPreview: UIImage?
    @State private var isShowingRemoveAvatarConfirmation = false

    @Environment(\.dismiss) private var dismiss

    init(profile: UserProfile, viewModel: SettingsViewModel) {
        self.profile = profile
        self.viewModel = viewModel
        _email = State(initialValue: profile.email)
        _url = State(initialValue: profile.url ?? "")
        _location = State(initialValue: profile.location ?? "")
        _bio = State(initialValue: profile.bio ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Group {
                                    if let avatarPreview {
                                        Image(uiImage: avatarPreview)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        AsyncImage(url: profile.avatar.flatMap { URL(string: $0) }) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                            default:
                                                Image(systemName: "person.crop.circle.fill")
                                                    .resizable()
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(.secondary.opacity(0.3), lineWidth: 1)
                                )
                            }

                            Text("Tap to change avatar")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if viewModel.isUploadingAvatar {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)

                    if profile.avatar != nil || avatarPreview != nil {
                        HStack {
                            Spacer()
                            Button(role: .destructive) {
                                isShowingRemoveAvatarConfirmation = true
                            } label: {
                                Text("Remove Avatar")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.isUploadingAvatar)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }

                Section("Edit Profile") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Enter email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Enter URL", text: $url)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Enter location", text: $location)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bio")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Enter bio", text: $bio, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        avatarPreview = image
                        if let jpegData = image.jpegData(compressionQuality: 0.85) {
                            await viewModel.uploadAvatar(jpegData: jpegData)
                        }
                    }
                }
            }
            .alert("Remove Avatar?", isPresented: $isShowingRemoveAvatarConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Remove Avatar", role: .destructive) {
                    Task {
                        await viewModel.removeAvatar()
                        if viewModel.error == nil {
                            avatarPreview = nil
                            selectedPhoto = nil
                        }
                    }
                }
            } message: {
                Text("Your profile avatar will be removed from SourceHut.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await viewModel.saveProfile(
                                email: email,
                                url: url,
                                location: location,
                                bio: bio
                            )
                            if viewModel.error == nil {
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.isSavingProfile {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(viewModel.isSavingProfile)
                }
            }
        }
    }
}

private enum ProfileDestructiveAction {
    case deleteSSHKey(SSHKey)
    case deletePGPKey(PGPKey)

    var title: String {
        switch self {
        case .deleteSSHKey:
            "Remove SSH Key?"
        case .deletePGPKey:
            "Remove PGP Key?"
        }
    }

    var confirmationLabel: String {
        switch self {
        case .deleteSSHKey:
            "Remove SSH Key"
        case .deletePGPKey:
            "Remove PGP Key"
        }
    }

    var message: String {
        switch self {
        case .deleteSSHKey(let key):
            "Remove SSH key \(key.fingerprint) from your account?"
        case .deletePGPKey(let key):
            "Remove PGP key \(key.fingerprint) from your account?"
        }
    }
}
