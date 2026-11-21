import XCTest

/// The "who did what" page (`09-who-does-what.md`, X2, DD10, D1 A): a parent's number opens the
/// list behind it, with as many rows as the number says, and a row opens its editor (Feeding Dev,
/// simulator only). Run with the FeedingDevAudit scheme:
/// `-only-testing:FeedingDevUITests/WhoDidWhatFlowTests`.
@MainActor
final class WhoDidWhatFlowTests: XCTestCase {
    /// These tests load made-up data: never on a real phone, where the data is a family's own.
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only: this test replaces the app's data.")
        #endif
    }

    func testANumberOpensItsListAndARowOpensItsEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES", "-sampleWeek", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle",
                               "-share.breastfeederAsked", "YES", "-share.range", "day", "-share.dayOffset", "1",
                               "-openScreen", "whoDidWhat"]
        app.launch()

        // Yesterday's nappies: "Sam 2" or similar, under the Nappies bar.
        // The bar's heading is read as one line: "Nappies, 3: Sam 2, Alex 1".
        let nappies = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Nappies, '")).firstMatch
        XCTAssertTrue(nappies.waitForExistence(timeout: 8))
        let number = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^[A-Za-z]+ [0-9]+$"))
            .allElementsBoundByIndex.filter { $0.frame.minY > nappies.frame.minY }
            .min { $0.frame.minY < $1.frame.minY }
        guard let number else { return XCTFail("no parent's number under Nappies") }
        let count = Int(number.label.split(separator: " ").last ?? "") ?? -1
        XCTAssertGreaterThan(count, 0, "the sample day has nappies for this parent: \(number.label)")
        for _ in 0..<4 where !number.isHittable { app.swipeUp() }
        number.tap()

        // The list: its chips, its count, and one row per entry, each "Done by" that parent.
        XCTAssertTrue(app.staticTexts["Yesterday"].waitForExistence(timeout: 3), "the range chip")
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Done by'"))
        XCTAssertEqual(rows.count, count, "the list has as many rows as the number")
        let list = XCTAttachment(screenshot: app.screenshot())
        list.name = "The list behind a number"
        list.lifetime = .keepAlways
        add(list)

        rows.firstMatch.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 3), "a row opens its editor")
    }
}
