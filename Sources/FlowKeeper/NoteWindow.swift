import AppKit
import SwiftUI

@MainActor
final class NoteWindowController: NSWindowController, NSWindowDelegate {
    let store: FlowStore
    var onClosed: (() -> Void)?
    private var suppressCloseCallback = false
    private var currentID: UUID?
    private var hosting: NSHostingView<NoteWindowRoot>?

    init(store: FlowStore) {
        self.store = store
        let panel = NotePanel(
            contentRect: NSRect(x: 0, y: 0, width: DeckMetrics.noteWindowWidth, height: DeckMetrics.noteWindowHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.minSize = NSSize(width: 280, height: 220)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)
        panel.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(id: UUID, near rect: NSRect, overFullscreen: Bool) {
        currentID = id
        applyLevel(overFullscreen: overFullscreen)
        refreshContent()
        if let win = window {
            var frame = rect
            if let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ?? NSScreen.main {
                let vf = screen.visibleFrame
                if frame.maxX > vf.maxX { frame.origin.x = vf.maxX - frame.width }
                if frame.minX < vf.minX { frame.origin.x = vf.minX }
                if frame.maxY > vf.maxY { frame.origin.y -= frame.maxY - vf.maxY }
                if frame.minY < vf.minY { frame.origin.y = vf.minY }
            }
            win.setFrame(frame, display: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func refreshContent() {
        guard let id = currentID, let item = store.items.first(where: { $0.id == id }) else { return }
        window?.title = item.tabLabel
        window?.backgroundColor = item.swatch.nsFill
        let root = NoteWindowRoot(store: store, itemID: id, onClose: { [weak self] in
            self?.window?.performClose(nil)
        })
        if let hosting {
            hosting.rootView = root
        } else {
            let view = NSHostingView(rootView: root)
            window?.contentView = view
            hosting = view
        }
    }

    func applyLevel(overFullscreen: Bool) {
        guard let panel = window as? NSPanel else { return }
        if overFullscreen {
            panel.level = .screenSaver
        } else {
            panel.level = .floating
        }
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func closeQuietly() {
        suppressCloseCallback = true
        window?.orderOut(nil)
        suppressCloseCallback = false
        currentID = nil
    }

    var currentItemID: UUID? { currentID }

    func windowWillClose(_ notification: Notification) {
        currentID = nil
        if !suppressCloseCallback {
            onClosed?()
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshContent()
    }
}

final class NotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct NoteWindowRoot: View {
    var store: FlowStore
    var itemID: UUID
    var onClose: () -> Void

    var body: some View {
        if let item = store.items.first(where: { $0.id == itemID }) {
            NoteWindowView(store: store, item: item, onClose: onClose)
        } else {
            Color.clear
                .onAppear { onClose() }
        }
    }
}

struct NoteWindowView: View {
    var store: FlowStore
    var item: FlowItem
    var onClose: () -> Void

    var body: some View {
        let swatch = item.swatch
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: store.titleBinding(item.id))
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(swatch.ink)

            HStack(spacing: 6) {
                Text("Tab")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(swatch.ink.opacity(0.42))
                TextField(FlowItem.shortTabName(from: item.displayTitle), text: store.tabNameBinding(item.id))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(swatch.ink.opacity(0.7))
            }

            NoteBodyView(
                text: store.bodyBinding(item.id),
                font: NoteFont.nsBody,
                color: swatch.nsInk.withAlphaComponent(0.9),
                showsScroller: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 7) {
                ForEach(StickySwatch.all) { sw in
                    Button {
                        store.update(item.id) { $0.colorID = sw.id }
                    } label: {
                        Circle()
                            .fill(sw.fill)
                            .overlay(
                                Circle().stroke(
                                    swatch.id == sw.id ? Color.black.opacity(0.45) : Color.black.opacity(0.08),
                                    lineWidth: swatch.id == sw.id ? 1.6 : 0.8
                                )
                            )
                            .frame(width: 11, height: 11)
                    }
                    .buttonStyle(.plain)
                    .help(sw.id)
                }
                Spacer()
                Text("Saved · \(RelativeDate.string(item.updatedAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(swatch.ink.opacity(0.42))
            }

            HStack {
                Button("Close") { onClose() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(swatch.ink.opacity(0.55))
                Spacer()
                Menu {
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
                    Divider()
                    Button("Archive") {
                        store.archive(item.id)
                        onClose()
                    }
                    Button("Delete") {
                        store.delete(item.id)
                        onClose()
                    }
                } label: {
                    Text("More")
                        .font(.system(size: 11))
                        .foregroundStyle(swatch.ink.opacity(0.45))
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(swatch.fill)
        .background(WindowChromeSync(title: item.tabLabel, color: swatch.nsFill))
    }
}

private struct WindowChromeSync: NSViewRepresentable {
    var title: String
    var color: NSColor

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.window?.title = title
        view.window?.backgroundColor = color
    }
}
