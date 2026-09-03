import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class FlowStore {
    var actors: [FlowActor] = FlowActor.seed()
    var statuses: [FlowStatus] = FlowStatus.seed()
    var items: [FlowItem] = []
    var showOverFullscreen = false
    var pendingUndo: UndoPayload?
    var deckRevision: Int = 0

    private var saveTask: Task<Void, Never>?
    private var undoTask: Task<Void, Never>?
    private var lastDeckIDs: [UUID] = []

    var orderedStatuses: [FlowStatus] {
        statuses.sorted { $0.rank < $1.rank }
    }

    var boardStatuses: [FlowStatus] {
        orderedStatuses.filter(\.showsOnBoard)
    }

    var nowStatuses: [FlowStatus] {
        orderedStatuses.filter(\.isNow)
    }

    var stickyStatuses: [FlowStatus] {
        orderedStatuses.filter(\.isSticky)
    }

    var deckItems: [FlowItem] {
        items
            .filter { item in
                let s = status(for: item.statusID)
                return s.isSticky && item.onDeck
            }
            .sorted { a, b in
                let ra = status(for: a.statusID).rank
                let rb = status(for: b.statusID).rank
                if ra != rb { return ra < rb }
                return a.rank < b.rank
            }
    }

    var visibleDeckItems: [FlowItem] {
        Array(deckItems.prefix(DeckMetrics.maxVisibleTabs))
    }

    var hiddenDeckCount: Int {
        max(0, deckItems.count - DeckMetrics.maxVisibleTabs)
    }

    init() {
        load()
        lastDeckIDs = deckItems.map(\.id)
    }

    func items(in statusID: UUID) -> [FlowItem] {
        items.filter { $0.statusID == statusID }.sorted { $0.rank < $1.rank }
    }

    func status(for id: UUID?) -> FlowStatus {
        if let id, let match = statuses.first(where: { $0.id == id }) {
            return match
        }
        return orderedStatuses.first ?? FlowStatus.seed()[0]
    }

    func defaultStatus() -> FlowStatus {
        boardStatuses.first ?? orderedStatuses[0]
    }

    func doneStatus() -> FlowStatus? {
        orderedStatuses.first { $0.dropsFromDeck && $0.showsOnBoard }
    }

    func archivedStatus() -> FlowStatus? {
        orderedStatuses.first { $0.dropsFromDeck && !$0.showsOnBoard } ?? orderedStatuses.first { $0.dropsFromDeck }
    }

    func actor(for id: UUID?) -> FlowActor? {
        guard let id else { return nil }
        return actors.first { $0.id == id }
    }

    func me() -> FlowActor {
        actors.first { $0.kind == .me } ?? actors[0]
    }

    func agent() -> FlowActor {
        actors.first { $0.kind == .agent } ?? actors[min(1, actors.count - 1)]
    }

    func matches(_ item: FlowItem, query: String, filter: LibraryScope, actorFilter: ActorFilter) -> Bool {
        switch filter {
        case .all:
            if status(for: item.statusID).dropsFromDeck && !status(for: item.statusID).showsOnBoard {
                return false
            }
        case .onDeck:
            if !item.onDeck { return false }
        case .status(let id):
            if item.statusID != id { return false }
        }

        switch actorFilter {
        case .all: break
        case .unassigned:
            if item.actorID != nil { return false }
        case .actor(let id):
            if item.actorID != id { return false }
        }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        let actorName = actor(for: item.actorID)?.name.lowercased() ?? ""
        let priorityLabel = item.priority.badge?.lowercased() ?? ""
        let hay = ([item.title, item.body, status(for: item.statusID).name, actorName, priorityLabel] + item.tags)
            .joined(separator: " ")
            .lowercased()
        return hay.contains(q)
    }

    @discardableResult
    func createItem(
        statusID: UUID? = nil,
        actorID: UUID? = nil,
        onDeck: Bool = true,
        title: String = "",
        body: String = "",
        colorID: String? = nil,
        priority: CardPriority = .none
    ) -> FlowItem {
        let used = Set(items.map(\.colorID))
        let color = colorID ?? StickySwatch.all.first { !used.contains($0.id) }?.id ?? StickySwatch.all[items.count % StickySwatch.all.count].id
        let resolvedStatus = statusID ?? defaultStatus().id
        let rank: Double
        if onDeck, let last = deckItems.last {
            rank = last.rank + 1
        } else if let last = items(in: resolvedStatus).last {
            rank = last.rank + 1
        } else {
            rank = 1
        }
        let now = Date()
        let item = FlowItem(
            id: UUID(),
            title: title,
            body: body,
            colorID: color,
            statusID: resolvedStatus,
            actorID: actorID,
            priority: priority,
            tags: [],
            onDeck: onDeck && status(for: resolvedStatus).isSticky,
            createdAt: now,
            updatedAt: now,
            rank: rank
        )
        items.append(item)
        noteDeckIfNeeded()
        saveSoon()
        return item
    }

    func update(_ id: UUID, mutate: (inout FlowItem) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[idx])
        items[idx].updatedAt = Date()
        noteDeckIfNeeded()
        saveSoon()
    }

    func move(_ id: UUID, to statusID: UUID, before neighbor: UUID? = nil) {
        update(id) { item in
            item.statusID = statusID
            item.onDeck = status(for: statusID).isSticky
        }
        recomputeRanks(in: statusID, moving: id, before: neighbor)
        noteDeckIfNeeded()
        saveSoon()
    }

    func assign(_ id: UUID, to actorID: UUID?) {
        update(id) { $0.actorID = actorID }
    }

    func setPriority(_ id: UUID, to priority: CardPriority) {
        update(id) { $0.priority = priority }
    }

    func pinToDeck(_ id: UUID, pin: Bool) {
        update(id) { item in
            item.onDeck = pin
            if pin && !status(for: item.statusID).isSticky {
                item.statusID = stickyStatuses.first?.id ?? defaultStatus().id
            }
        }
    }

    func archive(_ id: UUID) {
        if let archived = archivedStatus() {
            move(id, to: archived.id)
        }
    }

    func cycleColor(_ id: UUID) {
        update(id) { $0.colorID = StickySwatch.nextID(after: $0.colorID) }
    }

    func delete(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        noteDeckIfNeeded()
        pendingUndo = UndoPayload(item: item, expires: Date().addingTimeInterval(10))
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            if self?.pendingUndo?.item.id == id {
                self?.pendingUndo = nil
            }
        }
        saveSoon()
    }

    func undoDelete() {
        guard let payload = pendingUndo else { return }
        if !items.contains(where: { $0.id == payload.item.id }) {
            items.append(payload.item)
        }
        pendingUndo = nil
        undoTask?.cancel()
        noteDeckIfNeeded()
        saveSoon()
    }

    func addActor(name: String, kind: ActorKind = .other) -> FlowActor {
        let palette: [UInt32] = [0xD97757, 0x3AAFA9, 0xC45C9A, 0xE0A100, 0x4C8D6E]
        let actor = FlowActor(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            colorHex: palette[actors.count % palette.count]
        )
        actors.append(actor)
        saveSoon()
        return actor
    }

    func exportMarkdown(_ selected: [FlowItem]) -> String {
        selected.map { item in
            let actor = actor(for: item.actorID)?.name ?? "Unassigned"
            var md = "# \(item.displayTitle)\n\n"
            md += "- Status: \(status(for: item.statusID).name)\n"
            md += "- Actor: \(actor)\n"
            if let p = item.priority.badge {
                md += "- Priority: \(p)\n"
            }
            if !item.tags.isEmpty {
                md += "- Tags: \(item.tags.joined(separator: ", "))\n"
            }
            md += "\n\(item.body)\n"
            return md
        }
        .joined(separator: "\n---\n\n")
    }

    func addStatus(name: String, after afterID: UUID? = nil) -> FlowStatus {
        let ordered = orderedStatuses
        let rank: Double
        if let afterID, let idx = ordered.firstIndex(where: { $0.id == afterID }) {
            let current = ordered[idx].rank
            let next = idx + 1 < ordered.count ? ordered[idx + 1].rank : current + 2
            rank = (current + next) / 2
        } else {
            rank = (ordered.last?.rank ?? 0) + 1
        }
        let status = FlowStatus(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            detail: "",
            colorHex: FlowStatus.palette[statuses.count % FlowStatus.palette.count],
            rank: rank,
            showsOnBoard: true,
            dropsFromDeck: false,
            isNow: false,
            isSticky: false
        )
        statuses.append(status)
        saveSoon()
        return status
    }

    func renameStatus(_ id: UUID, to name: String) {
        guard let idx = statuses.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        statuses[idx].name = trimmed
        saveSoon()
    }

    func setStatusDetail(_ id: UUID, detail: String) {
        guard let idx = statuses.firstIndex(where: { $0.id == id }) else { return }
        statuses[idx].detail = detail
        saveSoon()
    }

    func cycleStatusColor(_ id: UUID) {
        guard let idx = statuses.firstIndex(where: { $0.id == id }) else { return }
        let current = statuses[idx].colorHex
        let palette = FlowStatus.palette
        let next = palette.firstIndex(of: current).map { palette[($0 + 1) % palette.count] } ?? palette[0]
        statuses[idx].colorHex = next
        saveSoon()
    }

    func setStatusShowsOnBoard(_ id: UUID, _ on: Bool) {
        guard let idx = statuses.firstIndex(where: { $0.id == id }) else { return }
        if !on && boardStatuses.count <= 1 { return }
        statuses[idx].showsOnBoard = on
        saveSoon()
    }

    func toggleStatusNow(_ id: UUID) {
        guard let idx = statuses.firstIndex(where: { $0.id == id }) else { return }
        statuses[idx].isNow.toggle()
        saveSoon()
    }

    func toggleStatusSticky(_ id: UUID) {
        guard let idx = statuses.firstIndex(where: { $0.id == id }) else { return }
        statuses[idx].isSticky.toggle()
        let on = statuses[idx].isSticky
        for i in items.indices where items[i].statusID == id {
            items[i].onDeck = on
        }
        noteDeckIfNeeded()
        saveSoon()
    }

    func shiftStatus(_ id: UUID, by delta: Int) {
        var ordered = orderedStatuses
        guard let idx = ordered.firstIndex(where: { $0.id == id }) else { return }
        let target = idx + delta
        guard ordered.indices.contains(target) else { return }
        ordered.swapAt(idx, target)
        for (i, status) in ordered.enumerated() {
            if let si = statuses.firstIndex(where: { $0.id == status.id }) {
                statuses[si].rank = Double(i + 1)
            }
        }
        noteDeckIfNeeded()
        saveSoon()
    }

    func deleteStatus(_ id: UUID) {
        guard statuses.count > 1 else { return }
        let fallback = boardStatuses.first(where: { $0.id != id })
            ?? orderedStatuses.first(where: { $0.id != id })
        guard let fallback else { return }
        for i in items.indices where items[i].statusID == id {
            items[i].statusID = fallback.id
        }
        statuses.removeAll { $0.id == id }
        noteDeckIfNeeded()
        saveSoon()
    }

    private func recomputeRanks(in statusID: UUID, moving id: UUID, before neighbor: UUID?) {
        var ordered = items(in: statusID).filter { $0.id != id }
        if let neighbor, let idx = ordered.firstIndex(where: { $0.id == neighbor }) {
            if let moving = items.first(where: { $0.id == id }) {
                ordered.insert(moving, at: idx)
            }
        } else if let moving = items.first(where: { $0.id == id }) {
            ordered.append(moving)
        }
        for (i, item) in ordered.enumerated() {
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx].rank = Double(i + 1)
            }
        }
    }

    private func noteDeckIfNeeded() {
        let ids = deckItems.map(\.id)
        if ids != lastDeckIDs {
            lastDeckIDs = ids
            deckRevision += 1
        }
    }

    func titleBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { self.items.first(where: { $0.id == id })?.title ?? "" },
            set: { newValue in self.update(id) { $0.title = newValue } }
        )
    }

    func bodyBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { self.items.first(where: { $0.id == id })?.body ?? "" },
            set: { newValue in self.update(id) { $0.body = newValue } }
        )
    }

    func saveSoon() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        let snapshot = StoreSnapshot(
            version: 2,
            actors: actors,
            statuses: statuses,
            items: items,
            showOverFullscreen: showOverFullscreen
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            let url = Self.fileURL()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let tmp = url.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            NSLog("FlowKeeper save failed: \(error)")
        }
    }

    private func load() {
        let url = Self.fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            items = Self.seedItems()
            saveNow()
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(StoreSnapshot.self, from: data)
            actors = snapshot.actors.isEmpty ? FlowActor.seed() : snapshot.actors
            statuses = (snapshot.statuses?.isEmpty == false) ? snapshot.statuses! : FlowStatus.seed()
            items = snapshot.items
            showOverFullscreen = snapshot.showOverFullscreen
        } catch {
            NSLog("FlowKeeper load failed: \(error)")
            items = Self.seedItems()
        }
    }

    static func fileURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return root.appendingPathComponent("app.flowkeeper.mac/store.json")
    }

    private static func seedItems() -> [FlowItem] {
        let now = Date()
        func item(
            title: String,
            body: String,
            color: String,
            statusID: UUID,
            actor: UUID?,
            onDeck: Bool,
            rank: Double,
            hoursAgo: Double,
            tags: [String] = []
        ) -> FlowItem {
            FlowItem(
                id: UUID(),
                title: title,
                body: body,
                colorID: color,
                statusID: statusID,
                actorID: actor,
                tags: tags,
                onDeck: onDeck,
                createdAt: now.addingTimeInterval(-hoursAgo * 3600),
                updatedAt: now.addingTimeInterval(-hoursAgo * 3600 * 0.3),
                rank: rank
            )
        }

        return [
            item(
                title: "Voice dump for shower thoughts",
                body: "Ideas arrive while walking or in the shower and vanish before I sit down. A global hotkey is the first capture. Voice later.",
                color: "peach",
                statusID: FlowStatus.ideaID,
                actor: nil,
                onDeck: true,
                rank: 1,
                hoursAgo: 2,
                tags: ["capture"]
            ),
            item(
                title: "Per-agent workspaces",
                body: "- one column of work per agent\n- see what Grok vs Claude vs Codex is holding\n- don't mix their threads in my head",
                color: "rose",
                statusID: FlowStatus.ideaID,
                actor: nil,
                onDeck: false,
                rank: 2,
                hoursAgo: 6,
                tags: ["agents"]
            ),
            item(
                title: "Timeline of what the agent did",
                body: "While I am in a meeting the agent keeps moving. I want a quiet timeline I can scan when I come back: started, waiting, done, blocked.",
                color: "lilac",
                statusID: FlowStatus.envisionedID,
                actor: FlowActor.meID,
                onDeck: true,
                rank: 1,
                hoursAgo: 8,
                tags: ["visibility"]
            ),
            item(
                title: "Markdown export from All Flows",
                body: "One file per card, or a single dump. Round-trip later. For now, get thoughts out of the app.",
                color: "sky",
                statusID: FlowStatus.plannedID,
                actor: FlowActor.meID,
                onDeck: false,
                rank: 1,
                hoursAgo: 12,
                tags: ["export"]
            ),
            item(
                title: "Hotkey cheatsheet overlay",
                body: "⌥⌘N new idea\n⌥⌘B board\n⌥⌘A all flows\n⌥⌘L archive\nEsc closes a note\n⌘. cycles colour",
                color: "sun",
                statusID: FlowStatus.comingUpID,
                actor: FlowActor.meID,
                onDeck: true,
                rank: 1,
                hoursAgo: 4,
                tags: ["ux"]
            ),
            item(
                title: "Shape the Flow Keeper prototype",
                body: "- edge deck like Hold My Notes\n- stages: idea → envisioned → planned → coming up → ongoing → done\n- assign You / Agent\n- use it for a week, then cut what is noise",
                color: "mint",
                statusID: FlowStatus.ongoingID,
                actor: FlowActor.meID,
                onDeck: true,
                rank: 1,
                hoursAgo: 1,
                tags: ["now"]
            ),
            item(
                title: "Draft the edge-deck interaction",
                body: "- dormant pill with colour dashes\n- hover fans tabs\n- click slides the note out\n- autosave 250ms after typing stops",
                color: "sky",
                statusID: FlowStatus.ongoingID,
                actor: FlowActor.agentID,
                onDeck: true,
                rank: 2,
                hoursAgo: 1,
                tags: ["now", "agent"]
            ),
            item(
                title: "Study Hold My Notes three-state deck",
                body: "Rest as a 12pt pill. Reach over and it fans. Open one where it sits. Archive instead of delete. Local only.",
                color: "foam",
                statusID: FlowStatus.doneID,
                actor: FlowActor.meID,
                onDeck: false,
                rank: 1,
                hoursAgo: 20,
                tags: ["research"]
            )
        ]
    }
}
