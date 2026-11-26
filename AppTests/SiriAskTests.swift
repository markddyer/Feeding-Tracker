import AppIntents
import AVFoundation
import FeedingCore
import FeedingInsights
import Foundation
import Testing
@testable import FeedingDev

// AI insights step 4 (`docs/planning/12-ai-insights-gauntlet.md`): the Siri action, the sound mode
// and the watch's "Last night" card. No Siri, no AI.

@MainActor
@Suite("Ask from Siri, the sound mode and the watch card")
struct SiriAskTests {
    /// D13: the AI never runs with the app closed. The Siri action opens the app after an unlock;
    /// copying the feed actions' background settings would break that.
    @Test func theSiriActionNeedsAnUnlockAndOpensTheApp() {
        #expect(AskLittleLogIntent.supportedModes == .foreground(.immediate))
        #expect(!AskLittleLogIntent.supportedModes.contains(.background))
        // This iPhone's own unlock, never a paired device's (Codex step 4 review, 8).
        guard case .requiresLocalDeviceAuthentication = AskLittleLogIntent.authenticationPolicy else {
            Issue.record("the Siri action must ask for this iPhone's own unlock")
            return
        }
    }

    /// F16 and the journal's T13: a reading puts the video's mode back, so a journal video never
    /// plays on silent at night after the voice.
    @Test func speakingPutsTheVideosModeBack() {
        AppSound.forVideo()
        #expect(AppSound.category == .ambient, "a video follows the silent switch")
        AppSound.beginSpeaking()
        #expect(AppSound.category == .playback)
        // A video started while it speaks doesn't take the mode from the voice.
        AppSound.forVideo()
        #expect(AppSound.category == .playback)
        AppSound.endSpeaking()
        #expect(AppSound.category == .ambient)
    }

    /// Codex step 4 review's test finding: Stop, the way a tap does it, puts the videos' mode back.
    @Test func stopPutsTheVideosModeBack() {
        let voice = ReadAloud.shared
        voice.clear()
        // At no volume: the simulator plays the voice through the Mac's speakers.
        UserDefaults.standard.set(true, forKey: "speechSilent")
        defer { UserDefaults.standard.removeObject(forKey: "speechSilent") }
        voice.read("Vitamin D: last logged at 09:05 today.", for: "test-stop")
        guard case .reading = voice.state else {
            // VoiceOver or an alert held the voice: nothing to stop.
            #expect(AppSound.category == .ambient)
            return
        }
        #expect(AppSound.category == .playback)
        voice.stop()
        #expect(voice.state == .stopped("test-stop"))
        #expect(AppSound.category == .ambient)
        voice.clear()
    }

    /// Codex step 4 review, 3: while Get help now holds the voice, an ordinary reply waits as
    /// "Read again" and is not spoken over it.
    @Test func getHelpNowHoldsTheVoice() {
        let voice = ReadAloud.shared
        voice.clear()
        voice.helpComing()
        voice.read("8 feeds logged yesterday.", for: "test-reply")
        #expect(voice.state == .stopped("test-reply"))
        voice.helpClosed()
        #expect(!voice.helpHolds)
        voice.clear()
    }

    /// Codex step 4 review, 12: just after a feed alert nothing starts to speak.
    @Test func anAlertKeepsTheVoiceQuiet() {
        let voice = ReadAloud.shared
        voice.clear()
        voice.alertCame()
        voice.read("8 feeds logged yesterday.", for: "test-alert")
        #expect(voice.state == .stopped("test-alert"))
        // The quiet ends (an alert long ago), for the other tests.
        voice.alertCame(now: .distantPast)
        voice.clear()
    }

    /// Design D8 A: last night's three facts, each "logged", zeros shown, and none when nothing was
    /// logged in the night.
    @Test func theWatchFactsSayLogged() {
        let start = Date(timeIntervalSince1970: 1_795_560_000)
        var night = NightFacts(evening: PlainDate(year: 2026, month: 11, day: 24)!, start: start,
                               end: start.addingTimeInterval(10 * 3600))
        #expect(WatchCardMaker.nightFacts(night, nappies: 0).isEmpty, "nothing logged")
        night.feeds = 4
        night.longestSleep = Stretch(from: start, to: start.addingTimeInterval(3 * 3600 + 600))
        let facts = WatchCardMaker.nightFacts(night, nappies: 0)
        #expect(facts.map(\.kind) == [.sleep, .feeds, .nappies])
        #expect(facts[0].number == HomeText.elapsed(3 * 3600 + 600) && facts[0].words == "longest sleep logged")
        #expect(facts[0].spoken.hasPrefix("Longest sleep logged, "))
        #expect(facts[1].number == "4" && facts[1].words == "feeds logged")
        #expect(facts[2].number == "0" && facts[2].words == "nappies logged", "a zero is shown")
        night.longestSleep = nil
        night.feeds = 1
        let noSleep = WatchCardMaker.nightFacts(night, nappies: 1)
        #expect(noSleep[0].number == nil && noSleep[0].words == "No sleep logged")
        #expect(noSleep[1].words == "feed logged" && noSleep[2].words == "nappy logged")
    }

    /// Design D9 A: the watch's own short line for each reason the phone shows the facts only.
    @Test func theWatchSaysWhyInItsOwnWords() {
        #expect(WatchCardMaker.watchWhy(CardText.pausedWhy) == "Paused. iPhone says why.")
        #expect(WatchCardMaker.watchWhy(CardText.noCardWhy) == "No card today.")
        #expect(WatchCardMaker.watchWhy("Couldn’t reach the AI since 07:10. Settings › AI insights says why.")
                == "Couldn't reach the AI. iPhone says why.")
    }
}
