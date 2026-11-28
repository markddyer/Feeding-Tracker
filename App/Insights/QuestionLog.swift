import FeedingInsights
import Foundation
import Observation
import UIKit

/// Ask's questions and answers on this phone (AI insights step 3, D4 and D5 A): never synced, kept
/// 24 hours, locked whenever the phone is locked (complete file protection), left out of the
/// phone's backups, and emptied when this parent turns AI insights off (Q12). `InsightQuestions`
/// alone decides what has expired; this file only keeps what it is given.
///
/// A question Siri answers on a locked phone (`docs/planning/15-hands-free-siri.md`, V5 A) can't go
/// in that file: a locked phone can neither read nor write it. It goes in a file of its own, which a
/// locked phone can make but only an unlocked one can open again ("complete unless open"), and joins
/// the list at the next unlock (`takeLocked`). While the phone is locked the main file is never
/// written, so the questions it couldn't read are never written over.
@MainActor
@Observable
final class QuestionLog {
    static let shared = QuestionLog()

    private(set) var questions: [KeptQuestion] = []
    @ObservationIgnored private let url: URL?
    @ObservationIgnored private let isUnlocked: @MainActor () -> Bool
    /// The main file was read, or there is none: it may be written.
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var unlocking: NSObjectProtocol?

    init(url: URL? = QuestionLog.defaultURL, now: Date = Date(),
         isUnlocked: @escaping @MainActor () -> Bool = { UIApplication.shared.isProtectedDataAvailable }) {
        self.url = url
        self.isUnlocked = isUnlocked
        let read = Self.read(url)
        loaded = read != nil
        questions = InsightQuestions.kept(read ?? [], now: now)
        #if FEEDING_DEV
        if UserDefaults.standard.object(forKey: "sampleQuestions") != nil, url == Self.defaultURL {
            questions = SampleQuestions.make(UserDefaults.standard.string(forKey: "sampleQuestions") ?? "", now: now)
            loaded = true
        }
        #endif
        takeLocked(now: now)
        if url == Self.defaultURL {
            unlocking = NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.takeLocked() }
            }
        }
    }

    /// Application Support, which the app alone can read; not the App Group the widgets share.
    nonisolated static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("questions.json")
    }

    /// The locked phone's own files: one per question, beside the main file.
    private var lockedFolder: URL? {
        url.map { $0.deletingLastPathComponent().appendingPathComponent("questions-locked", isDirectory: true) }
    }

    /// The phone is unlocked: the main file is read if it couldn't be before, the locked phone's
    /// questions join it, and their files go once the main file holds them (Codex review of doc 15,
    /// step 3, 7).
    func takeLocked(now: Date = Date()) {
        guard isUnlocked(), url != nil else { return }
        let hydrated = !loaded
        guard hydrate() else { return }
        var taken: [URL] = []
        if let folder = lockedFolder,
           let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                // A file that can't be read yet stays for the next time.
                guard let data = try? Data(contentsOf: file),
                      let question = try? JSONDecoder().decode(KeptQuestion.self, from: data) else { continue }
                // The one held here is newer (read aloud since, say) than its file.
                if !questions.contains(where: { $0.id == question.id }) { questions.append(question) }
                taken.append(file)
            }
        }
        questions = InsightQuestions.kept(questions, now: now)
        guard hydrated || !taken.isEmpty else { return }
        if save() {
            for file in taken { try? FileManager.default.removeItem(at: file) }
        }
    }

    /// Reads the main file if it couldn't be read before, joining what is held here; false while
    /// it still can't be read.
    private func hydrate() -> Bool {
        guard !loaded else { return true }
        guard isUnlocked(), let read = Self.read(url) else { return false }
        let ids = Set(questions.map(\.id))
        questions = read.filter { !ids.contains($0.id) } + questions
        loaded = true
        return true
    }

    /// The main file couldn't be read (a phone Siri started while locked) and changed in the last
    /// 10 minutes: it may hold the question before this one, which the danger check and the AI
    /// read with it (Codex review of doc 15, step 3, 3). A file's date can be read while locked.
    func mayHideRecent(now: Date = Date()) -> Bool {
        guard !loaded, let url,
              let changed = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        else { return false }
        return now.timeIntervalSince(changed) < InsightQuestions.earlierWithin
    }

    /// The questions to show at `now`, oldest first: an answer past its 24 hours goes even while
    /// Ask is open (X8).
    func shown(now: Date) -> [KeptQuestion] {
        InsightQuestions.kept(questions, now: now).sorted { $0.askedAt < $1.askedAt }
    }

    func add(_ question: KeptQuestion, now: Date = Date()) {
        questions = InsightQuestions.kept(questions + [question], now: now)
        if isUnlocked() {
            save()
        } else {
            keepLocked(question)
        }
    }

    /// A Siri question's reply was read aloud, or won't be (a stop, Ask closed): never by itself again.
    func markRead(_ id: String, at now: Date = Date()) {
        guard let index = questions.firstIndex(where: { $0.id == id }), questions[index].readAt == nil else { return }
        questions[index].readAt = now
        if isUnlocked() {
            save()
        } else {
            keepLocked(questions[index])
        }
    }

    /// Siri stopped waiting before the answer came: Ask reads it aloud when it shows it.
    func markUnread(_ id: String) {
        guard let index = questions.firstIndex(where: { $0.id == id }), questions[index].readAt != nil else { return }
        questions[index].readAt = nil
        if isUnlocked() {
            save()
        } else {
            keepLocked(questions[index])
        }
    }

    /// On a locked phone: the question in its own file (written anew on each change), which only an
    /// unlocked phone can open again. Left out of backups, as the main file.
    private func keepLocked(_ question: KeptQuestion) {
        guard let folder = lockedFolder else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var file = folder.appendingPathComponent("\(question.id).json")
            try JSONEncoder().encode(question).write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try file.setResourceValues(values)
        } catch {
            SyncLog.add("ask: couldn't keep a locked question")
        }
    }

    /// Takes out one question (a failed one sent again).
    func remove(_ id: String) {
        questions.removeAll { $0.id == id }
        // Its locked-phone file goes too, so the unlock doesn't bring it back (Codex, step 3, 9).
        if let file = lockedFolder?.appendingPathComponent("\(id).json") { try? FileManager.default.removeItem(at: file) }
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
        if let folder = lockedFolder { try? FileManager.default.removeItem(at: folder) }
        loaded = true
    }

    /// The main file's questions: none when there is no file; nil when it is there but can't be
    /// read (a locked phone).
    private static func read(_ url: URL?) -> [KeptQuestion]? {
        guard let url else { return [] }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode([KeptQuestion].self, from: data)) ?? []
    }

    /// True once the main file holds the questions. Never while locked, nor before the main file
    /// is read: it would write over questions this phone couldn't read. A change made just after
    /// the unlock reads the file first (Codex review of doc 15, step 3, 8).
    @discardableResult
    private func save() -> Bool {
        guard let url, isUnlocked(), hydrate() else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if questions.isEmpty {
                try? FileManager.default.removeItem(at: url)
                return true
            }
            try JSONEncoder().encode(questions).write(to: url, options: [.atomic, .completeFileProtection])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var file = url
            try file.setResourceValues(values)
            return true
        } catch {
            // Only that it failed: never what was asked (A9).
            SyncLog.add("ask: couldn't save the questions file")
            return false
        }
    }
}
