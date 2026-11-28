import FeedingCore
import Foundation
import SwiftUI
import Testing
import WidgetKit
@testable import FeedingDev

/// The words outside the app (the user's choice of 16 Nov 2026: start and finish a feed from the
/// Lock Screen, Control Center, the Action Button and Siri, and a Lock Screen widget).
@Suite("Outside the app")
@MainActor
struct GlanceTests {
    let start = Date(timeIntervalSince1970: 1_794_798_000) // 16 Nov 2026, 03:00 in London
    let me: MemberID = "a"
    let names: [MemberID: String] = ["a": "Alex", "b": "Sam"]

    func feed(by member: MemberID, minutes: Double? = nil) -> EventSnapshot {
        EventSnapshot(event: Event(id: "f", babyID: "baby", kind: .feed, startedAt: start,
                                   endedAt: minutes.map { start.addingTimeInterval($0 * 60) },
                                   timeZoneID: "Europe/London", loggedBy: member, createdAt: start, modifiedAt: start))
    }

    func said(_ result: QuickFeedResult) -> String {
        GlanceText.said(result, me: me, names: names, timeZoneID: "Europe/London", now: start)
    }

    @Test func whatSiriSays() {
        // "03:00", or "3:00 AM", as the phone's language writes it.
        let three = GlanceText.clock(start, timeZoneID: "Europe/London")
        #expect(three.contains("3:00"))
        // Siri asks the sides or the amount at Finish (docs/planning/15-hands-free-siri.md).
        #expect(said(.started(id: "f", at: start, bottle: nil)) == "Feed started at \(three).")
        #expect(said(.started(id: "f", at: start, bottle: .formula)) == "Formula bottle started at \(three).")
        #expect(said(.started(id: "f", at: start, bottle: .expressed)) == "Expressed milk bottle started at \(three).")
        #expect(said(.alreadyRunning(feed(by: "a"))) == "Your feed is running, started at \(three).")
        #expect(said(.alreadyRunning(feed(by: "b"))) == "Sam's feed is running, started at \(three).")
        #expect(said(.finished(feed(by: "a", minutes: 25))) == "Feed finished, after 25 minutes.")
        #expect(said(.finished(feed(by: "b", minutes: 61))) == "Sam's feed finished, after 1 hour, 1 minute.")
        #expect(said(.nothingRunning) == "No feed is running.")
    }

    @Test func noWordSoundsLikeAVerdict() {
        let words = [said(.started(id: "f", at: start, bottle: nil)), said(.started(id: "f", at: start, bottle: .formula)),
                     said(.alreadyRunning(feed(by: "b"))),
                     said(.finished(feed(by: "a", minutes: 25))), said(.nothingRunning), GlanceText.notSetUp,
                     "Feed running", "Last feed", "Feeding window", "No feeds logged yet", "Open the app to set up",
                     "Feed running, from 10:47", "Last feed · window 13:20", "Feed running for", "ago",
                     "Start feed", "Finish feed", "Start or finish a feed", "Formula", "Expressed", "Start a formula bottle",
                     "Start an expressed milk bottle", "Formula or expressed milk?", "Choose later", "Start"]
        for word in words {
            let plain = word.lowercased().filter { $0.isLetter || $0 == " " || $0 == "'" }
            for forbidden in AlertText.forbiddenWords {
                #expect(!plain.split(separator: " ").contains(Substring(forbidden)), "\(word)")
            }
        }
    }

    /// Small Control Center buttons show only the icon, so each bottle has its own.
    @Test func eachButtonHasItsOwnIcon() {
        let symbols = [ControlBottle.later, .formula, .expressed].map(\.symbol)
        #expect(Set(symbols).count == 3)
        #expect(ControlBottle.formula.symbol == "f.circle.fill")
        #expect(ControlBottle.expressed.symbol == "e.circle.fill")
    }

    /// The user's choice of 16 Nov 2026: Start and Finish work on a locked phone, with no Face ID.
    @Test func theButtonsWorkOnALockedPhone() {
        #expect(StartFeedIntent.authenticationPolicy == .alwaysAllowed)
        #expect(FinishFeedIntent.authenticationPolicy == .alwaysAllowed)
        #expect(FeedToggleIntent.authenticationPolicy == .alwaysAllowed)
    }

    /// With 90 moments, the wide widget's saved file went missing on the Duo and it showed the
    /// grey stand-in (16 Nov 2026). Its time updates by itself, so one moment is enough.
    @Test func theWideWidgetPreparesOneMoment() {
        #expect(LastFeedMoments.minutes(for: .accessoryRectangular) == [0])
        #expect(LastFeedMoments.minutes(for: .accessoryCircular).count == 169)
        #expect(LastFeedMoments.minutes(for: .accessoryInline).count == 169)
    }

    @Test func theAppAndTheWidgetWriteTimesTheSameWay() {
        #expect(HomeText.elapsed(6000) == GlanceText.elapsed(6000))
        #expect(GlanceText.elapsed(6000) == "1h 40m")
        #expect(GlanceText.elapsed(300) == "5m")
        #expect(GlanceText.compactElapsed(6000) == "1:40")
        #expect(GlanceText.compactElapsed(3900) == "1:05")
        #expect(GlanceText.compactElapsed(300) == "5m")
    }

    /// Draws the widget in each size and state, for a person to look at: run with
    /// `TEST_RUNNER_GLANCE_PICTURES=<folder>` to save the pictures there.
    @Test func widgetPictures() throws {
        let now = start.addingTimeInterval(6000)
        let states: [(String, FeedGlance?)] = [
            ("last", FeedGlance(lastFeedStart: start, windowOpens: start.addingTimeInterval(7200),
                                windowCloses: start.addingTimeInterval(14400))),
            ("running", FeedGlance(lastFeedStart: now.addingTimeInterval(-720), runningSince: now.addingTimeInterval(-720),
                                   windowOpens: now.addingTimeInterval(6480), windowCloses: now.addingTimeInterval(13680))),
            ("empty", FeedGlance()),
            ("notSetUp", nil),
        ]
        // The wide size as the Duo draws it (157 × 73.5, from the phone's log of 16 Nov 2026).
        let sizes: [(WidgetFamily, CGSize)] = [(.accessoryRectangular, CGSize(width: 157, height: 73.5)),
                                              (.accessoryCircular, CGSize(width: 76, height: 76)),
                                              (.accessoryInline, CGSize(width: 260, height: 26))]
        let folder = ProcessInfo.processInfo.environment["GLANCE_PICTURES"].map { URL(fileURLWithPath: $0) }
        for (name, glance) in states {
            for (family, size) in sizes {
                // Rectangular twice: a breast-and-bottle phone, and a bottle-only phone.
                for bottleOnly in family == .accessoryRectangular ? [false, true] : [false] {
                let view = LastFeedWidgetView(entry: LastFeedEntry(date: now, glance: glance, bottleOnly: bottleOnly), family: family)
                    .frame(width: size.width, height: size.height)
                    .foregroundStyle(.white)
                    .background(Color(white: 0.15))
                    .environment(\.colorScheme, .dark)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 3
                let image = try #require(renderer.uiImage, "\(name) \(family)")
                if let folder, let png = image.pngData() {
                    try png.write(to: folder.appendingPathComponent("widget-\(name)-\(family)\(bottleOnly ? "-bottleOnly" : "").png"))
                }
                }
            }
        }
    }
}
