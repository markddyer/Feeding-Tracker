import FeedingCore
import SwiftUI
import Testing
import UIKit
@testable import FeedingDev

/// The two typefaces from DESIGN.md, "Typography".
@Suite("Letters")
struct TypographyTests {
    @Test func fredokaIsBundledAndRegistered() {
        // A missing font fails silently in SwiftUI (it falls back to the system font), so check.
        #expect(!UIFont.fontNames(forFamilyName: FeedTextStyle.fredoka).isEmpty)
        for style in FeedTextStyle.allCases where style.usesFredoka {
            for look in [Look.day, .night] {
                #expect(UIFont(name: style.fredokaName(look), size: 20) != nil, "\(style.fredokaName(look))")
            }
        }
    }

    @Test func numbersAreNeverSetInFredoka() {
        // Every style that can hold a time, duration, amount or count: the main time, totals,
        // chips, chart times ("24h ago"), the age chip, and bar labels ("Feeding window 10:25").
        for style in [FeedTextStyle.mainTime, .total, .chip, .small, .smallButton, .subheadline, .body, .label] {
            #expect(!style.usesFredoka)
        }
    }

    @Test func headingsAndButtonsUseFredoka() {
        for style in [FeedTextStyle.title, .button, .tileValue, .dayHeading, .greeting] {
            #expect(style.usesFredoka)
        }
    }

    @Test(arguments: FeedTextStyle.allCases)
    func nothingIsHeavierAtNight(_ style: FeedTextStyle) {
        let order: [Font.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
        let day = order.firstIndex(of: style.weight(.day))
        let night = order.firstIndex(of: style.weight(.night))
        #expect(day != nil && night != nil)
        if let day, let night { #expect(night <= day) }
    }
}
