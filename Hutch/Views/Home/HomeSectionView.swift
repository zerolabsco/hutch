import SwiftUI

struct HomeSectionView<Accessory: View, Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let accessory: Accessory
    let content: Content

    init(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._isExpanded = isExpanded
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        Section {
            if isExpanded {
                content
            }
        } header: {
            HomeSectionHeader(
                title: title,
                isExpanded: $isExpanded,
                accessory: accessory
            )
        }
    }
}

private struct HomeSectionHeader<Accessory: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(title)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse \(title)" : "Expand \(title)")

            Spacer(minLength: 8)

            accessory
        }
        .textCase(nil)
    }
}
