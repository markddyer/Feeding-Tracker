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
        ("wait", Theme.wait), ("wait-tint", Theme.waitTint), ("backup", Theme.backup),
        ("backup-tint", Theme.backupTint), ("backup-stripe", Theme.backupStripe), ("on-backup", Theme.onBackup),
        ("breast", Theme.breast), ("breast-mark", Theme.breastMark), ("breast-tint", Theme.breastTint),
        ("bottle", Theme.bottle), ("bottle-mark", Theme.bottleMark), ("bottle-tint", Theme.bottleTint),
        ("pump", Theme.pump), ("pump-mark", Theme.pumpMark), ("pump-tint", Theme.pumpTint),
        ("bottle-soft", Theme.bottleSoft), ("breast-soft", Theme.breastSoft), ("chart", Theme.chart),
        ("chart-strip", Theme.chartStrip),
        ("sleep", Theme.sleep), ("sleep-mark", Theme.sleepMark), ("sleep-tint", Theme.sleepTint),
        ("sleep-soft", Theme.sleepSoft), ("wee", Theme.wee), ("wee-mark", Theme.weeMark), ("poo", Theme.poo), ("poo-mark", Theme.pooMark),
        ("nappy-tint", Theme.nappyTint),
        ("poo-brown", Theme.pooBrown), ("poo-yellow", Theme.pooYellow), ("poo-green", Theme.pooGreen),
        ("parent-1", Theme.parent1), ("on-parent-1", Theme.onParent1), ("parent-1-tint", Theme.parent1Tint),
        ("parent-2", Theme.parent2), ("on-parent-2", Theme.onParent2), ("parent-2-tint", Theme.parent2Tint),
        ("lavender", Theme.lavender), ("on-lavender", Theme.onLavender), ("lavender-tint", Theme.lavenderTint),
        ("plum", Theme.plum), ("on-plum", Theme.onPlum), ("plum-tint", Theme.plumTint),
        ("caramel", Theme.caramel), ("on-caramel", Theme.onCaramel), ("caramel-tint", Theme.caramelTint),
        ("stone", Theme.stone), ("on-stone", Theme.onStone), ("stone-tint", Theme.stoneTint),
        ("parent-1-mark", Theme.parent1Mark), ("parent-2-mark", Theme.parent2Mark), ("lavender-mark", Theme.lavenderMark),
        ("plum-mark", Theme.plumMark), ("caramel-mark", Theme.caramelMark), ("stone-mark", Theme.stoneMark),
        ("on-parent-mark", Theme.onParentMark),
        ("bath", Theme.bath), ("bath-mark", Theme.bathMark), ("bath-tint", Theme.bathTint),
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
        ("sleep-tint", Theme.sleepTint), ("nappy-tint", Theme.nappyTint),
    ]

    /// The sleep and nappy shapes and chart bars stand out on every tile, and on the 24-hour strip.
    @Test(arguments: [Look.day, .night])
    func sleepAndNappyShapesStandOut(_ look: Look) {
        for (mark, kind) in [(Theme.sleepMark, "sleep"), (Theme.weeMark, "wee"), (Theme.pooMark, "poo")] {
            for (name, tile) in Self.tiles {
                #expect(Self.ratio(mark, tile, look) >= 3, "\(kind) shape on \(name)")
            }
            #expect(Self.ratio(mark, Theme.chartStrip, look) >= 3, "\(kind) on the strip")
        }
        // Night sleep and day sleep in one stacked bar, told apart; day sleep sits on the 3:1 night bar.
        #expect(Self.ratio(Theme.sleepMark, Theme.sleepSoft, look) >= 1.5, "night sleep against day sleep")
        if look == .night {
            #expect(Self.ratio(Theme.sleepSoft, Theme.surface, look) >= 3, "day sleep on the tile")
        }
    }

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

    /// The 24-hour chart's blocks on their strip (`DayChart`).
    @Test(arguments: [Look.day, .night])
    func chartBlocksStandOutOnTheStrip(_ look: Look) {
        for (mark, kind) in [(Theme.breastMark, "breast"), (Theme.bottleMark, "bottle"), (Theme.textMuted, "unreadable feed")] {
            #expect(Self.ratio(mark, Theme.chartStrip, look) >= 3, "\(kind) block on the strip")
        }
        // The strip stands out from its card more than `track` did (the users' ask, 17 Nov 2026).
        #expect(Self.ratio(Theme.chartStrip, Theme.surface, look) > Self.ratio(Theme.track, Theme.surface, look))
    }

    /// The Graphs tab's bars on their tile, and the two shades of a kind told apart.
    @Test(arguments: [Look.day, .night])
    func graphBarsStandOut(_ look: Look) {
        #expect(Self.ratio(Theme.chart, Theme.surface, look) >= 4.5, "plain bars on the tile")
        #expect(Self.ratio(Theme.pumpMark, Theme.surface, look) >= 3, "pumping bars on the tile")
        // The soft shade sits on or beside its kind's mark, which carries the 3:1; the two must
        // look different, with or without colour.
        #expect(Self.ratio(Theme.bottleMark, Theme.bottleSoft, look) >= 1.5, "formula against expressed milk")
        #expect(Self.ratio(Theme.breastMark, Theme.breastSoft, look) >= 1.5, "left against right")
        if look == .night {
            #expect(Self.ratio(Theme.bottleSoft, Theme.surface, look) >= 3, "expressed milk on the tile")
            #expect(Self.ratio(Theme.breastSoft, Theme.surface, look) >= 3, "the right side on the tile")
        }
    }

    @Test(arguments: [Look.day, .night])
    func theInitialReadsOnEveryParentColour(_ look: Look) {
        for colour in ParentColour.allCases {
            #expect(Self.ratio(colour.onFill, colour.fill, look) >= 4.5, "\(colour.title)")
        }
    }

    /// Perceived colour difference (CIE76, in Lab): 15 or more reads as a different colour at a
    /// glance, so two parents' parts, or a bath and a bottle, are told apart by colour too.
    static func difference(_ first: Color, _ second: Color, _ look: Look) -> Double {
        func lab(_ rgb: UInt32) -> (Double, Double, Double) {
            func linear(_ value: UInt32) -> Double {
                let v = Double(value & 0xFF) / 255
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            let (r, g, b) = (linear(rgb >> 16), linear(rgb >> 8), linear(rgb))
            let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
            func f(_ t: Double) -> Double { t > 0.008856 ? pow(t, 1.0 / 3) : 7.787 * t + 16.0 / 116 }
            return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
        }
        let (a, b) = (lab(hex(first, look)), lab(hex(second, look)))
        return ((a.0 - b.0) * (a.0 - b.0) + (a.1 - b.1) * (a.1 - b.1) + (a.2 - b.2) * (a.2 - b.2)).squareRoot()
    }

    /// "Who does what" dots and bars (design 5A): each parent's mark on the tiles it sits on, the
    /// initial inside it, and every two parents' marks told apart.
    @Test(arguments: [Look.day, .night])
    func parentMarksStandOutAndDiffer(_ look: Look) {
        for colour in ParentColour.allCases {
            #expect(Self.ratio(colour.mark, Theme.surface, look) >= 3, "\(colour.title) mark on surface")
            #expect(Self.ratio(colour.mark, Theme.sleepTint, look) >= 3, "\(colour.title) mark on sleep-tint")
            #expect(Self.ratio(Theme.onParentMark, colour.mark, look) >= 4.5, "the initial on \(colour.title)")
        }
        for (index, first) in ParentColour.allCases.enumerated() {
            for second in ParentColour.allCases.dropFirst(index + 1) {
                #expect(Self.difference(first.mark, second.mark, look) >= 15, "\(first.title) against \(second.title)")
            }
        }
    }

    /// Bath's water-blue (design D6): its tub on its tile and on the surface, the words on its tile,
    /// and told apart from the bottle's blue and the teal parent.
    @Test(arguments: [Look.day, .night])
    func bathStandsOutAndDiffers(_ look: Look) {
        #expect(Self.ratio(Theme.bathMark, Theme.bathTint, look) >= 3, "tub on its tile")
        #expect(Self.ratio(Theme.bathMark, Theme.surface, look) >= 3, "tub on the surface")
        #expect(Self.ratio(Theme.text, Theme.bathTint, look) >= 7, "text on the bath tile")
        #expect(Self.ratio(Theme.textMuted, Theme.bathTint, look) >= 4.5, "muted text on the bath tile")
        #expect(Self.difference(Theme.bathMark, Theme.bottleMark, look) >= 15, "bath against bottle")
        #expect(Self.difference(Theme.bathMark, ParentColour.teal.mark, look) >= 15, "bath against teal")
    }

    /// The window bar's parts (the users' choice B, 21 Nov 2026): each told apart from the next,
    /// the misty blue from the bottle's blue, the empty parts seen on the tile better than `track`
    /// was, and the words and the bell on them readable.
    @Test(arguments: [Look.day, .night])
    func windowBarPartsDiffer(_ look: Look) {
        #expect(Self.difference(Theme.wait, Theme.primary, look) >= 15, "wait against the window")
        #expect(Self.difference(Theme.primary, Theme.backup, look) >= 15, "window against the backup")
        #expect(Self.difference(Theme.wait, Theme.bottle, look) >= 15, "wait against the bottle")
        #expect(Self.difference(Theme.wait, Theme.bottleMark, look) >= 15, "wait against the bottle's mark")
        #expect(Self.difference(Theme.wait, Theme.sleep, look) >= 15, "wait against sleep")
        for (part, name) in [(Theme.waitTint, "wait"), (Theme.backupTint, "backup")] {
            #expect(Self.difference(part, Theme.surface, look) > Self.difference(Theme.track, Theme.surface, look),
                    "\(name) still to come, on the tile")
        }
        #expect(Self.ratio(Theme.text, Theme.window, look) >= 4.5, "the window's name, still to come")
        #expect(Self.ratio(Theme.onPrimary, Theme.primary, look) >= 4.5, "the window's name, passed")
        #expect(Self.ratio(Theme.text, Theme.backupStripe, look) >= 3, "the bell on the stripes")
        #expect(Self.ratio(Theme.text, Theme.backupTint, look) >= 3, "the bell between the stripes")
        #expect(Self.ratio(Theme.onBackup, Theme.backup, look) >= 3, "the bell, passed")
    }

    /// The side being fed fills with the breast colour, with large letters (3:1 is the rule for
    /// large text): dark letters by day, the night text colour at night (`SideButton`).
    @Test func theSelectedSideButtonReads() {
        #expect(Self.ratio(Theme.onPrimary, Theme.breast, .day) >= 3)
        #expect(Self.ratio(Theme.text, Theme.breast, .night) >= 3)
    }
}
