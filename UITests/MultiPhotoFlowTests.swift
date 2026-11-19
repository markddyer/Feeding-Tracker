import XCTest

/// Up to 4 photos per first (step 2, D9, D13, D35), on made-up firsts (Feeding Dev, simulator
/// only). "First smile" has two photos. Run with the FeedingDevAudit scheme:
/// `-only-testing:FeedingDevUITests/MultiPhotoFlowTests`.
@MainActor
final class MultiPhotoFlowTests: XCTestCase {
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only: this test changes a first.")
        #endif
    }

    private func launch(_ screen: String, fresh: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", fresh ? "YES" : "NO", "-sampleFirsts", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle",
                               "-openScreen", screen, "-firstID", "sample-first-smile"]
        app.launch()
        return app
    }

    /// The second photo is made the cover, Save keeps it, and the editor opens on it again.
    func testASecondPhotoMadeTheCoverIsKept() {
        let app = launch("editFirst", fresh: true)
        let second = app.buttons["slot-sample-photo-smile-2"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertEqual(second.label, "Photo 2 of 2")
        second.tap()
        app.buttons["Make it the cover"].tap()
        XCTAssertEqual(second.label, "Photo 1 of 2, the cover")
        app.buttons["Save"].tap()
        app.terminate()

        let again = launch("editFirst", fresh: false)
        let reopened = again.buttons["slot-sample-photo-smile-2"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 5))
        XCTAssertEqual(reopened.label, "Photo 1 of 2, the cover")
    }

    /// The page: the first photo, then a swipe shows the second (checked by which photo is shown).
    func testThePageSwipesBetweenPhotos() {
        let app = launch("firstPage", fresh: true)
        let first = app.descendants(matching: .any)["pager-sample-photo-smile"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(first.label, "Photo 1 of 2")
        first.swipeLeft()
        let second = app.descendants(matching: .any)["pager-sample-photo-smile-2"]
        XCTAssertTrue(second.waitForExistence(timeout: 3))
        XCTAssertEqual(second.label, "Photo 2 of 2")
    }
}
