import Splash
import SwiftUI
import UIKit

private typealias ViewColor = SwiftUI.Color

struct FileTreeView: View {
    let repository: RepositorySummary
    let client: SRHTClient

    @State private var viewModel: FileTreeViewModel?

    var body: some View {
        Group {
            if let viewModel {
                FileTreeContentView(viewModel: viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading files…")
            }
        }
        .task {
            if viewModel == nil {
                let vm = FileTreeViewModel(
                    repositoryRid: repository.rid,
                    service: repository.service,
                    client: client
                )
                viewModel = vm
                async let loadTree: () = vm.loadRootTree()
                async let loadRefs: () = vm.loadReferences()
                _ = await (loadTree, loadRefs)
            }
        }
    }
}

// MARK: - Content View

private struct FileTreeContentView: View {
    let viewModel: FileTreeViewModel

    @AppStorage(AppStorageKeys.wrapRepositoryFileLines) private var wrapRepositoryFileLines = false
    @State private var showRefPicker = false
    @State private var showFileShareSheet = false
    @State private var showShareUnavailableAlert = false
    @State private var didCopyFileContents = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            Divider()
            contentArea
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showRefPicker = true
                } label: {
                    Label(
                        revspecLabel,
                        systemImage: "arrow.triangle.branch"
                    )
                    .font(.subheadline)
                }
            }
        }
        .sheet(isPresented: $showRefPicker) {
            RefPickerSheet(viewModel: viewModel, isPresented: $showRefPicker)
        }
        .srhtErrorBanner(error: Binding(
            get: { viewModel.error },
            set: { viewModel.error = $0 }
        ))
        .onChange(of: viewModel.viewingEntry?.name) { _, _ in
            resetCopyConfirmation()
        }
    }

    private var revspecLabel: String {
        let revspec = viewModel.revspec
        if revspec == "HEAD" {
            return "HEAD"
        }
        if revspec.hasPrefix("refs/heads/") {
            return String(revspec.dropFirst("refs/heads/".count))
        } else if revspec.hasPrefix("refs/tags/") {
            return String(revspec.dropFirst("refs/tags/".count))
        }
        return revspec
    }

    // MARK: - Breadcrumb Bar

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(Array(viewModel.navStack.enumerated()), id: \.offset) { index, navEntry in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Button {
                            Task {
                                await viewModel.navigateToBreadcrumb(at: index)
                            }
                        } label: {
                            Text(navEntry.name)
                                .font(.subheadline.monospaced())
                                .foregroundStyle(
                                    index == viewModel.navStack.count - 1 && viewModel.viewingEntry == nil
                                        ? .primary : .secondary
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if let viewing = viewModel.viewingEntry {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        Text(viewing.name)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.primary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.isLoading, viewModel.entries.isEmpty, viewModel.viewingEntry == nil {
            SRHTLoadingStateView(message: "Loading files…")
        } else if let entry = viewModel.viewingEntry, let object = viewModel.viewingObject {
            // Viewing a file
            fileContentView(entry: entry, object: object)
        } else if let error = viewModel.error, viewModel.entries.isEmpty {
            SRHTErrorStateView(
                title: "Couldn't Load Files",
                message: error,
                retryAction: { await viewModel.loadRootTree() }
            )
        } else if !viewModel.entries.isEmpty {
            // Viewing a directory listing
            treeListView
        } else if viewModel.navStack.isEmpty {
            ContentUnavailableView(
                "No Files",
                systemImage: "folder",
                description: Text("This repository could not be loaded.")
            )
        } else {
            ContentUnavailableView(
                "Empty Directory",
                systemImage: "folder",
                description: Text("This directory has no files.")
            )
        }
    }

    private func shareFileContents(_ text: String) {
        if text.isEmpty {
            showShareUnavailableAlert = true
        } else {
            showFileShareSheet = true
        }
    }

    private func copyFileContents(_ text: String) {
        UIPasteboard.general.string = text
        didCopyFileContents = true
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                didCopyFileContents = false
            }
        }
    }

    private func resetCopyConfirmation() {
        copyResetTask?.cancel()
        copyResetTask = nil
        didCopyFileContents = false
    }

    // MARK: - File Content View

    @ViewBuilder
    private func fileContentView(entry: TreeEntry, object: GitObject) -> some View {
        switch object {
        case .textBlob(let blob):
            textBlobView(entry, blob: blob)
        case .binaryBlob(let blob):
            binaryBlobView(entry: entry, blob: blob)
        default:
            ContentUnavailableView(
                "Unknown Object",
                systemImage: "questionmark.folder",
                description: Text("Cannot display this object type.")
            )
        }
    }

    // MARK: - Tree List

    private var treeListView: some View {
        let sorted = viewModel.entries.sorted { a, b in
            let aIsTree = a.object?.isTree == true
            let bIsTree = b.object?.isTree == true
            if aIsTree != bIsTree { return aIsTree }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        return List(sorted) { entry in
            TreeEntryRow(entry: entry)
                .contentShape(Rectangle())
                .onTapGesture {
                    Task {
                        await viewModel.navigateInto(entry: entry)
                    }
                }
                .themedRow()
        }
        .themedList()
        .listStyle(.plain)
        .refreshable {
            await viewModel.loadRootTree()
        }
    }

    // MARK: - Text Blob

    @ViewBuilder
    private func textBlobView(_ entry: TreeEntry, blob: GitTextBlob) -> some View {
        let text = blob.text ?? ""

        VStack(spacing: 0) {
            CodeFileTextView(
                text: text,
                fileName: entry.name,
                wrapLines: wrapRepositoryFileLines
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            fileActionToolbar(text: text)
        }
        .sheet(isPresented: $showFileShareSheet) {
            FileContentShareSheet(activityItems: [text])
        }
        .alert("Share Unavailable", isPresented: $showShareUnavailableAlert) {
            Button("OK", role: .cancel) {
                // no-op: .cancel role handles alert dismissal
            }
        } message: {
            Text(SRHTShareTarget.file.fallbackMessage)
        }
    }

    // MARK: - Binary Blob

    @ViewBuilder
    private func binaryBlobView(entry: TreeEntry, blob: GitBinaryBlob) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "doc.zipper")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(entry.name)
                .font(.headline)

            if let size = blob.size {
                Text(formatBytes(size))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Binary file — cannot be displayed inline.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            if let content = blob.content, let url = URL(string: content) {
                Link(destination: url) {
                    Label("Open in Safari", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                viewModel.dismissFileView()
            } label: {
                Text("Back to directory")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func fileActionToolbar(text: String) -> some View {
        HStack(spacing: 0) {
            toolbarButton(
                title: "Share",
                systemImage: "square.and.arrow.up"
            ) {
                shareFileContents(text)
            }

            toolbarButton(
                title: didCopyFileContents ? "Copied" : "Copy All",
                systemImage: didCopyFileContents ? "checkmark" : "doc.on.doc"
            ) {
                copyFileContents(text)
            }

            toolbarButton(
                title: wrapRepositoryFileLines ? "Wrap On" : "Wrap Off",
                systemImage: "text.word.spacing"
            ) {
                wrapRepositoryFileLines.toggle()
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func toolbarButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

struct CodeFileTextView: UIViewRepresentable {
    let text: String
    let fileName: String
    let wrapLines: Bool

    private let font = UIFont(name: "SFMono-Regular", size: 12)
        ?? UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    func makeUIView(context _: Context) -> CodeFileUIView {
        CodeFileUIView(
            text: text,
            fileName: fileName,
            font: font,
            wrapLines: wrapLines
        )
    }

    func updateUIView(_ uiView: CodeFileUIView, context _: Context) {
        uiView.updateContent(
            text: text,
            fileName: fileName,
            font: font,
            wrapLines: wrapLines
        )
    }
}

struct FileContentShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ : UIActivityViewController, context _: Context) {
        // no-op: UIActivityViewController manages its own state after presentation
    }
}

final class CodeFileUIView: UIView {
    private enum Layout {
        static let verticalPadding: CGFloat = 12
        static let gutterLeadingPadding: CGFloat = 12
        static let gutterTrailingPadding: CGFloat = 8
    }

    private final class LineRow {
        let gutterRow = UIView()
        let gutterLabel = UILabel()
        let codeRow = UIView()
        let codeLabel = UILabel()
        let gutterHeightConstraint: NSLayoutConstraint
        let codeHeightConstraint: NSLayoutConstraint

        init() {
            gutterRow.translatesAutoresizingMaskIntoConstraints = false
            gutterLabel.translatesAutoresizingMaskIntoConstraints = false
            codeRow.translatesAutoresizingMaskIntoConstraints = false
            codeLabel.translatesAutoresizingMaskIntoConstraints = false

            gutterHeightConstraint = gutterRow.heightAnchor.constraint(equalToConstant: 0)
            codeHeightConstraint = codeRow.heightAnchor.constraint(equalToConstant: 0)
        }
    }

    private let outerScrollView = UIScrollView()
    private let contentView = UIView()
    private let gutterContainerView = UIView()
    private let gutterStackView = UIStackView()
    private let horizontalScrollView = UIScrollView()
    private let codeContainerView = UIView()
    private let codeStackView = UIStackView()

    private var codeContainerWidthConstraint: NSLayoutConstraint?
    private var codeContainerExplicitWidthConstraint: NSLayoutConstraint?
    private var gutterWidthConstraint: NSLayoutConstraint?

    private var rows: [LineRow] = []
    private var currentText = ""
    private var currentFileName = ""
    private var currentFont: UIFont
    private var wrapLines: Bool
    private var needsLineLayoutUpdate = true
    private var lastMeasuredCodeWidth: CGFloat = 0

    init(text: String, fileName: String, font: UIFont, wrapLines: Bool) {
        self.currentFont = font
        self.wrapLines = wrapLines
        super.init(frame: .zero)
        setupViews()
        updateContent(text: text, fileName: fileName, font: font, wrapLines: wrapLines)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLineLayoutsIfNeeded()
    }

    func updateContent(text: String, fileName: String, font: UIFont, wrapLines: Bool) {
        let contentChanged = text != currentText || fileName != currentFileName || font != currentFont
        let wrapChanged = wrapLines != self.wrapLines

        currentText = text
        currentFileName = fileName
        currentFont = font
        self.wrapLines = wrapLines

        if contentChanged {
            rebuildRows()
        }

        if contentChanged || wrapChanged {
            updateWrapConfiguration(resetHorizontalOffset: wrapChanged)
            needsLineLayoutUpdate = true
            setNeedsLayout()
            layoutIfNeeded()
        }
    }

    private func setupViews() {
        backgroundColor = .systemBackground

        outerScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        gutterContainerView.translatesAutoresizingMaskIntoConstraints = false
        gutterStackView.translatesAutoresizingMaskIntoConstraints = false
        horizontalScrollView.translatesAutoresizingMaskIntoConstraints = false
        codeContainerView.translatesAutoresizingMaskIntoConstraints = false
        codeStackView.translatesAutoresizingMaskIntoConstraints = false

        gutterStackView.axis = .vertical
        gutterStackView.alignment = .fill
        gutterStackView.distribution = .fill
        gutterStackView.spacing = 0

        codeStackView.axis = .vertical
        codeStackView.alignment = .fill
        codeStackView.distribution = .fill
        codeStackView.spacing = 0

        outerScrollView.alwaysBounceVertical = true
        horizontalScrollView.alwaysBounceVertical = false
        horizontalScrollView.showsVerticalScrollIndicator = false

        addSubview(outerScrollView)
        outerScrollView.addSubview(contentView)
        contentView.addSubview(gutterContainerView)
        contentView.addSubview(horizontalScrollView)
        gutterContainerView.addSubview(gutterStackView)
        horizontalScrollView.addSubview(codeContainerView)
        codeContainerView.addSubview(codeStackView)

        codeContainerWidthConstraint = codeContainerView.widthAnchor.constraint(equalTo: horizontalScrollView.frameLayoutGuide.widthAnchor)
        codeContainerExplicitWidthConstraint = codeContainerView.widthAnchor.constraint(equalToConstant: 0)
        gutterWidthConstraint = gutterContainerView.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            outerScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            outerScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            outerScrollView.topAnchor.constraint(equalTo: topAnchor),
            outerScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: outerScrollView.frameLayoutGuide.widthAnchor),

            gutterContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            gutterContainerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Layout.verticalPadding),
            gutterContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Layout.verticalPadding),

            horizontalScrollView.leadingAnchor.constraint(equalTo: gutterContainerView.trailingAnchor),
            horizontalScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            horizontalScrollView.topAnchor.constraint(equalTo: gutterContainerView.topAnchor),
            horizontalScrollView.bottomAnchor.constraint(equalTo: gutterContainerView.bottomAnchor),

            gutterStackView.leadingAnchor.constraint(equalTo: gutterContainerView.leadingAnchor, constant: Layout.gutterLeadingPadding),
            gutterStackView.trailingAnchor.constraint(equalTo: gutterContainerView.trailingAnchor, constant: -Layout.gutterTrailingPadding),
            gutterStackView.topAnchor.constraint(equalTo: gutterContainerView.topAnchor),
            gutterStackView.bottomAnchor.constraint(equalTo: gutterContainerView.bottomAnchor),

            codeContainerView.leadingAnchor.constraint(equalTo: horizontalScrollView.contentLayoutGuide.leadingAnchor),
            codeContainerView.trailingAnchor.constraint(equalTo: horizontalScrollView.contentLayoutGuide.trailingAnchor),
            codeContainerView.topAnchor.constraint(equalTo: horizontalScrollView.contentLayoutGuide.topAnchor),
            codeContainerView.bottomAnchor.constraint(equalTo: horizontalScrollView.contentLayoutGuide.bottomAnchor),
            codeContainerView.heightAnchor.constraint(equalTo: horizontalScrollView.frameLayoutGuide.heightAnchor),

            codeStackView.leadingAnchor.constraint(equalTo: codeContainerView.leadingAnchor),
            codeStackView.trailingAnchor.constraint(equalTo: codeContainerView.trailingAnchor),
            codeStackView.topAnchor.constraint(equalTo: codeContainerView.topAnchor),
            codeStackView.bottomAnchor.constraint(equalTo: codeContainerView.bottomAnchor)
        ])

        gutterWidthConstraint?.isActive = true
    }

    private func rebuildRows() {
        rows.forEach { row in
            gutterStackView.removeArrangedSubview(row.gutterRow)
            row.gutterRow.removeFromSuperview()
            codeStackView.removeArrangedSubview(row.codeRow)
            row.codeRow.removeFromSuperview()
        }
        rows.removeAll()

        let attributedText = CodeSyntaxHighlighter.attributedText(
            for: currentText,
            fileName: currentFileName,
            font: currentFont
        )
        let lines = makeLines(from: attributedText, font: currentFont)

        gutterWidthConstraint?.constant = Self.gutterWidth(lineCount: lines.count, font: currentFont)

        for line in lines {
            let row = makeRow(for: line)
            rows.append(row)
            gutterStackView.addArrangedSubview(row.gutterRow)
            codeStackView.addArrangedSubview(row.codeRow)
        }
    }

    private func makeRow(for line: CodeFileLineData) -> LineRow {
        let row = LineRow()

        row.gutterLabel.font = currentFont
        row.gutterLabel.textColor = .secondaryLabel
        row.gutterLabel.textAlignment = .right
        row.gutterLabel.text = line.number

        row.codeLabel.attributedText = line.text
        row.codeLabel.font = currentFont

        row.gutterRow.addSubview(row.gutterLabel)
        row.codeRow.addSubview(row.codeLabel)

        NSLayoutConstraint.activate([
            row.gutterHeightConstraint,
            row.codeHeightConstraint,

            row.gutterLabel.leadingAnchor.constraint(equalTo: row.gutterRow.leadingAnchor),
            row.gutterLabel.trailingAnchor.constraint(equalTo: row.gutterRow.trailingAnchor),
            row.gutterLabel.topAnchor.constraint(equalTo: row.gutterRow.topAnchor),
            row.gutterLabel.bottomAnchor.constraint(lessThanOrEqualTo: row.gutterRow.bottomAnchor),

            row.codeLabel.leadingAnchor.constraint(equalTo: row.codeRow.leadingAnchor),
            row.codeLabel.trailingAnchor.constraint(equalTo: row.codeRow.trailingAnchor),
            row.codeLabel.topAnchor.constraint(equalTo: row.codeRow.topAnchor),
            row.codeLabel.bottomAnchor.constraint(lessThanOrEqualTo: row.codeRow.bottomAnchor)
        ])

        return row
    }

    private func updateWrapConfiguration(resetHorizontalOffset: Bool) {
        horizontalScrollView.alwaysBounceHorizontal = !wrapLines
        horizontalScrollView.isScrollEnabled = !wrapLines

        if wrapLines {
            codeContainerWidthConstraint?.isActive = true
            codeContainerExplicitWidthConstraint?.isActive = false
        } else {
            codeContainerWidthConstraint?.isActive = false
            codeContainerExplicitWidthConstraint?.isActive = true
        }

        for row in rows {
            row.codeLabel.numberOfLines = wrapLines ? 0 : 1
            row.codeLabel.lineBreakMode = wrapLines ? .byWordWrapping : .byClipping
        }

        if resetHorizontalOffset {
            horizontalScrollView.setContentOffset(.zero, animated: false)
        }
    }

    private func updateLineLayoutsIfNeeded() {
        let availableWidth = max(horizontalScrollView.bounds.width, 0)
        let shouldUpdateForWidth = wrapLines && abs(availableWidth - lastMeasuredCodeWidth) > 0.5

        guard needsLineLayoutUpdate || shouldUpdateForWidth else { return }

        lastMeasuredCodeWidth = availableWidth
        let measurementWidth = wrapLines ? max(availableWidth, 1) : CGFloat.greatestFiniteMagnitude

        for row in rows {
            row.codeLabel.preferredMaxLayoutWidth = wrapLines ? measurementWidth : 0
            let measuredSize = row.codeLabel.sizeThatFits(
                CGSize(width: measurementWidth, height: CGFloat.greatestFiniteMagnitude)
            )
            let rowHeight = max(ceil(measuredSize.height), ceil(currentFont.lineHeight))
            row.gutterHeightConstraint.constant = rowHeight
            row.codeHeightConstraint.constant = rowHeight
        }

        if wrapLines {
            codeContainerExplicitWidthConstraint?.constant = 0
        } else {
            let maxLineWidth = rows.reduce(CGFloat(0)) { partialResult, row in
                let measuredWidth = row.codeLabel.sizeThatFits(
                    CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                ).width
                return max(partialResult, ceil(measuredWidth))
            }
            codeContainerExplicitWidthConstraint?.constant = max(maxLineWidth, availableWidth)
        }

        needsLineLayoutUpdate = false
    }

    private func makeLines(from attributedText: NSAttributedString, font: UIFont) -> [CodeFileLineData] {
        let string = attributedText.string as NSString
        var lines: [CodeFileLineData] = []
        var currentLocation = 0
        var lineNumber = 1

        while currentLocation < attributedText.length {
            let searchRange = NSRange(location: currentLocation, length: attributedText.length - currentLocation)
            let newlineRange = string.range(of: "\n", options: [], range: searchRange)
            let lineRange: NSRange

            if newlineRange.location == NSNotFound {
                lineRange = searchRange
                currentLocation = attributedText.length
            } else {
                lineRange = NSRange(location: currentLocation, length: newlineRange.location - currentLocation)
                currentLocation = newlineRange.location + newlineRange.length
            }

            lines.append(CodeFileLineData(
                number: String(lineNumber),
                text: attributedText.attributedSubstring(from: lineRange)
            ))
            lineNumber += 1
        }

        if attributedText.length == 0 || string.hasSuffix("\n") {
            lines.append(CodeFileLineData(
                number: String(lineNumber),
                text: NSAttributedString(string: "", attributes: [.font: font])
            ))
        }

        return lines
    }

    private static func gutterWidth(lineCount: Int, font: UIFont) -> CGFloat {
        let digits = String(max(lineCount, 1)).count
        let sample = String(repeating: "8", count: digits)
        let numberWidth = ceil((sample as NSString).size(withAttributes: [.font: font]).width)
        return Layout.gutterLeadingPadding + numberWidth + Layout.gutterTrailingPadding
    }
}

private struct CodeFileLineData {
    let number: String
    let text: NSAttributedString
}

private enum CodeSyntaxHighlighter {
    static func attributedText(for text: String, fileName: String, font: UIFont) -> NSAttributedString {
        guard supportsSplashHighlighting(fileName: fileName) else {
            return plainText(text, font: font)
        }

        var splashFont = Font(size: Double(font.pointSize))
        splashFont.resource = .preloaded(font)

        let theme = Theme(
            font: splashFont,
            plainTextColor: .label,
            tokenColors: [
                .keyword: .systemPink,
                .string: .systemRed,
                .type: .systemTeal,
                .call: .systemBlue,
                .number: .systemPurple,
                .comment: .secondaryLabel,
                .property: .systemGreen,
                .dotAccess: .systemIndigo,
                .preprocessing: .systemOrange
            ],
            backgroundColor: .clear
        )

        let highlighted = SyntaxHighlighter(
            format: AttributedStringOutputFormat(theme: theme)
        ).highlight(text)

        return NSMutableAttributedString(attributedString: highlighted)
    }

    private static func plainText(_ text: String, font: UIFont) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: UIColor.label
            ]
        )
    }

    private static func supportsSplashHighlighting(fileName: String) -> Bool {
        let supportedExtensions: Set<String> = [
            "swift",
            "swiftinterface",
            "playground"
        ]
        return supportedExtensions.contains(
            (fileName as NSString).pathExtension.lowercased()
        )
    }
}

