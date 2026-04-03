import SwiftUI

/// Fetches and renders a single man.sr.ht page.
/// Internal man.sr.ht links update the current URL in-place rather than
/// opening the browser, so the user can follow wiki links without leaving
/// the view.
struct ManPageDetailView: View {
    let initialURL: URL

    @Environment(\.colorScheme) private var colorScheme
    @State private var currentURL: URL
    @State private var page: ManPage?
    @State private var isLoading = false
    @State private var error: String?

    init(url: URL) {
        initialURL = url
        _currentURL = State(initialValue: url)
    }

    var body: some View {
        ScrollView {
            if isLoading {
                SRHTLoadingStateView(message: "Loading page…")
                    .padding(.top, 40)
            } else if let error {
                SRHTErrorStateView(
                    title: "Couldn't Load Page",
                    message: error,
                    retryAction: { await loadPage() }
                )
                .padding()
            } else if let page {
                HTMLWebView(
                    html: page.contentHTML,
                    colorScheme: colorScheme,
                    style: .readme,
                    baseURL: page.url,
                    onInterceptURL: { url in
                        guard let destinationURL = normalizedManPageURL(for: url) else {
                            return false
                        }
                        currentURL = destinationURL
                        return true
                    }
                )
                .padding()
            }
        }
        .navigationTitle(page?.title ?? "Documentation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let page {
                    Link(destination: page.url) {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .task(id: currentURL) {
            await loadPage()
        }
    }

    private func loadPage() async {
        isLoading = true
        error = nil

        do {
            page = try await ManPageService.fetch(url: currentURL)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func normalizedManPageURL(for url: URL) -> URL? {
        if ManPageService.isTrustedDocumentationURL(url) {
            return url
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "about" || scheme == "file" else {
            return nil
        }

        let rawPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !rawPath.isEmpty else {
            if currentURL.host?.lowercased() == "srht.site" {
                return ManPageService.pagesBaseURL
            }
            return ManPageService.baseURL
        }

        if currentURL.host?.lowercased() == "srht.site" {
            return URL(string: "https://srht.site/\(rawPath)") ?? ManPageService.pagesBaseURL
        }
        return URL(string: "https://man.sr.ht/\(rawPath)/") ?? ManPageService.baseURL
    }
}
