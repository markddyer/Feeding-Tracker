import XCTest

/// Apple's accessibility audit (contrast, clipped text, Dynamic Type, tap sizes, VoiceOver labels)
/// on every screen of the redesign, in both looks and at a large text size
/// (`05-visual-redesign.md`, "Checks"). Each launch starts from a fresh made-up day (Feeding Dev,
/// simulator only).
///
/// A report, not a gate: the audit reads pixels, so text scrolled under the pinned buttons or the
/// top bar "fails" contrast, and switched-off controls are counted too. Every note is printed as an
/// AUDIT line and kept as an attachment, with a screenshot of each screen, for a person to read.
/// Colour contrast itself is checked exactly by `DesignTokensTests`.
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    /// Issues found in this test, as readable lines.
    private var issues: [String] = []

    /// Launches Feeding Dev on a fresh sample day.
    private func launch(_ extra: [String], look: String = "automatic", largeText: Bool = false,
                        setUpDone: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-sampleData", "YES", "-sampleDataFresh", "YES", "-look.setting", look]
        if setUpDone {
            arguments += ["-setup.disclaimerSeen", "YES", "-setup.inviteOffered", "YES",
                          "-setup.permissionsAsked", "YES", "-setup.feedingStyle", "breastAndBottle"]
        }
        if largeText {
            arguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launchArguments = arguments + extra
        continueAfterFailure = true
        app.launch()
        return app
    }

    /// Runs the audit on what is on screen now, noting each issue with the screen's name.
    private func audit(_ app: XCUIApplication, _ screen: String) {
        sleep(1)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = screen
        shot.lifetime = .keepAlways
        add(shot)
        do {
            try app.performAccessibilityAudit { issue in
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)'" } ?? "screen"
                self.issues.append("[\(screen)] \(issue.auditType): \(issue.compactDescription) — \(element)")
                return true
            }
        } catch {
            issues.append("[\(screen)] audit could not run: \(error)")
        }
    }

    private func report() {
        for line in issues { print("AUDIT \(line)") }
        let notes = XCTAttachment(string: issues.joined(separator: "\n"))
        notes.name = "\(name): \(issues.count) audit notes"
        notes.lifetime = .keepAlways
        add(notes)
    }

    func testHome() {
        for look in ["automatic", "alwaysNight"] {
            audit(launch([], look: look), "home \(look)")
            audit(launch(["-homeAtBottom", "YES"], look: look), "home lower \(look)")
            audit(launch(["-sampleFeedInProgress", "YES"], look: look), "feed running \(look)")
            audit(launch(["-sampleFeedInProgress", "other"], look: look), "other's feed \(look)")
            audit(launch(["-sampleFeedInProgress", "finishedForMe"], look: look), "details panel \(look)")
        }
        report()
    }

    func testOtherScreens() {
        for look in ["automatic", "alwaysNight"] {
            audit(launch(["-openScreen", "history", "-sampleFeedInProgress", "YES"], look: look), "history \(look)")
            audit(launch(["-openScreen", "settings"], look: look), "settings \(look)")
            audit(launch(["-openScreen", "editLastFeed"], look: look), "edit feed \(look)")
            audit(launch(["-openScreen", "pumping"], look: look), "pumping \(look)")
            for step in ["disclaimer", "about", "howYouFeed", "permissions"] {
                audit(launch(["-setupStep", step], look: look, setUpDone: false), "setup \(step) \(look)")
            }
        }
        report()
    }

    /// The Graphs tab, with a made-up week, in the tab bar as a parent sees it.
    func testGraphs() {
        let week = ["-sampleWeek", "YES", "-startTab", "graphs", "-graphs.range", "week"]
        for look in ["automatic", "alwaysNight"] {
            audit(launch(week, look: look), "graphs \(look)")
            audit(launch(week + ["-graphsAtBottom", "YES"], look: look), "graphs lower \(look)")
        }
        audit(launch(week, largeText: true), "graphs large text")
        audit(launch(week + ["-graphsAtBottom", "YES"], largeText: true), "graphs lower large text")
        report()
    }

    /// Each graph's own page (`10-graph-pages.md`), on yesterday, in both looks and at large text.
    func testGraphPages() {
        func page(_ kind: String) -> [String] {
            ["-sampleWeek", "YES", "-graphs.range", "week", "-openScreen", "graphPage", "-graphPage", kind, "-graphPageDay", "1"]
        }
        for look in ["automatic", "alwaysNight"] {
            for kind in ["feeds", "gaps", "rhythm", "weight"] {
                audit(launch(page(kind), look: look), "graph page \(kind) \(look)")
            }
        }
        audit(launch(page("feeds"), largeText: true), "graph page feeds large text")
        audit(launch(page("rhythm"), largeText: true), "graph page rhythm large text")
        report()
    }

    /// The Journal, with made-up firsts: the line, a first's page, the editor (empty, and with a
    /// photo in its square), the Firsts list and History with firsts in it.
    func testJournal() {
        let firsts = ["-sampleFirsts", "YES"]
        for look in ["automatic", "alwaysNight"] {
            audit(launch(firsts + ["-startTab", "journal"], look: look), "journal \(look)")
            audit(launch(firsts + ["-openScreen", "firstPage"], look: look), "first's page \(look)")
            audit(launch(firsts + ["-openScreen", "addFirst"], look: look), "add a first \(look)")
            audit(launch(firsts + ["-openScreen", "editFirst"], look: look), "edit a first \(look)")
            audit(launch(firsts + ["-openScreen", "firstsList"], look: look), "firsts list \(look)")
            audit(launch(firsts + ["-openScreen", "history"], look: look), "history with firsts \(look)")
        }
        audit(launch(firsts + ["-startTab", "journal"], largeText: true), "journal large text")
        audit(launch(firsts + ["-openScreen", "firstPage"], largeText: true), "first's page large text")
        audit(launch(firsts + ["-openScreen", "addFirst"], largeText: true), "add a first large text")
        audit(launch(firsts + ["-openScreen", "editFirst"], largeText: true), "edit a first large text")
        report()
    }

    /// "Who does what" (`09-who-does-what.md`, DT9): the page at each range, its question, Home's
    /// morning line and Undo card, the sleep's editor, and History with copies.
    func testWhoDoesWhat() {
        let page = ["-sampleWeek", "YES", "-openScreen", "whoDidWhat", "-share.breastfeederAsked", "YES"]
        for look in ["automatic", "alwaysNight"] {
            audit(launch(page + ["-share.range", "week"], look: look), "who did what 7 days \(look)")
            audit(launch(page + ["-share.range", "day", "-share.dayOffset", "1"], look: look), "who did what day \(look)")
            audit(launch(page + ["-share.range", "fourWeeks"], look: look), "who did what 4 weeks \(look)")
            audit(launch(["-sampleWeek", "YES", "-openScreen", "whoDidWhat", "-share.breastfeederAsked", "NO"], look: look),
                  "who breastfeeds \(look)")
            audit(launch(["-homeLastNight", "YES", "-sampleWeek", "YES"], look: look), "home last night \(look)")
            audit(launch(["-homeUndo", "nappy"], look: look), "undo card \(look)")
            audit(launch(["-openScreen", "editLastSleep"], look: look), "edit sleep \(look)")
            audit(launch(["-openScreen", "history", "-sampleDuplicate", "YES"], look: look), "history copies \(look)")
        }
        audit(launch(page + ["-share.range", "week"], largeText: true), "who did what 7 days large text")
        audit(launch(page + ["-share.range", "day", "-share.dayOffset", "1"], largeText: true), "who did what day large text")
        audit(launch(["-homeLastNight", "YES", "-sampleWeek", "YES"], largeText: true), "home last night large text")
        audit(launch(["-openScreen", "editLastSleep"], largeText: true), "edit sleep large text")
        report()
    }

    /// AI insights step 1 (`12-ai-insights-gauntlet.md`, AI5): Get help now, the NHS passages list,
    /// and one passage with its ticks.
    func testGetHelp() {
        for look in ["automatic", "alwaysNight"] {
            audit(launch(["-openScreen", "getHelp"], look: look), "get help now \(look)")
            audit(launch(["-openScreen", "nhsPassages"], look: look), "nhs passages \(look)")
            audit(launch(["-openScreen", "nhsPassage", "-passageID", "enough-milk-signs"], look: look), "nhs passage \(look)")
        }
        audit(launch(["-openScreen", "getHelp"], largeText: true), "get help now large text")
        audit(launch(["-openScreen", "nhsPassage", "-passageID", "enough-milk-signs"], largeText: true), "nhs passage large text")
        report()
    }

    /// AI insights step 2 (`12-ai-insights-gauntlet.md`, AI12): Settings › AI insights (waiting, on
    /// with a failure, paused), "What the AI sees", Home's lines, the morning card top and bottom,
    /// "Facts only today", Graphs' "This week" line and its card. Made-up cards; no AI runs.
    func testInsights() {
        let card = ["-sampleInsightCard", "YES"]
        let week = card + ["-sampleWeek", "30"]
        for look in ["automatic", "alwaysNight"] {
            audit(launch(["-openScreen", "aiInsights", "-sampleInsightYes", "other"], look: look), "ai settings waiting \(look)")
            audit(launch(["-openScreen", "aiInsights", "-sampleInsightYes", "both", "-sampleInsightFailure", "noSignal"], look: look),
                  "ai settings failure \(look)")
            audit(launch(card + ["-openScreen", "aiInsights", "-sampleWrong", "2"], look: look), "ai settings paused \(look)")
            audit(launch(week + ["-openScreen", "aiSees"], look: look), "what the ai sees \(look)")
            audit(launch(card + ["-homeLastNight", "YES"], look: look), "home card line \(look)")
            audit(launch(card + ["-homeCardLine", "YES"], look: look), "home afternoon line \(look)")
            audit(launch(card + ["-homeLastNight", "YES", "-homeSheet", "insightCard"], look: look), "morning card \(look)")
            audit(launch(card + ["-homeLastNight", "YES", "-homeSheet", "insightCard", "-cardAtBottom", "YES"], look: look),
                  "morning card end \(look)")
            let plain = launch(["-sampleInsightYes", "both", "-homeLastNight", "YES", "-homeSheet", "insightCard"], look: look)
            _ = plain.descendants(matching: .any)["factsOnlyCard"].firstMatch.waitForExistence(timeout: 8)
            audit(plain, "facts only \(look)")
            audit(launch(week + ["-startTab", "graphs"], look: look), "graphs week line \(look)")
            audit(launch(week + ["-startTab", "graphs", "-graphsSheet", "week"], look: look), "week card \(look)")
        }
        audit(launch(["-openScreen", "aiInsights", "-sampleInsightYes", "other"], largeText: true), "ai settings large text")
        audit(launch(card + ["-homeLastNight", "YES", "-homeSheet", "insightCard"], largeText: true), "morning card large text")
        audit(launch(card + ["-homeLastNight", "YES", "-homeSheet", "insightCard", "-cardAtBottom", "YES"], largeText: true),
              "morning card end large text")
        audit(launch(week + ["-startTab", "graphs", "-graphsSheet", "week"], largeText: true), "week card large text")
        report()
    }

    /// Ask (AI insights step 3): before asking, every kind of answer, a danger sign.
    func testAsk() {
        let card = ["-sampleInsightCard", "YES", "-openScreen", "ask"]
        for look in ["automatic", "alwaysNight"] {
            audit(launch(card + ["-sampleQuestions", "none"], look: look), "ask before asking \(look)")
            audit(launch(card + ["-sampleQuestions", "all"], look: look), "ask all answers \(look)")
            audit(launch(card + ["-sampleQuestions", "answer"], look: look), "ask an answer \(look)")
            audit(launch(card + ["-sampleQuestions", "failed"], look: look), "ask failed \(look)")
        }
        audit(launch(card + ["-sampleQuestions", "none"], largeText: true), "ask before asking large text")
        audit(launch(card + ["-sampleQuestions", "medicine"], largeText: true), "ask medicine large text")
        report()
    }

    func testLargeText() {
        audit(launch([], largeText: true), "home large text")
        audit(launch(["-homeAtBottom", "YES"], largeText: true), "home lower large text")
        audit(launch(["-sampleFeedInProgress", "YES"], largeText: true), "feed running large text")
        audit(launch(["-sampleFeedInProgress", "finishedForMe"], largeText: true), "details panel large text")
        audit(launch(["-openScreen", "history"], largeText: true), "history large text")
        audit(launch(["-openScreen", "settings"], largeText: true), "settings large text")
        audit(launch(["-openScreen", "editLastFeed"], largeText: true), "edit feed large text")
        report()
    }

    /// Nothing white at night: a menu, the Stop question, and the keyboard (DESIGN.md, "Day and
    /// night"). Screenshots are kept in the test results to look at.
    func testNightPopUps() {
        let settings = launch(["-openScreen", "settings"], look: "alwaysNight")
        settings.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Look'")).firstMatch.tap()
        keep(settings, "night menu")
        let running = launch(["-sampleFeedInProgress", "YES"], look: "alwaysNight")
        running.buttons["Stop and discard this feed"].tap()
        keep(running, "night stop question")
        let edit = launch(["-openScreen", "editLastFeed"], look: "alwaysNight")
        // The Note box is under "Who did it", off the screen until the form scrolls.
        let note = edit.textFields.firstMatch
        if !note.waitForExistence(timeout: 3) { edit.swipeUp() }
        note.tap()
        keep(edit, "night keyboard")
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        sleep(1)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
