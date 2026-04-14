import SwiftUI

// MARK: - Theme & Density Types

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case amoled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        case .amoled: "AMOLED"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        case .amoled: .dark
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

private struct IsAMOLEDThemeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var displayDensity: DisplayDensity {
        get { self[DisplayDensityKey.self] }
        set { self[DisplayDensityKey.self] = newValue }
    }

    var isAMOLEDTheme: Bool {
        get { self[IsAMOLEDThemeKey.self] }
        set { self[IsAMOLEDThemeKey.self] = newValue }
    }
}

// MARK: - Themed List Modifier

/// Combined modifier for List/Form that applies compact section spacing and AMOLED black backgrounds.
/// Apply once per List or Form.
struct ThemedListStyle: ViewModifier {
    @Environment(\.displayDensity) private var density
    @Environment(\.isAMOLEDTheme) private var isAMOLED

    func body(content: Content) -> some View {
        content
            .listSectionSpacing(density == .compact ? .compact : .default)
            .contentMargins(.vertical, density == .compact ? 2 : 8, for: .scrollContent)
            .controlSize(density == .compact ? .small : .regular)
            .modifier(AMOLEDListBackground(isAMOLED: isAMOLED))
    }
}

/// Hides the default grouped list background and replaces it with true black for OLED screens.
private struct AMOLEDListBackground: ViewModifier {
    let isAMOLED: Bool

    func body(content: Content) -> some View {
        if isAMOLED {
            content
                .scrollContentBackground(.hidden)
                .background(Color.black)
        } else {
            content
        }
    }
}

extension View {
    /// Apply themed appearance (density spacing) to a List or Form.
    func themedList() -> some View {
        modifier(ThemedListStyle())
    }
}

// MARK: - Themed Row Modifier

struct ThemedRowStyle: ViewModifier {
    @Environment(\.isAMOLEDTheme) private var isAMOLED

    func body(content: Content) -> some View {
        content
            .listRowBackground(isAMOLED ? Color.black : nil)
    }
}

extension View {
    /// Apply to each row view inside a List or Form section to get a true-black background in AMOLED mode.
    func themedRow() -> some View {
        modifier(ThemedRowStyle())
    }
}
