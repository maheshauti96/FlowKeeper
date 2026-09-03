import AppKit
import SwiftUI

@MainActor
final class BoardWindowController: NSWindowController, NSWindowDelegate {
    var onClosed: (() -> Void)?
    var onReveal: ((UUID) -> Void)?
    private var session: BoardSession!

    convenience init(store: FlowStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1320, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Board — Flow Keeper"
        window.minSize = NSSize(width: 960, height: 620)
        window.backgroundColor = Palette.nsCream
        window.setFrameAutosaveName("FlowKeeper.Board")
        window.center()
        self.init(window: window)
        window.delegate = self
        self.session = BoardSession()
        let root = BoardView(store: store, session: session, onReveal: { [weak self] id in
            self?.onReveal?(id)
        })
        window.contentView = NSHostingView(rootView: root)
    }

    func edit(_ item: FlowItem) {
        session.beginEdit(item)
    }

    func windowWillClose(_ notification: Notification) {
        onClosed?()
    }
}

@MainActor
final class LibraryWindowController: NSWindowController, NSWindowDelegate {
    var onClosed: (() -> Void)?
    var onReveal: ((UUID) -> Void)?
    private var filterHolder: LibraryFilterHolder

    convenience init(store: FlowStore) {
        let holder = LibraryFilterHolder()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "All Flows — Flow Keeper"
        window.minSize = NSSize(width: 820, height: 520)
        window.backgroundColor = Palette.nsCream
        window.setFrameAutosaveName("FlowKeeper.Library")
        window.center()
        self.init(window: window, holder: holder)
        window.delegate = self
        let root = LibraryView(
            store: store,
            holder: holder,
            onReveal: { [weak self] id in
                self?.onReveal?(id)
            }
        )
        window.contentView = NSHostingView(rootView: root)
    }

    private init(window: NSWindow, holder: LibraryFilterHolder) {
        self.filterHolder = holder
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setFilter(_ filter: LibraryScope) {
        filterHolder.filter = filter
        if case .status(let id) = filter, id == FlowStatus.archivedID {
            window?.title = "Archive — Flow Keeper"
        } else {
            window?.title = "All Flows — Flow Keeper"
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClosed?()
    }
}

enum BoardEditor: Equatable {
    case closed
    case create(statusID: UUID)
    case edit(UUID)
}

@Observable
final class BoardSession {
    var actorFilter: ActorFilter = .all
    var query = ""
    var targetedStatusID: UUID?
    var editor: BoardEditor = .closed
    var draftTitle = ""
    var draftBody = ""
    var draftStatusID = FlowStatus.ideaID
    var draftActorID: UUID?
    var draftColorID = "sky"
    var draftPriority: CardPriority = .none

    var queryBinding: Binding<String> {
        Binding(get: { self.query }, set: { self.query = $0 })
    }

    var actorFilterBinding: Binding<ActorFilter> {
        Binding(get: { self.actorFilter }, set: { self.actorFilter = $0 })
    }

    var draftTitleBinding: Binding<String> {
        Binding(get: { self.draftTitle }, set: { self.draftTitle = $0 })
    }

    var draftBodyBinding: Binding<String> {
        Binding(get: { self.draftBody }, set: { self.draftBody = $0 })
    }

    var isEditing: Bool {
        if case .edit = editor { return true }
        return false
    }

    func beginCreate(statusID: UUID, actorID: UUID? = nil) {
        editor = .create(statusID: statusID)
        draftTitle = ""
        draftBody = ""
        draftStatusID = statusID
        draftActorID = actorID
        draftColorID = StickySwatch.all.randomElement()?.id ?? "sky"
        draftPriority = .none
    }

    func beginEdit(_ item: FlowItem) {
        editor = .edit(item.id)
        draftTitle = item.title
        draftBody = item.body
        draftStatusID = item.statusID
        draftActorID = item.actorID
        draftColorID = item.colorID
        draftPriority = item.priority
    }

    func closeEditor() {
        editor = .closed
    }
}

@Observable
final class LibraryFilterHolder {
    var filter: LibraryScope = .all
    var actorFilter: ActorFilter = .all
    var query: String = ""
    var selectedID: UUID?

    var queryBinding: Binding<String> {
        Binding(get: { self.query }, set: { self.query = $0 })
    }

    var selectedBinding: Binding<UUID?> {
        Binding(get: { self.selectedID }, set: { self.selectedID = $0 })
    }

    var actorFilterBinding: Binding<ActorFilter> {
        Binding(get: { self.actorFilter }, set: { self.actorFilter = $0 })
    }
}
