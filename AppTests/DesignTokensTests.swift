import FeedingCore
import SwiftUI
import Testing
import UIKit
@testable import FeedingDev

/// The colours in `Theme` are the ones in `DESIGN.md`, in both looks, and every contrast pair
/// `DESIGN.md` promises holds (`05-visual-redesign.md`, "Checks": "recheck every pair").
@Suite("Colours match DESIGN.md")
struct DesignTokensTests {
    /// Every `Theme` colour and its token name in `DESIGN.md`.
    static let tokens: [(String, Color)] = [
        ("background", Theme.background), ("surface", Theme.surface), ("text", Theme.text),
        ("text-muted", Theme.textMuted), ("primary", Theme.primary), ("on-primary", Theme.onPrimary),
        ("track", Theme.track), ("window", Theme.window),
        ("breast", Theme.breast), ("breast-mark", Theme.breastMark), ("breast-tint", Theme.breastTint),
        ("bottle", Theme.bottle), ("bottle-mark", Theme.bottleMark), ("bottle-tint", Theme.bottleTint),
        ("pump", Theme.pump), ("pump-mark", Theme.pumpMark), ("pump-tint", Theme.pumpTint),
        ("parent-1", Theme.parent1), ("on-parent-1", Theme.onParent1), ("parent-1-tint", Theme.parent1Tint),
        ("parent-2", Theme.parent2), ("on-parent-2", Theme.onParent2), ("parent-2-tint", Theme.parent2Tint),
        ("lavender", Theme.lavender), ("on-lavender", Theme.onLavender), ("lavender-tint", Theme.lavenderTint),
        ("plum", Theme.plum), ("on-plum", Theme.onPlum), ("plum-tint", Theme.plumTint),
        ("caramel", Theme.caramel), ("on-caramel", Theme.onCaramel), ("caramel-tint", Theme.caramelTint),
        ("stone", Theme.stone), ("on-stone", Theme.onStone), ("stone-tint", Theme.stoneTint),
        ("notice", Theme.notice),
    ]

    /// The `colors:` block at the top of DESIGN.md. The simulator runs on the Mac, so the test can
    /// read the repository's file directly.
    static func designColours() throws -> [String: UInt32] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("DESIGN.md")
        var colours: [String: UInt32] = [:]
        var inColours = false
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("colors:") { inColours = true; continue }
            if inColours, !line.hasPrefix(" ") { break }
            guard inColours, !line.trimmingCharacters(in: .whitespaces).hasPrefix("#") else { continue }
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let hex = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"#"))
            if let value = UInt32(hex, radix: 16) { colours[parts[0]] = value }
        }
        return colours
    }

    /// A Theme colour in one look, as 0xRRGGBB.
    static func hex(_ colour: Color, _ look: Look) -> UInt32 {
        let resolved = UIColor(colour).resolvedColor(with: UITraitCollection(userInterfaceStyle: look == .night ? .dark : .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UInt32((r * 255).rounded()) << 16 | UInt32((g * 255).rounded()) << 8 | UInt32((b * 255).rounded())
    }

    /// WCAG contrast ratio of two 0xRRGGBB colours.
    static func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        func luminance(_ rgb: UInt32) -> Double {
            func channel(_ value: UInt32) -> Double {
                let v = Double(value & 0xFF) / 255
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(rgb >> 16) + 0.7152 * channel(rgb >> 8) + 0.0722 * channel(rgb)
        }
        let (a, b) = (luminance(first), luminance(second))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static func ratio(_ first: Color, _ second: Color, _ look: Look) -> Double {
        contrast(hex(first, look), hex(second, look))
    }

    @Test func everyThemeColourIsTheDesignColour() throws {
        let design = try Self.designColours()
        for (token, colour) in Self.tokens {
            let day = try #require(design[token], "\(token) is not in DESIGN.md")
            #expect(Self.hex(colour, .day) == day, "\(token) by day")
            // At night a "mark" shade is the kind's plain night colour (DESIGN.md, "Colors").
            let nightToken = design["\(token)-night"] != nil ? "\(token)-night"
                : token.replacingOccurrences(of: "-mark", with: "") + "-night"
            let night = try #require(design[nightToken], "\(nightToken) is not in DESIGN.md")
            #expect(Self.hex(colour, .night) == night, "\(token) at night")
        }
    }

    /// The tiles text and shapes sit on.
    static let tiles: [(String, Color)] = [
        ("background", Theme.background), ("surface", Theme.surface), ("breast-tint", Theme.breastTint),
        ("bottle-tint", Theme.bottleTint), ("pump-tint", Theme.pumpTint),
    ]

    @Test(arguments: [Look.day, .night])
    func textReadsOnEveryTile(_ look: Look) {
        #expect(Self.ratio(Theme.text, Theme.background, look) >= 12)
        for (name, tile) in Self.tiles {
            #expect(Self.ratio(Theme.text, tile, look) >= 7, "text on \(name)")
            #expect(Self.ratio(Theme.textMuted, tile, look) >= 4.5, "muted text on \(name)")
        }
    }

    @Test(arguments: [Look.day, .night])
    func theMainButtonsWordsRead(_ look: Look) {
        #expect(Self.ratio(Theme.onPrimary, Theme.primary, look) >= 4.5)
    }

    @Test(arguments: [Look.day, .night])
    func feedShapesStandOutOnEveryTile(_ look: Look) {
        for (mark, kind) in [(Theme.breastMark, "breast"), (Theme.bottleMark, "bottle"), (Theme.pumpMark, "pump")] {
            for (name, tile) in Self.tiles {
                #expect(Self.ratio(mark, tile, look) >= 3, "\(kind) shape on \(name)")
            }
        }
    }

    @Test(arguments: [Look.day, .night])
    func theInitialReadsOnEveryParentColour(_ look: Look) {
        for colour in ParentColour.allCases {
            #expect(Self.ratio(colour.onFill, colour.fill, look) >= 4.5, "\(colour.title)")
        }
    }

    /// The side being fed fills with the breast colour, with large letters (3:1 is the rule for
    /// large text): dark letters by day, the night text colour at night (`SideButton`).
    @Test func theSelectedSideButtonReads() {
        #expect(Self.ratio(Theme.onPrimary, Theme.breast, .day) >= 3)
        #expect(Self.ratio(Theme.text, Theme.breast, .night) >= 3)
    }
}
