import AppKit
import CoreGraphics
import SwiftUI

/// One source of truth for FlowKeeper chrome. Light keeps cream paper + charcoal ink;
/// dark flips to warm charcoal surfaces + cream ink. Sticky-note swatches stay pastel.
enum Palette {
    static let cream = Color(nsColor: .fkCream)
    static let creamDark = Color(nsColor: .fkCreamDark)
    static let ink = Color(nsColor: .fkInk)
    static let inkMuted = Color(nsColor: .fkInkMuted)
    static let hairline = Color(nsColor: .fkHairline)
    static let boardColumn = Color(nsColor: .fkBoardColumn)
    static let surface = Color(nsColor: .fkSurface)
    static let field = Color(nsColor: .fkField)
    static let chipFill = Color(nsColor: .fkChipFill)
    static let elevated = Color(nsColor: .fkElevated)
    static let accent = Color(nsColor: .fkAccent)

    static var nsCream: NSColor { .fkCream }
    static var nsInk: NSColor { .fkInk }
    static var nsInkMuted: NSColor { .fkInkMuted }
    static var nsField: NSColor { .fkField }
}

extension NSColor {
    func fkResolved(in appearance: NSAppearance) -> NSColor {
        var result = self
        appearance.performAsCurrentDrawingAppearance {
            result = self.usingColorSpace(.sRGB) ?? self
        }
        return result
    }

    static func fkDynamic(light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(hex: dark, alpha: darkAlpha)
            }
            return NSColor(hex: light, alpha: lightAlpha)
        }
    }

    static let fkCream = fkDynamic(light: 0xF3F0E8, dark: 0x1F1C18)
    static let fkCreamDark = fkDynamic(light: 0xE7E2D6, dark: 0x2A2621)
    static let fkInk = fkDynamic(light: 0x1C2430, dark: 0xF3F0E8)
    static let fkInkMuted = fkDynamic(light: 0x5C6570, dark: 0xA89F93)
    static let fkHairline = fkDynamic(light: 0x000000, lightAlpha: 0.08, dark: 0xF3F0E8, darkAlpha: 0.12)
    static let fkBoardColumn = fkDynamic(light: 0xFFFFFF, lightAlpha: 0.72, dark: 0x2C2924, darkAlpha: 0.92)
    static let fkSurface = fkDynamic(light: 0xFFFFFF, dark: 0x2E2A25)
    static let fkField = fkDynamic(light: 0xF3F0E8, dark: 0x161410)
    static let fkChipFill = fkDynamic(light: 0xFFFFFF, lightAlpha: 0.72, dark: 0x3A3530, darkAlpha: 1)
    static let fkElevated = fkDynamic(light: 0xFFFFFF, lightAlpha: 0.55, dark: 0x35312C, darkAlpha: 0.92)
    static let fkAccent = fkDynamic(light: 0x2F3A4A, dark: 0xD9D2C6)
}

extension View {
    /// Plain fields must set ink + fill; SwiftUI `.primary` is light in Dark Mode.
    func paletteFieldInk() -> some View {
        self
            .foregroundStyle(Palette.ink)
            .tint(Palette.ink)
    }

    func paletteFieldChrome(cornerRadius: CGFloat = 10, padding: CGFloat = 10) -> some View {
        self
            .paletteFieldInk()
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(Palette.field))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Palette.hairline, lineWidth: 1)
            )
    }

    func paletteSearchChrome() -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Palette.hairline, lineWidth: 1)
            )
    }

    /// `borderlessButton` draws an empty light bezel in Dark Mode and hides the label.
    func paletteMenuChrome() -> some View {
        self
            .buttonStyle(.plain)
            .fixedSize()
    }
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

enum AppFont {
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = postScriptName(for: nsWeight(weight))
        if NSFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight, design: .rounded)
    }

    static func ns(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let name = postScriptName(for: weight)
        if let font = NSFont(name: name, size: size) {
            return font
        }
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    static func nsWeight(_ weight: Font.Weight) -> NSFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }

    /// Noteworthy ships two faces: Light for body, Bold for titles and emphasis.
    private static func postScriptName(for weight: NSFont.Weight) -> String {
        if weight >= .medium {
            return "Noteworthy-Bold"
        }
        return "Noteworthy-Light"
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
