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

    func testNotTonightClosesTheCard() {
        let app = launch("fromOther")
        let card = text(app, "Sam asks you to take tonight")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
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
