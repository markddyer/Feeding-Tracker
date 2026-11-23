#if FEEDING_DEV
import FeedingCore
import FeedingInsights
import FoundationModels
import SwiftUI

/// Little Log Dev only (AI insights task AI14; S10 of `docs/planning/12-ai-insights-gauntlet.md`):
/// proves the AI link from a real phone without the family's log and without either parent's yes.
/// App Attest's first run, then one morning card made from a made-up week (never the household's
/// data) through the app's own `InsightEngine.make`. Nothing is stored. Each step is written to the
/// sync log as "ai-check:" lines, so it can be read off the phone. Run it from Home's Tests menu, or
/// at launch with `-aiConnectionCheck YES`.
@MainActor
enum AIConnectionCheck {
    static func runIfAsked() {
        guard UserDefaults.standard.bool(forKey: "aiConnectionCheck") else { return }
        Task { _ = await run() }
    }

    static func run() async -> [String] {
        var lines: [String] = []
        func note(_ line: String) {
            lines.append(line)
            SyncLog.add("ai-check: \(line)")
        }
        guard let claude = ClaudeAnswerer.fromInfo(Bundle.main.infoDictionary) else {
            note("this build has no client ID")
            return lines
        }
        let answerer = ErrorKeeper(claude)
        var started = Date()
        do {
            try await claude.prepare()
            note("App Attest passed in \(seconds(since: started))")
        } catch {
            note("App Attest failed (\(InsightEngine.failure(error))): \(String(describing: error).prefix(300))")
            return lines
        }
        let week = madeUpWeek()
        guard case .make(let job, _) = InsightCards.plan(.morning, data: week.data, babyID: week.baby, me: week.me,
                                                         participants: [week.me, week.other], tries: LocalCardTries(),
                                                         now: week.now) else {
            note("the made-up week gave no card to make")
            return lines
        }
        started = Date()
        // A made-up week with its own made-up yeses, never the household's log: its own gate.
        let result = await InsightEngine.make(job, data: { week.data }, babyID: week.baby, answerer: answerer,
                                              now: { week.now },
                                              gate: { InsightCards.gate(week.data, me: week.me, participants: [week.me, week.other],
                                                                        now: week.now).make },
                                              onCall: {})
        switch result {
        case .closed(let closed):
            note("the made-up week's gate closed (\(closed))")
        case .made(let card):
            note("card made in \(seconds(since: started)): \(card.choices.facts.count) facts, "
                 + "\(card.choices.patterns.count) patterns, \(card.choices.passages.count) passages")
        case .failed(let failure):
            note("card failed (\(failure))" + (answerer.lastError.map { ": \($0.prefix(300))" } ?? ""))
        }
        return lines
    }

    private static func seconds(since date: Date) -> String {
        String(format: "%.1f s", Date().timeIntervalSince(date))
    }

    /// Eight made-up days of steady bottle feeds and night sleeps, and both made-up parents' yes.
    static func madeUpWeek() -> (data: HouseholdData, baby: String, me: MemberID, other: MemberID, now: Date) {
        let zone = TimeZone(identifier: "Europe/London")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let today = PlainDate(Date(), in: zone)
        func at(_ day: PlainDate, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour))!
        }
        let me: MemberID = "check-parent-a", other: MemberID = "check-parent-b", baby = "check-baby"
        var data = HouseholdData()
        for back in 1...8 {
            let day = today.adding(days: -back)
            for (index, hour) in stride(from: 1, to: 24, by: 3).enumerated() {
                let start = at(day, hour)
                data.add(id: "check-feed-\(back)-\(hour)", kind: .feed, babyID: baby, startedAt: start,
                         endedAt: start.addingTimeInterval(1200),
                         payload: EventPayload(feed: FeedDetails(bottles: [Bottle(milk: .formula, ml: 80 + back * 2)])),
                         by: index.isMultiple(of: 2) ? me : other, timeZoneID: zone.identifier, now: start)
            }
            let night = at(day, 22)
            data.add(id: "check-sleep-\(back)", kind: .sleep, babyID: baby, startedAt: night,
                     endedAt: night.addingTimeInterval(6 * 3600), payload: EventPayload(), by: me,
                     timeZoneID: zone.identifier, now: night)
        }
        let now = at(today, 10)
        data.setInsightYes(true, member: me, now: now.addingTimeInterval(-86400))
        data.setInsightYes(true, member: other, now: now.addingTimeInterval(-86400))
        return (data, baby, me, other, now)
    }
}

/// The app's answerer, keeping the last error's words for the log.
private final class ErrorKeeper: CardAnswerer, @unchecked Sendable {
    let inner: ClaudeAnswerer
    private(set) var lastError: String?

    init(_ inner: ClaudeAnswerer) { self.inner = inner }

    func answer(_ prompt: String, schema: GenerationSchema) async throws -> String {
        do {
            return try await inner.answer(prompt, schema: schema)
        } catch {
            lastError = String(describing: error)
            throw error
        }
    }
}

/// Home's Tests menu › AI connection test.
struct AIConnectionCheckView: View {
    @State private var lines: [String] = []
    @State private var running = false

    var body: some View {
        List {
            Section {
                Button(running ? "Running…" : "Run the test") {
                    running = true
                    Task {
                        lines = await AIConnectionCheck.run()
                        running = false
                    }
                }
                .disabled(running)
            } footer: {
                Text("Sends one made-up week to the AI through App Attest, never your log. Needs no yes. Costs about 2p.")
            }
            if !lines.isEmpty {
                Section("Result") {
                    ForEach(lines, id: \.self) { Text($0).font(.footnote) }
                }
            }
        }
        .navigationTitle("AI connection test")
    }
}
#endif
