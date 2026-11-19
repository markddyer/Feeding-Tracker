import XCTest

/// Settings › Birth date opens its screen, and it stays open (the same fault as the photo picker's:
/// a screen hung on a form's section). Simulator only. Run with the FeedingDevAudit scheme:
/// `-only-testing:FeedingDevUITests/SettingsBirthDateFlowTests`.
@MainActor
final class SettingsBirthDateFlowTests: XCTestCase {
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only.")
        #endif
    }

    func testBirthDateOpensAndStays() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES", "-sampleFirsts", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle",
                               "-openScreen", "settings"]
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Birth date'")).firstMatch
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "the birth date screen opens")
        sleep(3)
        XCTAssertTrue(save.exists, "and stays open")
    }
}
