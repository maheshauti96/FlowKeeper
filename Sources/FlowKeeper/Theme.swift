import AppKit
import CoreGraphics
import SwiftUI

enum Palette {
    static let cream = Color(hex: 0xF3F0E8)
    static let creamDark = Color(hex: 0xE7E2D6)
    static let ink = Color(hex: 0x1C2430)
    static let inkMuted = Color(hex: 0x5C6570)
    static let hairline = Color.black.opacity(0.08)
    static let boardColumn = Color.white.opacity(0.72)
}

enum DeckMetrics {
    static let pillWidth: CGFloat = 12
    static let tabWidth: CGFloat = 32
    static let tabHeight: CGFloat = 98
    static let tabStride: CGFloat = 82
    static let previewWidth: CGFloat = 248
    static var peekSheetWidth: CGFloat { tabWidth + previewWidth }
    static let fanStagger: TimeInterval = 0.045
    static let noteWidth: CGFloat = 304
    static let noteMinHeight: CGFloat = 228
    static let noteResizeMinWidth: CGFloat = 240
    static let noteResizeMinHeight: CGFloat = 180
    static let plusSize: CGFloat = 28
    static let plusGap: CGFloat = 12
    static let boardTabHeight: CGFloat = 46
    static let boardTabGap: CGFloat = 8
    static let shadowPad: CGFloat = 22
    static let topGutter: CGFloat = 18
    static let maxVisibleTabs = 8
    static let drawerDuration: TimeInterval = 0.32
}

struct StickySwatch: Identifiable, Hashable {
    var id: String
    var fillHex: UInt32
    var inkHex: UInt32
    var dashHex: UInt32

    var fill: Color { Color(hex: fillHex) }
    var ink: Color { Color(hex: inkHex) }
    var dash: Color { Color(hex: dashHex) }
    var nsFill: NSColor { NSColor(hex: fillHex) }
    var nsInk: NSColor { NSColor(hex: inkHex) }

    static let all: [StickySwatch] = [
        .init(id: "sky", fillHex: 0xC7DFF6, inkHex: 0x1C3350, dashHex: 0x7EB6E4),
        .init(id: "mint", fillHex: 0xC5EFD3, inkHex: 0x1A3D2A, dashHex: 0x6DC48A),
        .init(id: "lilac", fillHex: 0xDDD0F5, inkHex: 0x35245A, dashHex: 0xA78BDB),
        .init(id: "sun", fillHex: 0xF6E59B, inkHex: 0x4A3B10, dashHex: 0xE2C44A),
        .init(id: "peach", fillHex: 0xF8D3C0, inkHex: 0x5A2E1E, dashHex: 0xE8A07A),
        .init(id: "rose", fillHex: 0xF5C9D4, inkHex: 0x5A1E32, dashHex: 0xE08AA0),
        .init(id: "foam", fillHex: 0xC6EDE8, inkHex: 0x1A3D3A, dashHex: 0x6EC4B8),
        .init(id: "sand", fillHex: 0xF0E6D0, inkHex: 0x4A3F2A, dashHex: 0xD4C4A0)
    ]

    static func swatch(_ id: String) -> StickySwatch {
        all.first { $0.id == id } ?? all[0]
    }

    static func nextID(after id: String) -> String {
        guard let idx = all.firstIndex(where: { $0.id == id }) else { return all[0].id }
        return all[(idx + 1) % all.count].id
    }
}

enum NoteFont {
    static func title(_ size: CGFloat) -> Font {
        if NSFont(name: "Noteworthy-Bold", size: size) != nil {
            return .custom("Noteworthy-Bold", size: size)
        }
        return .system(size: size, weight: .bold, design: .rounded)
    }

    static func body(_ size: CGFloat) -> Font {
        if NSFont(name: "Noteworthy-Light", size: size) != nil {
            return .custom("Noteworthy-Light", size: size)
        }
        return .system(size: size, weight: .regular, design: .rounded)
    }

    static var nsTitle: NSFont {
        NSFont(name: "Noteworthy-Bold", size: 20) ?? .systemFont(ofSize: 20, weight: .bold)
    }

    static var nsBody: NSFont {
        NSFont(name: "Noteworthy-Light", size: 16) ?? .systemFont(ofSize: 16)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

enum RelativeDate {
    static func string(_ date: Date, from now: Date = Date()) -> String {
        let s = now.timeIntervalSince(date)
        if s < 45 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        if s < 86400 * 7 { return "\(Int(s / 86400))d" }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }
}
