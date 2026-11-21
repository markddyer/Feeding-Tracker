import XCTest

/// The Undo card ("who does what", design DD5 and DD7; task DT2): after a quick log on Home the
/// card shows at the top with who did it; one tap swaps it to the other parent; × closes it at
/// once; a poo's details panel carries the same swap (Feeding Dev, simulator only). Run with the FeedingDevAudit scheme:
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

    /// A poo opens its details panel over the card, so the panel carries the same swap (Codex 8).
    func testThePooPanelCarriesTheSwap() {
        let app = launch()
        let poo = app.buttons["Log poo"]
        XCTAssertTrue(poo.waitForExistence(timeout: 5))
        poo.tap()

        XCTAssertTrue(app.buttons["Undo: remove this nappy"].waitForExistence(timeout: 3), "the details panel opened")
        // The card's swap is behind the panel; the panel's own is the one a finger can reach.
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
