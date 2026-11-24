import XCTest

/// "Discard this first?" (design review D37; task T19), on a made-up day (Feeding Dev, simulator
/// only): a swipe down on Add a first with nothing typed closes it; with something typed it asks
/// first, and Keep editing keeps the words. Run with the FeedingDevAudit scheme:
/// `-only-testing:FeedingDevUITests/DiscardFlowTests`.
@MainActor
final class DiscardFlowTests: XCTestCase {
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only.")
        #endif
        continueAfterFailure = false
    }

    private func openAddAFirst() -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES", "-sampleFirsts", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle",
                               "-startTab", "journal"]
        app.launch()
        let add = app.buttons["Add a first"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let title = app.textFields["First smile"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        return (app, title)
    }

    /// A swipe down from the form's top bar, as a parent closes a sheet.
    private func swipeDown(_ app: XCUIApplication) {
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        let start = cancel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 140, dy: 0))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 650)), withVelocity: .fast,
                    thenHoldForDuration: 0)
    }

    /// And Add a first opens again after: the swipe reached SwiftUI, which the bridge passes on.
    func testACleanSwipeCloses() {
        let (app, title) = openAddAFirst()
        swipeDown(app)
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "the empty form stayed open")
        XCTAssertFalse(app.buttons["Discard"].exists)
        app.buttons["Add a first"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Add a first didn't open again")
    }

    func testASwipeWithWordsAsksAndKeepEditingKeepsThem() {
        let (app, title) = openAddAFirst()
        title.tap()
        title.typeText("First giggle")
        swipeDown(app)
        XCTAssertTrue(app.buttons["Discard"].firstMatch.waitForExistence(timeout: 5), "no question before closing")
        // iOS 27 may show the question as a small card with Discard only: a tap outside backs out.
        let keep = app.buttons["Keep editing"].firstMatch
        if keep.exists {
            keep.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        }
        let typed = app.textFields.matching(NSPredicate(format: "value == 'First giggle'")).firstMatch
        XCTAssertTrue(typed.waitForExistence(timeout: 3), "the words went")
        // Asked again, Discard closes it.
        swipeDown(app)
        let discard = app.buttons["Discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        XCTAssertTrue(typed.waitForNonExistence(timeout: 5), "Discard left the form open")
        app.buttons["Add a first"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Add a first didn't open again")
        XCTAssertFalse(typed.exists, "the discarded words came back")
    }

    func testCancelWithWordsAsks() {
        let (app, title) = openAddAFirst()
        title.tap()
        title.typeText("First giggle")
        app.buttons["Cancel"].tap()
        let discard = app.buttons["Discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "Cancel closed with no question")
        discard.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
    }
}
