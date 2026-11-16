import XCTest

/// Taps through the bottle amount wheel (the user's choice of 16 Nov 2026, in place of the 30, 60,
/// 90 and 120 ml buttons) on a made-up day (Feeding Dev, simulator only). Run with the
/// FeedingDevAudit scheme: `-only-testing:FeedingDevUITests/AmountWheelFlowTests`.
@MainActor
final class AmountWheelFlowTests: XCTestCase {
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES"] + extra
        app.launch()
        return app
    }

    /// After a bottle feed: the wheel starts at the last formula amount (30 ml in the made-up
    /// day), turning it saves nothing, and Save saves the amount on the wheel.
    func testTheWheelSavesTheAmountShown() {
        let app = launch(["-setup.feedingStyle", "bottleOnly", "-sampleFeedInProgress", "finishedForMe"])
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        XCTAssertEqual(wheel.value as? String, "30 ml")
        XCTAssertTrue(app.buttons["Save 30 millilitres"].exists)
        wheel.adjust(toPickerWheelValue: "75 ml")
        let save = app.buttons["Save 75 millilitres"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        save.tap()
        // A bottle-only parent's panel closes by itself once the amount is in.
        XCTAssertTrue(wheel.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Start feed"].waitForExistence(timeout: 3))
    }

    /// The form: tap a bottle's row for the wheel; the row shows the new amount.
    func testTheFormOpensTheWheelFromTheRow() {
        let app = launch(["-setup.feedingStyle", "breastAndBottle", "-openScreen", "editLastFeed"])
        let row = app.buttons["Formula, 30 ml"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(app.pickerWheels.firstMatch.exists)
        row.tap()
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 3))
        wheel.adjust(toPickerWheelValue: "45 ml")
        XCTAssertTrue(app.buttons["Formula, 45 ml"].waitForExistence(timeout: 3))
    }
}
