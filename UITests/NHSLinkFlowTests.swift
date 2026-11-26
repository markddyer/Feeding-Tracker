import XCTest

/// The "About … ›" NHS links on the forms (AI insights step 4: D5 A, D6 A; design D3 B, D11 A, D13 A,
/// D18 A). Made-up data with every passage ticked (`-samplePassagesTicked YES`) and AI insights off.
final class NHSLinkFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle"] + extra
        app.launch()
        return app
    }

    /// The poo panel's link shows with AI insights off, lists the passages by heading, and opens one
    /// word for word with its credit.
    func testThePooPanelsLinkOpensTheNHSWords() {
        let app = launch(["-samplePassagesTicked", "YES", "-homeSheet", "pooDetails"])
        let link = app.buttons["nhsLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 8), "the link shows with AI insights off")
        XCTAssertEqual(link.label, "NHS information: About baby poo")
        link.tap()
        let row = app.buttons["nhsPassageRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the passages, by their headings")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Checked against the NHS page by'"))
            .firstMatch.exists, "the foot names who ticked them")
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["nhsPassagePage"].waitForExistence(timeout: 5), "one passage opens")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Information from the NHS website, as at'"))
            .firstMatch.exists, "with the NHS's credit")
    }

    /// No passage ticked: no link, and the panel is as before.
    func testNoTickNoLink() {
        let app = launch(["-homeSheet", "pooDetails"])
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["nhsLink"].exists)
    }

    /// An editor's link, before Note and Delete, named for its kind.
    func testTheSleepEditorsLink() {
        let app = launch(["-samplePassagesTicked", "YES", "-openScreen", "editLastSleep"])
        let link = app.buttons["nhsLink"]
        for _ in 0..<4 where !(link.exists && link.isHittable) { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 8))
        XCTAssertEqual(link.label, "NHS information: About baby sleep")
    }
}
