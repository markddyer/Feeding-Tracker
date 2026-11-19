import XCTest

/// Drags a photo in its square in Edit (design review D39), on made-up firsts (Feeding Dev,
/// simulator only). Run with the FeedingDevAudit scheme:
/// `-only-testing:FeedingDevUITests/CropFlowTests`.
@MainActor
final class CropFlowTests: XCTestCase {
    /// These tests change the app's data: never on a real phone, where it is a family's own.
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only: this test deletes and changes entries.")
        #endif
    }

    private func launch(fresh: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", fresh ? "YES" : "NO", "-sampleFirsts", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle",
                               "-openScreen", "editFirst", "-firstID", "sample-first-smile"]
        app.launch()
        return app
    }

    /// "First smile" has a tall photo. Dragging it down shows its top; Save keeps that, so the
    /// editor opens on it again after the app is closed.
    func testADragMovesThePhotoAndSaveKeepsIt() {
        let app = launch(fresh: true)
        let square = app.descendants(matching: .any)["Photo in its square"]
        XCTAssertTrue(square.waitForExistence(timeout: 5))
        XCTAssertEqual(square.value as? String, "The middle")
        let from = square.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        from.press(forDuration: 0.1, thenDragTo: square.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        XCTAssertEqual(square.value as? String, "The top")
        // Sideways does nothing on a tall photo.
        from.press(forDuration: 0.1, thenDragTo: square.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.3)))
        XCTAssertEqual(square.value as? String, "The top")
        app.buttons["Save"].tap()
        app.terminate()

        let again = launch(fresh: false)
        let reopened = again.descendants(matching: .any)["Photo in its square"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 5))
        XCTAssertEqual(reopened.value as? String, "The top")
    }
}
