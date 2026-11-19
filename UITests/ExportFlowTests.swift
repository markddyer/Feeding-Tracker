import XCTest

/// "Export the journal" end to end on made-up firsts (design review D12; task T10). The sample
/// "First trip out" has a photo that isn't on this phone and can't be fetched (no iCloud in the
/// simulator): it is named, then "Save without this one" packs the rest. Run with the
/// FeedingDevAudit scheme: `-only-testing:FeedingDevUITests/ExportFlowTests`.
@MainActor
final class ExportFlowTests: XCTestCase {
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only: made-up firsts.")
        #endif
    }

    func testAMissingPhotoIsNamedThenTheRestIsSaved() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES", "-sampleFirsts", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle",
                               "-openScreen", "export"]
        app.launch()
        let export = app.buttons["Export"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        export.tap()
        XCTAssertTrue(app.staticTexts["A photo couldn't be fetched"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["· First trip out"].exists)
        app.buttons["Save without this one"].tap()
        XCTAssertTrue(app.buttons["Save the file"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["The file is ready"].exists)
    }
}
