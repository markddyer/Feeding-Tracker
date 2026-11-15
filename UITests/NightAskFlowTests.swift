import XCTest

/// Taps through "Ask the other parent to take a night" on a made-up day (Feeding Dev, simulator
/// only), to check the buttons are wired up. The rules themselves are tested in FeedingCore
/// (`NightAskTests`). Run with the FeedingDevAudit scheme:
/// `-only-testing:FeedingDevUITests/NightAskFlowTests`.
@MainActor
final class NightAskFlowTests: XCTestCase {
    private func launch(_ sample: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES", "-sampleNightAsk", sample,
                               "-homeAtBottom", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle"]
        app.launch()
        return app
    }

    private func text(_ app: XCUIApplication, _ value: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", value)).firstMatch
    }

    func testAskingShowsTheWaitingLineAndUndoTakesItBack() {
        let app = launch("meOnDuty")
        let ask = app.buttons["Ask Sam to take it"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5))
        ask.tap()
        let waiting = text(app, "You asked Sam to take tonight. You stay on until Sam says yes.")
        XCTAssertTrue(waiting.waitForExistence(timeout: 3))
        app.buttons["Undo"].tap()
        XCTAssertTrue(ask.waitForExistence(timeout: 3))
        XCTAssertFalse(waiting.exists)
    }

    /// No rota yet: nobody is on and both phones alert, so the tile offers both buttons.
    func testWithNoRotaYouCanAsk() {
        let app = launch("noRota")
        let ask = app.buttons["Ask Sam to take tonight"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["I'll take tonight"].exists)
        ask.tap()
        let waiting = text(app, "You asked Sam to take tonight. Both phones alert until Sam says yes.")
        XCTAssertTrue(waiting.waitForExistence(timeout: 3))
        XCTAssertFalse(ask.exists)
        app.buttons["Undo"].tap()
        XCTAssertTrue(ask.waitForExistence(timeout: 3))
    }

    /// No rota, and Sam took tonight: "Both phones tonight" gives it back, as before the ask.
    func testBothPhonesTonightGivesTheNightBack() {
        let app = launch("takenByOther")
        XCTAssertTrue(text(app, "Sam's on tonight").waitForExistence(timeout: 5))
        app.buttons["Both phones tonight"].tap()
        XCTAssertTrue(text(app, "No night rota yet: both phones alert at night.").waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["I'll take tonight"].exists)
        XCTAssertTrue(app.buttons["Ask Sam to take tonight"].exists)
        XCTAssertFalse(app.buttons["Both phones tonight"].exists)
    }

    func testNotTonightClosesTheCard() {
        let app = launch("fromOther")
        let card = text(app, "Sam asks you to take tonight")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        // Large enough to hit at night (the first phone test found the small pills hard to hit).
        XCTAssertGreaterThanOrEqual(app.buttons["Not tonight"].frame.height, 50)
        XCTAssertGreaterThanOrEqual(app.buttons["Not tonight"].frame.width, 120)
        app.buttons["Not tonight"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 3))
        // "I'll take it" stays in the Nights tile.
        XCTAssertTrue(text(app, "Sam's on tonight").exists)
    }

    func testIllTakeItMovesTheNight() {
        let app = launch("fromOther")
        let card = text(app, "Sam asks you to take tonight")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.buttons.matching(identifier: "I'll take it").firstMatch.tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 3))
        XCTAssertTrue(text(app, "You're on tonight").waitForExistence(timeout: 3))
    }
}
