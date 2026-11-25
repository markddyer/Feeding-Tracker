import XCTest

/// The calmer Home (`docs/planning/13-calm-home.md`): the care list logs with one tap, Today and
/// Recent start closed and open with a tap, a Recent row opens its entry, and Tonight's "I'll
/// take it" shows while the week is folded (Feeding Dev, simulator only). Run with the
/// FeedingDevAudit scheme: `-only-testing:FeedingDevUITests/CalmHomeFlowTests`.
@MainActor
final class CalmHomeFlowTests: XCTestCase {
    /// These tests load made-up data: never on a real phone, where the data is a family's own.
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only: this test replaces the app's data.")
        #endif
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle"]
        app.launch()
        return app
    }

    /// A folded part's heading, closed first: each phone remembers what is open, so an earlier
    /// run may have left it open. (A launch argument would pin it, so taps couldn't change it.)
    private func heading(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let heading = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        if heading.waitForExistence(timeout: 8), heading.value as? String == "Open" {
            scrollTo(app, heading)
            heading.tap()
        }
        return heading
    }

    private func scrollTo(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<8 where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    func testTheListLogsWithOneTap() {
        let app = launch()
        let wee = app.buttons["Log wee"]
        XCTAssertTrue(wee.waitForExistence(timeout: 8))
        wee.tap()
        XCTAssertTrue(app.staticTexts["Wee logged"].waitForExistence(timeout: 3))
        app.buttons["Close"].tap()
        let bath = app.buttons["Bath given"]
        for _ in 0..<8 where !(bath.exists && bath.isHittable) { app.swipeUp(velocity: .slow) }
        bath.tap()
        XCTAssertTrue(app.staticTexts["Bath logged"].waitForExistence(timeout: 3))
    }

    func testTodayOpensWithATap() {
        let app = launch()
        let today = heading(app, "Today")
        XCTAssertTrue(today.waitForExistence(timeout: 8))
        scrollTo(app, today)
        let chart = app.otherElements["Chart of feeds in the last 24 hours"]
        XCTAssertFalse(chart.exists, "closed at first")
        today.tap()
        XCTAssertTrue(chart.waitForExistence(timeout: 3), "open after a tap")
        today.tap()
        XCTAssertTrue(chart.waitForNonExistence(timeout: 3), "closed again")
    }

    func testARecentRowOpensItsEntry() {
        let app = launch()
        let recent = heading(app, "Recent")
        XCTAssertTrue(recent.waitForExistence(timeout: 8))
        scrollTo(app, recent)
        recent.tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Logged by' OR label CONTAINS 'Done by' OR label CONTAINS 'Settled by'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3), "the rows show")
        scrollTo(app, row)
        row.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3), "the entry's form opened")
        app.buttons["Cancel"].tap()
    }

    /// The open Duo's left page (`-openScreen duo`): Tonight is a card, and a tap opens the week
    /// of nights and its buttons in a window; the nappy card opens a poo's details.
    func testDuoTonightCardOpensTheWeek() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle",
                               "-openScreen", "duo"]
        app.launch()
        // The page fits with no scrolling (CH10): the last card, Bath, is in sight above Start
        // feed, with the sample's medicine making three rows.
        let bath = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Bath, '")).firstMatch
        XCTAssertTrue(bath.waitForExistence(timeout: 8))
        XCTAssertTrue(bath.isHittable, "the last card shows without scrolling")
        // The sample's last poo has no details: its card opens the panel.
        let nappy = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Add details'")).firstMatch
        XCTAssertTrue(nappy.waitForExistence(timeout: 8))
        nappy.tap()
        // The panel's colours ("Colour" itself is drawn in capitals).
        let colour = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Yellow'")).firstMatch
        XCTAssertTrue(colour.waitForExistence(timeout: 3), "the poo's panel opened")
        app.buttons["Done"].tap()
        XCTAssertTrue(colour.waitForNonExistence(timeout: 3))

        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tonight: '")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 3), "Tonight is a card")
        let week = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Tonight, '")).firstMatch
        XCTAssertFalse(week.exists, "the week waits for a tap")
        card.tap()
        XCTAssertTrue(week.waitForExistence(timeout: 3), "the week shows in the window")
        XCTAssertTrue(app.buttons["I'll take it"].exists, "with its button")
        app.buttons["Done"].tap()
        XCTAssertTrue(week.waitForNonExistence(timeout: 3), "closed again")
    }

    func testTonightsButtonShowsWhileTheWeekIsFolded() {
        let app = launch()
        let tonight = heading(app, "Tonight")
        let take = app.buttons["I'll take it"]
        scrollTo(app, take)
        XCTAssertTrue(take.waitForExistence(timeout: 8))
        let week = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Tonight, '")).firstMatch
        XCTAssertFalse(week.exists, "the week is folded")
        tonight.tap()
        XCTAssertTrue(week.waitForExistence(timeout: 3), "the week shows once opened")
    }
}
