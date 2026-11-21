import XCTest

/// A graph's own page (`docs/planning/10-graph-pages.md`, the users' choice C): a tap on a graph's
/// tile opens its page on today; ‹ goes back a day; the day's list has as many feeds as its total
/// says; a tap on another bar picks that day; a row opens its editor (Feeding Dev, simulator
/// only). Run with the FeedingDevAudit scheme: `-only-testing:FeedingDevUITests/GraphPageFlowTests`.
@MainActor
final class GraphPageFlowTests: XCTestCase {
    /// These tests load made-up data: never on a real phone, where the data is a family's own.
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only: this test replaces the app's data.")
        #endif
    }

    func testATileOpensItsPageAndABarPicksItsDay() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES", "-sampleWeek", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle",
                               "-graphs.range", "week", "-startTab", "graphs"]
        app.launch()

        // The "Feeds each day" tile, further down the Graphs tab.
        let label = app.staticTexts.matching(NSPredicate(format: "label ==[c] 'Feeds each day'")).firstMatch
        XCTAssertTrue(app.staticTexts["Graphs"].waitForExistence(timeout: 8))
        for _ in 0..<8 where !(label.exists && label.isHittable) { app.swipeUp() }
        XCTAssertTrue(label.isHittable, "the Feeds each day tile is on the Graphs tab")
        label.tap()

        // Its page, on today.
        XCTAssertTrue(app.navigationBars["Feeds each day"].waitForExistence(timeout: 3), "the tile opens its page")
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 3), "the page opens on today")

        // ‹ goes back a day; yesterday's list has as many feeds as its total says.
        app.buttons["Day before"].tap()
        XCTAssertTrue(app.staticTexts["Yesterday"].waitForExistence(timeout: 3))
        let total = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+ feeds?$")).firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 3), "the day's total: \"8 feeds\"")
        let count = Int(total.label.split(separator: " ").first ?? "") ?? -1
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Done by'"))
        XCTAssertEqual(rows.count, count, "the list has as many feeds as the total")
        let page = XCTAttachment(screenshot: app.screenshot())
        page.name = "Feeds each day, yesterday"
        page.lifetime = .keepAlways
        add(page)

        // A tap on the first bar picks the first of the 7 days (named, not Today or Yesterday).
        let picker = app.buttons["7 days"]
        let before = app.buttons["Day before"]
        let x = app.windows.firstMatch.frame.width * 0.14
        let y = (picker.frame.maxY + before.frame.minY) / 2
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)).tap()
        let named = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[A-Z][a-z]+day [0-9]{1,2} [A-Z][a-z]+$"))
        XCTAssertTrue(named.firstMatch.waitForExistence(timeout: 3), "a tap on a bar picks its day")
        XCTAssertFalse(app.staticTexts["Yesterday"].exists)
        XCTAssertFalse(before.isEnabled, "the first day has no day before it in 7 days")

        // A row opens its editor, as in History.
        let row = rows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 3), "a row opens its editor")
    }

    /// On the Graphs tab, a tap on a bar opens the page on that bar's day, not on today.
    func testABarOnTheTabOpensThePageOnItsDay() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES", "-sampleWeek", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle",
                               "-graphs.range", "week", "-startTab", "graphs"]
        app.launch()

        let label = app.staticTexts.matching(NSPredicate(format: "label ==[c] 'Feeds each day'")).firstMatch
        XCTAssertTrue(app.staticTexts["Graphs"].waitForExistence(timeout: 8))
        for _ in 0..<8 where !(label.exists && label.isHittable) { app.swipeUp() }
        // Bring the whole tile up, clear of the tab bar.
        if label.frame.minY > app.windows.firstMatch.frame.height * 0.5 { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(label.isHittable)
        // The first bar: under the label, at the left of the graph.
        let x = app.windows.firstMatch.frame.width * 0.14
        let y = label.frame.maxY + 90
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)).tap()

        XCTAssertTrue(app.navigationBars["Feeds each day"].waitForExistence(timeout: 3), "a bar opens its page")
        let named = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[A-Z][a-z]+day [0-9]{1,2} [A-Z][a-z]+$"))
        XCTAssertTrue(named.firstMatch.waitForExistence(timeout: 3), "on the first bar's day, not today")
        XCTAssertFalse(app.staticTexts["Today"].exists)
    }
}
