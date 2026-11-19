import XCTest

/// Videos on a first's page (design review D36), on made-up firsts (Feeding Dev, simulator only).
/// "First laugh" has a photo and a short clip. Run with the FeedingDevAudit scheme:
/// `-only-testing:FeedingDevUITests/VideoFlowTests`.
@MainActor
final class VideoFlowTests: XCTestCase {
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only: made-up firsts.")
        #endif
    }

    private func launch(look: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES", "-sampleFirsts", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle",
                               "-look.setting", look, "-openScreen", "firstPage", "-firstID", "sample-first-laugh"]
        app.launch()
        return app
    }

    /// Never plays by itself: a still with "Play the video" until tapped.
    func testAVideoPlaysOnlyWhenTapped() {
        let app = launch(look: "alwaysDay")
        let pager = app.descendants(matching: .any)["pager-sample-photo-laugh"]
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        pager.swipeLeft()
        XCTAssertTrue(app.descendants(matching: .any)["pager-sample-video-laugh"].waitForExistence(timeout: 3))
        let play = app.buttons["Play the video"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        XCTAssertTrue(play.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Sound on"].exists, "by day the Silent switch decides, no button")
    }

    /// At night it starts muted, with "Sound on".
    func testAtNightAVideoStartsMuted() {
        let app = launch(look: "alwaysNight")
        let pager = app.descendants(matching: .any)["pager-sample-photo-laugh"]
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        pager.swipeLeft()
        let play = app.buttons["Play the video"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        XCTAssertTrue(app.buttons["Sound on"].waitForExistence(timeout: 5))
    }
}
