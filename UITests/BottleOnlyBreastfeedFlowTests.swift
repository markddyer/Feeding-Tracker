import XCTest

/// "Breastfeed (Sam)" on a bottle-only phone (`09-who-does-what.md`, DD15, 4B, DT5): once "Who
/// breastfeeds?" names the other parent, Start feed offers their breastfeed beside the two bottles,
/// and the feed it starts shows Left and Right (Codex 7). With no answer, only the bottles (Feeding
/// Dev, simulator only). Run with the FeedingDevAudit scheme:
/// `-only-testing:FeedingDevUITests/BottleOnlyBreastfeedFlowTests`.
@MainActor
final class BottleOnlyBreastfeedFlowTests: XCTestCase {
    /// These tests load made-up data: never on a real phone, where the data is a family's own.
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only: this test replaces the app's data.")
        #endif
    }

    private func launch(breastfeeder: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "bottleOnly"]
            + (breastfeeder.map { ["-sampleBreastfeeder", $0] } ?? [])
        app.launch()
        return app
    }

    private var breastfeedChoice: NSPredicate { NSPredicate(format: "label BEGINSWITH 'Breastfeed ('") }

    func testWithNoAnswerOnlyTheBottlesShow() {
        let app = launch(breastfeeder: nil)
        let start = app.buttons["Start feed"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        XCTAssertTrue(app.buttons["Formula"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons.matching(breastfeedChoice).firstMatch.exists, "nothing changes with no answer")
    }

    func testTheOtherParentsBreastfeedStartsWithLeftAndRight() {
        let app = launch(breastfeeder: "other")
        let start = app.buttons["Start feed"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        let breastfeed = app.buttons.matching(breastfeedChoice).firstMatch
        XCTAssertTrue(breastfeed.waitForExistence(timeout: 3), "the third choice")
        XCTAssertTrue(app.buttons["Formula"].exists)
        breastfeed.tap()
        // A side button may add "suggested" to its name.
        let left = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Left'")).firstMatch
        let right = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Right'")).firstMatch
        XCTAssertTrue(left.waitForExistence(timeout: 3), "a breastfeed shows Left and Right")
        XCTAssertTrue(right.exists)
        XCTAssertTrue(app.buttons["Finish"].exists)
    }
}
