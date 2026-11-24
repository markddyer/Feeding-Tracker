import XCTest

/// AI insights step 2, task AI12 (`docs/planning/12-ai-insights-gauntlet.md`): the real taps, from
/// Home and the Graphs tab, on what AI9 and AI11 built. Settings › AI insights takes this parent's
/// yes and the off switch; "What the AI sees" shows the request with no names and no medicines;
/// "Last night" opens the card with the night's entries; the afternoon line opens the card alone;
/// "This was wrong" asks first and, at the second report, pauses AI insights until a parent turns
/// them back on; a card with no AI shows "Facts only today"; and a line on "This week" opens its
/// graph's page, which stays open (the 21 Nov pitfall, one navigation style).
///
/// Made-up data only (`-sampleInsightCard YES` makes a card from fixed choices, passed by the same
/// checker). No AI runs: the simulator has no iCloud, so the gate before a call stays shut.
/// Simulator only. Run with the FeedingDevAudit scheme:
/// `-only-testing:FeedingDevUITests/InsightCardFlowTests`.
@MainActor
final class InsightCardFlowTests: XCTestCase {
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only: this test replaces the app's data.")
        #endif
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

    /// From Home's gear to Settings › AI insights.
    private func openAISettings(_ app: XCUIApplication) -> XCUIElement {
        let gear = app.buttons["Settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 8))
        gear.tap()
        let row = app.buttons["aiInsightsRow"]
        scrollTo(row, in: app)
        return row
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 where !(element.exists && element.isHittable) { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 3), "\(element)")
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The other parent said yes; this parent says yes (behind a question), then turns it off.
    func testYesThenOffInSettings() {
        let app = launch(["-sampleInsightYes", "other"])
        let row = openAISettings(app)
        XCTAssertTrue(row.label.contains("Waiting for you"), row.label)
        row.tap()

        let status = app.staticTexts["insightStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.hasPrefix("Sam said yes."), status.label)

        // Yes asks first, with what is sent.
        app.buttons["insightYes"].tap()
        let ask = app.alerts["Use AI insights?"]
        XCTAssertTrue(ask.waitForExistence(timeout: 3))
        XCTAssertTrue(ask.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Never names, notes or medicines'")).firstMatch.exists)
        ask.buttons["Yes"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "identifier == 'insightStatus' AND label BEGINSWITH 'On.'"))
            .firstMatch.waitForExistence(timeout: 3), status.label)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'You' AND label CONTAINS 'Yes ·'")).firstMatch.exists,
                      "this parent's yes, with its date")
        keep(app, "AI insights on")

        // Off asks first too, and needs no other parent.
        app.buttons["insightOff"].tap()
        let off = app.alerts["Turn off AI insights?"]
        XCTAssertTrue(off.waitForExistence(timeout: 3))
        off.buttons["Turn off"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "identifier == 'insightStatus' AND label BEGINSWITH 'Off. You turned'"))
            .firstMatch.waitForExistence(timeout: 3), status.label)
        XCTAssertEqual(app.buttons["insightYes"].label, "Turn AI insights back on")

        // Settings' row says so.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertTrue(row.label.hasSuffix("Off"), row.label)
    }

    /// "What the AI sees": the request as it would be sent, for each card, with no names, no
    /// medicines and no record names in it.
    func testWhatTheAISeesHasNoNamesOrMedicines() {
        let app = launch(["-sampleInsightYes", "both", "-sampleWeek", "30"])
        openAISettings(app).tap()
        let link = app.buttons["whatTheAISees"]
        scrollTo(link, in: app)
        link.tap()

        let request = any(app, "insightRequest")
        XCTAssertTrue(request.waitForExistence(timeout: 5))
        let morning = request.label
        app.buttons["This week"].tap()
        let week = any(app, "insightRequest")
        XCTAssertTrue(week.waitForExistence(timeout: 3))
        XCTAssertNotEqual(week.label, morning, "the switch shows the other card's request")
        keep(app, "What the AI sees, this week")

        for (card, text) in [("morning", morning), ("week", week.label)] {
            XCTAssertTrue(text.contains("{") && text.contains("}"), "\(card): the log's numbers in JSON")
            for word in ["Alex", "Sam", "Vitamin", "sample-baby"] {
                XCTAssertNil(text.range(of: "\\b\(word)\\b", options: .regularExpression),
                             "\(card): \(word) is never sent")
            }
        }
    }

    /// Home's "Last night" with the AI mark opens the card, then the night's entries, then Get help
    /// now, which opens and stays open.
    func testLastNightOpensTheCardAndItsEntries() {
        let app = launch(["-sampleInsightCard", "YES", "-homeLastNight", "YES"])
        let line = app.buttons["lastNightLine"]
        XCTAssertTrue(line.waitForExistence(timeout: 8))
        XCTAssertTrue(line.label.hasSuffix("with a card picked by AI"), line.label)
        line.tap()

        XCTAssertTrue(any(app, "aiCard").waitForExistence(timeout: 5), "the AI's card")
        XCTAssertTrue(app.staticTexts["Last night and yesterday"].exists, "the card's title")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == 'Picked by AI'")).firstMatch.exists, "the AI mark")
        keep(app, "Morning card")

        let help = app.buttons["cardGetHelp"]
        scrollTo(help, in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Picked by AI from your log.'")).firstMatch.exists,
                      "the foot")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Summary · AI, '")).firstMatch.exists,
                      "the NHS passage's summary is marked AI")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Information from the NHS website, as at'"))
            .firstMatch.exists, "the NHS credit")
        // "Sunday night · slept 7h 10m", over the night's entries.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[A-Z][a-z]+day night( · slept .*)?$"))
            .firstMatch.exists, "the night's entries under the card")
        keep(app, "Morning card, its end")
        help.tap()
        XCTAssertTrue(app.buttons["Call 9 9 9"].waitForExistence(timeout: 5))
        sleep(2)
        XCTAssertTrue(app.buttons["Call 9 9 9"].exists, "Get help now stays open")
    }

    /// From 12:00 the slim line opens the same card, with no night's entries.
    func testTheAfternoonLineOpensTheCard() {
        let app = launch(["-sampleInsightCard", "YES", "-homeCardLine", "YES"])
        let line = app.buttons["aiCardLine"]
        XCTAssertTrue(line.waitForExistence(timeout: 8))
        XCTAssertEqual(line.label, "Last night and yesterday, picked by AI")
        XCTAssertFalse(app.buttons["lastNightLine"].exists, "one line, not two")
        line.tap()
        XCTAssertTrue(any(app, "aiCard").waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(line.waitForExistence(timeout: 3), "Close goes back to Home")
    }

    /// "This was wrong" asks first. The second report in 30 days pauses AI insights: the card turns
    /// to the facts only, with why; Settings says Paused, and Turn back on brings the card back.
    func testTheSecondWrongReportPausesUntilTurnedBackOn() {
        let app = launch(["-sampleInsightCard", "YES", "-sampleWrong", "1", "-homeLastNight", "YES"])
        let line = app.buttons["lastNightLine"]
        XCTAssertTrue(line.waitForExistence(timeout: 8))
        line.tap()
        XCTAssertTrue(any(app, "aiCard").waitForExistence(timeout: 5))

        let wrong = app.buttons["cardWrong"]
        scrollTo(wrong, in: app)
        wrong.tap()
        let report = app.buttons["Report"]
        XCTAssertTrue(report.waitForExistence(timeout: 3), "it asks first")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Two reports in 30 days'")).firstMatch.exists)
        report.tap()

        XCTAssertTrue(any(app, "factsOnlyCard").waitForExistence(timeout: 5), "paused: the facts only")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'AI insights are paused'")).firstMatch.exists)
        XCTAssertFalse(any(app, "aiCard").exists)
        keep(app, "Paused, facts only")
        app.buttons["Close"].tap()
        XCTAssertTrue(line.waitForExistence(timeout: 3))
        // At once, not at Home's next 20-second tick: the screen's tick is older than the report.
        let unmarked = NSPredicate(format: "NOT (label CONTAINS 'picked by AI')")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: unmarked, evaluatedWith: line)], timeout: 2), .completed,
                       "Home's line loses the AI mark: \(line.label)")

        let row = openAISettings(app)
        XCTAssertTrue(row.label.hasSuffix("Paused"), row.label)
        row.tap()
        let resume = app.buttons["insightResume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["insightStatus"].label.hasPrefix("Paused. 2 cards"), app.staticTexts["insightStatus"].label)
        resume.tap()
        let ask = app.alerts["Turn AI insights back on?"]
        XCTAssertTrue(ask.waitForExistence(timeout: 3))
        ask.buttons["Turn back on"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "identifier == 'insightStatus' AND label BEGINSWITH 'On.'"))
            .firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(resume.exists)
        let count = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'In the last 30 days'")).firstMatch
        scrollTo(count, in: app)
        XCTAssertTrue(count.label.hasSuffix("0"), "the count starts again: \(count.label)")
    }

    /// With both yeses and no way to reach the AI (the simulator has no iCloud), "Last night" has
    /// no AI mark and opens "Facts only today", with why.
    func testNoAIMeansFactsOnly() {
        let app = launch(["-sampleInsightYes", "both", "-homeLastNight", "YES"])
        let line = app.buttons["lastNightLine"]
        XCTAssertTrue(line.waitForExistence(timeout: 8))
        // The look fails at once here, so "Making…" goes.
        let deadline = Date().addingTimeInterval(8)
        while line.label.contains("picked by AI") && Date() < deadline { usleep(250_000) }
        XCTAssertFalse(line.label.contains("picked by AI"), line.label)
        line.tap()
        XCTAssertTrue(any(app, "factsOnlyCard").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Facts only today"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Couldn’t reach the AI'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label == 'Picked by AI'")).firstMatch.exists,
                       "nothing on it is the AI's")
        keep(app, "Facts only today")
    }

    /// Graphs' "This week" opens its card; a line on it closes the card and opens its graph's page
    /// on the line's own day, and the page stays open (the 21 Nov pitfall). The line's day can be
    /// older than the 7 days shown (on a Sunday, the week's last night is 7 days back): the range
    /// widens to reach it. On other days it is inside the 7 days, and the range stays.
    func testThisWeekLineOpensItsGraphPage() {
        // No `-graphs.range` here: a launch argument would hide the range the app sets.
        let app = launch(["-sampleInsightCard", "YES", "-sampleWeek", "30", "-startTab", "graphs"])
        let line = app.buttons["aiCardLine"]
        XCTAssertTrue(line.waitForExistence(timeout: 8))
        XCTAssertTrue(line.label.hasPrefix("This week · Mon "), line.label)
        XCTAssertTrue(line.label.hasSuffix(", picked by AI"), line.label)
        app.buttons["7 days"].tap()
        line.tap()

        XCTAssertTrue(any(app, "aiCard").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Monday '")).firstMatch.exists, "the week, in full")
        keep(app, "This week")
        let first = app.buttons.matching(identifier: "cardGraphLine").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 3), "the card's lines open their graphs")
        // "4 feeds logged on the night of 15 November.", "… on Sunday night." within the last
        // week, or "… last night." when the week ended yesterday (a Monday): its day.
        let label = first.label
        XCTAssertTrue(label.contains("feed"), label)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let today = calendar.startOfDay(for: Date())
        let day: Date?
        if label.hasSuffix("last night.") {
            // Before 07:00 the night still running is today's yesterday's, so last night started
            // the day before that (the household's night, 21:00 to 07:00).
            let hour = calendar.component(.hour, from: Date())
            day = calendar.date(byAdding: .day, value: hour < 7 ? -2 : -1, to: today)
        } else if let name = label.range(of: #"[A-Z][a-z]+day(?= night\.$)"#, options: .regularExpression).map({ String(label[$0]) }) {
            // "… on Sunday night.": a night in the last week, named by its evening's weekday.
            let names = DateFormatter()
            names.locale = Locale(identifier: "en_GB")
            names.timeZone = calendar.timeZone
            names.dateFormat = "EEEE"
            day = (1...7).lazy.compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
                .first { names.string(from: $0) == name }
        } else if let text = label.range(of: #"\d{1,2} [A-Z][a-z]+(?=\.$)"#, options: .regularExpression).map({ String(label[$0]) }) {
            let reader = DateFormatter()
            reader.locale = Locale(identifier: "en_GB")
            reader.calendar = calendar
            reader.timeZone = calendar.timeZone
            reader.dateFormat = "d MMMM yyyy"
            let year = calendar.component(.year, from: today)
            let thisYear = reader.date(from: "\(text) \(year)")
            day = thisYear.flatMap { $0 > today ? reader.date(from: "\(text) \(year - 1)") : $0 }
        } else {
            day = nil
        }
        guard let day else { return XCTFail("no day in the line: \(label)") }
        first.tap()

        let page = app.navigationBars["Feeds each day"]
        XCTAssertTrue(page.waitForExistence(timeout: 5), "the line opens its graph's page")
        XCTAssertFalse(any(app, "aiCard").exists, "the card closed first")
        sleep(2)
        XCTAssertTrue(page.exists, "the page stays open")
        keep(app, "This week's line, its graph")
        // The page names it "Sunday 15 Nov".
        let writer = DateFormatter()
        writer.locale = Locale(identifier: "en_GB")
        writer.timeZone = calendar.timeZone
        writer.dateFormat = "EEEE d MMM"
        let short = calendar.isDate(day, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today)!)
            ? "Yesterday" : writer.string(from: day)
        XCTAssertTrue(app.staticTexts[short].exists, "the page is on the line's day, \(short): "
                      + app.staticTexts.allElementsBoundByIndex.prefix(4).map(\.label).joined(separator: " | "))
        // 7 days shows today and the 6 before; a day older than that widens the range (`GraphRange.fitting`).
        let back = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        let range = back < 7 ? "7 days" : "4 weeks"
        XCTAssertTrue(app.buttons[range].isSelected, "the range reaches that day, \(back) days back: \(range)")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(line.waitForExistence(timeout: 3), "back to the Graphs tab")
    }
}
