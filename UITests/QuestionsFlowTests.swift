import XCTest

/// Ask (AI insights step 3, task AI20): the user flows with made-up data. No AI runs: the simulator
/// has no iCloud, so a question that would go to the AI meets "Couldn't reach the AI".
final class QuestionsFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        // `-speechSilent`: the voice reads at no volume, so the Mac doesn't speak during a run.
        app.launchArguments = ["-sampleData", "YES", "-sampleDataFresh", "YES", "-speechSilent", "YES",
                               "-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                               "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle"] + extra
        app.launch()
        return app
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

    private func openAsk(_ app: XCUIApplication) {
        let button = app.buttons["askButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 8), "Ask is in Home's top bar")
        button.tap()
        XCTAssertTrue(app.textFields["questionField"].waitForExistence(timeout: 5)
                      || app.textViews["questionField"].waitForExistence(timeout: 1))
    }

    private func type(_ text: String, in app: XCUIApplication) {
        let field = app.textFields["questionField"].exists ? app.textFields["questionField"] : app.textViews["questionField"]
        field.tap()
        field.typeText(text)
        app.buttons["sendQuestion"].tap()
    }

    /// Before asking: what Ask is, suggestions, and "Worried right now?" with both call buttons.
    /// Closing goes back to Home; a question is still there when Ask opens again.
    func testBeforeAskingThenAQuestionIsKept() {
        let app = launch(["-sampleInsightCard", "YES", "-sampleQuestions", "none"])
        openAsk(app)
        XCTAssertTrue(any(app, "askWorried").exists)
        XCTAssertTrue(app.buttons["Call 9 9 9"].exists)
        XCTAssertTrue(app.buttons["Call NHS 1 1 1"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "askSuggestion").count, 4)
        keep(app, "Before asking")
        type("Can I give Calpol?", in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Little Log doesn' AND label CONTAINS 'medicines'"))
            .firstMatch.waitForExistence(timeout: 5), "a medicine question gets the fixed reply")
        XCTAssertFalse(any(app, "askWorried").exists, "the intro goes once there is a question")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["askButton"].waitForExistence(timeout: 3))
        app.buttons["askButton"].tap()
        XCTAssertTrue(any(app, "questionBubble").waitForExistence(timeout: 5), "kept on this phone")
    }

    /// A danger sign: the Get help now card in place of an answer, with no AI and no signal needed.
    func testADangerSignBringsGetHelpNow() {
        let app = launch(["-sampleInsightCard", "YES", "-sampleQuestions", "none"])
        openAsk(app)
        type("she feels really hot and floppy", in: app)
        // An answer with one part takes the bubble's name, so the card is found by its words.
        XCTAssertTrue(app.staticTexts["Get help now"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Call 9 9 9"].exists)
        XCTAssertFalse(app.staticTexts["Couldn't reach the AI. Your question wasn't answered."].exists, "no AI was asked")
        keep(app, "Danger sign")
    }

    /// "When did she last have Vitamin D?" is answered from the log, with no AI (D6, X4).
    func testTheLastVitaminDComesFromTheLog() {
        let app = launch(["-sampleInsightCard", "YES", "-sampleQuestions", "none"])
        openAsk(app)
        type("When did she last have Vitamin D?", in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Vitamin D: last logged at'"))
            .firstMatch.waitForExistence(timeout: 5))
        // A look ahead gets the fixed reply, never a time.
        type("When can I give Vitamin D again?", in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Little Log doesn'"))
            .firstMatch.waitForExistence(timeout: 5))
    }

    /// With no yes yet, a log question gets the fixed reply and a way to Settings › AI insights.
    func testWithNoYesTheAIIsNotAsked() {
        let app = launch(["-sampleQuestions", "none"])
        openAsk(app)
        type("How many feeds last night?", in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'AI insights are off'"))
            .firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Settings › AI insights"].exists)
    }

    /// No iCloud in the simulator: "Couldn't reach the AI", Call 111, and Send again, which tries
    /// once more as a new question (never by itself).
    func testCouldNotReachTheAIOffersSendAgain() {
        let app = launch(["-sampleInsightCard", "YES", "-sampleQuestions", "none"])
        openAsk(app)
        type("How many feeds last night?", in: app)
        let again = app.buttons["askSendAgain"]
        XCTAssertTrue(again.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Call NHS 1 1 1"].exists)
        again.tap()
        XCTAssertTrue(app.buttons["askSendAgain"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "askSendAgain").count, 1, "the failed one was replaced, not added to")
    }

    /// A kept answer: the log's facts, the AI's sentence marked as AI, the footer, and "This was
    /// wrong", which asks first.
    func testAnAnswerKeepsItsPartsApart() {
        let app = launch(["-sampleInsightCard", "YES", "-sampleQuestions", "answer", "-openScreen", "ask"])
        XCTAssertTrue(any(app, "fromYourLog").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'logged yesterday.'")).firstMatch.exists)
        XCTAssertTrue(any(app, "aiSentences").exists)
        XCTAssertTrue(any(app, "aiSentences").label.hasPrefix("Written by AI:"))
        let wrong = app.buttons["cardWrong"]
        for _ in 0..<6 where !(wrong.exists && wrong.isHittable) { app.swipeUp() }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'AI · not medical advice'")).firstMatch.exists)
        wrong.tap()
        XCTAssertTrue(app.buttons["Report"].waitForExistence(timeout: 3), "it asks first")
        keep(app, "An answer")
    }

    /// The AI's button on a question about how a parent feels shows the NHS's urgent help for
    /// mental health, with both call buttons, not the baby's list (step 3 D13 A).
    func testTheHelpButtonOnAParentsQuestionShowsTheirHelp() {
        let app = launch(["-sampleInsightCard", "YES", "-sampleQuestions", "parentHelp", "-openScreen", "ask"])
        XCTAssertTrue(app.staticTexts["Get help now"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'mental health'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'babies under 3 months'")).firstMatch.exists,
                       "not the baby's list")
        XCTAssertTrue(app.buttons["Call 9 9 9"].exists)
    }

    /// The third question on a topic within 2 hours starts with the line to people.
    func testTheThirdOnATopicBringsPeople() {
        let app = launch(["-sampleInsightCard", "YES", "-sampleQuestions", "people", "-openScreen", "ask"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH \"You've asked about this a few times\""))
            .firstMatch.waitForExistence(timeout: 8))
    }

    // MARK: AI insights step 4: Siri (`-siriQuestion` hands the words in as the Siri action does)

    /// D3 A, design D10 A, D12 A: Ask opens by itself, the question says "Asked with Siri", the reply
    /// is read aloud with Stop, and after Stop, "Read again". The reply here is the log's own (a
    /// medicine's last time), so no AI runs.
    func testASiriQuestionIsAskedAndRead() {
        let app = launch(["-sampleQuestions", "none", "-siriQuestion", "When was the last Vitamin D?"])
        XCTAssertTrue(app.staticTexts["Asked with Siri"].waitForExistence(timeout: 10), "Ask opened with the Siri question")
        // A reply with one part takes the bubble's name, so look for its words.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Vitamin D: last logged'"))
            .firstMatch.waitForExistence(timeout: 8), "the reply shows")
        let stop = app.buttons["stopReading"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5), "read aloud, with Stop")
        stop.tap()
        XCTAssertTrue(app.buttons["readAgain"].waitForExistence(timeout: 3), "Read again after a stop")
        keep(app, "siri question read")
    }

    /// D9 A, design D14 B, Y1: a danger sign said to Siri shows Get help now at once, over a
    /// half-filled form, which is there again when the sheet closes.
    func testASiriDangerSignCoversAnOpenForm() {
        let app = launch(["-sampleQuestions", "none", "-homeSheet", "pooDetails",
                          "-siriQuestion", "She is floppy and her lips look blue"])
        XCTAssertTrue(app.buttons["Call 9 9 9"].waitForExistence(timeout: 10), "Get help now at once, over the form")
        XCTAssertTrue(app.buttons["Call NHS 1 1 1"].exists)
        keep(app, "siri danger sign over a form")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Yellow'")).firstMatch.waitForExistence(timeout: 5),
                      "the poo panel is there again")
    }
}
