import SwiftUI
import UIKit

struct BuildTaskLogView: View {
    let taskName: String
    let viewModel: BuildDetailViewModel

    /// Always reflects the latest version of the task from the live job data.
    private var task: BuildTask? {
        viewModel.job?.tasks.first(where: { $0.name == taskName })
    }

    var body: some View {
        Group {
            if let task {
                if let logText = viewModel.displayedLogText(for: task) {
                    BuildLogTextView(text: logText)
                    .safeAreaInset(edge: .bottom) {
                        if viewModel.isShowingBuildLogFallback(for: task) {
                            Text("Showing the live build log until a task-specific log is available.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(.thinMaterial)
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: logText)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                UIPasteboard.general.string = logText
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .accessibilityLabel("Copy log to clipboard")
                        }
                    }
                } else if viewModel.loadingTaskLogs.contains(task.logCacheKey) {
                    SRHTLoadingStateView(message: "Loading log…")
                } else if task.log == nil {
                    if task.status == .running || task.status == .pending {
                        if viewModel.isLoadingBuildLog {
                            SRHTLoadingStateView(message: "Loading build log…")
                        } else {
                            SRHTLoadingStateView(message: "Waiting for log…")
                        }
                    } else {
                        ContentUnavailableView(
                            "No Log",
                            systemImage: "doc.text",
                            description: Text("This task has no log output.")
                        )
                    }
                } else if viewModel.failedTaskLogs.contains(task.logCacheKey) {
                    ContentUnavailableView {
                        Label("Couldn't Load Log", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("The log is temporarily unavailable. Retry to fetch the latest output.")
                    } actions: {
                        Button("Retry") {
                            Task {
                                await viewModel.retryTaskLog(task: task)
                            }
                        }
                    }
                } else {
                    SRHTLoadingStateView(message: "Loading log…")
                }
            } else {
                SRHTLoadingStateView(message: "Loading log…")
            }
        }
        .navigationTitle(taskName)
        .navigationBarTitleDisplayMode(.inline)
        // Re-runs whenever the log URL changes or a retry is requested.
        .task(id: viewModel.taskLogTrigger(for: task)) {
            guard let task else { return }
            await viewModel.loadTaskLog(task: task)
        }
        .task(id: viewModel.job?.log?.fullURL) {
            guard let task else { return }
            guard task.status == .running || task.status == .pending else { return }
            await viewModel.loadBuildLog()
        }
    }
}

private struct BuildLogTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context _: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.alwaysBounceHorizontal = true
        textView.showsHorizontalScrollIndicator = true
        textView.showsVerticalScrollIndicator = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = false
        textView.font = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize, weight: .regular)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context _: Context) {
        guard uiView.text != text else { return }
        uiView.text = text
    }
}
