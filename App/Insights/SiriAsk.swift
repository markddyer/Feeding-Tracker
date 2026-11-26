import AlarmKit
import AppIntents
import AVFoundation
import FeedingCore
import FeedingInsights
import Observation
import SwiftUI
import UIKit

// "Ask Little Log" with Siri (AI insights step 4, `docs/planning/12-ai-insights-gauntlet.md`: D3 A,
// D7 A, D8 A, D9 A, D10 B; design D10 A, D12 A, D14 B, D20 A). Siri takes the question after the
// phrase ("What's your question?"), the phone asks for an unlock, and Little Log opens: the AI
// runs only with the app open (D13). A danger sign opens Get help now at once, before anything can
// make it wait (Y1); every other question goes through Ask's own route, in turn (F9), and its
// reply is read aloud once Ask shows it.
//
//   Siri ─► AskLittleLogIntent ─► SiriQuestions.receive
//              danger sign ─► Get help now sheet over anything (HelpPresenter), heading read once
//              repeat while waiting ─► "Already asking."
//              otherwise ─► queue ─► NotificationTaps.showAsk (an open form stays in front, F13)
//                                 ─► InsightEngine.ask(fromSiri:) ─► QuestionLog ─► Ask reads it (ReadAloud)

/// "Ask Little Log": the question is asked after the phrase, as an App Shortcut phrase can't hold
/// free words (F2).
struct AskLittleLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Little Log"
    static let description = IntentDescription("Ask about your log or what the NHS says. Little Log opens with the answer and reads it out.")
    /// Opens the app: the AI never runs with the app closed, and nothing shows on the Lock Screen (D13).
    static let supportedModes: IntentModes = .foreground(.immediate)
    /// The question and its answer are kept where only an unlocked phone can read them (`QuestionLog`):
    /// this iPhone's own unlock, never a paired device's (Codex step 4 review, 8).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static var allowedExecutionTargets: IntentExecutionTargets { [.main] }

    @Parameter(title: "Question", requestValueDialog: "What's your question?")
    var question: String

    init() {}

    init(question: String) {
        self.question = question
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let said = await SiriQuestions.shared.receive(question)
        return .result(dialog: "\(said)")
    }
}

/// Siri's questions, in turn (F9): one at a time through `InsightEngine.ask`, the same question
/// never twice while it waits (design D10 A).
@MainActor @Observable
final class SiriQuestions {
    static let shared = SiriQuestions()

    /// Questions waiting their turn, oldest first.
    private(set) var waiting: [String] = []
    /// The question with the AI now, if it came from Siri.
    private(set) var inFlight: String?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var leaving: NSObjectProtocol?

    /// A Siri question or one still to be answered: Ask's bar says "Waiting for the answer…".
    var isWaiting: Bool { inFlight != nil || !waiting.isEmpty }

