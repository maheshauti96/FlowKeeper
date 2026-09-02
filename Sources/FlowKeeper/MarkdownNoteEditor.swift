import AppKit

/// Live markdown paint for the note body. The backing string stays markdown;
/// attributes are display-only.
enum MarkdownNoteStyler {
    private static let boldRegex = try! NSRegularExpression(
        pattern: #"\*\*(?=\S)(.+?)(?<=\S)\*\*"#
    )
    private static let italicStarRegex = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9*_])\*(?!\*)(?=\S)([^*\n]+?)(?<=\S)\*(?!\*)(?![A-Za-z0-9*])"#
    )
    private static let italicUnderscoreRegex = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_])_(?=\S)([^_\n]+?)(?<=\S)_(?![A-Za-z0-9_])"#
    )
    private static let headingRegex = try! NSRegularExpression(
        pattern: #"^([ \t]{0,3})(#{1,3}) (.*)$"#
    )
    private static let unorderedRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)([-*]) (.*)$"#
    )
    private static let orderedRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)(\d+)\. (.*)$"#
    )
    private static let tableRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*\|.*\|[ \t]*$"#
    )

    struct ListLine {
        var indent: String
        var ordered: Bool
        var number: Int
        var bullet: String
        var content: String
        var prefix: String
    }

    static func apply(to tv: NSTextView, font: NSFont, color: NSColor) {
        guard let storage = tv.textStorage else { return }
        let color = color.fkResolved(in: tv.effectiveAppearance)
        let selected = tv.selectedRange()
        let ns = storage.string as NSString
        let full = NSRange(location: 0, length: ns.length)
        let base: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: bodyParagraph()
        ]

        storage.beginEditing()
        if full.length == 0 {
            storage.setAttributes(base, range: full)
        } else {
            storage.setAttributes(base, range: full)
            ns.enumerateSubstrings(
                in: full,
                options: [.byLines, .substringNotRequired]
            ) { _, range, enclosing, _ in
                let lineRange = range.length > 0 ? range : enclosing
                guard lineRange.length > 0 else { return }
                let raw = ns.substring(with: lineRange)
                styleLine(raw, range: lineRange, storage: storage, font: font, color: color)
            }
            applyEmphasis(in: storage, ns: ns, full: full, font: font, color: color)
        }
        storage.endEditing()

        let maxLoc = storage.length
        var restored = selected
        if restored.location > maxLoc { restored.location = maxLoc }
        if restored.location + restored.length > maxLoc {
            restored.length = maxLoc - restored.location
        }
        tv.setSelectedRange(restored)
        if storage.length == 0 {
            tv.typingAttributes = base
        } else {
            let loc = min(restored.location, max(0, storage.length - 1))
            tv.typingAttributes = storage.attributes(at: loc, effectiveRange: nil)
        }
    }

    static func handleReturn(in tv: NSTextView) -> Bool {
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        guard sel.length == 0 else { return false }
        let loc = min(sel.location, ns.length)
        let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
        var line = ns.substring(with: lineRange)
        let hadNL = line.hasSuffix("\n")
        if hadNL { line = String(line.dropLast()) }
        guard let item = parseListLine(line) else { return false }

        if item.content.trimmingCharacters(in: .whitespaces).isEmpty {
            let replacement = item.indent + (hadNL ? "\n" : "")
            tv.insertText(replacement, replacementRange: lineRange)
            tv.setSelectedRange(NSRange(location: lineRange.location + (item.indent as NSString).length, length: 0))
            return true
        }

        let next: String
        if item.ordered {
            next = "\(item.indent)\(item.number + 1). "
        } else {
            next = "\(item.indent)\(item.bullet) "
        }
        tv.insertText("\n" + next, replacementRange: sel)
        return true
    }

    static func handleTab(in tv: NSTextView, outdent: Bool) -> Bool {
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        let loc = min(sel.location, ns.length)
        let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
        var line = ns.substring(with: lineRange)
        let hadNL = line.hasSuffix("\n")
        if hadNL { line = String(line.dropLast()) }
        guard parseListLine(line) != nil else { return false }

        let suffix = hadNL ? "\n" : ""
        if outdent {
            if line.hasPrefix("  ") {
                let next = String(line.dropFirst(2)) + suffix
                tv.insertText(next, replacementRange: lineRange)
                tv.setSelectedRange(NSRange(location: max(lineRange.location, sel.location - 2), length: sel.length))
                return true
            }
            if line.hasPrefix("\t") {
                let next = String(line.dropFirst()) + suffix
                tv.insertText(next, replacementRange: lineRange)
                tv.setSelectedRange(NSRange(location: max(lineRange.location, sel.location - 1), length: sel.length))
                return true
            }
            return true
        }

        let next = "  " + line + suffix
        tv.insertText(next, replacementRange: lineRange)
        tv.setSelectedRange(NSRange(location: sel.location + 2, length: sel.length))
        return true
    }

    static func parseListLine(_ line: String) -> ListLine? {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let m = unorderedRegex.firstMatch(in: line, range: full) {
            return ListLine(
                indent: ns.substring(with: m.range(at: 1)),
                ordered: false,
                number: 0,
                bullet: ns.substring(with: m.range(at: 2)),
                content: ns.substring(with: m.range(at: 3)),
                prefix: ns.substring(with: NSRange(location: 0, length: m.range(at: 3).location))
            )
        }
        if let m = orderedRegex.firstMatch(in: line, range: full) {
            let numStr = ns.substring(with: m.range(at: 2))
            return ListLine(
                indent: ns.substring(with: m.range(at: 1)),
                ordered: true,
                number: Int(numStr) ?? 1,
                bullet: "",
                content: ns.substring(with: m.range(at: 3)),
                prefix: ns.substring(with: NSRange(location: 0, length: m.range(at: 3).location))
            )
        }
        return nil
    }

    private static func styleLine(
        _ raw: String,
        range: NSRange,
        storage: NSTextStorage,
        font: NSFont,
        color: NSColor
    ) {
        let line = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
        let ns = line as NSString
        let lineFull = NSRange(location: 0, length: ns.length)
        guard lineFull.length > 0 else { return }

        if tableRegex.firstMatch(in: line, range: lineFull) != nil {
            let mono = NSFont.monospacedSystemFont(ofSize: max(11, font.pointSize * 0.86), weight: .regular)
            let ps = NSMutableParagraphStyle()
            ps.lineHeightMultiple = 0.96
            ps.paragraphSpacing = 0
            storage.addAttributes([
                .font: mono,
                .foregroundColor: color,
                .paragraphStyle: ps,
                .kern: -0.2
            ], range: range)
            return
        }

        if let m = headingRegex.firstMatch(in: line, range: lineFull) {
            let hashes = ns.substring(with: m.range(at: 2))
            let level = hashes.count
            let headingFont = headingFont(from: font, level: level)
            let ps = NSMutableParagraphStyle()
            ps.paragraphSpacingBefore = level == 1 ? 8 : 5
            ps.paragraphSpacing = 2
            storage.addAttributes([
                .font: headingFont,
                .foregroundColor: color,
                .paragraphStyle: ps
            ], range: range)
            let markerLen = m.range(at: 1).length + m.range(at: 2).length + 1
            if markerLen > 0 && markerLen <= range.length {
                storage.addAttributes([
                    .foregroundColor: color.withAlphaComponent(max(0.28, color.alphaComponent * 0.38)),
                    .font: headingFont
                ], range: NSRange(location: range.location, length: min(markerLen, range.length)))
            }
            return
        }

        if let item = parseListLine(line) {
            let markerWidth = (item.prefix as NSString).size(withAttributes: [.font: font]).width
            let ps = NSMutableParagraphStyle()
            ps.firstLineHeadIndent = 0
            ps.headIndent = markerWidth
            ps.paragraphSpacing = 1
            storage.addAttributes([.paragraphStyle: ps], range: range)
            let markerNs = item.prefix as NSString
            if markerNs.length > 0 {
                let markerRange = NSRange(location: range.location, length: min(markerNs.length, range.length))
                storage.addAttributes([
                    .foregroundColor: color.withAlphaComponent(max(0.32, color.alphaComponent * 0.45))
                ], range: markerRange)
            }
        }
    }

    private static func applyEmphasis(
        in storage: NSTextStorage,
        ns: NSString,
        full: NSRange,
        font: NSFont,
        color: NSColor
    ) {
        let dim = color.withAlphaComponent(max(0.28, color.alphaComponent * 0.38))
        let boldFont = emphasized(font, bold: true, italic: false)
        let italicFont = emphasized(font, bold: false, italic: true)
        var protected = IndexSet()

        func paint(_ regex: NSRegularExpression, openLen: Int, closeLen: Int, font: NSFont) {
            regex.enumerateMatches(in: ns as String, range: full) { match, _, _ in
                guard let match else { return }
                let r = match.range
                if r.length < openLen + closeLen { return }
                for i in r.location..<(r.location + r.length) {
                    if protected.contains(i) { return }
                }
                let open = NSRange(location: r.location, length: openLen)
                let close = NSRange(location: NSMaxRange(r) - closeLen, length: closeLen)
                let inner = NSRange(location: r.location + openLen, length: r.length - openLen - closeLen)
                if inner.length > 0 {
                    storage.addAttribute(.font, value: font, range: inner)
                }
                storage.addAttribute(.foregroundColor, value: dim, range: open)
                storage.addAttribute(.foregroundColor, value: dim, range: close)
                protected.insert(integersIn: r.location..<(r.location + r.length))
            }
        }

        paint(boldRegex, openLen: 2, closeLen: 2, font: boldFont)
        paint(italicStarRegex, openLen: 1, closeLen: 1, font: italicFont)
        paint(italicUnderscoreRegex, openLen: 1, closeLen: 1, font: italicFont)
    }

    private static func bodyParagraph() -> NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.lineBreakMode = .byWordWrapping
        ps.paragraphSpacing = 1
        return ps
    }

    private static func headingFont(from base: NSFont, level: Int) -> NSFont {
        let scale: CGFloat = level == 1 ? 1.48 : level == 2 ? 1.26 : 1.12
        let size = (base.pointSize * scale).rounded()
        if base.fontName.lowercased().contains("noteworthy") {
            return NSFont(name: "Noteworthy-Bold", size: size)
                ?? NSFont.systemFont(ofSize: size, weight: .bold)
        }
        let bolded = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        return NSFont(descriptor: bolded.fontDescriptor, size: size) ?? .systemFont(ofSize: size, weight: .bold)
    }

    private static func emphasized(_ base: NSFont, bold: Bool, italic: Bool) -> NSFont {
        var font = base
        if bold {
            if base.fontName.lowercased().contains("noteworthy") {
                font = NSFont(name: "Noteworthy-Bold", size: base.pointSize) ?? font
            } else {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
        }
        if italic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }
}

final class MarkdownNoteTextView: NSTextView {
    var onPlainTextChange: ((String) -> Void)?
    var styleFont: NSFont = .systemFont(ofSize: 16)
    var styleColor: NSColor = .textColor
    private var restyling = false

    override func didChangeText() {
        super.didChangeText()
        guard !restyling else { return }
        onPlainTextChange?(string)
        restyle()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        restyle()
    }

    func restyle() {
        restyling = true
        MarkdownNoteStyler.apply(to: self, font: styleFont, color: styleColor)
        restyling = false
    }

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    override func insertNewline(_ sender: Any?) {
        if MarkdownNoteStyler.handleReturn(in: self) { return }
        super.insertNewline(sender)
    }

    override func insertTab(_ sender: Any?) {
        if MarkdownNoteStyler.handleTab(in: self, outdent: false) { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if MarkdownNoteStyler.handleTab(in: self, outdent: true) { return }
        super.insertBacktab(sender)
    }
}
