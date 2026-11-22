import XCTest

/// AI insights step 1, task AI5 (`docs/planning/12-ai-insights-gauntlet.md`, R4): from Home's gear,
/// Settings › "Worried? Get help now" opens the NHS's urgent list with its credit, its link, and
/// Call 999 and Call 111; Settings › NHS information takes Parent A's ticks, which the Settings row
/// counts. The real path from Home, not a screen opened alone. Simulator only. Run with the
/// FeedingDevAudit scheme: `-only-testing:FeedingDevUITests/GetHelpFlowTests`.
@MainActor
final class GetHelpFlowTests: XCTestCase {
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only: this test replaces the app's data.")
        #endif
    }

    private func launchAtSettings() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle"]
        app.launch()
        let gear = app.buttons["Settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 8))
        gear.tap()
        return app
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 where !(element.exists && element.isHittable) { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 3))
    }

    func testGetHelpNowOpensFromSettings() {
        let app = launchAtSettings()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Worried? Get help now'")).firstMatch
        scrollTo(row, in: app)
        row.tap()

        XCTAssertTrue(app.buttons["Call 9 9 9"].waitForExistence(timeout: 5), "Call 999")
        XCTAssertTrue(app.buttons["Call NHS 1 1 1"].exists, "Call 111")
        XCTAssertTrue(app.staticTexts["Immediate action required: Call 999 or go to A&E if:"].exists,
                      "the NHS's own words")
        let credit = app.staticTexts["Information from the NHS website, as at 22/11/26"]
        scrollTo(credit, in: app)
        XCTAssertTrue(app.links["Open the NHS page"].exists || app.buttons["Open the NHS page"].exists, "the page's link")

        // It stays open: the screen isn't dropped a moment later.
        sleep(2)
        XCTAssertTrue(app.buttons["Call 9 9 9"].exists)
    }

    func testATickIsCountedInSettings() {
        let app = launchAtSettings()
        let nhs = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'NHS information'")).firstMatch
        scrollTo(nhs, in: app)
        XCTAssertTrue(nhs.label.contains("38 to check"), nhs.label)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "settings-about"
        shot.lifetime = .keepAlways
        add(shot)
        nhs.tap()

        let passage = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Signs your baby is getting enough milk'")).firstMatch
        XCTAssertTrue(passage.waitForExistence(timeout: 5))
        XCTAssertTrue(passage.label.contains("To check"), passage.label)
        passage.tap()

        for label in ["Checked against the NHS page", "Summary checked against the passage"] {
            let tick = app.switches[label].firstMatch
            scrollTo(tick, in: app)
            XCTAssertEqual(tick.value as? String, "0")
            tick.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            XCTAssertEqual(tick.value as? String, "1", label)
        }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Checked '")).firstMatch.exists,
                      "the day it was checked")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(passage.waitForExistence(timeout: 5))
        XCTAssertTrue(passage.label.contains("Checked"), passage.label)
        XCTAssertFalse(passage.label.contains("To check"), passage.label)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(nhs.waitForExistence(timeout: 5))
        XCTAssertTrue(nhs.label.contains("36 to check"), nhs.label)
    }
}
