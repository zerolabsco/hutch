import SwiftUI

struct BuildTaskLogView: View {
    @Environment(AppState.self) private var appState

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
                    BuildTaskLogContentView(text: logText)
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
                                    appState.copyToPasteboard(logText, label: "build log")
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

private struct BuildTaskLogContentView: View {
    let text: String

    @State private var searchQuery = ""
    @State private var matches: [LogTextRange] = []
    @State private var anchors: [LogAnchor] = []
    @State private var selectedMatchIndex: Int?
    @State private var scrollTarget: LogScrollTarget?

    private var selectedMatch: LogTextRange? {
        guard let selectedMatchIndex, matches.indices.contains(selectedMatchIndex) else { return nil }
        return matches[selectedMatchIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            searchControls

            if !anchors.isEmpty {
                anchorBar
            }

            BuildLogTextView(
                text: text,
                highlights: matches,
                selectedHighlight: selectedMatch,
                scrollTarget: scrollTarget
            )
        }
        .task(id: text) {
            await refreshAnchors()
            await refreshSearch()
        }
        .task(id: searchQuery) {
            await refreshSearch()
        }
    }

    private var searchControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search log", text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.thinMaterial)
                }

                HStack(spacing: 4) {
                    Button {
                        moveSelection(step: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(matches.isEmpty)

                    Button {
                        moveSelection(step: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(matches.isEmpty)
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
            }

            HStack {
                if searchQuery.isEmpty {
                    Text("\(anchors.count) error anchors")
                } else if matches.isEmpty {
                    Text("No matches")
                } else if let selectedMatchIndex {
                    Text("\(selectedMatchIndex + 1) of \(matches.count) matches")
                }

                Spacer()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.bar)
    }

    private var anchorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(anchors) { anchor in
                    Button {
                        requestScroll(to: anchor.range)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Line \(anchor.lineNumber)")
                                .font(.caption.weight(.semibold))
                            Text(anchor.label)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: 220, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.red.opacity(0.12))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .background(.bar)
    }

    private func refreshAnchors() async {
        let text = text
        let newAnchors = await Task.detached(priority: .userInitiated) {
            detectLogAnchors(in: text)
        }.value

        guard !Task.isCancelled else { return }
        anchors = newAnchors
    }

    private func refreshSearch() async {
        let query = searchQuery
        let text = text

        if !query.isEmpty {
            try? await Task.sleep(for: .milliseconds(150))
        }
        guard !Task.isCancelled else { return }

        let newMatches = await Task.detached(priority: .userInitiated) {
            logMatchRanges(in: text, query: query)
        }.value

        guard !Task.isCancelled else { return }

        let previousSelectedRange = selectedMatch
        matches = newMatches

        if newMatches.isEmpty {
            selectedMatchIndex = nil
            return
        }

        if let previousSelectedRange,
           let newIndex = newMatches.firstIndex(of: previousSelectedRange) {
            selectedMatchIndex = newIndex
            return
        }

        selectedMatchIndex = 0
        requestScroll(to: newMatches[0])
    }

    private func moveSelection(step: Int) {
        guard !matches.isEmpty else { return }
        let currentIndex = selectedMatchIndex ?? 0
        let nextIndex = (currentIndex + step + matches.count) % matches.count
        selectedMatchIndex = nextIndex
        requestScroll(to: matches[nextIndex])
    }

    private func requestScroll(to range: LogTextRange) {
        let nextID = (scrollTarget?.id ?? 0) + 1
        scrollTarget = LogScrollTarget(id: nextID, range: range)
    }
}

private struct BuildLogTextView: UIViewRepresentable {
    let text: String
    let highlights: [LogTextRange]
    let selectedHighlight: LogTextRange?
    let scrollTarget: LogScrollTarget?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

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
        textView.font = UIFont.monospacedSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize,
            weight: .regular
        )
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let coordinator = context.coordinator

        if coordinator.lastText != text {
            uiView.attributedText = NSAttributedString(string: text, attributes: baseAttributes(for: uiView))
            coordinator.lastText = text
            coordinator.lastHighlights = []
            coordinator.lastSelectedHighlight = nil
        }

        if coordinator.lastHighlights != highlights || coordinator.lastSelectedHighlight != selectedHighlight {
            applyHighlights(to: uiView)
            coordinator.lastHighlights = highlights
            coordinator.lastSelectedHighlight = selectedHighlight
        }

        if coordinator.lastScrollTarget != scrollTarget, let scrollTarget {
            scroll(to: scrollTarget.range.nsRange, in: uiView)
            coordinator.lastScrollTarget = scrollTarget
        }
    }

    private func applyHighlights(to textView: UITextView) {
        let textStorage = textView.textStorage
        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.beginEditing()
        textStorage.removeAttribute(.backgroundColor, range: fullRange)
        textStorage.removeAttribute(.foregroundColor, range: fullRange)
        textStorage.addAttributes(baseAttributes(for: textView), range: fullRange)

        for range in highlights {
            textStorage.addAttribute(
                .backgroundColor,
                value: UIColor.systemYellow.withAlphaComponent(0.28),
                range: range.nsRange
            )
        }

        if let selectedHighlight {
            textStorage.addAttributes([
                .backgroundColor: UIColor.systemOrange.withAlphaComponent(0.5),
                .foregroundColor: UIColor.label
            ], range: selectedHighlight.nsRange)
        }
        textStorage.endEditing()
    }

    private func scroll(to range: NSRange, in textView: UITextView) {
        guard range.location != NSNotFound else { return }
        textView.selectedRange = range
        textView.scrollRangeToVisible(range)
    }

    private func baseAttributes(for textView: UITextView) -> [NSAttributedString.Key: Any] {
        [
            .font: textView.font as Any,
            .foregroundColor: UIColor.label
        ]
    }

    final class Coordinator {
        var lastText = ""
        var lastHighlights: [LogTextRange] = []
        var lastSelectedHighlight: LogTextRange?
        var lastScrollTarget: LogScrollTarget?
    }
}

struct LogTextRange: Hashable, Equatable, Sendable {
    let location: Int
    let length: Int

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}

struct LogAnchor: Identifiable, Equatable, Sendable {
    let lineNumber: Int
    let label: String
    let range: LogTextRange

