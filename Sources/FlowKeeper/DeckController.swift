import AppKit
import CoreGraphics
import SwiftUI

enum DeckMode: Equatable {
    case dormant
    case peek
    case expanded(UUID)
}

@MainActor
@Observable
final class DeckController: NSObject, NSWindowDelegate {
    let store: FlowStore
    let displayID: CGDirectDisplayID
    var mode: DeckMode = .dormant
    var hoverInside = false
    var previewID: UUID?
    var fanCount = 0
    var expandedSize = CGSize(width: DeckMetrics.noteWidth, height: DeckMetrics.noteMinHeight)
    var isResizing = false
    var resizeOrigin: CGSize?

    private static let expandedWidthKey = "FlowKeeper.expandedNoteWidth"
    private static let expandedHeightKey = "FlowKeeper.expandedNoteHeight"

    var onOpenBoard: (() -> Void)?
    var onOpenLibrary: ((LibraryScope) -> Void)?
    var onQuit: (() -> Void)?
    var onWillExpand: ((CGDirectDisplayID) -> Void)?

    private var panel: DeckPanel!
    private var hosting: DeckHostingView!
    private var leaveTask: Task<Void, Never>?
    private var fanTask: Task<Void, Never>?
    private var outsideMonitor: Any?
    private var localOutsideMonitor: Any?
    private var ignoreExitUntil: Date?

    static var drawerAnimation: Animation {
        .easeInOut(duration: DeckMetrics.drawerDuration)
    }

    var isExpanded: Bool {
        if case .expanded = mode { return true }
        return false
    }

    init(store: FlowStore, displayID: CGDirectDisplayID) {
        self.store = store
        self.displayID = displayID
        super.init()
        expandedSize = Self.loadExpandedSize()
        let panel = DeckPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = false
        panel.isFloatingPanel = true
        panel.delegate = self
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let root = DeckRoot(store: store, deck: self)
        let hosting = DeckHostingView(rootView: root)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.masksToBounds = true
        hosting.autoresizingMask = [.minXMargin, .minYMargin]
        panel.contentView = hosting

        self.panel = panel
        self.hosting = hosting
        hosting.onPointer = { [weak self] point in
            self?.handlePointer(point)
        }
        applyFullscreenPreference()
        installOutsideClickMonitor()
    }

    func show() {
        applyLayout(animated: false)
        panel.orderFrontRegardless()
    }

    func relayout() {
        applyLayout(animated: false)
    }

    func close() {
        leaveTask?.cancel()
        fanTask?.cancel()
        if let outsideMonitor {
            NSEvent.removeMonitor(outsideMonitor)
        }
        if let localOutsideMonitor {
            NSEvent.removeMonitor(localOutsideMonitor)
        }
        outsideMonitor = nil
        localOutsideMonitor = nil
        panel.orderOut(nil)
        panel.delegate = nil
    }

    func forceDormant() {
        leaveTask?.cancel()
        fanTask?.cancel()
        previewID = nil
        fanCount = 0
        hoverInside = false
        guard mode != .dormant else { return }
        mode = .dormant
        applyLayout(animated: true)
        syncRoot()
    }

