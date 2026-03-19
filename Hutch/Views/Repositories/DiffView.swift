import SwiftUI

/// Renders a unified diff string with syntax highlighting:
/// - Green background for added lines (+)
/// - Red background for removed lines (-)
/// - Gray for hunk headers (@@)
/// - File headers (--- / +++ / diff) in bold
struct DiffView: View {
    let diff: String

    var body: some View {
        let lines = normalizedDiff.components(separatedBy: "\n")

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                DiffLineView(line: line)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var normalizedDiff: String {
        diff
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

private struct DiffLineView: View {
    let line: String

    var body: some View {
        Text(line.isEmpty ? " " : line)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
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
