import SwiftUI

struct SafariExtensionHelpView: View {
    private let supportedServices = [
        "git.sr.ht",
        "hg.sr.ht",
        "todo.sr.ht",
        "builds.sr.ht",
        "lists.sr.ht",
        "meta.sr.ht",
        "sr.ht",
    ]

    var body: some View {
        Form {
            Section {
                Text("Enable Open in Hutch from Settings > Apps > Safari > Extensions, then turn on Hutch and allow it for SourceHut websites.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .themedRow()
            } header: {
                Text("Enable")
            }

            Section("Supported Services") {
                ForEach(supportedServices, id: \.self) { service in
                    Label(service, systemImage: "checkmark.circle")
                        .themedRow()
                }
            }

            Section {
                Text("The extension adds a Safari action named Open in Hutch. It converts supported SourceHut web URLs into Hutch deep links, then opens the matching screen in the app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .themedRow()

                Text("This is separate from Universal Links. Hutch cannot claim sr.ht links system-wide because those domains are owned by SourceHut and would need Apple App Site Association files hosted there.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .themedRow()
            } header: {
                Text("How It Works")
            }

            Section {
                Text("Pages are never redirected automatically by default. The optional in-page Open in Hutch banner is off unless the extension setting is explicitly enabled.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .themedRow()
            } header: {
                Text("Privacy")
            }
        }
        .themedList()
        .navigationTitle("Safari Extension")
        .navigationBarTitleDisplayMode(.inline)
    }
}