    private init() {
        leaving = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                         object: nil, queue: .main) { _ in
            Task { @MainActor in SiriQuestions.shared.appLeft() }
        }
    }

    /// The app left the screen (the phone locked, or another app): the questions still waiting
    /// are kept as "Stopped when the phone locked", with Send again, so none is lost if the system
    /// then closes the app (Codex step 4 review, 10). Nothing is sent with the app closed (D13).
    func appLeft(log: QuestionLog = .shared, now: Date = Date()) {
        guard !waiting.isEmpty else { return }
        SyncLog.add("ask: Siri, \(waiting.count) waiting stopped, the app left")
        for text in waiting {
            log.add(KeptQuestion(askedAt: now, text: text, kind: .stopped, viaSiri: true, readAt: now), now: now)
        }
        waiting.removeAll()
    }

    /// What Siri says back.
    func receive(_ spoken: String, model: AppModel = .shared, log: QuestionLog = .shared,
                 engine: InsightEngine = .shared) -> String {
        let text = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "Say \"Ask Little Log\" again with your question." }
        let now = Date()
        // Y1: the danger signs first, before set-up, the busy check, the queue or an open form
        // (Codex step 4 review, 2: a phone still loading its iCloud ID still gets Get help now).
        let babySigns = !InsightQuestions.dangerSigns(text, kept: log.questions, now: now).isEmpty
        if babySigns || InsightQuestions.parentInDanger(text, kept: log.questions, now: now) {
            SyncLog.add(babySigns ? "ask: Siri, danger sign, Get help now" : "ask: Siri, a parent's danger words, their help")
            // Kept as read: Ask doesn't read it again once the sheet closes (G7).
            log.add(KeptQuestion(askedAt: now, text: text, kind: babySigns ? .helpNow : .parentHelp, viaSiri: true, readAt: now),
                    now: now)
            // The sheet reads its heading once it is on screen, and holds the voice until it closes.
            HelpPresenter.show(forParent: !babySigns)
            return InsightQuestions.siriAsking
        }
        guard model.me != nil, model.baby != nil else { return InsightQuestions.siriNotSetUp }
        let pending = waiting + [inFlight].compactMap { $0 }
        if pending.contains(where: { InsightQuestions.isSameQuestion($0, text) }) {
            return InsightQuestions.siriAlreadyAsking
        }
        waiting.append(text)
        NotificationTaps.shared.showAsk()
        run(engine: engine)
        return InsightQuestions.siriAsking
    }

    private func run(engine: InsightEngine) {
        guard !running else { return }
        running = true
        Task {
            while !waiting.isEmpty {
                // A typed question with the AI goes first; this one waits its turn (F9).
                while engine.askingQuestion { try? await Task.sleep(for: .milliseconds(300)) }
                let next = waiting.removeFirst()
                inFlight = next
                await engine.ask(next, fromSiri: true)
                inFlight = nil
            }
            running = false
        }
    }
}

/// Reads a Siri question's reply aloud (D7 A, D8 A, D10 B; design D10 A, D12 A): the phone's own
/// voice, even on silent, at half volume in the night hours. A tap, an alarm, a feed alert or
/// leaving Ask stops it; "Read again" brings it back. With VoiceOver on, VoiceOver reads the
/// words instead and the app doesn't speak. Never a typed question.
@MainActor @Observable
final class ReadAloud {
    static let shared = ReadAloud()

    enum State: Equatable {
        case idle
        /// Speaking the reply with this ID.
        case reading(String)
        /// Stopped by a tap, an alarm or an alert: "Read again" until the next question.
        case stopped(String)
    }

    private(set) var state: State = .idle
    /// The phone's volume was at zero as it began: the bar says "Volume is off".
    private(set) var volumeOff = false
    /// Get help now is on screen, or on its way: its words alone are read; an ordinary reply that
    /// comes meanwhile shows with "Read again" (Codex step 4 review, 3).
    private(set) var helpHolds = false
    /// Replies to questions asked before Ask last closed are never read (design D10 A: leaving
    /// Ask cancels a reading, the one still coming included; Codex step 4 review, 9).
    @ObservationIgnored private(set) var silencedBefore = Date.distantPast

    /// The reply ID Get help now reads under.
    static let helpID = "getHelpNow"

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let delegate: SpeechDelegate
    @ObservationIgnored private var words: [String: String] = [:]
    @ObservationIgnored private var speaking: ObjectIdentifier?
    @ObservationIgnored private var alarmWatch: Task<Void, Never>?
    @ObservationIgnored private var interruptions: NSObjectProtocol?
    /// A feed alert or another sound came: nothing starts to speak until it has been heard.
    @ObservationIgnored private var quietUntil = Date.distantPast

