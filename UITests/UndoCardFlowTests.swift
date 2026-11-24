import XCTest

/// The Undo card ("who does what", design DD5 and DD7; task DT2): after a quick log on Home the
/// card shows at the top with who did it; one tap swaps it to the other parent; × closes it at
/// once; a poo's details panel carries the same swap, and the poo's card comes only once the
/// panel closes (Feeding Dev, simulator only). Run with the FeedingDevAudit scheme:
/// `-only-testing:FeedingDevUITests/UndoCardFlowTests`.
@MainActor
final class UndoCardFlowTests: XCTestCase {
    /// These tests change the app's data: never on a real phone, where it is a family's own.
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only: this test logs entries.")
        #endif
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle"]
        app.launch()
        return app
    }

    func testAWeeShowsTheCardTheSwapChangesWhoDidItAndCloseShutsIt() {
        let app = launch()
        let wee = app.buttons["Log wee"]
        XCTAssertTrue(wee.waitForExistence(timeout: 5))
        wee.tap()

        XCTAssertTrue(app.staticTexts["Wee logged"].waitForExistence(timeout: 3))
        let swap = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Done by'")).firstMatch
        XCTAssertTrue(swap.waitForExistence(timeout: 3))
        let before = swap.label
        XCTAssertTrue(before.contains("Double-tap to change to"), "two parents, so the swap is offered: \(before)")
        swap.tap()
        let changed = NSPredicate(format: "label BEGINSWITH 'Done by' AND label != %@", before)
        XCTAssertTrue(app.buttons.matching(changed).firstMatch.waitForExistence(timeout: 3), "the swap gave it to the other parent")

        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Wee logged"].waitForNonExistence(timeout: 2), "× closes the card at once")
    }

    /// A poo's Undo card waits for its details panel to close, so its 10 seconds start once the
    /// nappy is fully logged, and it says the details (the user's ask, 24 Nov 2026).
    func testAPoosCardComesOnceItsDetailsAreIn() {
        let app = launch()
        let poo = app.buttons["Log poo"]
        XCTAssertTrue(poo.waitForExistence(timeout: 5))
        poo.tap()
        XCTAssertTrue(app.buttons["Undo: remove this nappy"].waitForExistence(timeout: 3), "the details panel opened")
        let card = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Poo logged'")).firstMatch
        XCTAssertFalse(card.exists, "no card counting down behind the panel")

        // Longer than the card's 10 seconds: the card must still come, with its full time.
        sleep(11)
        app.buttons["Brown"].tap()
        app.buttons["Loose"].tap()
        XCTAssertTrue(app.buttons["Undo: remove this nappy"].waitForNonExistence(timeout: 3), "the panel closes by itself")
        XCTAssertTrue(card.waitForExistence(timeout: 3), "the card comes now")
        XCTAssertEqual(card.label, "Poo logged · brown, loose")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Done by'")).firstMatch.exists)
    }

    /// Undo in the panel removes the nappy, and no card follows.
    func testUndoInThePanelLeavesNoCard() {
        let app = launch()
        let both = app.buttons["Log wee and poo"]
        XCTAssertTrue(both.waitForExistence(timeout: 5))
        both.tap()
        let undo = app.buttons["Undo: remove this nappy"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertTrue(undo.waitForNonExistence(timeout: 3))
        sleep(1)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Wee and poo logged'")).firstMatch.exists)
    }

    /// The panel carries the same swap as the card (Codex 8).
    func testThePooPanelCarriesTheSwap() {
        let app = launch()
        let poo = app.buttons["Log poo"]
        XCTAssertTrue(poo.waitForExistence(timeout: 5))
        poo.tap()

        XCTAssertTrue(app.buttons["Undo: remove this nappy"].waitForExistence(timeout: 3), "the details panel opened")
        let swaps = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Done by'"))
        XCTAssertTrue(swaps.firstMatch.waitForExistence(timeout: 3))
        guard let swap = swaps.allElementsBoundByIndex.first(where: \.isHittable) else {
            return XCTFail("no swap in the panel")
        }
        let before = swap.label
        swap.tap()
        let changed = NSPredicate(format: "label BEGINSWITH 'Done by' AND label != %@", before)
        XCTAssertTrue(app.buttons.matching(changed).firstMatch.waitForExistence(timeout: 3), "the swap works in the panel")
    }
}
