import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    var store: FlowStore
    var holder: LibraryFilterHolder
    var onReveal: (UUID) -> Void

    private var filtered: [FlowItem] {
        store.items
            .filter { store.matches($0, query: holder.query, filter: holder.filter, actorFilter: holder.actorFilter) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var selected: FlowItem? {
        if let id = holder.selectedID {
            return store.items.first { $0.id == id }
        }
        return filtered.first
    }

    var body: some View {
        HSplitView {
            listPane
                .frame(minWidth: 320, idealWidth: 380)
            detailPane
                .frame(minWidth: 420)
        }
        .background(Palette.cream)
        .onAppear {
            if holder.selectedID == nil {
                holder.selectedID = filtered.first?.id
            }
        }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("All Flows")
                    .font(AppFont.ui(20, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button("Export…") { exportSelected() }
                    .controlSize(.small)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.inkMuted)
                TextField("Search titles, bodies, tags", text: holder.queryBinding)
                    .textFieldStyle(.plain)
                    .paletteFieldInk()
                Text("\(filtered.count)")
                    .font(AppFont.ui(11, weight: .medium))
                    .foregroundStyle(Palette.inkMuted)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    FilterPill(title: "All", selected: holder.filter == .all) {
                        holder.filter = .all
                    }
                    FilterPill(title: "On deck", selected: holder.filter == .onDeck) {
                        holder.filter = .onDeck
                    }
                    ForEach(store.orderedStatuses) { status in
                        FilterPill(title: status.name, selected: holder.filter == .status(status.id)) {
                            holder.filter = .status(status.id)
                        }
                    }
                }
            }

            ActorFilterBar(store: store, selection: holder.actorFilterBinding)

            Divider().opacity(0.4)

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("Nothing in this view")
                        .font(AppFont.ui(13, weight: .medium))
                        .foregroundStyle(Palette.inkMuted)
                    Text("Capture with ⌥⌘N, or loosen the filters.")
                        .font(AppFont.ui(12))
                        .foregroundStyle(Palette.inkMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: holder.selectedBinding) {
                    ForEach(filtered) { item in
                        LibraryRow(store: store, item: item)
                            .tag(Optional(item.id))
                            .listRowBackground(Color.clear)
                            .contextMenu {
                                Button("Open on deck") { onReveal(item.id) }
                                Button(item.onDeck ? "Remove from deck" : "Pin to deck") {
                                    store.pinToDeck(item.id, pin: !item.onDeck)
                                }
                                Button("Archive") { store.archive(item.id) }
                                Button("Delete") { store.delete(item.id) }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(18)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let item = selected, let live = store.items.first(where: { $0.id == item.id }) {
            LibraryDetail(store: store, item: live, onReveal: onReveal)
        } else {
            VStack(spacing: 8) {
                Text("Select a flow")
                    .font(AppFont.ui(15, weight: .medium))
                    .foregroundStyle(Palette.inkMuted)
                Text("Every idea you capture lives here, even after it leaves the deck.")
                    .font(AppFont.ui(12))
                    .foregroundStyle(Palette.inkMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func exportSelected() {
        let targets: [FlowItem]
        if let selected {
            targets = [selected]
        } else {
            targets = filtered
        }
        guard !targets.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "flowkeeper-export.md"
        panel.canCreateDirectories = true
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let markdown = store.exportMarkdown(targets)
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

struct LibraryRow: View {
    var store: FlowStore
    var item: FlowItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(item.swatch.dash)
                .frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.displayTitle)
                        .font(AppFont.ui(13, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    StageChip(status: store.status(for: item.statusID))
                    PriorityBadge(priority: item.priority)
                    Text(RelativeDate.string(item.updatedAt))
                        .font(AppFont.ui(11))
                        .foregroundStyle(Palette.inkMuted)
                        .frame(width: 36, alignment: .trailing)
                }
                Text(item.preview.isEmpty ? " " : item.preview)
                    .font(AppFont.ui(12))
                    .foregroundStyle(Palette.inkMuted)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let actor = store.actor(for: item.actorID) {
                        ActorChip(actor: actor, compact: false)
                    }
                    if item.onDeck {
                        Text("ON DECK")
                            .font(AppFont.ui(9, weight: .semibold))
                            .foregroundStyle(Palette.inkMuted)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct LibraryDetail: View {
    var store: FlowStore
    var item: FlowItem
    var onReveal: (UUID) -> Void

    var body: some View {
        let swatch = item.swatch
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(swatch.dash).frame(width: 8, height: 8)
                    Text(item.onDeck ? "ON DECK" : store.status(for: item.statusID).chip)
                        .font(AppFont.ui(11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Palette.inkMuted)
                }
                Spacer()
                Button("Open on deck") { onReveal(item.id) }
                Button(store.status(for: item.statusID).dropsFromDeck ? "Reopen" : "Mark done") {
                    if store.status(for: item.statusID).dropsFromDeck {
                        store.move(item.id, to: store.nowStatuses.first?.id ?? store.defaultStatus().id)
                    } else if let done = store.doneStatus() {
                        store.move(item.id, to: done.id)
                    }
                }
                Button("Export…") { exportOne() }
                Button("Delete") { store.delete(item.id) }
                    .foregroundStyle(.red)
            }
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: store.titleBinding(item.id))
                    .textFieldStyle(.plain)
                    .font(AppFont.ui(22, weight: .semibold))
                    .foregroundStyle(swatch.ink)
                    .tint(swatch.ink)
                NoteBodyView(
                    text: store.bodyBinding(item.id),
                    font: AppFont.ns(15),
                    color: swatch.nsInk.withAlphaComponent(0.92),
                    showsScroller: true
                )
                .frame(minHeight: 180)
                HStack {
                    Text("Created \(RelativeDate.string(item.createdAt)) · Updated \(RelativeDate.string(item.updatedAt))")
                        .font(AppFont.ui(11))
                        .foregroundStyle(swatch.ink.opacity(0.5))
                    Spacer()
                }
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(swatch.fill)
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            )

            HStack(spacing: 12) {
                ActorAssignMenu(store: store, item: item)
                StageAssignMenu(store: store, item: item)
                Button(item.onDeck ? "Remove from deck" : "Pin to deck") {
                    store.pinToDeck(item.id, pin: !item.onDeck)
                }
                .controlSize(.small)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(StickySwatch.all) { sw in
                        Button {
                            store.update(item.id) { $0.colorID = sw.id }
                        } label: {
                            Circle()
                                .fill(sw.fill)
                                .overlay(
                                    Circle().stroke(swatch.id == sw.id ? Color.black.opacity(0.45) : Color.black.opacity(0.08), lineWidth: swatch.id == sw.id ? 2 : 1)
                                )
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer()
        }
        .padding(22)
    }

    private func exportOne() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(item.displayTitle).md"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            try? store.exportMarkdown([item]).write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
