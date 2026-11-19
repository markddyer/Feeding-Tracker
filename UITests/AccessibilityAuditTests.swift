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
        edit.textFields.firstMatch.tap()
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
