import XCTest

/// Eng D6 (task T11): deleting from History as a parent does it, on a made-up day with firsts
/// (Feeding Dev, simulator only). A feed goes at once with no question, as before the journal; a
/// first asks "Delete this first?" and then offers Undo. Run with the FeedingDevAudit scheme:
/// `-only-testing:FeedingDevUITests/HistoryDeleteFlowTests`.
@MainActor
final class HistoryDeleteFlowTests: XCTestCase {
    /// These tests change the app's data: never on a real phone, where it is a family's own.
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only: this test deletes and changes entries.")
        #endif
    }

    private func launch(filter: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES", "-sampleFirsts", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle",
                               "-openScreen", "history", "-history.filter", filter]
        app.launch()
        return app
    }

    func testAFeedIsDeletedAtOnceWithNoQuestion() {
        let app = launch(filter: "feeds")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Logged by'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let label = row.label
        row.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        XCTAssertFalse(app.sheets.firstMatch.waitForExistence(timeout: 1.5), "a feed's delete asks nothing")
        XCTAssertTrue(app.buttons[label].waitForNonExistence(timeout: 3))
    }

    func testAFirstAsksFirstThenOffersUndo() {
        let app = launch(filter: "firsts")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS ': first, First laugh'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let label = row.label
        row.swipeLeft()
        let swipeDelete = app.buttons["Delete"]
        XCTAssertTrue(swipeDelete.waitForExistence(timeout: 3))
        swipeDelete.tap()
        // The question. iOS 27 shows it as a small card with Delete only: a tap outside backs out
        // ("Keep it" is the cancel role, which iOS leaves off the card).
        let question = app.sheets["Delete this first?"]
        XCTAssertTrue(question.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons[label].exists, "nothing is deleted before the answer")
        question.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons[label].waitForNonExistence(timeout: 3))
        // Undo brings it back.
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 3))
    }
}