    func expand(_ id: UUID) {
        fanTask?.cancel()
        leaveTask?.cancel()
        onWillExpand?(displayID)
        store.pinToDeck(id, pin: true)
        withAnimation(Self.drawerAnimation) {
            previewID = id
            fanCount = store.visibleDeckItems.count
            mode = .expanded(id)
        }
        applyLayout(animated: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        syncRoot()
    }

    func collapse() {
        fanTask?.cancel()
        leaveTask?.cancel()
        if hoverInside {
            withAnimation(Self.drawerAnimation) {
                mode = .peek
                fanCount = store.visibleDeckItems.count
            }
            applyLayout(animated: true)
            syncRoot()
        } else {
            withAnimation(Self.drawerAnimation) {
                previewID = nil
                fanCount = 0
                mode = .dormant
            }
            applyLayout(animated: true)
            syncRoot()
        }
    }

    func enterPeek(fromTap: Bool = false) {
        guard mode == .dormant else { return }
        fanTask?.cancel()
        leaveTask?.cancel()
        // Swapping the pill for the stack fires a fake mouse-exit. Ignore it
        // so the first hover does not collapse and reopen.
        ignoreExitUntil = Date().addingTimeInterval(0.45)
        mode = .peek
        fanCount = store.visibleDeckItems.count
        applyLayout(animated: false, refreshRoot: false)
    }

    func openFromClick(_ id: UUID) {
        toggleExpand(id)
    }

    func toggleExpand(_ id: UUID) {
        if case .expanded(let current) = mode, current == id {
            collapse()
        } else {
            expand(id)
        }
    }

    func handleHover(_ inside: Bool) {
        hoverInside = inside
        leaveTask?.cancel()
        if inside {
            if mode == .dormant {
                enterPeek()
            }
        } else if mode == .peek {
            leaveTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 220_000_000)
                guard let self, !self.hoverInside, self.mode == .peek else { return }
                if self.previewID != nil {
                    withAnimation(Self.drawerAnimation) {
                        self.previewID = nil
                    }
                    try? await Task.sleep(nanoseconds: UInt64(DeckMetrics.drawerDuration * 1_000_000_000))
                    guard !Task.isCancelled, !self.hoverInside, self.mode == .peek else { return }
                }
                self.fanTask?.cancel()
                withAnimation(Self.drawerAnimation) {
                    self.previewID = nil
                    self.fanCount = 0
                    self.mode = .dormant
                }
                self.applyLayout(animated: true)
                self.syncRoot()
            }
        }
    }

    func handlePointer(_ point: NSPoint?) {
        guard let point else {
            if let until = ignoreExitUntil, Date() < until { return }
            handleHover(false)
            return
        }
        ignoreExitUntil = nil
        handleHover(true)
        guard mode == .peek else { return }
        let yFromTop = hosting.isFlipped ? point.y : (hosting.bounds.height - point.y)
        if let id = tabID(atYFromTop: yFromTop) {
            setPreview(id)
        }
    }

    func setPreview(_ id: UUID?) {
        guard mode == .peek else { return }
        guard previewID != id else { return }
        withAnimation(Self.drawerAnimation) {
            previewID = id
        }
    }

    func tabID(atYFromTop yFromTop: CGFloat) -> UUID? {
        let items = store.visibleDeckItems
        guard !items.isEmpty else { return nil }
        let start = DeckMetrics.topGutter
        let stack = tabStackHeight(count: items.count)
        if yFromTop < 0 { return items[0].id }
        if yFromTop < start + DeckMetrics.tabStride {
            return items[0].id
        }
        let y = yFromTop - start
        if y >= stack { return nil }
        let index = min(items.count - 1, max(0, Int(y / DeckMetrics.tabStride)))
        return items[index].id
    }

    func syncPreviewToMouse() {
        guard mode == .peek else { return }
        let screenRect = NSRect(origin: NSEvent.mouseLocation, size: .zero)
        let windowPoint = panel.convertFromScreen(screenRect).origin
        let point = hosting.convert(windowPoint, from: nil)
        if hosting.bounds.contains(point) {
            handlePointer(point)
        }
    }

    func createAndExpand(statusID: UUID? = nil, actorID: UUID? = nil) {
        let resolved = statusID
            ?? store.stickyStatuses.first?.id
            ?? store.nowStatuses.first?.id
            ?? store.defaultStatus().id
        let item = store.createItem(statusID: resolved, actorID: actorID, onDeck: true)
        expand(item.id)
    }

    func applyFullscreenPreference() {
        if store.showOverFullscreen {
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        } else {
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        }
    }

    func rebuildMenu() {
        panel.menu = AppDelegate.shared.buildMenu()
    }

    func applyLayout(animated: Bool, refreshRoot: Bool = true) {
        guard let screen = assignedScreen() else {
            panel.orderOut(nil)
            return
        }
        let frame = clamp(targetFrame(on: screen), to: screen.visibleFrame)
        if refreshRoot {
            syncRoot()
        }
        pinHosting(to: frame.size)
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = DeckMetrics.drawerDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }, completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.pinHosting(to: frame.size)
                }
            })
        } else {
            panel.setFrame(frame, display: true)
            pinHosting(to: frame.size)
            syncPreviewToMouse()
        }
    }

    /// Keep SwiftUI content glued to the panel's trailing/top edges so a grow-left
    /// (or grow-down) animation reveals the drawer instead of clipping tabs.
    private func pinHosting(to size: NSSize) {
        let bounds = panel.contentView?.bounds ?? hosting.superview?.bounds ?? .zero
        hosting.autoresizingMask = [.minXMargin, .minYMargin]
        hosting.frame = NSRect(
            x: bounds.maxX - size.width,
            y: bounds.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    func targetFrame(on screen: NSScreen) -> NSRect {
        let vf = screen.visibleFrame
        let items = store.visibleDeckItems
        let top = vf.minY + vf.height * 0.72
        let pad = DeckMetrics.shadowPad

        switch mode {
        case .dormant:
            let dashCount = max(items.count, 1)
            let height = CGFloat(dashCount) * 16 + 20
            let width = DeckMetrics.pillWidth
            return NSRect(
                x: vf.maxX - width - 1,
                y: top - height,
                width: width + 1,
                height: height
            )
        case .peek:
            let stack = tabStackHeight(count: max(items.count, 1))
            let sheet = DeckMetrics.peekSheetWidth
            let height = stack + DeckMetrics.plusSize + DeckMetrics.plusGap + pad + DeckMetrics.topGutter
            let width = sheet + pad
            return NSRect(
                x: vf.maxX - sheet,
                y: top - stack - DeckMetrics.plusSize - DeckMetrics.plusGap,
                width: width,
                height: height
            )
        case .expanded(let id):
            let stack = tabStackHeight(count: max(items.count, 1))
            let index = items.firstIndex(where: { $0.id == id }) ?? 0
            let noteSize = clampExpandedSize(expandedSize, visible: vf)
            let sheet = max(noteSize.width, DeckMetrics.peekSheetWidth)
            let noteTopOffset = CGFloat(index) * DeckMetrics.tabStride
            let noteBottomNeeded = noteTopOffset + noteSize.height
            let contentHeight = max(stack + DeckMetrics.plusSize + DeckMetrics.plusGap, noteBottomNeeded)
            let width = sheet + pad
            let height = contentHeight + pad + DeckMetrics.topGutter
            return NSRect(
                x: vf.maxX - sheet,
                y: top - contentHeight,
                width: width,
                height: height
            )
        }
    }

    private func clamp(_ rect: NSRect, to vf: NSRect) -> NSRect {
        var r = rect
        if r.maxY > vf.maxY {
            r.origin.y -= (r.maxY - vf.maxY)
        }
        if r.minY < vf.minY {
            r.origin.y = vf.minY
        }
        if r.maxX > vf.maxX {
            r.origin.x -= (r.maxX - vf.maxX)
        }
        if r.minX < vf.minX {
            r.origin.x = vf.minX
        }
        return r
    }

    func tabStackHeight(count: Int) -> CGFloat {
        if count <= 0 { return DeckMetrics.tabHeight }
        return DeckMetrics.tabHeight + CGFloat(count - 1) * DeckMetrics.tabStride
    }

    func assignedScreen() -> NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }

    func syncRoot() {
        hosting.rootView = DeckRoot(store: store, deck: self)
        panel.menu = AppDelegate.shared.buildMenu()
    }

    private func installOutsideClickMonitor() {
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.collapseIfClickOutside()
            }
        }
        localOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.collapseIfClickOutside()
            }
            return event
        }
    }

    func setExpandedSize(_ size: CGSize) {
        isResizing = true
        let vf = assignedScreen()?.visibleFrame
        let clamped = clampExpandedSize(size, visible: vf)
        expandedSize = clamped
        applyLayout(animated: false, refreshRoot: false)
    }

    func beginExpandedResize() {
        if resizeOrigin == nil {
            resizeOrigin = expandedSize
        }
        isResizing = true
    }

    func endExpandedResize() {
        persistExpandedSize()
        resizeOrigin = nil
        isResizing = false
        applyLayout(animated: false, refreshRoot: false)
    }

    func clampExpandedSize(_ size: CGSize, visible vf: NSRect? = nil) -> CGSize {
        let frame = vf ?? assignedScreen()?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxW = max(DeckMetrics.noteResizeMinWidth, frame.width - DeckMetrics.shadowPad - 8)
        let maxH = max(DeckMetrics.noteResizeMinHeight, frame.height - DeckMetrics.topGutter - DeckMetrics.shadowPad)
        return CGSize(
            width: min(max(size.width.rounded(), DeckMetrics.noteResizeMinWidth), maxW),
            height: min(max(size.height.rounded(), DeckMetrics.noteResizeMinHeight), maxH)
        )
    }

    private static func loadExpandedSize() -> CGSize {
        let defaults = UserDefaults.standard
        let width = defaults.object(forKey: expandedWidthKey) as? Double
        let height = defaults.object(forKey: expandedHeightKey) as? Double
        return CGSize(
            width: width ?? DeckMetrics.noteWidth,
            height: height ?? DeckMetrics.noteMinHeight
        )
    }

    private func persistExpandedSize() {
        UserDefaults.standard.set(Double(expandedSize.width), forKey: Self.expandedWidthKey)
        UserDefaults.standard.set(Double(expandedSize.height), forKey: Self.expandedHeightKey)
    }

    private func collapseIfClickOutside() {
        guard case .expanded = mode, !isResizing else { return }
        let loc = NSEvent.mouseLocation
        if !panel.frame.contains(loc) {
            collapse()
        }
    }
}

final class DeckPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class DeckHostingView: NSHostingView<DeckRoot> {
    var onPointer: ((NSPoint?) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        onPointer?(convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        onPointer?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        onPointer?(nil)
    }
}

struct DeckRoot: View {
    var store: FlowStore
    var deck: DeckController

    var body: some View {
        DeckView(store: store, deck: deck)
            .onChange(of: store.deckRevision) { _, _ in
                deck.applyLayout(animated: true)
            }
    }
}
