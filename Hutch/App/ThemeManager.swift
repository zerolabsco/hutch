import SwiftUI

// MARK: - Theme & Density Types

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum DisplayDensity: String, CaseIterable, Identifiable {
    case standard
    case compact

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .compact: "Compact"
        }
    }
}

// MARK: - Environment Keys

private struct DisplayDensityKey: EnvironmentKey {
    static let defaultValue: DisplayDensity = .standard
}

extension EnvironmentValues {
    var displayDensity: DisplayDensity {
        get { self[DisplayDensityKey.self] }
        set { self[DisplayDensityKey.self] = newValue }
    }
}

// MARK: - Themed List Modifier

/// Combined modifier for List/Form that applies compact section spacing.
/// Apply once per List or Form.
struct ThemedListStyle: ViewModifier {
    @Environment(\.displayDensity) private var density

    func body(content: Content) -> some View {
        content
            .listSectionSpacing(density == .compact ? .compact : .default)
            .contentMargins(.vertical, density == .compact ? 2 : 8, for: .scrollContent)
            .controlSize(density == .compact ? .small : .regular)
    }
}

extension View {
    /// Apply themed appearance (density spacing) to a List or Form.
    func themedList() -> some View {
        modifier(ThemedListStyle())
    }
}
