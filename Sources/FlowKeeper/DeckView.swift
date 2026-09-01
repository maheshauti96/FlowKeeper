import AppKit
import SwiftUI

struct DeckView: View {
    var store: FlowStore
    var deck: DeckController

    private var items: [FlowItem] { store.visibleDeckItems }

    var body: some View {
        Group {
            switch deck.mode {
            case .dormant:
                dormantPill
            case .peek, .expanded:
                openDeck
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .contextMenu { deckMenu }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Flow Keeper deck")
    }

    private var dormantPill: some View {
        let count = max(items.count, 0)
        return Capsule()
            .fill(.ultraThinMaterial)
            .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.6))
            .overlay {
                VStack(spacing: 6) {
                    if items.isEmpty {
                        Capsule()
                            .fill(Color.white.opacity(0.35))
                            .frame(width: 6, height: 10)
                    } else {
                        ForEach(items) { item in
                            Capsule()
                                .fill(item.swatch.dash)
                                .frame(width: 6, height: 10)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(width: DeckMetrics.pillWidth, height: CGFloat(max(count, 1)) * 16 + 20)
            .shadow(color: .black.opacity(0.18), radius: 6, x: -1, y: 1)
            .onTapGesture {
                deck.mode = .peek
                deck.startFan()
                deck.applyLayout(animated: true)
                deck.syncRoot()
            }
    }

    private var openDeck: some View {
        OpenDeckStack(store: store, deck: deck, items: items)
    }

    @ViewBuilder
    private var deckMenu: some View {
        Button("New idea") { deck.createAndExpand(statusID: FlowStatus.ideaID) }
        Button("Board") { deck.onOpenBoard?() }
        Button("All Flows") { deck.onOpenLibrary?(.all) }
        Button("Archive") { deck.onOpenLibrary?(.status(FlowStatus.archivedID)) }
        Divider()
        Button(store.showOverFullscreen ? "Don’t show over full-screen apps" : "Show over full-screen apps") {
            store.showOverFullscreen.toggle()
            store.saveNow()
            deck.applyFullscreenPreference()
            AppDelegate.shared.rebuildMenu()
        }
        Divider()
        Button("Quit Flow Keeper") { deck.onQuit?() }
    }
}

struct OpenDeckStack: View {
    var store: FlowStore
    var deck: DeckController
    var items: [FlowItem]

    var body: some View {
        VStack(alignment: .trailing, spacing: DeckMetrics.tabStride - DeckMetrics.tabHeight) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let selected: Bool = {
                    if case .expanded(let id) = deck.mode { return id == item.id }
                    return false
                }()
                PeekSpine(
                    item: item,
                    selected: selected,
                    peeked: deck.previewID == item.id,
                    index: index,
                    appeared: deck.fanOpen
                )
                .onTapGesture { deck.openFromClick(item.id) }
                .contextMenu { itemMenu(item) }
            }

            plusButton
                .padding(.top, DeckMetrics.plusGap)
                .padding(.trailing, 1)
                .opacity(deck.fanOpen ? 1 : 0)
                .animation(
                    .easeOut(duration: 0.18).delay(Double(max(items.count, 1)) * DeckMetrics.fanStagger),
                    value: deck.fanOpen
                )
        }
        .padding(.top, DeckMetrics.topGutter)
        .padding(.leading, DeckMetrics.shadowPad)
        .overlay(alignment: .topTrailing) {
            if store.hiddenDeckCount > 0 {
                Text("+\(store.hiddenDeckCount)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .offset(x: -28, y: 4)
                    .onTapGesture { AppDelegate.shared.openLibrary(filter: .onDeck) }
            }
        }
        .overlay(alignment: .bottom) {
            if let undo = store.pendingUndo {
                undoBanner(undo)
                    .padding(.bottom, 8)
            }
        }
        .animation(.easeOut(duration: 0.12), value: deck.previewID)
        .animation(.easeOut(duration: 0.16), value: deck.mode)
    }

    private var plusButton: some View {
        Menu {
            Button("New idea") { deck.createAndExpand(statusID: FlowStatus.ideaID) }
            Button("Now for you") {
                deck.createAndExpand(statusID: store.nowStatuses.first?.id, actorID: FlowActor.meID)
            }
            Button("Now for agent") {
                deck.createAndExpand(statusID: store.nowStatuses.first?.id, actorID: FlowActor.agentID)
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.6))
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: DeckMetrics.plusSize, height: DeckMetrics.plusSize)
            .shadow(color: .black.opacity(0.16), radius: 6, y: 1)
        }
        .menuStyle(.borderlessButton)
        .frame(width: DeckMetrics.plusSize, height: DeckMetrics.plusSize)
    }

    private func undoBanner(_ undo: UndoPayload) -> some View {
        HStack(spacing: 10) {
            Text("Deleted “\(undo.item.displayTitle)”")
                .font(.system(size: 11))
            Button("Undo") { store.undoDelete() }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
    }

    @ViewBuilder
    private func itemMenu(_ item: FlowItem) -> some View {
        Button("Open") { deck.expand(item.id) }
        Button("Rename tab…") { renameTab(item) }
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
        Button("Cycle colour") { store.cycleColor(item.id) }
        Divider()
        Button(item.onDeck ? "Remove from deck" : "Pin to deck") {
            store.pinToDeck(item.id, pin: !item.onDeck)
        }
        Button("Archive") {
            store.archive(item.id)
            if case .expanded(let id) = deck.mode, id == item.id { deck.collapse() }
        }
        Button("Delete") {
            store.delete(item.id)
            if case .expanded(let id) = deck.mode, id == item.id { deck.collapse() }
        }
    }

    private func renameTab(_ item: FlowItem) {
        let alert = NSAlert()
        alert.messageText = "Tab name"
        alert.informativeText = "Short label on the edge. Clear it to use a word from the title."
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: item.tabName)
        field.placeholderString = FlowItem.shortTabName(from: item.displayTitle)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.update(item.id) { $0.tabName = field.stringValue }
    }
}

struct PeekSpine: View {
    var item: FlowItem
    var selected: Bool
    var peeked: Bool
    var index: Int
    var appeared: Bool

    var body: some View {
        ZStack {
            Text(item.tabLabel)
                .font(.system(size: 9, weight: .medium))
                .tracking(1.6)
                .foregroundStyle(item.swatch.ink.opacity(0.78))
                .lineLimit(1)
                .rotationEffect(.degrees(90))
                .frame(width: DeckMetrics.tabHeight - 16, height: DeckMetrics.tabWidth)
        }
        .frame(width: DeckMetrics.tabWidth, height: DeckMetrics.tabHeight)
        .background(
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 11, bottomLeading: 11, bottomTrailing: 0, topTrailing: 0)
            )
            .fill(item.swatch.fill)
            .shadow(color: .black.opacity(selected || peeked ? 0.22 : 0.11), radius: peeked ? 8 : 5, x: -1, y: 1)
        )
        .overlay(alignment: .leading) {
            DashedFold(color: item.swatch.ink)
                .padding(.vertical, 12)
                .padding(.leading, 5)
        }
        .offset(x: appeared ? (peeked || selected ? -DeckMetrics.peekNudge : 0) : 18)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.2).delay(Double(index) * DeckMetrics.fanStagger), value: appeared)
        .contentShape(Rectangle())
        .accessibilityLabel(item.displayTitle)
    }
}