// MARK: - Tree Entry Row

private struct TreeEntryRow: View {
    let entry: TreeEntry

    var body: some View {
        Label {
            Text(entry.name)
                .font(.body.monospaced())
                .lineLimit(1)
        } icon: {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
        }
    }

    private var iconName: String {
        switch entry.object {
        case .tree: "folder.fill"
        case .unknown: "questionmark.circle"
        default: "doc"
        }
    }

    private var iconColor: ViewColor {
        switch entry.object {
        case .tree: .blue
        case .unknown: .orange
        default: .secondary
        }
    }
}

// MARK: - Ref Picker Sheet

private struct RefPickerSheet: View {
    let viewModel: FileTreeViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task {
                            await viewModel.changeRevspec("HEAD")
                            isPresented = false
                        }
                    } label: {
                        refRow(
                            title: "HEAD",
                            systemImage: "arrow.triangle.branch",
                            color: .blue,
                            isSelected: viewModel.revspec == "HEAD"
                        )
                    }
                    .buttonStyle(.plain)
                    .themedRow()
                }

                if !viewModel.branches.isEmpty {
                    Section("Branches") {
                        ForEach(viewModel.branches, id: \.name) { ref in
                            Button {
                                Task {
                                    await viewModel.changeRevspec(ref.name)
                                    isPresented = false
                                }
                            } label: {
                                refRow(
                                    title: ref.name.replacingOccurrences(of: "refs/heads/", with: ""),
                                    systemImage: "arrow.triangle.branch",
                                    color: .blue,
                                    isSelected: viewModel.revspec == ref.name
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .themedRow()
                    }
                }

                if !viewModel.tags.isEmpty {
                    Section("Tags") {
                        ForEach(viewModel.tags, id: \.name) { ref in
                            Button {
                                Task {
                                    await viewModel.changeRevspec(ref.name)
                                    isPresented = false
                                }
                            } label: {
                                refRow(
                                    title: ref.name.replacingOccurrences(of: "refs/tags/", with: ""),
                                    systemImage: "tag",
                                    color: .orange,
                                    isSelected: viewModel.revspec == ref.name
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .themedRow()
                    }
                }
            }
            .themedList()
            .listStyle(.insetGrouped)
            .navigationTitle("Select Ref")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .overlay {
                if viewModel.isLoadingRefs {
                    SRHTLoadingStateView(message: "Loading references…")
                }
            }
        }
    }

    private func refRow(title: String, systemImage: String, color: ViewColor, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(color)

            Text(title)
                .font(.body.monospaced())
                .foregroundStyle(.primary)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }
}
