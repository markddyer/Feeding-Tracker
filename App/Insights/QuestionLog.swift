import FeedingInsights
import Foundation
import Observation

/// Ask's questions and answers on this phone (AI insights step 3, D4 and D5 A): never synced, kept
/// 24 hours, locked whenever the phone is locked (complete file protection), left out of the
/// phone's backups, and emptied when this parent turns AI insights off (Q12). `InsightQuestions`
/// alone decides what has expired; this file only keeps what it is given.
@MainActor
@Observable
final class QuestionLog {
    static let shared = QuestionLog()

    private(set) var questions: [KeptQuestion] = []
    @ObservationIgnored private let url: URL?

    init(url: URL? = QuestionLog.defaultURL, now: Date = Date()) {
        self.url = url
        questions = InsightQuestions.kept(Self.read(url), now: now)
        #if FEEDING_DEV
        if UserDefaults.standard.object(forKey: "sampleQuestions") != nil, url == Self.defaultURL {
            questions = SampleQuestions.make(UserDefaults.standard.string(forKey: "sampleQuestions") ?? "", now: now)
        }
        #endif
    }

    /// Application Support, which the app alone can read; not the App Group the widgets share.
    nonisolated static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("questions.json")
    }

    /// The questions to show at `now`, oldest first: an answer past its 24 hours goes even while
    /// Ask is open (X8).
    func shown(now: Date) -> [KeptQuestion] {
        InsightQuestions.kept(questions, now: now).sorted { $0.askedAt < $1.askedAt }
    }

    func add(_ question: KeptQuestion, now: Date = Date()) {
        questions = InsightQuestions.kept(questions + [question], now: now)
        save()
    }

    /// A Siri question's reply was read aloud, or won't be (a stop, Ask closed): never by itself again.
    func markRead(_ id: String, at now: Date = Date()) {
        guard let index = questions.firstIndex(where: { $0.id == id }), questions[index].readAt == nil else { return }
        questions[index].readAt = now
        save()
    }

    /// Takes out one question (a failed one sent again).
    func remove(_ id: String) {
        questions.removeAll { $0.id == id }
        save()
    }

    /// Drops what has expired, on opening Ask and on each launch.
    func removeExpired(now: Date = Date()) {
        let kept = InsightQuestions.kept(questions, now: now)
        guard kept.count != questions.count else { return }
        questions = kept
        save()
    }

    /// This parent turned AI insights off: nothing is kept (Q12).
    func empty() {
        questions = []
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    private static func read(_ url: URL?) -> [KeptQuestion] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([KeptQuestion].self, from: data)) ?? []
    }

    private func save() {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if questions.isEmpty {
                try? FileManager.default.removeItem(at: url)
                return
            }
            try JSONEncoder().encode(questions).write(to: url, options: [.atomic, .completeFileProtection])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var file = url
            try file.setResourceValues(values)
        } catch {
            // Only that it failed: never what was asked (A9).
            SyncLog.add("ask: couldn't save the questions file")
        }
    }
}
