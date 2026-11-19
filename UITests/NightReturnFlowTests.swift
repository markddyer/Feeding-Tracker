import XCTest

/// Coming back to the app (design review D40, eng2 D3), on a made-up day (Feeding Dev, simulator
/// only). `-pretendReturn night` (or `day`) counts a return as at 03:00 (or 14:00) on the
/// household's clock after 10 minutes away. Run with the FeedingDevAudit scheme:
/// `-only-testing:FeedingDevUITests/NightReturnFlowTests`.
@MainActor
final class NightReturnFlowTests: XCTestCase {
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only.")
        #endif
    }

    private func launch(_ pretend: String, tab: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES", "-sampleFirsts", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle",
                               "-startTab", tab, "-pretendReturn", pretend]
        app.launch()
        return app
    }

    private func leaveAndComeBack(_ app: XCUIApplication) {
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        // The check gives a tap a moment to arrive first.
        sleep(2)
    }

    /// At night after a while away: Home, with Start feed in front.
    func testANightReturnOpensHome() {
        let app = launch("night", tab: "journal")
        XCTAssertTrue(app.buttons["Add a first"].waitForExistence(timeout: 5))
        leaveAndComeBack(app)
        XCTAssertTrue(app.buttons["Start feed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Add a first"].exists)
    }

    /// By day after the same time away: as it was.
    func testADayReturnStaysAsItWas() {
        let app = launch("day", tab: "journal")
        XCTAssertTrue(app.buttons["Add a first"].waitForExistence(timeout: 5))
        leaveAndComeBack(app)
        XCTAssertTrue(app.buttons["Add a first"].exists)
        XCTAssertFalse(app.buttons["Start feed"].exists)
    }

    /// Eng2 D3: a form open stays in front with what was typed, and the tab under it too.
    func testAnOpenFormStaysAsItWas() {
        let app = launch("night", tab: "journal")
        let add = app.buttons["Add a first"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let title = app.textFields["First smile"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("First giggle")
        leaveAndComeBack(app)
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == 'First giggle'")).firstMatch.exists)
        app.buttons["Cancel"].tap()
        let discard = app.buttons["Discard"].firstMatch
        if discard.waitForExistence(timeout: 3) { discard.tap() }
        XCTAssertTrue(app.buttons["Add a first"].waitForExistence(timeout: 5), "the Journal was still under the form")
    }

    /// OV2: Settings opened from Home is closed by a night return: Home's main screen.
    func testANightReturnClosesSettings() {
        let app = launch("night", tab: "home")
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let heading = app.staticTexts["Settings"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Start feed"].exists)
        leaveAndComeBack(app)
        XCTAssertTrue(app.buttons["Start feed"].waitForExistence(timeout: 5))
        XCTAssertFalse(heading.exists)
    }

    /// A form on Settings' stack (Medicines) is kept, with what was typed (Codex review of D40).
    func testANightReturnKeepsTheMedicinesForm() {
        let app = launch("night", tab: "home")
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let medicines = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Medicines'")).firstMatch
        XCTAssertTrue(app.staticTexts["Settings"].firstMatch.waitForExistence(timeout: 5))
        for _ in 0..<8 where !medicines.isHittable { app.swipeUp() }
        medicines.tap()
        let field = app.textFields["Add a medicine or vitamin"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Iron")
        leaveAndComeBack(app)
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == 'Iron'")).firstMatch.exists)
    }
}
