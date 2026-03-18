import SwiftUI

// MARK: - SRHTErrorBanner ViewModifier

/// Displays a dismissible error banner at the top of the screen.
/// Attach to any view with `.srhtErrorBanner(error:)`.
struct SRHTErrorBanner: ViewModifier {
    @Binding var error: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message = error {
                    banner(message)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: error)
    }

    @ViewBuilder
    private func banner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(3)

            Spacer()

            Button {
                error = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(12)
        .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}

extension View {
    /// Attach an error banner that shows at the top when `error` is non-nil.
    func srhtErrorBanner(error: Binding<String?>) -> some View {
        modifier(SRHTErrorBanner(error: error))
    }
}

// MARK: - Shared Screen States

struct SRHTLoadingStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SRHTErrorStateView: View {
    let title: String
    let message: String
    let retryAction: (() async -> Void)?

    var body: some View {
        ContentUnavailableView {
            SwiftUI.Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if let retryAction {
                Button("Retry") {
                    Task { await retryAction() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - NoConnectionView

/// Empty state view shown when the device is offline. Includes a retry button.
struct NoConnectionView: View {
    var retryAction: () async -> Void

    var body: some View {
        ContentUnavailableView {
            SwiftUI.Label("No Connection", systemImage: "wifi.slash")
        } description: {
            Text("Check your internet connection and try again.")
        } actions: {
            Button {
                Task { await retryAction() }
            } label: {
                Text("Retry")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Connectivity Overlay

/// ViewModifier that shows NoConnectionView when the device is offline and
/// there is no content to display. When content exists, shows a subtle
/// offline indicator instead.
struct ConnectivityOverlay: ViewModifier {
    @Environment(NetworkMonitor.self) private var networkMonitor
    let hasContent: Bool
    var retryAction: () async -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if !networkMonitor.isConnected, !hasContent {
                    NoConnectionView(retryAction: retryAction)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !networkMonitor.isConnected, hasContent {
                    offlineBadge
                }
            }
    }

    private var offlineBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .font(.caption2)
            Text("Offline — showing cached data")
                .font(.caption2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.orange.gradient, in: Capsule())
        .padding(.bottom, 4)
    }
}

extension View {
    /// Overlay a no-connection view when offline with no content, or a
    /// subtle offline badge when showing cached data.
    func connectivityOverlay(hasContent: Bool, retryAction: @escaping () async -> Void) -> some View {
        modifier(ConnectivityOverlay(hasContent: hasContent, retryAction: retryAction))
    }
}
