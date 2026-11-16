#if FEEDING_DEV
import FeedingCore
import Foundation

/// Feeding Dev only: made-up states for screenshots in the watch simulator, with no phone. Launch
/// with `-sampleWatch` and `idle`, `running`, `other`, `bottleOnly`, `bottleRunning`, `amount`,
/// `faceStart`, `waiting`, `firstFeed` or `notSetUp`; add `-sampleLook night` for the night look.
/// "Sam" is a made-up name.
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
        case "bottleRunning", "amount":
            state.bottleOnly = true
            state.running = WatchFeed(id: "sample", startedAt: started, mine: true, byName: "", byColour: "lavender",
                                      side: nil, bottles: [Bottle(id: "sample-bottle", milk: .formula)])
            state.lastFeedStart = started
        case "firstFeed":
            state.lastFeedStart = nil
            state.previousFeedStart = nil
        case "notSetUp":
            state = WatchState(madeAt: now, setUp: false)
        default:
            break
        }
        return state
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

    /// `-watchSendTest start` (or `finish`): sends that tap two seconds after the link is up, to
    /// test the link with a paired phone simulator, where nothing can tap the watch.
    static func runSendTest(_ link: PhoneLink) {
        guard let test = UserDefaults.standard.string(forKey: "watchSendTest") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            switch test {
            case "start":
                link.send(.start(feedID: UUID().uuidString, bottle: nil, bottleID: UUID().uuidString))
            case "finish":
                if let running = link.shown?.running { link.send(.finish(feedID: running.id)) }
            default:
                break
            }
        }
    }
}
#endif
