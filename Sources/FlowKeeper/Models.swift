import Foundation
import SwiftUI

struct FlowStatus: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var detail: String
    var colorHex: UInt32
    var rank: Double
    var showsOnBoard: Bool
    var dropsFromDeck: Bool
    var isNow: Bool
    var isSticky: Bool

    var tint: Color { Color(hex: colorHex) }

    var chip: String {
        let u = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if u.count <= 12 { return u }
        return String(u.prefix(11))
    }

    static let ideaID = UUID(uuidString: "00000000-0000-4000-8000-000000000101")!
    static let envisionedID = UUID(uuidString: "00000000-0000-4000-8000-000000000102")!
    static let plannedID = UUID(uuidString: "00000000-0000-4000-8000-000000000103")!
    static let comingUpID = UUID(uuidString: "00000000-0000-4000-8000-000000000104")!
    static let ongoingID = UUID(uuidString: "00000000-0000-4000-8000-000000000105")!
    static let doneID = UUID(uuidString: "00000000-0000-4000-8000-000000000106")!
    static let archivedID = UUID(uuidString: "00000000-0000-4000-8000-000000000107")!

    static let palette: [UInt32] = [
        0xE8A07A, 0xA78BDB, 0x7EB4E0, 0xE2C44A, 0x6DC48A, 0xE08AA0, 0x6EC4B8, 0xC45C9A, 0x8A9098
    ]

    static func seed() -> [FlowStatus] {
        [
            FlowStatus(id: ideaID, name: "Ideas", detail: "Fleeting thoughts, captured before they vanish", colorHex: 0xE8A07A, rank: 1, showsOnBoard: true, dropsFromDeck: false, isNow: false, isSticky: false),
            FlowStatus(id: envisionedID, name: "Envisioned", detail: "Shapes of things you might build", colorHex: 0xA78BDB, rank: 2, showsOnBoard: true, dropsFromDeck: false, isNow: false, isSticky: false),
            FlowStatus(id: plannedID, name: "Planned", detail: "Decided, not yet scheduled", colorHex: 0x7EB4E0, rank: 3, showsOnBoard: true, dropsFromDeck: false, isNow: false, isSticky: false),
            FlowStatus(id: comingUpID, name: "Coming up", detail: "Next on the table", colorHex: 0xE2C44A, rank: 4, showsOnBoard: true, dropsFromDeck: false, isNow: false, isSticky: false),
            FlowStatus(id: ongoingID, name: "Ongoing", detail: "In flight right now", colorHex: 0x6DC48A, rank: 5, showsOnBoard: true, dropsFromDeck: false, isNow: true, isSticky: true),
            FlowStatus(id: doneID, name: "Done", detail: "Closed, still searchable", colorHex: 0x8A9098, rank: 6, showsOnBoard: true, dropsFromDeck: true, isNow: false, isSticky: false),
            FlowStatus(id: archivedID, name: "Archived", detail: "Off the deck, not gone", colorHex: 0xB0B4B8, rank: 7, showsOnBoard: false, dropsFromDeck: true, isNow: false, isSticky: false)
        ]
    }

    enum CodingKeys: String, CodingKey {
        case id, name, detail, colorHex, rank, showsOnBoard, dropsFromDeck, isNow, isSticky
    }

    init(id: UUID, name: String, detail: String, colorHex: UInt32, rank: Double, showsOnBoard: Bool, dropsFromDeck: Bool, isNow: Bool, isSticky: Bool) {
        self.id = id
        self.name = name
        self.detail = detail
        self.colorHex = colorHex
        self.rank = rank
        self.showsOnBoard = showsOnBoard
        self.dropsFromDeck = dropsFromDeck
        self.isNow = isNow
        self.isSticky = isSticky
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        colorHex = try c.decode(UInt32.self, forKey: .colorHex)
        rank = try c.decode(Double.self, forKey: .rank)
        showsOnBoard = try c.decodeIfPresent(Bool.self, forKey: .showsOnBoard) ?? true
        dropsFromDeck = try c.decodeIfPresent(Bool.self, forKey: .dropsFromDeck) ?? false
        isNow = try c.decodeIfPresent(Bool.self, forKey: .isNow) ?? false
        isSticky = try c.decodeIfPresent(Bool.self, forKey: .isSticky) ?? isNow
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(detail, forKey: .detail)
        try c.encode(colorHex, forKey: .colorHex)
        try c.encode(rank, forKey: .rank)
        try c.encode(showsOnBoard, forKey: .showsOnBoard)
        try c.encode(dropsFromDeck, forKey: .dropsFromDeck)
        try c.encode(isNow, forKey: .isNow)
        try c.encode(isSticky, forKey: .isSticky)
    }

    static func legacyID(_ raw: String) -> UUID {
        switch raw {
        case "idea": return ideaID
        case "envisioned": return envisionedID
        case "planned": return plannedID
        case "comingUp": return comingUpID
        case "ongoing": return ongoingID
        case "done": return doneID
        case "archived": return archivedID
        default: return ideaID
        }
    }
}

