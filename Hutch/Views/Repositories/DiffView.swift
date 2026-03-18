import SwiftUI

/// Renders a unified diff string with syntax highlighting:
/// - Green background for added lines (+)
/// - Red background for removed lines (-)
/// - Gray for hunk headers (@@)
/// - File headers (--- / +++ / diff) in bold
struct DiffView: View {
    let diff: String

    var body: some View {
        let lines = diff.components(separatedBy: "\n")

        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                DiffLineView(line: line)
            }
        }
        .font(.caption.monospaced())
    }
}

private struct DiffLineView: View {
    let line: String

    var body: some View {
        Text(line.isEmpty ? " " : line)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
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
        case .hunk:       .gray.opacity(0.12)
        case .fileHeader: .gray.opacity(0.08)
        case .meta:       .gray.opacity(0.05)
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
