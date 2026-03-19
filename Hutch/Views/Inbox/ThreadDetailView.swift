import MessageUI
import os
import SwiftUI
import UIKit

private let inboxReplyLogger = Logger(subsystem: "net.cleberg.Hutch", category: "InboxReply")

struct ThreadDetailView: View {
    let thread: InboxThreadSummary
    let onViewed: () -> Void
    var onMarkRead: (() -> Void)? = nil
    var onMarkUnread: (() -> Void)? = nil

    @Environment(AppState.self) private var appState
    @State private var viewModel: ThreadViewModel?
    @State private var replySuccessMessage: String?
    @State private var loadedThreadID: String?
    @State private var hasMarkedCurrentThreadViewed = false
    @State private var suppressAutoMarkViewed = false
    @State private var isUnread: Bool

    init(
        thread: InboxThreadSummary,
        onViewed: @escaping () -> Void,
        onMarkRead: (() -> Void)? = nil,
        onMarkUnread: (() -> Void)? = nil
    ) {
        self.thread = thread
        self.onViewed = onViewed
        self.onMarkRead = onMarkRead
        self.onMarkUnread = onMarkUnread
        self._isUnread = State(initialValue: thread.isUnread)
    }

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading thread…")
            }
        }
        .navigationTitle("Thread")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: thread.id) {
            guard loadedThreadID != thread.id else { return }
            let vm = ThreadViewModel(summary: thread, client: appState.client)
            viewModel = vm
            loadedThreadID = thread.id
            hasMarkedCurrentThreadViewed = false
            suppressAutoMarkViewed = false
            isUnread = thread.isUnread
            await vm.loadThread()
        }
        .onChange(of: viewModel?.thread?.id) { _, threadID in
            guard threadID != nil, !hasMarkedCurrentThreadViewed, !suppressAutoMarkViewed else { return }
            hasMarkedCurrentThreadViewed = true
            isUnread = false
            onViewed()
        }
        .sheet(item: Binding(
            get: { viewModel?.composeDraft },
            set: { _ in viewModel?.dismissReply() }
        )) { draft in
            MailComposeView(draft: draft) { result in
                switch result {
                case .failed(let message):
                    inboxReplyLogger.error("Inbox reply failed for thread \(thread.debugIdentifierSummary, privacy: .public): \(message, privacy: .public)")
                    viewModel?.error = message
                case .cancelled:
                    inboxReplyLogger.debug("Inbox reply cancelled for thread \(thread.debugIdentifierSummary, privacy: .public)")
                case .saved:
                    inboxReplyLogger.debug("Inbox reply draft saved for thread \(thread.debugIdentifierSummary, privacy: .public)")
                case .sent:
                    inboxReplyLogger.debug("Inbox reply handed off to Mail for thread \(thread.debugIdentifierSummary, privacy: .public)")
                    replySuccessMessage = "Reply handed off to Mail."
                    Task {
                        await viewModel?.loadThread()
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if let replySuccessMessage {
                Text(replySuccessMessage)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: replySuccessMessage)
        .onChange(of: replySuccessMessage) { _, message in
            guard message != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if self.replySuccessMessage == message {
                    self.replySuccessMessage = nil
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: ThreadViewModel) -> some View {
        @Bindable var vm = viewModel

        List {
            if let thread = viewModel.thread {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(thread.displaySubject)
                            .font(.headline)
                        Text(headerMetadata(thread))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if let partialWarning = viewModel.partialWarning {
                    Section {
                        Text(partialWarning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(thread.messages) { message in
                    InboxMessageRow(message: message)
                }
            }
        }
        .listStyle(.plain)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    if onMarkRead != nil || onMarkUnread != nil {
                        Button(isUnread ? "Mark Read" : "Mark Unread") {
                            suppressAutoMarkViewed = !isUnread
                            if isUnread {
                                onMarkRead?()
                                isUnread = false
                            } else {
                                onMarkUnread?()
                                isUnread = true
                            }
                        }
                    }

                    Button("Reply") {
                        viewModel.prepareReply()
                    }
                }
            }
        }
        .overlay {
            if viewModel.isLoading, viewModel.thread == nil {
                SRHTLoadingStateView(message: "Loading thread…")
            } else if let error = viewModel.error, viewModel.thread == nil {
                SRHTErrorStateView(
                    title: "Failed to load thread",
                    message: error,
                    retryAction: { await viewModel.loadThread() }
                )
            }
        }
        .srhtErrorBanner(error: $vm.error)
        .refreshable {
            await viewModel.loadThread()
        }
    }

    private func headerMetadata(_ thread: InboxThreadDetail) -> String {
        var parts = [thread.listDisplayName]
        if let messageCount = thread.messageCount, messageCount > 1 {
            parts.append("\(messageCount) messages")
        }
        parts.append(thread.lastActivityAt.relativeDescription)
        return parts.joined(separator: " • ")
    }
}

private struct InboxMessageRow: View {
    let message: InboxMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(senderLine)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    Text(message.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if message.isPatch {
                    Text("Patch")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(message.contentBlocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .plainText(let text):
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                case .diff(let diff):
                    ScrollView(.horizontal) {
                        DiffView(diff: diff)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .listRowSeparator(.visible)
    }

    private var senderLine: String {
        if let email = message.senderEmailAddress,
           email.caseInsensitiveCompare(message.senderDisplayName) != .orderedSame {
            return "\(message.senderDisplayName) <\(email)>"
        }
        return message.senderDisplayName
    }
}

private struct MailComposeView: UIViewControllerRepresentable {
    let draft: MailComposeDraft
    let onComplete: (Result) -> Void

    enum Result {
        case cancelled
        case saved
        case sent
        case failed(String)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        guard MFMailComposeViewController.canSendMail() else {
            let controller = UINavigationController(rootViewController: MailUnavailableViewController(onDismiss: {
                context.coordinator.onComplete(.failed("Mail is not configured on this device."))
            }))
            DispatchQueue.main.async {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            return controller
        }

        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(draft.recipients)
        if !draft.ccRecipients.isEmpty {
            controller.setCcRecipients(draft.ccRecipients)
        }
        if !draft.subject.isEmpty {
            controller.setSubject(draft.subject)
        }
        if !draft.body.isEmpty {
            controller.setMessageBody(draft.body, isHTML: false)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onComplete: (Result) -> Void

        init(onComplete: @escaping (Result) -> Void) {
            self.onComplete = onComplete
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            if error != nil {
                let message = error?.localizedDescription ?? "The reply could not be sent."
                presentFailureAlert(on: controller, message: message)
                onComplete(.failed(message))
                return
            }
            switch result {
            case .cancelled:
                controller.dismiss(animated: true)
                onComplete(.cancelled)
            case .saved:
                controller.dismiss(animated: true)
                onComplete(.saved)
            case .sent:
                controller.dismiss(animated: true)
                onComplete(.sent)
            case .failed:
                let message = "Mail could not send the reply from the configured iOS Mail account."
                presentFailureAlert(on: controller, message: message)
                onComplete(.failed(message))
            @unknown default:
                let message = "Mail returned an unknown result while sending the reply."
                presentFailureAlert(on: controller, message: message)
                onComplete(.failed(message))
            }
        }

        private func presentFailureAlert(on controller: UIViewController, message: String) {
            guard controller.presentedViewController == nil else { return }
            let alert = UIAlertController(title: "Reply Failed", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            controller.present(alert, animated: true)
        }
    }
}

private final class MailUnavailableViewController: UIViewController {
    private let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.title = "Reply"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissSelf)
        )

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Mail is not configured on this device."
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .secondaryLabel

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc
    private func dismissSelf() {
        dismiss(animated: true)
        onDismiss()
    }
}
