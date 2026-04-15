import SwiftUI

/// A sheet that fetches and displays a single repository file by path,
/// using the `repository.path()` GraphQL field — one API call, no tree traversal.
struct LinkedFileSheetView: View {
    let rid: String
    let service: SRHTService
    let client: SRHTClient
    let request: LinkedFileRequest

    @AppStorage(AppStorageKeys.wrapRepositoryFileLines) private var wrapLines = false
    @Environment(\.dismiss) private var dismiss

    @State private var entry: TreeEntry?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    SRHTLoadingStateView(message: "Loading \(request.fileName)…")
                } else if let error {
                    SRHTErrorStateView(
                        title: "Couldn't Load File",
                        message: error,
                        retryAction: { await load() }
                    )
                } else if let entry, let object = entry.object {
                    fileContentView(entry: entry, object: object)
                } else {
                    ContentUnavailableView(
                        "File Not Found",
                        systemImage: "doc.questionmark",
                        description: Text("\(request.path) could not be found in this repository.")
                    )
                }
            }
            .navigationTitle(request.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        let vm = FileTreeViewModel(repositoryRid: rid, service: service, client: client)
        do {
            entry = try await vm.fetchLinkedFile(path: request.path, revspec: request.revspec)
        } catch {
            self.error = error.userFacingMessage
        }
        isLoading = false
    }

    @ViewBuilder
    private func fileContentView(entry: TreeEntry, object: GitObject) -> some View {
        switch object {
        case .textBlob(let blob):
            CodeFileTextView(
                text: blob.text ?? "",
                fileName: entry.name,
                wrapLines: wrapLines
            )
        case .binaryBlob:
            ContentUnavailableView(
                "Binary File",
                systemImage: "doc.zipper",
                description: Text("Binary files cannot be displayed inline.")
            )
        default:
            ContentUnavailableView(
                "Unknown File",
                systemImage: "questionmark.folder",
                description: Text("This object type cannot be displayed.")
            )
        }
    }
}
