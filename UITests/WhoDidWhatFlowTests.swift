import XCTest

/// The "who did what" page (`09-who-does-what.md`, X2, DD10, D1 A): a parent's number opens the
/// list behind it, with as many rows as the number says; a row opens its editor, and giving the
/// entry to the other parent there lowers the count while the row stays until the list is left
/// (DD8, 2C) (Feeding Dev, simulator only). Run with the FeedingDevAudit scheme:
/// `-only-testing:FeedingDevUITests/WhoDidWhatFlowTests`.
@MainActor
final class WhoDidWhatFlowTests: XCTestCase {
    /// These tests load made-up data: never on a real phone, where the data is a family's own.
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only: this test replaces the app's data.")
        #endif
    }

    func testANumberOpensItsListAndARowOpensItsEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES", "-sampleWeek", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle",
                               "-share.breastfeederAsked", "YES", "-share.range", "day", "-share.dayOffset", "1",
                               "-openScreen", "whoDidWhat"]
        app.launch()

        // Yesterday's nappies: "Sam 2" or similar, under the Nappies bar.
        // The bar's heading is read as one line: "Nappies, 3: Sam 2, Alex 1".
        let nappies = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Nappies, '")).firstMatch
        XCTAssertTrue(nappies.waitForExistence(timeout: 8))
        // The numbers on the row just under the Nappies bar; the first parent with any. The made-up
        // week follows the time of day, so either parent may have none yesterday (at 23:40 on
        // 21 Nov 2026 the first had "Sam 0").
        let numbers = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^[A-Za-z]+ [0-9]+$"))
            .allElementsBoundByIndex.filter { $0.frame.minY > nappies.frame.minY }
        let rowY = numbers.map(\.frame.minY).min() ?? 0
        let number = numbers.filter { abs($0.frame.minY - rowY) < 4 }
            .first { (Int($0.label.split(separator: " ").last ?? "") ?? 0) > 0 }
        guard let number else { return XCTFail("no parent with a nappy under Nappies") }
        let count = Int(number.label.split(separator: " ").last ?? "") ?? -1
        let parent = String(number.label.split(separator: " ").first ?? "")
        XCTAssertGreaterThan(count, 0, "the sample day has nappies for this parent: \(number.label)")
        for _ in 0..<4 where !number.isHittable { app.swipeUp() }
        number.tap()

        // The list: its chips, its count, and one row per entry, each "Done by" that parent.
        XCTAssertTrue(app.staticTexts["Yesterday"].waitForExistence(timeout: 3), "the range chip")
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Done by'"))
        XCTAssertEqual(rows.count, count, "the list has as many rows as the number")
        let list = XCTAttachment(screenshot: app.screenshot())
        list.name = "The list behind a number"
        list.lifetime = .keepAlways
        add(list)

        rows.firstMatch.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 3), "a row opens its editor")

        // "Who did it" in the editor (DD8): give it to the other parent, and the list follows.
        let other = app.buttons.matching(NSPredicate(format: "label IN %@ AND label != %@", ["Sam", "Alex"], parent)).firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 3), "both parents are offered")
        for _ in 0..<4 where !other.isHittable { app.swipeUp() }
        other.tap()
        app.buttons["Save"].tap()
        // The count goes down by one; the row stays, with its new picture, until the list is left
        // (design 2C).
        let fewer = count - 1
        let newCount = app.staticTexts.matching(NSPredicate(format: "label == %@", "\(fewer) \(fewer == 1 ? "entry" : "entries")"))
        XCTAssertTrue(newCount.firstMatch.waitForExistence(timeout: 5), "the count follows")
        XCTAssertEqual(rows.count, count, "the changed row stays in the open list")
    }

    /// With no `range`, the page opens on whatever this phone last showed.
    private func launch(_ range: String?, dayOffset: Int? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES", "-sampleWeek", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle",
                               "-share.breastfeederAsked", "YES", "-openScreen", "whoDidWhat"]
            + (range.map { ["-share.range", $0] } ?? [])
            + (dayOffset.map { ["-share.dayOffset", String($0)] } ?? [])
        app.launch()
        return app
    }

    /// A tap on a bar (or its heading) opens everyone's entries for that line (the users' choice B,
    /// 21 Nov 2026): as many rows as the line's total, under an "Everyone" chip.
    func testABarOpensEveryonesList() {
        let app = launch("day", dayOffset: 1)
        let bar = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Nappies, '")).firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 8), "the Nappies bar is a button")
        // "Nappies, 3: Sam 2, Alex 1": the total is the number before the colon.
        let total = Int(bar.label.dropFirst("Nappies, ".count).prefix { $0.isNumber }) ?? -1
        XCTAssertGreaterThan(total, 0, "the sample day has nappies: \(bar.label)")
        for _ in 0..<4 where !bar.isHittable { app.swipeUp() }
        bar.tap()

        XCTAssertTrue(app.staticTexts["Everyone"].waitForExistence(timeout: 3), "the Everyone chip")
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Done by'"))
        XCTAssertEqual(rows.count, total, "every parent's entries, as many as the total")
        let list = XCTAttachment(screenshot: app.screenshot())
        list.name = "Everyone's list behind a bar"
        list.lifetime = .keepAlways
        add(list)
    }

    /// The way a parent gets there: Graphs, the tile, then a bar and a number. Each list must stay
    /// open (on the phone, 21 Nov 2026, it showed for a moment and went back to the page).
    func testFromTheGraphsTabEachListStaysOpen() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES", "-sampleWeek", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle",
                               "-share.breastfeederAsked", "YES", "-startTab", "graphs"]
        app.launch()
        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Who did what'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 8), "the tile on Graphs")
        tile.tap()

        // The bar: everyone's list, still there a few seconds later.
        let bar = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Feeds, '")).firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "the Feeds bar")
        for _ in 0..<4 where !bar.isHittable { app.swipeUp() }
        bar.tap()
        XCTAssertTrue(app.staticTexts["Everyone"].waitForExistence(timeout: 3), "everyone's list opens")
        sleep(3)
        XCTAssertTrue(app.staticTexts["Everyone"].exists, "everyone's list stays open")
        app.navigationBars.buttons.firstMatch.tap()

        // A parent's number: their list, still there a few seconds later.
        let number = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^[A-Za-z]+ [0-9]+$")).firstMatch
        XCTAssertTrue(number.waitForExistence(timeout: 5), "a parent's number")
        for _ in 0..<4 where !number.isHittable { app.swipeUp() }
        let parent = String(number.label.split(separator: " ").first ?? "")
        number.tap()
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Done by' OR label CONTAINS 'Got up'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 3), "\(parent)'s list opens")
        sleep(3)
        XCTAssertTrue(rows.firstMatch.exists, "\(parent)'s list stays open")
    }

    /// On 7 days, a tap on a night's dots opens that night in the Day view.
    func testANightOpensInTheDayView() {
        // A `-share.range` launch setting would pin the range, so the page couldn't switch: pick
        // 7 days with a tap instead.
        let app = launch(nil)
        let week = app.buttons["7 days"]
        XCTAssertTrue(week.waitForExistence(timeout: 8))
        week.tap()
        let night = app.buttons.matching(NSPredicate(format: "label CONTAINS ' night: '")).firstMatch
        XCTAssertTrue(night.waitForExistence(timeout: 8), "each night is a button")
        let weekday = String(night.label.prefix { $0 != " " })
        night.tap()
        XCTAssertTrue(app.buttons["Day before"].waitForExistence(timeout: 3), "the Day view, with its arrows")
        let shown = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label == 'Yesterday' OR label == 'Today'", weekday))
        XCTAssertTrue(shown.firstMatch.waitForExistence(timeout: 3), "the night tapped: \(weekday)")
    }
}
