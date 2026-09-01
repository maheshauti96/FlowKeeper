import SwiftUI

struct BoardView: View {
    var store: FlowStore
    var session: BoardSession
    var onReveal: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            NowStrip(
                store: store,
                session: session,
                items: filtered(store.items.filter { store.status(for: $0.statusID).isNow })
            )
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
            columns
        }
        .background(Palette.cream)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if session.editor != .closed {
                ZStack {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .onTapGesture { session.closeEditor() }
                    CardDialog(store: store, session: session, onOpenOnDeck: onReveal)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Board")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("What’s in your head, what’s planned, and who’s holding it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.inkMuted)
            }
            Spacer()
            ActorFilterBar(store: store, selection: session.actorFilterBinding)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.inkMuted)
                TextField("Search flows", text: session.queryBinding)
                    .textFieldStyle(.plain)
                    .frame(width: 160)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))

            Button {
                session.beginCreate(statusID: store.defaultStatus().id)
            } label: {
                Label("New idea", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: 0x2F3A4A))
            .accessibilityLabel("New idea")
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var columns: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(store.boardStatuses) { status in
                    BoardColumn(
                        store: store,
                        session: session,
                        status: status,
                        items: filtered(store.items(in: status.id)),
                        onReveal: onReveal
                    )
                    .frame(width: 210)
                }
                AddStatusColumn(store: store)
                    .frame(width: 180)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
    }

    private func filtered(_ items: [FlowItem]) -> [FlowItem] {
        items.filter { store.matches($0, query: session.query, filter: .all, actorFilter: session.actorFilter) }
    }
}

struct AddStatusColumn: View {
    var store: FlowStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Statuses")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text("Add a column for a new kind of work.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.inkMuted)
            Button {
                if let name = TextPrompt.ask(
                    title: "New status",
                    message: "This becomes a column on the board. The edge deck sorts cards in this same order.",
                    confirm: "Add"
                ) {
                    store.addStatus(name: name)
                }
            } label: {
                Label("Add status", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Palette.ink.opacity(0.18))
        )
    }
}

struct NowStrip: View {
    var store: FlowStore
    var session: BoardSession
    var items: [FlowItem]

    private var groups: [(FlowActor?, [FlowItem])] {
        var result: [(FlowActor?, [FlowItem])] = []
        for actor in store.actors {
            let held = items.filter { $0.actorID == actor.id }
            if !held.isEmpty {
                result.append((actor, held))
            }
        }
        let unassigned = items.filter { $0.actorID == nil }
        if !unassigned.isEmpty {
            result.append((nil, unassigned))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("NOW")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(Palette.inkMuted)
                Text("Work in flight, by who is holding it")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.inkMuted.opacity(0.8))
                Spacer()
                Text(items.isEmpty ? "Nothing ongoing" : "\(items.count) in flight")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.inkMuted)
            }

            if groups.isEmpty {
                EmptyColumn(text: "Move a card into Ongoing, or capture a new idea with ⌥⌘N.")
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                ActorAvatar(actor: group.0, size: 20)
                                Text(group.0?.name ?? "Unassigned")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("\(group.1.count)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(Palette.inkMuted)
                                    .padding(.horizontal, 6)
                                    .background(Capsule().fill(Color.white))
                            }
                            ForEach(group.1) { item in
                                Button {
                                    session.beginEdit(item)
                                } label: {
                                    HStack(spacing: 8) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(item.swatch.dash)
                                            .frame(width: 4, height: 22)
                                        Text(item.displayTitle)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Palette.ink)
                                            .lineLimit(1)
                                        Spacer()
                                        Image(systemName: "square.and.pencil")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(Palette.inkMuted)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(item.swatch.fill.opacity(0.85))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: 320, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.7))
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Palette.hairline, lineWidth: 1)
        )
    }
}

struct BoardColumn: View {
    var store: FlowStore
    var session: BoardSession
    var status: FlowStatus
    var items: [FlowItem]
    var onReveal: (UUID) -> Void

