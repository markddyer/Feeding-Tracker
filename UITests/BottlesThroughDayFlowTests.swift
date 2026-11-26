import XCTest

/// "Bottles through the day" (`docs/planning/14-bottles-through-the-day.md`, Parent A's choices A, A,
/// A of 26 Nov 2026): Home's line in Today opens the page; ‹ goes to yesterday, whose last bottle's
/// running total is the day's whole number; the Graphs tab's tile opens the page too (Feeding Dev,
/// simulator only). Run with the FeedingDevAudit scheme:
/// `-only-testing:FeedingDevUITests/BottlesThroughDayFlowTests`.
@MainActor
final class BottlesThroughDayFlowTests: XCTestCase {
    /// These tests load made-up data: never on a real phone, where the data is a family's own.
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only: this test replaces the app's data.")
        #endif
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES", "-sampleWeek", "YES", "-speechSilent", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle"] + extra
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The number in "Today: 210 ml".
    private func ml(_ element: XCUIElement) -> Int? {
        guard let colon = element.label.lastIndex(of: ":") else { return nil }
        return Int(element.label[element.label.index(after: colon)...].split(separator: " ").first ?? "")
    }

    func testHomesLineOpensThePageAndYesterdayAddsUp() {
        let app = launch(["-home.open.today", "YES", "-home.open.recent", "NO"])
        let line = any(app, "bottlesTodayLine")
        XCTAssertTrue(app.buttons["Start feed"].waitForExistence(timeout: 8))
        for _ in 0..<8 where !(line.exists && line.isHittable) { app.swipeUp() }
        XCTAssertTrue(line.isHittable, "the line is in Today")
        XCTAssertTrue(line.label.hasPrefix("Bottles since midnight: "), line.label)
        XCTAssertTrue(line.label.contains(" ml today"), line.label)
        XCTAssertTrue(line.label.contains("ml yesterday by now"), line.label)
        XCTAssertTrue(line.label.contains("ml average by now"), line.label)
        keep(app, "Home's line")
        line.tap()

        XCTAssertTrue(app.navigationBars["Bottles through the day"].waitForExistence(timeout: 3), "the line opens the page")
        let soFar = any(app, "bottlesSoFar")
        XCTAssertTrue(soFar.waitForExistence(timeout: 3))
        XCTAssertTrue(soFar.label.hasPrefix("Today: "), soFar.label)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Today, by '")).firstMatch.exists)
        XCTAssertTrue(any(app, "bottlesChart").label.hasPrefix("A line of the bottles from midnight"))
        keep(app, "The page, today")

        // ‹ goes to yesterday: the whole day, and its last bottle's running total is that number.
        app.buttons["Day before"].tap()
        XCTAssertTrue(app.staticTexts["Yesterday"].waitForExistence(timeout: 3))
        XCTAssertTrue(soFar.label.hasPrefix("Whole day: "), soFar.label)
        // A whole made-up day has breastfeeds (today's may not yet, just after midnight).
        XCTAssertTrue(any(app, "bottlesAlso").label.contains("A breastfeed has no amount."), "the breastfeeds aren't in the total, and it says so")
        let whole = ml(soFar)
        // Each row's words, wherever the row puts its note: "… 240 ml from midnight".
        let totals = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS ' ml from midnight'"))
        for _ in 0..<10 { app.swipeUp() }
        XCTAssertGreaterThan(totals.count, 0, "the day's bottles are listed")
        let numbers = totals.allElementsBoundByIndex.compactMap { element -> Int? in
            guard let range = element.label.range(of: " ml from midnight") else { return nil }
            return Int(element.label[..<range.lowerBound].split(whereSeparator: { !$0.isNumber }).last ?? "")
        }
        XCTAssertEqual(numbers.max(), whole, "the last bottle's total is the day's")
        keep(app, "The page, yesterday")
    }

    func testTheGraphsTileOpensThePage() {
        let app = launch(["-graphs.range", "week", "-startTab", "graphs"])
        XCTAssertTrue(app.staticTexts["Graphs"].waitForExistence(timeout: 8))
        let open = app.buttons["bottlesTileOpen"]
        for _ in 0..<8 where !(open.exists && open.isHittable) { app.swipeUp() }
        XCTAssertTrue(open.isHittable, "the tile is on the Graphs tab")
        keep(app, "The Graphs tile")
        open.tap()
        XCTAssertTrue(app.navigationBars["Bottles through the day"].waitForExistence(timeout: 3), "the tile opens the page")
        XCTAssertTrue(any(app, "bottlesSoFar").waitForExistence(timeout: 3))
    }
}
