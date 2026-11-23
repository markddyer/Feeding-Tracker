import XCTest

/// Ask (AI insights step 3, task AI20): the user flows with made-up data. No AI runs: the simulator
/// has no iCloud, so a question that would go to the AI meets "Couldn't reach the AI".
final class QuestionsFlowTests: XCTestCase {
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

    /// The third question on a topic within 2 hours starts with the line to people.
    func testTheThirdOnATopicBringsPeople() {
        let app = launch(["-sampleInsightCard", "YES", "-sampleQuestions", "people", "-openScreen", "ask"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH \"You've asked about this a few times\""))
            .firstMatch.waitForExistence(timeout: 8))
    }
}
