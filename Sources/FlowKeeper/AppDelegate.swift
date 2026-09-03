import AppKit
import SwiftUI

@main
enum FlowKeeperMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = AppDelegate.shared
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()

    let store: FlowStore
    let decks: DeckManager
    private var board: BoardWindowController?
    private var library: LibraryWindowController?
    private var statusItem: NSStatusItem?
    private var keyMonitor: Any?

    override init() {
        let store = FlowStore()
        self.store = store
        self.decks = DeckManager(store: store)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        decks.onOpenBoard = { [weak self] in self?.openBoard() }
        decks.onOpenLibrary = { [weak self] filter in self?.openLibrary(filter: filter) }
        decks.onQuit = { NSApp.terminate(nil) }
        decks.rebuild()

        setupMainMenu()
        setupStatusItem()
        setupHotkeys()
        setupKeyMonitor()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    func openBoard() {
        if board == nil {
            board = BoardWindowController(store: store)
            board?.onReveal = { [weak self] id in
                self?.revealOnDeck(id)
            }
            board?.onClosed = { [weak self] in
                self?.board = nil
                self?.updateActivationPolicy()
            }
        }
        updateActivationPolicy()
        NSApp.activate(ignoringOtherApps: true)
        board?.showWindow(nil)
        board?.window?.makeKeyAndOrderFront(nil)
    }

    func openBoard(editing item: FlowItem?) {
        openBoard()
        if let item {
            board?.edit(item)
        }
    }

    func openLibrary(filter: LibraryScope = .all) {
        if library == nil {
            library = LibraryWindowController(store: store)
            library?.onReveal = { [weak self] id in
                self?.revealOnDeck(id)
            }
            library?.onClosed = { [weak self] in
                self?.library = nil
                self?.updateActivationPolicy()
            }
        }
        library?.setFilter(filter)
        updateActivationPolicy()
        NSApp.activate(ignoringOtherApps: true)
        library?.showWindow(nil)
        library?.window?.makeKeyAndOrderFront(nil)
    }

    func captureIdea() {
        let item = store.createItem(actorID: nil, onDeck: true)
        decks.active?.expand(item.id)
    }

    func revealOnDeck(_ id: UUID) {
        store.pinToDeck(id, pin: true)
        decks.active?.expand(id)
    }

    @objc private func screensChanged() {
        decks.rebuild()
    }

    private func setupHotkeys() {
        let keys = Hotkeys.shared
        keys.onNewIdea = { [weak self] in self?.captureIdea() }
        keys.onBoard = { [weak self] in self?.openBoard() }
        keys.onLibrary = { [weak self] in self?.openLibrary(filter: .all) }
        keys.onArchive = { [weak self] in self?.openLibrary(filter: .status(FlowStatus.archivedID)) }
        keys.start()
    }

    private func updateActivationPolicy() {
        // Accessory hides the menu bar, so Edit → Paste would hit another app.
        // Promote to regular while a real window is open.
        if board != nil || library != nil {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Flow Keeper", action: nil, keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Flow Keeper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if Self.dispatchTextEditingShortcut(event) {
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) && event.charactersIgnoringModifiers == "." {
                if case .expanded(let id) = self.decks.expanded?.mode {
                    self.store.cycleColor(id)
                    return nil
                }
            }
            if flags.contains(.command) && event.keyCode == 51 {
                if case .expanded(let id) = self.decks.expanded?.mode {
                    self.store.delete(id)
                    self.decks.expanded?.collapse()
                    return nil
                }
            }
            if event.keyCode == 53 {
                if case .expanded = self.decks.expanded?.mode {
                    self.decks.expanded?.collapse()
                    return nil
                }
            }
            return event
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = Self.statusImage()
            button.imagePosition = .imageOnly
            button.toolTip = "Flow Keeper"
        }
        item.menu = buildMenu()
        statusItem = item
    }

    func rebuildMenu() {
        statusItem?.menu = buildMenu()
        decks.rebuildMenus()
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(Self.item("New idea", key: "n", modifiers: [.command, .option], action: #selector(menuNewIdea), target: self))
        menu.addItem(Self.item("Board", key: "b", modifiers: [.command, .option], action: #selector(menuBoard), target: self))
        menu.addItem(Self.item("All Flows", key: "a", modifiers: [.command, .option], action: #selector(menuLibrary), target: self))
        menu.addItem(Self.item("Archive", key: "l", modifiers: [.command, .option], action: #selector(menuArchive), target: self))
        menu.addItem(.separator())

        let over = NSMenuItem(
            title: "Show over full-screen apps",
            action: #selector(menuToggleFullscreen),
            keyEquivalent: ""
        )
        over.target = self
        over.state = store.showOverFullscreen ? .on : .off
        menu.addItem(over)

        menu.addItem(.separator())
        menu.addItem(Self.item("Quit Flow Keeper", key: "q", modifiers: [.command], action: #selector(menuQuit), target: self))
        return menu
    }

    @objc private func menuNewIdea() { captureIdea() }
    @objc private func menuBoard() { openBoard() }
    @objc private func menuLibrary() { openLibrary(filter: .all) }
    @objc private func menuArchive() { openLibrary(filter: .status(FlowStatus.archivedID)) }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    @objc private func menuToggleFullscreen() {
        store.showOverFullscreen.toggle()
        store.saveNow()
        decks.applyFullscreenPreference()
        rebuildMenu()
    }

    /// Cmd+C/X/V/A/Z only work if an Edit menu exists *or* we send them to the field editor.
    /// Accessory apps have no default Edit menu, so New flow / note fields otherwise never receive paste.
    /// Returns true if the event was handled and should be swallowed.
    private static func dispatchTextEditingShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let commandOnly = flags == .command
        let commandShift = flags == [.command, .shift]
        guard commandOnly || commandShift else { return false }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        guard let responder = NSApp.keyWindow?.firstResponder, Self.isTextEditingResponder(responder) else {
            return false
        }

        let selector: Selector
        if commandOnly {
            switch key {
            case "v": selector = #selector(NSText.paste(_:))
            case "c": selector = #selector(NSText.copy(_:))
            case "x": selector = #selector(NSText.cut(_:))
            case "a": selector = #selector(NSText.selectAll(_:))
            case "z": selector = Selector(("undo:"))
            default: return false
            }
        } else if key == "z" {
            selector = Selector(("redo:"))
        } else {
            return false
        }

        return NSApp.sendAction(selector, to: nil, from: nil)
    }

    private static func isTextEditingResponder(_ responder: NSResponder) -> Bool {
        if responder is NSTextView || responder is NSText || responder is NSTextField {
            return true
        }
        return responder.nextResponder.map(isTextEditingResponder) ?? false
    }

    private static func item(_ title: String, key: String, modifiers: NSEvent.ModifierFlags, action: Selector, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }

    private static func statusImage() -> NSImage {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.labelColor.withAlphaComponent(0.92).setFill()
            let tabs: [(CGFloat, CGFloat)] = [(2.5, 4.4), (7.3, 4.4), (12.1, 4.4)]
            for (y, h) in tabs {
                let path = NSBezierPath(roundedRect: NSRect(x: 5.5, y: y, width: 10.5, height: h), xRadius: 2.2, yRadius: 2.2)
                path.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
