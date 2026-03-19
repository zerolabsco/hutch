import SwiftUI
import UIKit

enum SRHTShareTarget: String {
    case repository = "repository"
    case commit = "commit"
    case file = "file"
    case build = "build"
    case tracker = "tracker"
    case ticket = "ticket"
    case profile = "profile"
    case paste = "paste"

    var fallbackMessage: String {
        "This \(rawValue) does not have a valid web URL to share."
    }
}

struct SRHTShareButton<Label: View>: View {
    let url: URL?
    let target: SRHTShareTarget
    @ViewBuilder let label: () -> Label

    @State private var isShowingShareSheet = false
    @State private var isShowingFallbackAlert = false

    var body: some View {
        Button {
            if url != nil {
                isShowingShareSheet = true
            } else {
                isShowingFallbackAlert = true
            }
        } label: {
            label()
        }
        .sheet(isPresented: $isShowingShareSheet) {
            if let url {
                ShareSheet(activityItems: [url])
            }
        }
        .alert("Share Unavailable", isPresented: $isShowingFallbackAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(target.fallbackMessage)
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