enum ActorKind: String, Codable {
    case me
    case agent
    case other
}

struct FlowActor: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: ActorKind
    var colorHex: UInt32

    var color: Color { Color(hex: colorHex) }

    var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(1)).uppercased()
    }

    static let meID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let agentID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!

    static func seed() -> [FlowActor] {
        [
            FlowActor(id: meID, name: "You", kind: .me, colorHex: 0x3D7EEB),
            FlowActor(id: agentID, name: "Agent", kind: .agent, colorHex: 0x7B5CDB)
        ]
    }
}

struct FlowItem: Identifiable, Hashable {
    var id: UUID
    var title: String
    var body: String
    var colorID: String
    var statusID: UUID
    var actorID: UUID?
    var tags: [String]
    var onDeck: Bool
    var createdAt: Date
    var updatedAt: Date
    var rank: Double

    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let first = body.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled idea" : trimmed
    }

    var tabLabel: String {
        let raw = displayTitle.uppercased()
        let compact = raw.replacingOccurrences(of: " ", with: "-")
        if compact.count <= 10 { return compact }
        return String(compact.prefix(9))
    }

    var preview: String {
        body.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var swatch: StickySwatch { StickySwatch.swatch(colorID) }
}

extension FlowItem: Codable {
    enum CodingKeys: String, CodingKey {
        case id, title, body, colorID, statusID, stage, actorID, tags, onDeck, createdAt, updatedAt, rank
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decode(String.self, forKey: .body)
        colorID = try c.decode(String.self, forKey: .colorID)
        if let sid = try c.decodeIfPresent(UUID.self, forKey: .statusID) {
            statusID = sid
        } else if let legacy = try c.decodeIfPresent(String.self, forKey: .stage) {
            statusID = FlowStatus.legacyID(legacy)
        } else {
            statusID = FlowStatus.ideaID
        }
        actorID = try c.decodeIfPresent(UUID.self, forKey: .actorID)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        onDeck = try c.decode(Bool.self, forKey: .onDeck)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        rank = try c.decode(Double.self, forKey: .rank)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(body, forKey: .body)
        try c.encode(colorID, forKey: .colorID)
        try c.encode(statusID, forKey: .statusID)
        try c.encodeIfPresent(actorID, forKey: .actorID)
        try c.encode(tags, forKey: .tags)
        try c.encode(onDeck, forKey: .onDeck)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(rank, forKey: .rank)
    }
}

struct UndoPayload: Identifiable {
    var item: FlowItem
    var expires: Date
    var id: UUID { item.id }
}

struct StoreSnapshot: Codable {
    var version: Int
    var actors: [FlowActor]
    var statuses: [FlowStatus]?
    var items: [FlowItem]
    var showOverFullscreen: Bool
}

enum LibraryScope: Hashable {
    case all
    case onDeck
    case status(UUID)
}

enum ActorFilter: Hashable {
    case all
    case unassigned
    case actor(UUID)
}
