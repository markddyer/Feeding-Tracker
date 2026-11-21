#if FEEDING_DEV
import FeedingCore
import Foundation

/// Feeding Dev only: made-up states for screenshots in the watch simulator, with no phone. Launch
/// with `-sampleWatch` and `idle`, `running`, `other`, `bottleOnly`, `bottleRunning`, `amount`,
/// `faceStart`, `breastfeedRunning`, `waiting`, `firstFeed`, `notSetUp`, `asleep` or `awake`; add
/// `-sampleLook night` for the night look, and `-sampleBreastfeeder YES` for "Breastfeed (Sam)" on
/// a bottle-only watch (design DD15). `asleep` and `awake` open on page two (sleep and nappy); `-watchPage 2`
/// opens any state there. Every state but `firstFeed` has a nappy 40 minutes ago. "Sam" is a
/// made-up name.
enum WatchSamples {
    private static var name: String? { UserDefaults.standard.string(forKey: "sampleWatch") }

    static func fromLaunchArguments(now: Date = Date()) -> WatchState? {
        guard let name else { return nil }
        let look: LookSetting = UserDefaults.standard.string(forKey: "sampleLook") == "night" ? .alwaysNight : .alwaysDay
        var state = WatchState(madeAt: now, setUp: true, lastFeedStart: now.addingTimeInterval(-100 * 60),
                               previousFeedStart: now.addingTimeInterval(-100 * 60), lookSetting: look,
                               nextSide: .right, lastFormulaML: 90, lastExpressedML: 60, lastMilk: .formula,
                               myColour: "lavender")
        let started = now.addingTimeInterval(-(12 * 60 + 4))
        // Awake for 25 minutes after a sleep of 1h 50m, and a wet and dirty nappy 40 minutes ago.
        state.sleep = WatchSleep(id: "sample-sleep", start: now.addingTimeInterval(-135 * 60), end: now.addingTimeInterval(-25 * 60))
        state.lastNappy = WatchNappy(id: "sample-nappy", at: now.addingTimeInterval(-40 * 60), wee: true, poo: true)
        switch name {
        case "running":
            state.running = WatchFeed(id: "sample", startedAt: started, mine: true, byName: "", byColour: "lavender",
                                      side: .left, bottles: [])
            state.lastFeedStart = started
        case "other":
            state.running = WatchFeed(id: "sample", startedAt: started, mine: false, byName: "Sam", byColour: "teal",
                                      side: .left, bottles: [])
            state.lastFeedStart = started
        case "bottleOnly", "faceStart":
            state.bottleOnly = true
        case "breastfeedRunning":
            // "Breastfeed (Sam)" started on this bottle-only watch: Left and Right show.
            state.bottleOnly = true
            state.running = WatchFeed(id: "sample", startedAt: started, mine: true, byName: "", byColour: "lavender",
                                      side: nil, bottles: [], breastfeed: true)
            state.lastFeedStart = started
        case "bottleRunning", "amount":
            state.bottleOnly = true
            state.running = WatchFeed(id: "sample", startedAt: started, mine: true, byName: "", byColour: "lavender",
                                      side: nil, bottles: [Bottle(id: "sample-bottle", milk: .formula)])
            state.lastFeedStart = started
        case "firstFeed":
            state.lastFeedStart = nil
            state.previousFeedStart = nil
            state.sleep = nil
            state.lastNappy = nil
        case "asleep":
            state.sleep = WatchSleep(id: "sample-sleep", start: now.addingTimeInterval(-80 * 60))
        case "notSetUp":
            state = WatchState(madeAt: now, setUp: false)
        default:
            break
        }
        if state.bottleOnly, UserDefaults.standard.bool(forKey: "sampleBreastfeeder") {
            state.breastfeeder = MemberID(rawValue: "sample-sam")
            state.breastfeederName = "Sam"
        }
        return state
    }

    /// The page the app opens on: page two for `asleep` and `awake`, or with `-watchPage 2`.
    static func page() -> WatchPage {
        name == "asleep" || name == "awake" || UserDefaults.standard.integer(forKey: "watchPage") == 2 ? .care : .feeds
    }

    /// The amount screen, for `-sampleWatch amount`.
    static func question() -> AmountAsk? {
        guard name == "amount" else { return nil }
        return AmountAsk(feedID: "sample", bottles: [Bottle(id: "sample-bottle", milk: .formula)])
    }

    /// "Formula or expressed?", for `-sampleWatch faceStart`: as after Start feed on the watch face.
    static func milkAsk() -> Date? {
        name == "faceStart" ? Date() : nil
    }

    /// `-sampleWatch waiting`: a tap kept while the phone is out of reach.
    static var showsWaiting: Bool { name == "waiting" }

    /// `-watchSendTest start` (or `finish`, `sleep` for Fell asleep or Woke up, `nappy` for a wet
    /// and dirty nappy): sends that tap two seconds after the link is up, to test the link with a
    /// paired phone simulator, where nothing can tap the watch.
    static func runSendTest(_ link: PhoneLink) {
        guard let test = UserDefaults.standard.string(forKey: "watchSendTest") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            switch test {
            case "start":
                link.send(.start(feedID: UUID().uuidString, bottle: nil, bottleID: UUID().uuidString))
            case "finish":
                if let running = link.shown?.running { link.send(.finish(feedID: running.id)) }
            case "sleep":
                if let command = link.shown?.sleepTap() { link.send(command) }
            case "nappy":
                link.send(.nappy(nappyID: UUID().uuidString, wee: true, poo: true))
            default:
                break
            }
        }
    }
}
#endif