    var id: String {
        "\(lineNumber):\(range.location)"
    }
}

private struct LogScrollTarget: Equatable {
    let id: Int
    let range: LogTextRange
}

nonisolated func logMatchRanges(in text: String, query: String, limit: Int = 2_000) -> [LogTextRange] {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else { return [] }

    let nsText = text as NSString
    var searchRange = NSRange(location: 0, length: nsText.length)
    var matches: [LogTextRange] = []

    while searchRange.length > 0, matches.count < limit {
        let foundRange = nsText.range(
            of: trimmedQuery,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchRange
        )

        guard foundRange.location != NSNotFound else { break }
        matches.append(LogTextRange(location: foundRange.location, length: foundRange.length))

        let nextLocation = foundRange.location + max(foundRange.length, 1)
        guard nextLocation <= nsText.length else { break }
        searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
    }

    return matches
}

nonisolated func detectLogAnchors(in text: String, limit: Int = 24) -> [LogAnchor] {
    let nsText = text as NSString
    let strongMarkers = [
        "fatal error",
        "fatal:",
        "error:",
        "exception:",
        "uncaught exception",
        "traceback",
        "panic:",
        "undefined reference",
        "segmentation fault",
        "assertion failed",
        "failed:"
    ]

    var anchors: [LogAnchor] = []
    var lineNumber = 1
    var cursor = 0
    var lastAnchorLine: Int?

    while cursor < nsText.length, anchors.count < limit {
        let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
        let rawLine = nsText.substring(with: lineRange)
        let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let foldedLine = trimmedLine.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        let isMatch = !trimmedLine.isEmpty && strongMarkers.contains { foldedLine.contains($0) }
        let isDistinctFromPrevious = lastAnchorLine.map { lineNumber - $0 > 1 } ?? true

        if isMatch, isDistinctFromPrevious {
            anchors.append(
                LogAnchor(
                    lineNumber: lineNumber,
                    label: String(trimmedLine.prefix(100)),
                    range: LogTextRange(location: lineRange.location, length: lineRange.length)
                )
            )
            lastAnchorLine = lineNumber
        }

        cursor = lineRange.upperBound
        lineNumber += 1
    }

    return anchors
}
