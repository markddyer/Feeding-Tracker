import XCTest

/// Choosing photos and videos in Add and Edit (a parent's report, 19 Nov 2026: the picker opened
/// and closed at once, and the "+" square did nothing). Simulator only. Run with the
/// FeedingDevAudit scheme: `-only-testing:FeedingDevUITests/PhotoPickerFlowTests`.
@MainActor
final class PhotoPickerFlowTests: XCTestCase {
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only.")
        #endif
    }

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES", "-sampleFirsts", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle",
                               "-openScreen", screen, "-firstID", "sample-first-smile"]
        app.launch()
        return app
    }

    /// The picker is open, and still open 3 seconds later.
    private func assertPickerStays(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let picker = app.navigationBars["Photos"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "the picker opens", file: file, line: line)
        sleep(3)
        XCTAssertTrue(picker.exists, "the picker stays open", file: file, line: line)
    }

    func testTheWordsOpenThePicker() {
        let app = launch("addFirst")
        let words = app.buttons["Choose from Photos"]
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        words.tap()
        assertPickerStays(app)
    }

    /// An empty first: the "+" square takes the tap too.
    func testTheSquareOpensThePicker() {
        let app = launch("addFirst")
        let square = app.buttons["Add a photo or video"]
        XCTAssertTrue(square.waitForExistence(timeout: 5))
        square.tap()
        let choose = app.buttons["Choose from Photos"].firstMatch
        XCTAssertTrue(choose.waitForExistence(timeout: 3))
        app.buttons.matching(identifier: "Choose from Photos").allElementsBoundByIndex.last?.tap()
        assertPickerStays(app)
    }

    /// A first with photos already: the "+" slot after them.
    func testThePlusSlotOpensThePickerWithPhotosThere() {
        let app = launch("editFirst")
        let slot = app.buttons["Add a photo or video"]
        XCTAssertTrue(slot.waitForExistence(timeout: 5))
        slot.tap()
        let choose = app.buttons["Choose from Photos"]
        XCTAssertTrue(choose.waitForExistence(timeout: 3))
        choose.tap()
        assertPickerStays(app)
    }
}
