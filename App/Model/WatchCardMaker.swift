import FeedingCore
import FeedingInsights
import Foundation

/// Writes the watch's "Last night" card (AI insights step 4: D4 A, F4, F6, F11; design D8 A, D9 A,
/// D16 B) from what Home shows (`CardShown`): the watch never decides anything about the card and
/// never calls a model. Nothing with no yes, the AI off, or no card yet (`.nothing`, `.making`).
@MainActor
enum WatchCardMaker {
    static func card(now: Date = Date(), model: AppModel = .shared, shown: CardShown? = nil) -> WatchCard? {
        guard let babyID = model.baby?.name else { return nil }
        let shown = shown ?? CardShown.now(.morning, at: now, model: model)
        let mode: WatchCard.Mode
        let period: CardPeriod
        var why: String?
        var checked: CheckedCard?
        switch shown {
        case .nothing, .making:
            return nil
        case .card(let card, let cardPeriod):
            mode = .card
            period = cardPeriod
            checked = card
        case .factsOnly(_, let cardPeriod, let reason):
            mode = .factsOnly
            period = cardPeriod
            why = watchWhy(reason)
        }
        let data = model.store.data
        let settings = data.householdSettings
        guard let evening = period.nights?.last,
              let night = InsightFacts.nightWindow(evening, dayHours: settings.dayHours, timeZone: settings.timeZone)
        else { return nil }
        // F11: the card is current until the next night ends, when the next morning card is due.
        let ends = InsightFacts.nightWindow(evening.adding(days: 1), dayHours: settings.dayHours, timeZone: settings.timeZone)?.end
            ?? night.end.addingTimeInterval(24 * 3600)
        let facts = nightFacts(data.insightFacts(babyID: babyID, now: now).nights.first { $0.evening == evening },
                               nappies: data.visibleSnapshots(babyID: babyID).filter {
                                   $0.event.kind == .nappy && $0.event.startedAt >= night.start && $0.event.startedAt < night.end
                               }.count)
        var sections: [WatchCard.Section] = []
        if let checked {
            for (title, nights) in [("Last night", true), ("Yesterday", false)] {
                let lines = zip(checked.lines, checked.factRefs).filter { $0.1.scope.isNight == nights }.map(\.0)
                let patterns = zip(checked.patterns, checked.patternChoices).filter { $0.1.nights == nights }.map(\.0)
                if !lines.isEmpty || !patterns.isEmpty {
                    sections.append(WatchCard.Section(title: title, lines: lines, patterns: patterns))
                }
            }
        }
        return WatchCard(mode: mode, why: why, facts: facts, sections: sections,
                         medicines: mode == .card ? MedicineChips.given(in: period, model: model).map(\.text) : [],
                         madeAt: mode == .card ? data.insightCard(.morning)?.madeAt : nil, ends: ends)
    }

    /// The three night facts (design D8 A); none when nothing was logged in the night.
    static func nightFacts(_ night: NightFacts?, nappies: Int) -> [WatchCard.Fact] {
        let feeds = night?.feeds ?? 0
        let sleep = night?.longestSleep.map { $0.to.timeIntervalSince($0.from) }
        guard feeds > 0 || nappies > 0 || (sleep ?? 0) > 0 else { return [] }
        let sleepFact: WatchCard.Fact
        if let sleep, sleep > 0 {
            sleepFact = WatchCard.Fact(kind: .sleep, number: HomeText.elapsed(sleep), words: "longest sleep logged",
                                       spoken: "Longest sleep logged, \(HomeText.spokenElapsed(sleep))")
        } else {
            sleepFact = WatchCard.Fact(kind: .sleep, number: nil, words: "No sleep logged", spoken: "No sleep logged")
        }
        return [
            sleepFact,
            WatchCard.Fact(kind: .feeds, number: "\(feeds)", words: feeds == 1 ? "feed logged" : "feeds logged",
                           spoken: "\(feeds) \(feeds == 1 ? "feed" : "feeds") logged"),
            WatchCard.Fact(kind: .nappies, number: "\(nappies)", words: nappies == 1 ? "nappy logged" : "nappies logged",
                           spoken: "\(nappies) \(nappies == 1 ? "nappy" : "nappies") logged"),
        ]
    }

    /// The watch's one line for facts only (design D9 A), from the phone's reason.
    static func watchWhy(_ reason: String) -> String {
        if reason == CardText.pausedWhy { return "Paused. iPhone says why." }
        if reason == CardText.noCardWhy { return "No card today." }
        return "Couldn't reach the AI. iPhone says why."
    }
}