    private init() {
        delegate = SpeechDelegate { utterance in ReadAloud.shared.finished(utterance) }
        synthesizer.delegate = delegate
        interruptions = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                                               queue: .main) { _ in
            Task { @MainActor in ReadAloud.shared.alertCame() }
        }
    }

    /// Reads `text`, the reply with ID `id`. It waits as "Read again" instead while Get help now
    /// holds the voice, just after an alert, or while an alarm rings (Y4).
    func read(_ text: String, for id: String) {
        words[id] = text
        if case .reading = state {
            synthesizer.stopSpeaking(at: .immediate)
            done()
        }
        if (helpHolds && id != Self.helpID) || Date() < quietUntil || Self.alarmRinging() {
            state = .stopped(id)
            return
        }
        // With VoiceOver on, one voice: VoiceOver's (design D12 A).
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: text)
            state = .stopped(id)
            return
        }
        AppSound.beginSpeaking()
        volumeOff = AVAudioSession.sharedInstance().outputVolume == 0
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        utterance.volume = Self.isNight() ? 0.5 : 1
        state = .reading(id)
        speaking = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
        watchForAlarms()
    }

    /// Stops the voice. Anything it hadn't finished can be read again.
    func stop() {
        guard case .reading(let id) = state else { return }
        synthesizer.stopSpeaking(at: .immediate)
        state = .stopped(id)
        done()
    }

    /// A feed alert or another sound's interruption: the voice stops, and nothing starts for a
    /// few seconds, so the alert is heard (Y4; Codex step 4 review, 12).
    func alertCame(now: Date = Date()) {
        quietUntil = now.addingTimeInterval(15)
        stop()
    }

    func readAgain() {
        guard case .stopped(let id) = state, let text = words[id] else { return }
        quietUntil = .distantPast
        read(text, for: id)
    }

    /// Ask closed, or a new question: nothing to read again, and nothing still coming is read.
    func clear(now: Date = Date()) {
        silencedBefore = now
        synthesizer.stopSpeaking(at: .immediate)
        state = .idle
        done()
    }

    /// Get help now's sheet is coming: it holds the voice until it closes.
    func helpComing() {
        helpHolds = true
    }

    /// Get help now's sheet is on screen: its words, once.
    func helpShown(forParent: Bool) {
        helpHolds = true
        let title = NHSPassages.passage(InsightQuestions.parentHelpPassage)?.title
        read(InsightQuestions.spoken(forParent ? .parentHelp : .helpNow, helpTitle: title), for: Self.helpID)
    }

    /// Get help now's sheet closed.
    func helpClosed() {
        helpHolds = false
        if state == .reading(Self.helpID) || state == .stopped(Self.helpID) {
            synthesizer.stopSpeaking(at: .immediate)
            state = .idle
            done()
        }
    }

    /// Only the reading now going on ends this way: an older one's late call is ignored (Codex step
    /// 4 review, 11).
    private func finished(_ utterance: ObjectIdentifier) {
        guard utterance == speaking, case .reading = state else { return }
        state = .idle
        done()
    }

    private static func alarmRinging() -> Bool {
        ((try? AlarmManager.shared.alarms) ?? []).contains { $0.state == .alerting }
    }

    private func done() {
        speaking = nil
        alarmWatch?.cancel()
        alarmWatch = nil
        AppSound.endSpeaking()
    }

    /// An alarm that starts ringing stops the voice at once (Y4); a feed alert does too
    /// (`NotificationDelegate`), and so does any other sound's interruption.
    private func watchForAlarms() {
        alarmWatch?.cancel()
        alarmWatch = Task {
            for await alarms in AlarmManager.shared.alarmUpdates {
                if Task.isCancelled { return }
                if alarms.contains(where: { $0.state == .alerting }) {
                    stop()
                    return
                }
            }
        }
    }

    /// The household's night hours (the rota's, 21:00 to 07:00 by default).
    static func isNight(at now: Date = Date()) -> Bool {
        let settings = AppModel.shared.store.data.householdSettings
        if case .night = settings.dayHours.period(at: now, in: settings.timeZone) { return true }
        return false
    }

    private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate, Sendable {
        let finished: @MainActor @Sendable (ObjectIdentifier) -> Void

        init(finished: @escaping @MainActor @Sendable (ObjectIdentifier) -> Void) {
            self.finished = finished
        }

        nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            let id = ObjectIdentifier(utterance)
            Task { @MainActor in self.finished(id) }
        }
    }
}

