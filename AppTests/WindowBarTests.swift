import FeedingCore
import Foundation
import SwiftUI
import Testing
@testable import FeedingDev

/// The feeding window bar (the users' choice B, 21 Nov 2026): the line in words, the parts, where
/// now sits, and the labels' places. Facts only: never "due", "missed" or "overdue".
@Suite("Window bar")
struct WindowBarTests {
    let feed = Date(timeIntervalSince1970: 1_795_000_000)
    let zone = TimeZone(identifier: "Europe/London")!

    func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone).hour(.twoDigits(amPM: .omitted)).minute())
    }

    func steps(after minutes: Double, _ settings: FeedWindowSettings = FeedWindowSettings()) -> WindowSteps {
        WindowSteps(window: FeedWindow(lastFeedStart: feed, settings: settings), settings: settings,
                    now: feed.addingTimeInterval(minutes * 60))
    }

    func at(_ minutes: Double) -> String { clock(feed.addingTimeInterval(minutes * 60)) }

    @Test func theLineSaysWhereNowIs() {
        let before = steps(after: 100)
        #expect(before.phase == .beforeWindow)
        #expect(before.line(clock).main == "Window opens in 20m")
        #expect(before.line(clock).more == " · at \(at(120))")

        let inside = steps(after: 185)
        #expect(inside.phase == .inWindow)
        #expect(inside.line(clock).main == "In the feeding window")
        #expect(inside.line(clock).more == " · alert at \(at(240))")

        let after = steps(after: 260)
        #expect(after.phase == .afterWindow)
        #expect(after.line(clock).main == "Window closed at \(at(240))")
        #expect(after.line(clock).more == " · backup alarm \(at(270))")
    }

    /// Part of a minute counts as a minute, so "in 0m" never shows before the window opens.
    @Test func theMinutesToTheOpeningRoundUp() {
        #expect(steps(after: 99.5).line(clock).main == "Window opens in 21m")
        #expect(steps(after: 119.9).line(clock).main == "Window opens in 1m")
        #expect(steps(after: 120).line(clock).main == "In the feeding window")
    }

    @Test func withAlertsOffThereIsNoBackupAndTheLineSaysSo() {
        let off = FeedWindowSettings(alertsEnabled: false)
        #expect(steps(after: 100, off).parts.map(\.kind) == [.sinceFeed, .window])
        #expect(steps(after: 100, off).line(clock).more == " · at \(at(120)) · alerts off")
        #expect(steps(after: 185, off).line(clock).more == " · until \(at(240)) · alerts off")
        #expect(steps(after: 260, off).line(clock).more == " · alerts off")
        #expect(steps(after: 260, off).spoken(clock).hasSuffix("Alerts are off."))
    }

    @Test func thePartsFollowTheSettings() {
        let parts = steps(after: 0).parts
        #expect(parts.map(\.kind) == [.sinceFeed, .window, .backup])
        #expect(parts.map(\.from) == [0, 7200, 14400])
        #expect(parts.map(\.to) == [7200, 14400, 16200])
        // A window that opens when it closes has no part of its own.
        let none = FeedWindowSettings(opensAfter: 3 * 3600, closesAfter: 3 * 3600)
        #expect(steps(after: 0, none).parts.map(\.kind) == [.sinceFeed, .backup])
    }

    @Test func eachPartFillsUpToNow() {
        let inside = steps(after: 180)
        let parts = inside.parts
        #expect(inside.filled(parts[0]) == 1)
        #expect(inside.filled(parts[1]) == 0.5)
        #expect(inside.filled(parts[2]) == 0)
        #expect(inside.currentPart == .window)
        // Past the backup alarm, the bar is full and now stays at its end.
        let late = steps(after: 400)
        #expect(late.parts.allSatisfy { late.filled($0) == 1 })
        #expect(late.currentPart == .backup)
        #expect(late.nowX(width: 300) == 300)
    }

    /// The parts fill the bar's width, with their gaps, and the backup's short stretch keeps a
    /// width a finger and an eye can find.
    @Test func thePartsFillTheBarAndTheBackupStaysVisible() throws {
        let frames = steps(after: 100).frames(width: 300, gap: 3, minimum: 26)
        let last = try #require(frames.last)
        #expect(abs(last.x + last.width - 300) < 0.01)
        #expect(last.width >= 26)
        let short = FeedWindowSettings(backupAfterClose: 5 * 60)
        let tiny = try #require(steps(after: 100, short).frames(width: 300).last)
        #expect(tiny.width >= 26)
        #expect(abs(tiny.x + tiny.width - 300) < 0.01)
        // Now sits inside its part: 100 of the first part's 120 minutes.
        let first = frames[0]
        #expect(abs(steps(after: 100).nowX(width: 300) - (first.x + first.width * 100 / 120)) < 0.01)
    }

    @Test func theLabelsSitAtTheirPartsOrStack() throws {
        let sizes = [CGSize(width: 60, height: 30), CGSize(width: 100, height: 30), CGSize(width: 45, height: 30)]
        let xs = try #require(StepLabels.positions(starts: [0, 133, 266], width: 300, sizes: sizes, spacing: 8))
        #expect(xs == [0, 133, 255])
        // A label that would touch the one before is pushed along.
        let pushed = try #require(StepLabels.positions(starts: [0, 40, 266], width: 300, sizes: sizes, spacing: 8))
        #expect(pushed[1] == 68)
        // Too narrow for all three side by side: they stack.
        #expect(StepLabels.positions(starts: [0, 60, 120], width: 180, sizes: sizes, spacing: 8) == nil)
    }

    @Test func theWordsAreFactsOnly() {
        let words = [100.0, 185, 260].flatMap { minutes -> [String] in
            let s = steps(after: minutes)
            let line = s.line(clock)
            return [line.main, line.more, s.spoken(clock)] + s.parts.map { s.label($0.kind, clock).name }
        }
        for word in ["due", "missed", "overdue", "should", "late"] {
            #expect(!words.contains { $0.lowercased().contains(word) }, "\"\(word)\" in the window bar")
        }
    }
}