    private var targeted: Bool { session.targetedStatusID == status.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(status.tint).frame(width: 8, height: 8)
                Text(status.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                if status.isSticky {
                    Image(systemName: "rectangle.trailinghalf.inset.filled")
                        .font(.system(size: 10))
                        .foregroundStyle(status.tint)
                        .help("This status sits on the edge deck")
                }
                Text("\(items.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.inkMuted)
                statusMenu
            }
            Text(status.detail.isEmpty ? " " : status.detail)
                .font(.system(size: 10))
                .foregroundStyle(Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        BoardCard(store: store, session: session, item: item, onReveal: onReveal)
                            .draggable(item.id.uuidString)
                            .dropDestination(for: String.self) { ids, _ in
                                drop(ids, before: item.id)
                            }
                    }
                    if items.isEmpty {
                        EmptyColumn(text: "Drop here")
                            .dropDestination(for: String.self) { ids, _ in
                                drop(ids, before: nil)
                            } isTargeted: { hovering in
                                session.targetedStatusID = hovering ? status.id : nil
                            }
                    }
                }
                .padding(4)
            }
            .dropDestination(for: String.self) { ids, _ in
                drop(ids, before: nil)
            } isTargeted: { hovering in
                session.targetedStatusID = hovering ? status.id : nil
            }

            Button {
                session.beginCreate(statusID: status.id)
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.inkMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(targeted ? status.tint.opacity(0.14) : Palette.boardColumn)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(targeted ? status.tint.opacity(0.7) : Palette.hairline, lineWidth: 1)
        )
    }

    private var statusMenu: some View {
        Menu {
            Button("Rename…") {
                if let name = TextPrompt.ask(title: "Rename status", message: "Shown on the board and used to sort the edge deck.", defaultValue: status.name) {
                    store.renameStatus(status.id, to: name)
                }
            }
            Button("Edit description…") {
                if let detail = TextPrompt.ask(title: "Status description", message: "A short line under the column title.", defaultValue: status.detail, confirm: "Save") {
                    store.setStatusDetail(status.id, detail: detail)
                }
            }
            Button("Cycle colour") { store.cycleStatusColor(status.id) }
            Button(status.isNow ? "Remove from Now" : "Show in Now") {
                store.toggleStatusNow(status.id)
            }
            Button(status.isSticky ? "Remove from edge deck" : "Show on edge deck") {
                store.toggleStatusSticky(status.id)
            }
            Divider()
            Button("Move left") { store.shiftStatus(status.id, by: -1) }
            Button("Move right") { store.shiftStatus(status.id, by: 1) }
            Divider()
            Button("Hide from board") {
                store.setStatusShowsOnBoard(status.id, false)
            }
            Button("Delete status…") {
                store.deleteStatus(status.id)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.inkMuted)
                .frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
    }

    private func drop(_ ids: [String], before neighbor: UUID?) -> Bool {
        var did = false
        for raw in ids {
            if let id = UUID(uuidString: raw) {
                store.move(id, to: status.id, before: neighbor)
                did = true
            }
        }
        return did
    }
}

struct BoardCard: View {
    var store: FlowStore
    var session: BoardSession
    var item: FlowItem
    var onReveal: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(item.swatch.dash)
                .frame(height: 4)
            Text(item.displayTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if !item.preview.isEmpty {
                Text(item.preview)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.inkMuted)
                    .lineLimit(2)
            }
            HStack {
                ActorChip(actor: store.actor(for: item.actorID), compact: false)
                Spacer()
                if item.onDeck {
                    Image(systemName: "rectangle.trailinghalf.inset.filled")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.inkMuted)
                }
                Text(RelativeDate.string(item.updatedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.inkMuted)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        )
        .onTapGesture { session.beginEdit(item) }
        .contextMenu {
            Button("Open on deck") { onReveal(item.id) }
            Menu("Move to") {
                ForEach(store.orderedStatuses) { status in
                    Button(status.name) { store.move(item.id, to: status.id) }
                }
            }
            Menu("Assign") {
                Button("Unassigned") { store.assign(item.id, to: nil) }
                ForEach(store.actors) { actor in
                    Button(actor.name) { store.assign(item.id, to: actor.id) }
                }
            }
            Button(item.onDeck ? "Remove from deck" : "Pin to deck") {
                store.pinToDeck(item.id, pin: !item.onDeck)
            }
            Button("Delete") { store.delete(item.id) }
        }
    }
}