/// The one owner of the app's sound mode (F16): journal videos follow the silent switch, muted at
/// night (T13); the read-aloud speaks on silent too (D7 A). Each use sets the mode it needs, and
/// speaking puts the video's mode back when it ends, so a video never plays aloud at night.
@MainActor
enum AppSound {
    /// For a journal video: the silent switch decides; nothing else of the app's sound is touched.
    static let videoCategory: AVAudioSession.Category = .ambient
    private static var speaking = false

    static func forVideo() {
        guard !speaking else { return }
        try? AVAudioSession.sharedInstance().setCategory(videoCategory)
    }

    static func beginSpeaking() {
        speaking = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    static func endSpeaking() {
        guard speaking else { return }
        speaking = false
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        try? session.setCategory(videoCategory)
    }

    /// For the tests: the mode now.
    static var category: AVAudioSession.Category { AVAudioSession.sharedInstance().category }
}

/// Get help now from a Siri danger sign (D9 A; design D14 B, D20 A): a sheet over whatever is open,
/// a half-filled form included, which keeps its typing underneath. The keyboard is put away and
/// VoiceOver starts on "Get help now".
@MainActor
enum HelpPresenter {
    /// A danger sign waits for its sheet: kept until the sheet is on screen, so a screen still
    /// opening or closing can't lose it (Codex step 4 review, 2).
    private(set) static var waiting = false
    private static var trying = false
    /// The parent's own urgent help, not the baby's (a parent's danger words).
    private static var forParent = false

    static func show(forParent: Bool = false) {
        waiting = true
        // The baby's list wins if both were said.
        self.forParent = trying ? (self.forParent && forParent) : forParent
        ReadAloud.shared.helpComing()
        guard !trying else { return }
        trying = true
        Task {
            // Tries again every 0.3 s while the request waits: the app may still be coming to the
            // front, or a screen may be on its way in or out. It stops once the sheet is shown.
            while waiting {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                if let top = topController() {
                    if (top as? UIHostingController<GetHelpNowSheet>) != nil {
                        // One sheet at a time: the first danger's stays.
                        waiting = false
                    } else if !top.isBeingPresented, !top.isBeingDismissed, top.transitionCoordinator == nil {
                        // gstack-shortcut(dec-6ac49277): a sheet a swipe can close (the parents' D14 B);
                        // upgrade to a full-screen cover if a parent swipes it away by mistake, or before
                        // another family uses the app.
                        let host = UIHostingController(rootView: GetHelpNowSheet(forParent: forParent))
                        host.modalPresentationStyle = .pageSheet
                        top.present(host, animated: true)
                    }
                }
                if waiting { try? await Task.sleep(for: .milliseconds(300)) }
            }
            trying = false
        }
    }

    /// The sheet is on screen.
    static func shown() {
        waiting = false
    }

    private static func topController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }
}

/// Get help now as a sheet, with its round ✕: the baby's urgent list, or a parent's own urgent help.
struct GetHelpNowSheet: View {
    var forParent = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GetHelpNowView(focusHeading: true,
                           passage: forParent ? NHSPassages.passage(InsightQuestions.parentHelpPassage) ?? NHSPassages.urgent
                                              : NHSPassages.urgent)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Close")
                    }
                }
        }
        .tint(Theme.text)
        .modifier(LookModifier())
        .onAppear {
            HelpPresenter.shown()
            ReadAloud.shared.helpShown(forParent: forParent)
        }
        .onDisappear { ReadAloud.shared.helpClosed() }
    }
}
