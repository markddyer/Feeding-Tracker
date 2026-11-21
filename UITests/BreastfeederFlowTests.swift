import XCTest

/// "Who breastfeeds?" (`09-who-does-what.md`, DD11, 2A, DT7; DD12): asked on the "Who did what"
/// page the first time; "Not now" leaves a quiet line that asks again; an answer takes the line
/// away, and History's breastfeeds then count for that parent, with a small picture of who logged
/// them (Feeding Dev, simulator only). Run with the FeedingDevAudit scheme:
/// `-only-testing:FeedingDevUITests/BreastfeederFlowTests`.
@MainActor
final class BreastfeederFlowTests: XCTestCase {
    /// These tests load made-up data: never on a real phone, where the data is a family's own.
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only: this test replaces the app's data.")
        #endif
    }

    func testNotNowLeavesTheQuietLineAndAnAnswerChangesHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle",
                               "-share.breastfeederAsked", "NO", "-startTab", "history"]
        app.launch()

        // Before an answer, every row's big picture is who logged it: no "logged by" second picture.
        let secondPicture = app.buttons.matching(NSPredicate(format: "label CONTAINS ', logged by '"))
        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 8))
        XCTAssertEqual(secondPicture.count, 0)

        app.tabBars.buttons["Graphs"].tap()
        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Who did what'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        tile.tap()

        // Asked the first time; "Not now" leaves the quiet line.
        XCTAssertTrue(app.staticTexts["Who breastfeeds?"].waitForExistence(timeout: 5))
        app.buttons["Not now"].tap()
        let quiet = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Set who breastfeeds'")).firstMatch
        XCTAssertTrue(quiet.waitForExistence(timeout: 3), "the quiet line")

        // The quiet line asks again; an answer takes it away.
        quiet.tap()
        XCTAssertTrue(app.staticTexts["Who breastfeeds?"].waitForExistence(timeout: 3))
        app.buttons["Sam"].tap()
        XCTAssertTrue(quiet.waitForNonExistence(timeout: 3), "answered, so the line goes")

        // History: the other parent's breastfeeds now count for Sam, with who logged them small.
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(secondPicture.firstMatch.waitForExistence(timeout: 5),
                      "a breastfeed logged by the other parent shows Sam big and its logger small")
        XCTAssertTrue(secondPicture.firstMatch.label.contains("Done by"))
    }
}
