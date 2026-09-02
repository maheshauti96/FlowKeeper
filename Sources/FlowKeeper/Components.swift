import SwiftUI
import AppKit

struct NoteBodyView: NSViewRepresentable {
    var text: Binding<String>
    var font: NSFont
    var color: NSColor
    var background: NSColor = .clear
    var showsScroller: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(text: text, font: font, color: color)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.borderType = .noBorder
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = showsScroller
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScrollElasticity = .allowed

        let tv = MarkdownNoteTextView()
        tv.isRichText = true
        tv.importsGraphics = false
        tv.allowsImageEditing = false
        tv.styleFont = font
        tv.styleColor = color
        tv.font = font
        tv.textColor = color
        tv.insertionPointColor = color
        applyChrome(tv)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainerInset = NSSize(width: 0, height: 2)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.enabledTextCheckingTypes = 0
        tv.string = text.wrappedValue
        tv.onPlainTextChange = { [weak coord = context.coordinator] value in
            coord?.text.wrappedValue = value
        }
        tv.restyle()
        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = text
        context.coordinator.font = font
        context.coordinator.color = color
        guard let tv = scroll.documentView as? MarkdownNoteTextView else { return }
        tv.onPlainTextChange = { [weak coord = context.coordinator] value in
            coord?.text.wrappedValue = value
        }
        applyChrome(tv)
        let fontChanged = tv.styleFont.fontName != font.fontName || tv.styleFont.pointSize != font.pointSize
        let resolved = color.fkResolved(in: tv.effectiveAppearance)
        let colorChanged = tv.textColor?.isEqual(resolved) != true
        tv.styleFont = font
        tv.styleColor = color
        if tv.string != text.wrappedValue {
            tv.string = text.wrappedValue
        } else if fontChanged || colorChanged {
            tv.restyle()
        }
        scroll.hasVerticalScroller = showsScroller
    }

    private func applyChrome(_ tv: MarkdownNoteTextView) {
        let bg = background.fkResolved(in: tv.effectiveAppearance)
        let ink = color.fkResolved(in: tv.effectiveAppearance)
        let fills = bg.alphaComponent > 0.01
        tv.backgroundColor = fills ? bg : .clear
        tv.drawsBackground = fills
        tv.textColor = ink
        tv.insertionPointColor = ink
        tv.styleColor = color
    }

    final class Coordinator {
        var text: Binding<String>
        var font: NSFont
        var color: NSColor
        init(text: Binding<String>, font: NSFont, color: NSColor) {
            self.text = text
            self.font = font
            self.color = color
        }
    }
}

struct ActorChip: View {
    var actor: FlowActor?
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(actor?.color ?? Color.gray.opacity(0.4))
                .frame(width: compact ? 8 : 10, height: compact ? 8 : 10)
            if !compact {
                Text(actor?.name ?? "Unassigned")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, compact ? 0 : 8)
        .padding(.vertical, compact ? 0 : 4)
        .background(
            Capsule().fill(compact ? Color.clear : Palette.chipFill)
        )
    }
}

struct StageChip: View {
    var status: FlowStatus

    var body: some View {
        Text(status.chip)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(status.tint.opacity(0.28))
            )
    }
}

enum TextPrompt {
    static func ask(title: String, message: String, defaultValue: String = "", confirm: String = "Save") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: defaultValue)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct ActorAvatar: View {
    var actor: FlowActor?
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle().fill(actor?.color ?? Color(hex: 0x9AA3AD))
            Text(actor?.initial ?? "?")
                .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct EmptyColumn: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Palette.inkMuted.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Palette.ink.opacity(0.12))
            )
    }
}

struct ActorFilterBar: View {
    var store: FlowStore
    var selection: Binding<ActorFilter>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                FilterPill(title: "Everyone", selected: selection.wrappedValue == .all) {
                    selection.wrappedValue = .all
                }
                ForEach(store.actors) { actor in
                    FilterPill(title: actor.name, selected: selection.wrappedValue == .actor(actor.id)) {
                        selection.wrappedValue = .actor(actor.id)
                    }
                }
                FilterPill(title: "Unassigned", selected: selection.wrappedValue == .unassigned) {
                    selection.wrappedValue = .unassigned
                }
                Button {
                    if let name = TextPrompt.ask(
                        title: "Add an actor",
                        message: "Someone — or another agent — who can hold work in parallel.",
                        confirm: "Add"
                    ) {
                        let actor = store.addActor(name: name)
                        selection.wrappedValue = .actor(actor.id)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.inkMuted)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Palette.surface))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add actor")
            }
            .padding(4)
        }
        .background(Capsule().fill(Palette.creamDark))
        .frame(maxWidth: 420)
    }
}

struct FilterPill: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Palette.ink : Palette.inkMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(selected ? Palette.surface : Color.clear)
                )
                .shadow(color: selected ? .black.opacity(0.06) : .clear, radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ActorAssignMenu: View {
    var store: FlowStore
    var item: FlowItem

    var body: some View {
        Menu {
            Button("Unassigned") { store.assign(item.id, to: nil) }
            Divider()
            ForEach(store.actors) { actor in
                Button {
                    store.assign(item.id, to: actor.id)
                } label: {
                    HStack {
                        Text(actor.name)
                        if item.actorID == actor.id { Image(systemName: "checkmark") }
                    }
                }
            }
            Divider()
            Button("Add actor…") { promptNewActor() }
        } label: {
            ActorChip(actor: store.actor(for: item.actorID))
        }
        .paletteMenuChrome()
    }

    private func promptNewActor() {
        let alert = NSAlert()
        alert.messageText = "Add an actor"
        alert.informativeText = "Someone — or another agent — who can hold work in parallel."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: "")
        field.placeholderString = "Name"
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                let actor = store.addActor(name: name)
                store.assign(item.id, to: actor.id)
            }
        }
    }
}


struct PriorityChip: View {
    var priority: CardPriority

    var body: some View {
        Text(priority.chip)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(Color(hex: priority.ink))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color(hex: priority.wash).opacity(priority == .none ? 0.7 : 0.95))
            )
    }
}

struct PriorityBadge: View {
    var priority: CardPriority

    var body: some View {
        if let label = priority.badge {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.3)
                .foregroundStyle(Color(hex: priority.ink))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    Capsule().fill(Color(hex: priority.wash))
                )
        }
    }
}

struct PriorityAssignMenu: View {
    var store: FlowStore
    var item: FlowItem

    var body: some View {
        Menu {
            Button("None") { store.setPriority(item.id, to: .none) }
            Divider()
            Button("P0") { store.setPriority(item.id, to: .p0) }
            Button("P1") { store.setPriority(item.id, to: .p1) }
            Button("P2") { store.setPriority(item.id, to: .p2) }
        } label: {
            PriorityChip(priority: item.priority)
        }
        .paletteMenuChrome()
    }
}


struct StageAssignMenu: View {
    var store: FlowStore
    var item: FlowItem

    var body: some View {
        Menu {
            ForEach(store.orderedStatuses) { status in
                Button {
                    store.move(item.id, to: status.id)
                } label: {
                    HStack {
                        Text(status.name)
                        if item.statusID == status.id { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            StageChip(status: store.status(for: item.statusID))
        }
        .paletteMenuChrome()
    }
}

struct DashedFold: View {
    var color: Color

    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0.5, y: 10))
                path.addLine(to: CGPoint(x: 0.5, y: geo.size.height - 10))
            }
            .stroke(color.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [3.5, 3.5]))
        }
        .frame(width: 1)
    }
}
