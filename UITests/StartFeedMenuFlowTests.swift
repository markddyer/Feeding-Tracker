import XCTest

/// Start feed asks when first: Now, Just finished or Earlier, and Pumping sits beside it (the
/// user's choice, 24 Nov 2026). A tap outside the list starts nothing (Feeding Dev, simulator
/// only). Run with the FeedingDevAudit scheme:
/// `-only-testing:FeedingDevUITests/StartFeedMenuFlowTests`.
@MainActor
final class StartFeedMenuFlowTests: XCTestCase {
    /// These tests load made-up data: never on a real phone, where the data is a family's own.
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only: this test replaces the app's data.")
        #endif
    }

    private func launch(style: String = "breastAndBottle", look: String = "alwaysDay") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", style,
                               "-look.setting", look]
        app.launch()
        return app
    }

    private func openStart(_ app: XCUIApplication) {
        let start = app.buttons["Start feed"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testNowStartsAFeed() {
        let app = launch()
        keep(app, "home")
        openStart(app)
        let now = app.buttons["Now"]
        XCTAssertTrue(now.waitForExistence(timeout: 3), "the list asks when")
        XCTAssertTrue(app.buttons["Just finished"].exists)
        XCTAssertTrue(app.buttons["Earlier"].exists)
        keep(app, "list")
        now.tap()
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 3), "a feed runs")
    }

    func testATapOutsideStartsNothing() {
        let app = launch()
        openStart(app)
        XCTAssertTrue(app.buttons["Now"].waitForExistence(timeout: 3))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(app.buttons["Now"].waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Finish"].exists, "no feed started")
        XCTAssertTrue(app.buttons["Start feed"].exists)
    }

    func testJustFinishedLogsAPastFeed() {
        let app = launch()
        openStart(app)
        let justFinished = app.buttons["Just finished"]
        XCTAssertTrue(justFinished.waitForExistence(timeout: 3))
        justFinished.tap()
        let twenty = app.buttons["Started about 20 min ago"]
        XCTAssertTrue(twenty.waitForExistence(timeout: 3))
        keep(app, "just finished")
        twenty.tap()
        // The details panel, and no feed left running.
        XCTAssertTrue(app.staticTexts["Add to this feed"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Feed logged"].exists, "the Undo bar")
        XCTAssertFalse(app.buttons["Finish"].exists)
    }

    func testEarlierOpensTheForm() {
        let app = launch()
        openStart(app)
        let earlier = app.buttons["Earlier"]
        XCTAssertTrue(earlier.waitForExistence(timeout: 3))
        earlier.tap()
        XCTAssertTrue(app.staticTexts["Earlier feed"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Start feed"].waitForExistence(timeout: 3))
    }

    func testPumpingOpensItsForm() {
        let app = launch()
        let pumping = app.buttons["Log pumping"]
        XCTAssertTrue(pumping.waitForExistence(timeout: 8))
        pumping.tap()
        XCTAssertTrue(app.staticTexts["Pumping"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
    }

    /// On a bottle-only phone the milks are the "Now" answers: still two taps to start a bottle.
    func testABottleOnlyPhoneStartsABottleInTwoTaps() {
        let app = launch(style: "bottleOnly", look: "alwaysNight")
        openStart(app)
        let formula = app.buttons["Formula"]
        XCTAssertTrue(formula.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Expressed milk"].exists)
        XCTAssertTrue(app.buttons["Just finished"].exists)
        XCTAssertTrue(app.buttons["Earlier"].exists)
        keep(app, "bottle-only list at night")
        formula.tap()
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 3), "a bottle feed runs")
    }
}
