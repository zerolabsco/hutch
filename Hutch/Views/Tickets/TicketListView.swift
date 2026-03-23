import SwiftUI

struct TicketListView: View {
    let ownerUsername: String
    let trackerName: String
    let trackerId: Int
    let trackerRid: String

    @Environment(AppState.self) private var appState
    @State private var viewModel: TicketListViewModel?
    @State private var showCreateTicketSheet = false
    @State private var createdTicket: TicketSummary?

    var body: some View {
        Group {
            if let viewModel {
                listContent(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading tickets…")
            }
        }
        .navigationTitle(trackerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                SRHTShareButton(url: SRHTWebURL.tracker(ownerUsername: ownerUsername, trackerName: trackerName), target: .tracker) {
                    Image(systemName: "square.and.arrow.up")
                }

                if viewModel != nil {
                    Button {
                        showCreateTicketSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create ticket")
                }
            }
        }
        .sheet(isPresented: $showCreateTicketSheet) {
            if let viewModel {
                CreateTicketSheet(viewModel: viewModel) { ticket in
                    showCreateTicketSheet = false
                    createdTicket = ticket
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { createdTicket != nil },
            set: { isPresented in
                if !isPresented {
                    createdTicket = nil
                }
            }
        )) {
            if let createdTicket {
                TicketDetailView(ownerUsername: ownerUsername, trackerName: trackerName, trackerId: trackerId, trackerRid: trackerRid, ticketId: createdTicket.id)
            }
        }
        .task {
            if viewModel == nil {
                let vm = TicketListViewModel(
                    ownerUsername: ownerUsername,
                    trackerName: trackerName,
                    trackerId: trackerId,
                    client: appState.client
                )
                viewModel = vm
                await vm.loadTickets()
            }
        }
    }

    @ViewBuilder
    private func listContent(_ viewModel: TicketListViewModel) -> some View {
        @Bindable var vm = viewModel

        List {
            // Filter picker
            Section {
                Picker("Filter", selection: $vm.filter) {
                    ForEach(TicketFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            // Tickets
            ForEach(viewModel.filteredTickets) { ticket in
                NavigationLink(value: ticket) {
                    TicketRowView(ticket: ticket)
                }
                .task {
                    await viewModel.loadMoreIfNeeded(currentItem: ticket)
                }
            }

            if viewModel.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .searchable(
            text: $vm.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search tickets"
        )
        .overlay {
            if viewModel.isLoading, viewModel.tickets.isEmpty {
                SRHTLoadingStateView(message: "Loading tickets…")
            } else if let error = viewModel.error, viewModel.tickets.isEmpty {
                SRHTErrorStateView(
                    title: "Couldn't Load Tickets",
                    message: error,
                    retryAction: { await viewModel.loadTickets() }
                )
            } else if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      viewModel.filteredTickets.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            } else if viewModel.filteredTickets.isEmpty, viewModel.error == nil {
                ContentUnavailableView(
                    "No Tickets",
                    systemImage: "ticket",
                    description: Text("No \(viewModel.filter.rawValue.lowercased()) tickets found.")
                )
            }
        }
        .connectivityOverlay(hasContent: !viewModel.filteredTickets.isEmpty) {
            await viewModel.loadTickets()
        }
        .srhtErrorBanner(error: $vm.error)
        .refreshable {
            await viewModel.loadTickets()
        }
        .navigationDestination(for: TicketSummary.self) { ticket in
            TicketDetailView(ownerUsername: ownerUsername, trackerName: trackerName, trackerId: trackerId, trackerRid: trackerRid, ticketId: ticket.id)
        }
    }
}

private struct CreateTicketSheet: View {
    let viewModel: TicketListViewModel
    let onCreated: (TicketSummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var subject = ""
    @State private var descriptionText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Ticket Details") {
                    TextField("Title", text: $subject)
                    TextField("Description (optional)", text: $descriptionText, axis: .vertical)
                        .lineLimit(6...12)
                }
            }
            .navigationTitle("New Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let ticket = await viewModel.createTicket(subject: subject, body: descriptionText) {
                                onCreated(ticket)
                            }
                        }
                    } label: {
                        if viewModel.isCreatingTicket {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Create Ticket")
                        }
                    }
                    .disabled(subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isCreatingTicket)
                }
            }
        }
    }
}

// MARK: - Ticket Row

private struct TicketRowView: View {
    let ticket: TicketSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                TicketStatusIcon(status: ticket.status)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text("#\(ticket.id)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    + Text(" ")
                    + Text(ticket.title)
                        .font(.subheadline)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Text(ticket.submitter.canonicalName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(ticket.created.relativeDescription)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if !ticket.labels.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(ticket.labels) { label in
                        LabelPill(label: label)
                    }
                }
            }

            if !ticket.assignees.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(ticket.assignees.map(\.canonicalName).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Ticket Status Icon

struct TicketStatusIcon: View {
    let status: TicketStatus

    var body: some View {
        Image(systemName: iconName)
            .foregroundStyle(color)
    }

    private var iconName: String {
        switch status {
        case .reported:   "circle"
        case .confirmed:  "circle.inset.filled"
        case .inProgress: "arrow.trianglehead.2.clockwise.rotate.90"
        case .pending:    "clock.fill"
        case .resolved:   "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .reported:   .gray
        case .confirmed:  .blue
        case .inProgress: .yellow
        case .pending:    .orange
        case .resolved:   .green
        }
    }
}

// MARK: - Label Pill

struct LabelPill: View {
    let label: TicketLabel

    var body: some View {
        Text(label.name)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        Color(hex: label.backgroundColor) ?? .gray.opacity(0.2)
    }

    private var foregroundColor: Color {
        Color(hex: label.foregroundColor) ?? .primary
    }
}

// MARK: - Color from hex string

extension Color {
    init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }

        guard hexString.count == 6,
              let hexNumber = UInt64(hexString, radix: 16) else {
            return nil
        }

        let r = Double((hexNumber & 0xFF0000) >> 16) / 255
        let g = Double((hexNumber & 0x00FF00) >> 8) / 255
        let b = Double(hexNumber & 0x0000FF) / 255

        self.init(red: r, green: g, blue: b)
    }

    /// Returns a `#rrggbb` hex string for this color.
    var hexString: String {
        let resolved = resolve(in: .init())
        let r = Int(max(0, min(1, resolved.red)) * 255)
        let g = Int(max(0, min(1, resolved.green)) * 255)
        let b = Int(max(0, min(1, resolved.blue)) * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

// MARK: - Flow Layout (for label pills)

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private struct LayoutResult {
        var positions: [CGPoint]
        var sizes: [CGSize]
        var size: CGSize
    }

    private func layoutSubviews(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
            totalHeight = currentY + lineHeight
        }

        return LayoutResult(
            positions: positions,
            sizes: sizes,
            size: CGSize(width: totalWidth, height: totalHeight)
        )
    }
}
