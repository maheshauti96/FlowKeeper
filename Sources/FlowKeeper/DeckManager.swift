import AppKit
import CoreGraphics

@MainActor
final class DeckManager {
    let store: FlowStore
    private var controllers: [CGDirectDisplayID: DeckController] = [:]

    var onOpenBoard: (() -> Void)?
    var onOpenLibrary: ((LibraryScope) -> Void)?
    var onQuit: (() -> Void)?

    var all: [DeckController] { Array(controllers.values) }

    var active: DeckController? {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
           let match = controllers[screen.displayID] {
            return match
        }
        return controllers.values.first { $0.mode != .dormant } ?? controllers.values.first
    }

    var expanded: DeckController? {
        controllers.values.first { controller in
            if case .expanded = controller.mode { return true }
            return false
        }
    }

    init(store: FlowStore) {
        self.store = store
    }

    func rebuild() {
        let screens = NSScreen.screens
        let live = Set(screens.map(\.displayID))

        for (id, controller) in controllers where !live.contains(id) {
            controller.close()
            controllers[id] = nil
        }

        for screen in screens {
            let id = screen.displayID
            if let existing = controllers[id] {
                existing.relayout()
            } else {
                let controller = DeckController(store: store, displayID: id)
                wire(controller)
                controller.show()
                controllers[id] = controller
            }
        }
    }

    func collapseOthers(except displayID: CGDirectDisplayID) {
        for (id, controller) in controllers where id != displayID {
            controller.forceDormant()
        }
    }

    func applyFullscreenPreference() {
        all.forEach { $0.applyFullscreenPreference() }
    }

    func rebuildMenus() {
        all.forEach { $0.rebuildMenu() }
    }

    private func wire(_ controller: DeckController) {
        controller.onOpenBoard = { [weak self] in self?.onOpenBoard?() }
        controller.onOpenLibrary = { [weak self] filter in self?.onOpenLibrary?(filter) }
        controller.onQuit = { [weak self] in self?.onQuit?() }
        controller.onWillExpand = { [weak self] displayID in
            self?.collapseOthers(except: displayID)
        }
    }
}
