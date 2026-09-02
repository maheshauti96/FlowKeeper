import SwiftUI

struct CardDialog: View {
    var store: FlowStore
    var session: BoardSession
    var onOpenOnDeck: ((UUID) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(session.isEditing ? "Edit flow" : "New flow")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button {
                    session.closeEditor()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.inkMuted)
                }
                .buttonStyle(.plain)
            }

            TextField("Title", text: session.draftTitleBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .semibold))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.cream))

            NoteBodyView(
                text: session.draftBodyBinding,
                font: .systemFont(ofSize: 14),
                color: NSColor(hex: 0x1C2430),
                showsScroller: true
            )
            .frame(height: 160)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.cream))

            HStack(spacing: 10) {
                Menu {
                    Button("Unassigned") { session.draftActorID = nil }
                    Divider()
                    ForEach(store.actors) { actor in
                        Button(actor.name) { session.draftActorID = actor.id }
                    }
                    Divider()
                    Button("Add actor…") {
                        if let name = TextPrompt.ask(title: "Add an actor", message: "Someone who can hold this work.", confirm: "Add") {
                            session.draftActorID = store.addActor(name: name).id
                        }
                    }
                } label: {
                    ActorChip(actor: store.actor(for: session.draftActorID))
                }
                .menuStyle(.borderlessButton)

                Menu {
                    ForEach(store.orderedStatuses) { status in
                        Button(status.name) { session.draftStatusID = status.id }
                    }
                } label: {
                    StageChip(status: store.status(for: session.draftStatusID))
                }
                .menuStyle(.borderlessButton)

                Menu {
                    Button("None") { session.draftPriority = .none }
                    Divider()
                    Button("P0") { session.draftPriority = .p0 }
                    Button("P1") { session.draftPriority = .p1 }
                    Button("P2") { session.draftPriority = .p2 }
                } label: {
                    PriorityChip(priority: session.draftPriority)
                }
                .menuStyle(.borderlessButton)

                Spacer()

                HStack(spacing: 6) {
                    ForEach(StickySwatch.all) { swatch in
                        Button {
                            session.draftColorID = swatch.id
                        } label: {
                            Circle()
                                .fill(swatch.fill)
                                .overlay(
                                    Circle().stroke(
                                        session.draftColorID == swatch.id ? Color.black.opacity(0.45) : Color.black.opacity(0.08),
                                        lineWidth: session.draftColorID == swatch.id ? 2 : 1
                                    )
                                )
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                if case .edit(let id) = session.editor {
                    Button("Delete", role: .destructive) {
                        store.delete(id)
                        session.closeEditor()
                    }
                    if store.status(for: session.draftStatusID).isSticky {
                        Button("Open on edge") {
                            save()
                            onOpenOnDeck?(id)
                        }
                    }
                }
                Spacer()
                Button("Cancel") { session.closeEditor() }
                    .keyboardShortcut(.cancelAction)
                Button(session.isEditing ? "Save" : "Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: 0x2F3A4A))
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.2), radius: 24, y: 8)
        )
    }

    private func save() {
        switch session.editor {
        case .create:
            store.createItem(
                statusID: session.draftStatusID,
                actorID: session.draftActorID,
                onDeck: store.status(for: session.draftStatusID).isSticky,
                title: session.draftTitle,
                body: session.draftBody,
                colorID: session.draftColorID,
                priority: session.draftPriority
            )
        case .edit(let id):
            store.update(id) { item in
                item.title = session.draftTitle
                item.body = session.draftBody
                item.colorID = session.draftColorID
                item.priority = session.draftPriority
            }
            if store.items.first(where: { $0.id == id })?.statusID != session.draftStatusID {
                store.move(id, to: session.draftStatusID)
            }
            store.assign(id, to: session.draftActorID)
        case .closed:
            break
        }
        session.closeEditor()
    }
}
