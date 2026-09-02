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
                deck.enterPeek(fromTap: true)
            }
    }

    private var openDeck: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let selected = isSelected(item)
                NoteSheet(store: store, item: item, deck: deck, revealed: index < deck.fanCount)
                    .zIndex(selected ? 40 : Double(index))
                    .padding(.top, DeckMetrics.topGutter + CGFloat(index) * DeckMetrics.tabStride)
                    .onTapGesture { deck.openFromClick(item.id) }
                    .contextMenu { itemMenu(item) }
            }

            boardTab
                .padding(.top, DeckMetrics.topGutter + deck.tabStackHeight(count: max(items.count, 1)) + DeckMetrics.boardTabGap)
                .zIndex(6)

            plusButton
                .padding(.top, DeckMetrics.topGutter + deck.tabStackHeight(count: max(items.count, 1)) + DeckMetrics.boardTabGap + DeckMetrics.boardTabHeight + DeckMetrics.plusGap)
                .padding(.trailing, 2)
                .zIndex(5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
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
    }

    private func isSelected(_ item: FlowItem) -> Bool {
        if case .expanded(let id) = deck.mode, id == item.id { return true }
        return deck.previewID == item.id
    }


    private var boardTab: some View {
        let shape = UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 10, bottomLeading: 10, bottomTrailing: 0, topTrailing: 0)
        )
        return Button {
            deck.onOpenBoard?()
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.ink.opacity(0.8))
                .frame(width: DeckMetrics.tabWidth, height: DeckMetrics.boardTabHeight)
                .background(shape.fill(Palette.cream))
                .overlay(shape.stroke(Palette.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 4, x: -1, y: 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
        .help("Open the board")
        .accessibilityLabel("Open the board")
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
        .paletteMenuChrome()
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

private enum SheetPhase: Equatable {
    case hidden
    case tab
    case peek
    case expanded
}

struct NoteSheet: View {
    var store: FlowStore
    var item: FlowItem
    var deck: DeckController
    var revealed: Bool

    private var phase: SheetPhase {
        if !revealed { return .hidden }
        if case .expanded(let id) = deck.mode, id == item.id { return .expanded }
        if deck.previewID == item.id { return .peek }
        return .tab
    }

    private var sheetWidth: CGFloat {
        switch phase {
        case .hidden: return 0
        case .tab: return DeckMetrics.tabWidth
        case .peek: return DeckMetrics.peekSheetWidth
        case .expanded: return max(deck.expandedSize.width, DeckMetrics.peekSheetWidth)
        }
    }

    private var sheetHeight: CGFloat {
        switch phase {
        case .hidden: return DeckMetrics.tabHeight
        case .tab, .peek: return DeckMetrics.tabHeight
        case .expanded: return deck.expandedSize.height
        }
    }

    private var interiorWidth: CGFloat {
        max(0, sheetWidth - DeckMetrics.tabWidth)
    }

    private var showInterior: Bool {
        phase == .peek || phase == .expanded
    }

    private var paperShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 13, bottomLeading: 13, bottomTrailing: 0, topTrailing: 0)
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            tabStrip

            HStack(spacing: 0) {
                DashedFold(color: item.swatch.ink)
                    .padding(.vertical, phase == .expanded ? 4 : 0)

                if phase == .expanded {
                    expandedInterior
                } else {
                    peekInterior
                }
            }
            .frame(width: interiorWidth, height: sheetHeight, alignment: .topLeading)
            .opacity(showInterior ? 1 : 0)
            .allowsHitTesting(showInterior)
        }
        .frame(width: sheetWidth, height: sheetHeight, alignment: .topLeading)
        .background(paperShape.fill(item.swatch.fill))
        .clipShape(paperShape)
        .contentShape(paperShape)
        .shadow(color: .black.opacity(showInterior ? 0.22 : 0.12), radius: showInterior ? 12 : 5, x: -2, y: 2)
        .opacity(phase == .hidden ? 0 : 1)
        .animation(DeckController.drawerAnimation, value: deck.previewID)
        .animation(DeckController.drawerAnimation, value: deck.mode)
        .accessibilityLabel(item.displayTitle)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
        .overlay(alignment: .leading) {
            if phase == .expanded { resizeEdge(widthSign: -1, heightSign: 0, width: 8, height: nil) }
        }
        .overlay(alignment: .bottom) {
            if phase == .expanded { resizeEdge(widthSign: 0, heightSign: 1, width: nil, height: 8) }
        }
        .overlay(alignment: .bottomLeading) {
            if phase == .expanded {
                Color.clear
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering { NSCursor.crosshair.push() }
                        else { NSCursor.pop() }
                    }
                    .gesture(resizeGesture(widthSign: -1, heightSign: 1))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if phase == .expanded {
                PaperResizeGrip(ink: item.swatch.ink)
                    .gesture(resizeGesture(widthSign: 1, heightSign: 1))
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
            }
        }
        .onExitCommand {
            if phase == .expanded { deck.collapse() }
        }
    }

    private var tabStrip: some View {
        ZStack {
            Text(item.tabLabel)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(item.swatch.ink.opacity(0.82))
                .lineLimit(1)
                .rotationEffect(.degrees(90))
                .frame(width: DeckMetrics.tabHeight - 16, height: DeckMetrics.tabWidth)
        }
        .frame(width: DeckMetrics.tabWidth, height: min(sheetHeight, DeckMetrics.tabHeight))
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var peekInterior: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.displayTitle)
                .font(NoteFont.title(18))
                .foregroundStyle(item.swatch.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                StageChip(status: store.status(for: item.statusID))
                PriorityBadge(priority: item.priority)
                if let actorName = store.actor(for: item.actorID)?.name {
                    Text(actorName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(item.swatch.ink.opacity(0.55))
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var expandedInterior: some View {
        let swatch = item.swatch
        return VStack(alignment: .leading, spacing: 6) {
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
                    .tint(swatch.ink)
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
                PriorityAssignMenu(store: store, item: item)
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

    @ViewBuilder
    private func resizeEdge(widthSign: CGFloat, heightSign: CGFloat, width: CGFloat?, height: CGFloat?) -> some View {
        Color.clear
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    if widthSign != 0 && heightSign != 0 { NSCursor.crosshair.push() }
                    else if widthSign != 0 { NSCursor.resizeLeftRight.push() }
                    else { NSCursor.resizeUpDown.push() }
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(resizeGesture(widthSign: widthSign, heightSign: heightSign))
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
