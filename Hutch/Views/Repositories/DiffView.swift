import SwiftUI

/// Renders a unified diff string with syntax highlighting:
/// - Green background for added lines (+)
/// - Red background for removed lines (-)
/// - Gray for hunk headers (@@)
/// - File headers (--- / +++ / diff) in bold
struct DiffView: View {
    let diff: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(fileSections) { section in
                DiffFileSectionView(section: section)
            }
        }
    }

    private var fileSections: [DiffFileSection] {
        DiffFileSection.parse(from: normalizedDiff)
    }

    private var normalizedDiff: String {
        diff
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

private struct DiffFileSectionView: View {
    let section: DiffFileSection
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Text(section.filename)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(section.changeSummary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(.tertiarySystemBackground))

            if isExpanded {
                DiffBlockView(lines: section.lines)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
    }
}

private struct DiffBlockView: View {
    let lines: [String]

    var body: some View {
        let hunks = DiffHunk.split(lines: lines)
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(hunks) { hunk in
                DiffHunkView(hunk: hunk)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .background(Color(.secondarySystemBackground))
    }
}

private struct DiffHunk: Identifiable {
    let id: Int
    let header: String?
    let lines: [String]
    let isFileHeader: Bool

    static func split(lines: [String]) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var current: [String] = []
        var hunkIndex = 0
        var headerLines: [String] = []
        var passedFirstHunk = false

        for line in lines {
            if line.hasPrefix("@@") {
                if !passedFirstHunk {
                    // Collect file header lines before first hunk
                    if !current.isEmpty {
                        headerLines = current
                        hunks.append(DiffHunk(id: hunkIndex, header: nil, lines: headerLines, isFileHeader: true))
                        hunkIndex += 1
                    }
                    current = [line]
                    passedFirstHunk = true
                } else {
                    // End previous hunk, start new one
                    if !current.isEmpty {
                        let header = current.first
                        hunks.append(DiffHunk(id: hunkIndex, header: header, lines: current, isFileHeader: false))
                        hunkIndex += 1
                    }
                    current = [line]
                }
            } else {
                current.append(line)
            }
        }

        if !current.isEmpty {
            if passedFirstHunk {
                let header = current.first(where: { $0.hasPrefix("@@") }) ?? current.first
                hunks.append(DiffHunk(id: hunkIndex, header: header, lines: current, isFileHeader: false))
            } else {
                hunks.append(DiffHunk(id: hunkIndex, header: nil, lines: current, isFileHeader: true))
            }
        }

        return hunks
    }
}

private struct DiffHunkView: View {
    let hunk: DiffHunk
    @State private var isExpanded = true

    private var isCollapsible: Bool {
        !hunk.isFileHeader && hunk.lines.count > 1
    }

    var body: some View {
        if isCollapsible {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)

                    Text(hunk.header ?? "")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(.systemBackground).opacity(0.5))

            if isExpanded {
                hunkContent(lines: hunk.lines.dropFirst().map { $0 })
            }
        } else {
            hunkContent(lines: hunk.lines)
        }
    }

    @ViewBuilder
    private func hunkContent(lines: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    DiffLineView(line: line)
                }
            }
        }
    }
}

private struct DiffFileSection: Identifiable {
    let id: String
    let filename: String
    let lines: [String]
    let additions: Int
    let deletions: Int

    var changeSummary: String {
        "+\(additions)  -\(deletions)"
    }

    static func parse(from diff: String) -> [DiffFileSection] {
        let lines = diff.components(separatedBy: "\n")
        guard !lines.isEmpty else { return [] }

        let boundaries = lines.enumerated().compactMap { index, line in
            line.hasPrefix("diff --git ") ? index : nil
        }

        guard !boundaries.isEmpty else {
            let section = makeSection(lines: lines, fallbackIndex: 0)
            return section.lines.isEmpty ? [] : [section]
        }

        var sections: [DiffFileSection] = []
        for (position, startIndex) in boundaries.enumerated() {
            let endIndex = position + 1 < boundaries.count ? boundaries[position + 1] : lines.count
            let sectionLines = Array(lines[startIndex..<endIndex])
            let section = makeSection(lines: sectionLines, fallbackIndex: position)
            if !section.lines.isEmpty {
                sections.append(section)
            }
        }
        return sections
    }

    private static func makeSection(lines: [String], fallbackIndex: Int) -> DiffFileSection {
        let filename = fileName(from: lines) ?? "File \(fallbackIndex + 1)"
        let additions = lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
        let deletions = lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count
        return DiffFileSection(
            id: "\(fallbackIndex)-\(filename)",
            filename: filename,
            lines: lines,
            additions: additions,
            deletions: deletions
        )
    }

    private static func fileName(from lines: [String]) -> String? {
        if let diffHeader = lines.first(where: { $0.hasPrefix("diff --git ") }) {
            let parts = diffHeader.split(separator: " ")
            if let rhs = parts.last, rhs.hasPrefix("b/") {
                return String(rhs.dropFirst(2))
            }
        }

        if let plusHeader = lines.first(where: { $0.hasPrefix("+++ ") }) {
            let path = String(plusHeader.dropFirst(4))
            if path.hasPrefix("b/") {
                return String(path.dropFirst(2))
            }
            return path
        }

        if let minusHeader = lines.first(where: { $0.hasPrefix("--- ") }) {
            let path = String(minusHeader.dropFirst(4))
            if path.hasPrefix("a/") {
                return String(path.dropFirst(2))
            }
            return path
        }

        return nil
    }
}

private struct DiffLineView: View {
    let line: String

    var body: some View {
        Text(line.isEmpty ? " " : line)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .fontWeight(isHeader ? .semibold : .regular)
    }

    private var kind: DiffLineKind {
        if line.hasPrefix("@@") { return .hunk }
        if line.hasPrefix("+++") || line.hasPrefix("---") { return .fileHeader }
        if line.hasPrefix("diff ") { return .fileHeader }
        if line.hasPrefix("index ") { return .meta }
        if line.hasPrefix("+") { return .added }
        if line.hasPrefix("-") { return .removed }
        return .context
    }

    private var backgroundColor: Color {
        switch kind {
        case .added:      .green.opacity(0.15)
        case .removed:    .red.opacity(0.15)
        case .hunk:       .clear
        case .fileHeader: .clear
        case .meta:       .clear
        case .context:    .clear
        }
    }

    private var foregroundColor: Color {
        switch kind {
        case .added:   .green
        case .removed: .red
        case .hunk:    .secondary
        case .meta:    .secondary
        default:       .primary
        }
    }

    private var isHeader: Bool {
        kind == .fileHeader
    }
}

private enum DiffLineKind {
    case added
    case removed
    case hunk
    case fileHeader
    case meta
    case context
}
