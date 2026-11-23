#if FEEDING_DEV
import FeedingCore
import FeedingInsights
import Foundation

/// `-sampleQuestions` (Little Log Dev only): made-up questions in Ask, for screenshots and tap
/// tests; no AI runs. `answer` (a log question with its answer), `help` (a danger sign),
/// `medicine` (a medicine question), `closed` (AI insights off), `failed` (couldn't reach the AI),
/// `people` (the third question on a topic), `parentHelp` (the AI's button on a parent's question), or
/// `all` for one of each.
enum SampleQuestions {
    static func make(_ state: String, now: Date) -> [KeptQuestion] {
        let zone = TimeZone(identifier: "Europe/London") ?? .current
        let yesterday = PlainDate(now, in: zone).adding(days: -1)
        let passage = NHSPassages.all.first { $0.page.localizedCaseInsensitiveContains("feed") }?.id
        let answer = QuestionAnswer(topic: .feeding, facts: [FactRef(.day(yesterday), .feeds)], today: [.feeds, .lastFeed],
                                    passages: passage.map { [PassageChoice($0, summary: nil)] } ?? [],
                                    sentences: ["Many babies feed more often in the evening."])
        func at(_ minutesAgo: Double) -> Date { now.addingTimeInterval(-minutesAgo * 60) }
        let asked = KeptQuestion(id: "sample-answer", askedAt: at(12), text: "How many feeds yesterday, and today so far?",
                                 kind: .asked, answer: answer, offered: passage.map { [$0] } ?? [])
        let help = KeptQuestion(id: "sample-help", askedAt: at(9), text: "She feels really hot and she's very sleepy",
                                kind: .helpNow)
        let medicine = KeptQuestion(id: "sample-medicine", askedAt: at(7), text: "When did she last have Vitamin D?",
                                    kind: .lastGiven)
        let closed = KeptQuestion(id: "sample-closed", askedAt: at(5), text: "How long did she sleep last night?", kind: .closed)
        let failed = KeptQuestion(id: "sample-failed", askedAt: at(3), text: "How many wet nappies today?", kind: .couldNotAsk)
        var people = asked
        people.id = "sample-people"
        people.askedAt = at(1)
        people.text = "Is it OK that she feeds every hour tonight?"
        people.peopleLine = true
        switch state {
        case "answer": return [asked]
        case "help": return [help]
        case "medicine": return [medicine]
        case "closed": return [closed]
        case "failed": return [failed]
        case "people": return [people]
        case "parentHelp":
            return [KeptQuestion(id: "sample-parent-help", askedAt: at(2), text: "I'm so tired I can't think straight",
                                 kind: .parentHelp)]
        case "all": return [asked, help, medicine, closed, failed, people]
        default: return []
        }
    }
}
#endif
