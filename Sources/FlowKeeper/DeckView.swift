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
                deck.applyLayout(animated: true)
                deck.syncRoot()
            }
    }

    private var drawerSlotWidth: CGFloat {
        if case .expanded = deck.mode {
            return deck.expandedSize.width
        }
        return DeckMetrics.previewWidth
    }

    @ViewBuilder
    private var drawerPaper: some View {
        ZStack(alignment: .topTrailing) {
            if case .expanded(let id) = deck.mode, let item = store.items.first(where: { $0.id == id }) {
                ExpandedNote(store: store, item: item, deck: deck)
                    .frame(width: deck.expandedSize.width, height: deck.expandedSize.height)
                    .padding(.top, CGFloat(items.firstIndex(where: { $0.id == id }) ?? 0) * DeckMetrics.tabStride)
                    .offset(x: deck.drawerOpen ? 0 : deck.expandedSize.width)
            } else if let previewID = deck.previewID,
                      let item = store.items.first(where: { $0.id == previewID }),
                      let index = items.firstIndex(where: { $0.id == previewID }) {
                PeekPreview(
                    item: item,
                    status: store.status(for: item.statusID),
                    actorName: store.actor(for: item.actorID)?.name
                )
                    .id(previewID)
                    .padding(.top, CGFloat(index) * DeckMetrics.tabStride)
                    .offset(x: deck.drawerOpen ? 0 : DeckMetrics.previewWidth)
                    .onTapGesture { deck.openFromClick(item.id) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private var openDeck: some View {
        HStack(alignment: .top, spacing: 0) {
            drawerPaper
                .frame(width: drawerSlotWidth)

            VStack(alignment: .trailing, spacing: DeckMetrics.tabStride - DeckMetrics.tabHeight) {
                ForEach(items) { item in
                    let selected: Bool = {
                        if case .expanded(let id) = deck.mode { return id == item.id }
                        return false
                    }()
                    PeekSpine(item: item, selected: selected)
                        .onTapGesture { deck.openFromClick(item.id) }
                        .contextMenu { itemMenu(item) }
                }

                plusButton
                    .padding(.top, DeckMetrics.plusGap)
                    .padding(.trailing, 2)
            }
        }
        .padding(.top, DeckMetrics.topGutter)
        .padding(.leading, DeckMetrics.shadowPad)
        .overlay(alignment: .topTrailing) {
            if store.hiddenDeckCount > 0 {
                Text("+\(store.hiddenDeckCount)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .offset(x: -36, y: 4)
                    .onTapGesture { AppDelegate.shared.openLibrary(filter: .onDeck) }
            }
        }
        .overlay(alignment: .bottom) {
            if let undo = store.pendingUndo {
                undoBanner(undo)
                    .padding(.bottom, 8)
            }
        }
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
                    .font(.system(size: 12, weight: .semibold))
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

    @ViewBuilder
    private func itemMenu(_ item: FlowItem) -> some View {
        Button("Open") { deck.expand(item.id) }
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
}

struct PeekSpine: View {
    var item: FlowItem
    var selected: Bool

    var body: some View {
        ZStack {
            Text(item.tabLabel)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(item.swatch.ink.opacity(0.82))
                .lineLimit(1)
                .rotationEffect(.degrees(90))
                .frame(width: DeckMetrics.tabHeight - 16, height: DeckMetrics.tabWidth)
        }
        .frame(width: DeckMetrics.tabWidth, height: DeckMetrics.tabHeight)
        .background(
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 13, bottomLeading: 13, bottomTrailing: 0, topTrailing: 0)
            )
            .fill(item.swatch.fill)
            .shadow(color: .black.opacity(selected ? 0.2 : 0.12), radius: 5, x: -1, y: 1)
        )
        .contentShape(Rectangle())
        .accessibilityLabel(item.displayTitle)
    }
}

struct PeekPreview: View {
    var item: FlowItem
    var status: FlowStatus
    var actorName: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.displayTitle)
                    .font(NoteFont.title(18))
                    .foregroundStyle(item.swatch.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    StageChip(status: status)
                    if let actorName {
                        Text(actorName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(item.swatch.ink.opacity(0.55))
                    }
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

            DashedFold(color: item.swatch.ink)
        }
        .frame(width: DeckMetrics.previewWidth, height: DeckMetrics.tabHeight)
        .background(
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 13, bottomLeading: 13, bottomTrailing: 0, topTrailing: 0)
            )
            .fill(item.swatch.fill)
            .shadow(color: .black.opacity(0.22), radius: 12, x: -2, y: 2)
        )
        .accessibilityLabel(item.displayTitle)
    }
}

struct ExpandedNote: View {
    var store: FlowStore
    var item: FlowItem
    var deck: DeckController

    var body: some View {
        let swatch = item.swatch
        HStack(spacing: 0) {
            ZStack {
                Text(item.tabLabel)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(swatch.ink.opacity(0.82))
                    .lineLimit(1)
                    .rotationEffect(.degrees(90))
                    .frame(width: 86, height: 22)
            }
            .frame(width: 28)

            DashedFold(color: swatch.ink)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Button {
                        AppDelegate.shared.openBoard(editing: item)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(swatch.ink)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() }
                        else { NSCursor.pop() }
                    }
                    .help("Edit on board")
                    .accessibilityLabel("Edit on board")

                    TextField("Title", text: store.titleBinding(item.id))
                        .textFieldStyle(.plain)
                        .font(NoteFont.title(22))
                        .foregroundStyle(swatch.ink)
                    Button {
                        deck.collapse()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(swatch.ink.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }

                NoteBodyView(
                    text: store.bodyBinding(item.id),
                    font: NoteFont.nsBody,
                    color: swatch.nsInk.withAlphaComponent(0.9),
                    showsScroller: true
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                HStack(spacing: 8) {
                    ActorAssignMenu(store: store, item: item)
                    StageAssignMenu(store: store, item: item)
                    Spacer()
                    Button {
                        store.cycleColor(item.id)
                    } label: {
                        Circle().fill(swatch.dash).frame(width: 10, height: 10)
                    }
                    .buttonStyle(.plain)
                    .help("Cycle colour (⌘.)")
                }
                .padding(.top, 2)
            }
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(swatch.fill)
                .shadow(color: .black.opacity(0.22), radius: 16, x: -2, y: 4)
        )
        .overlay(alignment: .leading) {
            Color.clear
                .frame(width: 8)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering { NSCursor.resizeLeftRight.push() }
                    else { NSCursor.pop() }
                }
                .gesture(resizeGesture(widthSign: -1, heightSign: 0))
        }
        .overlay(alignment: .bottom) {
            Color.clear
                .frame(height: 8)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering { NSCursor.resizeUpDown.push() }
                    else { NSCursor.pop() }
                }
                .gesture(resizeGesture(widthSign: 0, heightSign: 1))
        }
        .overlay(alignment: .bottomLeading) {
            Color.clear
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering { NSCursor.crosshair.push() }
                    else { NSCursor.pop() }
                }
                .gesture(resizeGesture(widthSign: -1, heightSign: 1))
        }
        .overlay(alignment: .bottomTrailing) {
            PaperResizeGrip(ink: swatch.ink)
                .gesture(resizeGesture(widthSign: 1, heightSign: 1))
                .padding(.trailing, 6)
                .padding(.bottom, 6)
        }
        .onExitCommand { deck.collapse() }
    }

    private func resizeGesture(widthSign: CGFloat, heightSign: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                deck.beginExpandedResize()
                let origin = deck.resizeOrigin ?? deck.expandedSize
                deck.setExpandedSize(CGSize(
                    width: origin.width + value.translation.width * widthSign,
                    height: origin.height + value.translation.height * heightSign
                ))
            }
            .onEnded { _ in
                deck.endExpandedResize()
            }
    }
}

private struct PaperResizeGrip: View {
    var ink: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 3, y: size.height - 3))
            path.addLine(to: CGPoint(x: size.width - 3, y: size.height - 3))
            path.addLine(to: CGPoint(x: size.width - 3, y: 3))
            context.stroke(
                path,
                with: .color(ink.opacity(0.38)),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            )
            var inner = Path()
            inner.move(to: CGPoint(x: 8, y: size.height - 3))
            inner.addLine(to: CGPoint(x: size.width - 3, y: size.height - 3))
            inner.addLine(to: CGPoint(x: size.width - 3, y: 8))
            context.stroke(
                inner,
                with: .color(ink.opacity(0.22)),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: 16, height: 16)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { NSCursor.crosshair.push() }
            else { NSCursor.pop() }
        }
        .help("Resize")
        .accessibilityLabel("Resize note")
    }
}
