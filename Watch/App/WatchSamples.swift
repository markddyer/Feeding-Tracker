#if FEEDING_DEV
import FeedingCore
import Foundation

/// Feeding Dev only: made-up states for screenshots in the watch simulator, with no phone. Launch
/// with `-sampleWatch` and `idle`, `running`, `other`, `bottleOnly`, `bottleRunning`, `amount`,
/// `faceStart`, `breastfeedRunning`, `waiting`, `firstFeed`, `notSetUp`, `asleep` or `awake`; add
/// `-sampleLook night` for the night look, and `-sampleBreastfeeder YES` for "Breastfeed (Sam)" on
/// a bottle-only watch (design DD15). `asleep` and `awake` open on page two (sleep and nappy); `-watchPage 2`
/// opens any state there. Every state but `firstFeed` has a nappy 40 minutes ago. "Sam" is a
/// made-up name. `-sampleFeedAgo 185` puts the last feed that many minutes ago (100 by default),
/// to see the window bar at any moment; `-watchFaceGallery YES` shows the big watch face piece's
/// words and bar at four moments (`WatchFaceGallery`).
enum WatchSamples {
    private static var name: String? { UserDefaults.standard.string(forKey: "sampleWatch") }

    static func fromLaunchArguments(now: Date = Date()) -> WatchState? {
        guard let name else { return nil }
        let look: LookSetting = UserDefaults.standard.string(forKey: "sampleLook") == "night" ? .alwaysNight : .alwaysDay
        let ago = UserDefaults.standard.double(forKey: "sampleFeedAgo")
        let lastFeed = now.addingTimeInterval(-(ago > 0 ? ago : 100) * 60)
        var state = WatchState(madeAt: now, setUp: true, lastFeedStart: lastFeed,
                               previousFeedStart: lastFeed, lookSetting: look,
                               nextSide: .right, lastFormulaML: 90, lastExpressedML: 60, lastMilk: .formula,
                               myColour: "lavender")
        let started = now.addingTimeInterval(-(12 * 60 + 4))
        // Awake for 25 minutes after a sleep of 1h 50m, and a wet and dirty nappy 40 minutes ago.
        state.sleep = WatchSleep(id: "sample-sleep", start: now.addingTimeInterval(-135 * 60), end: now.addingTimeInterval(-25 * 60))
        state.lastNappy = WatchNappy(id: "sample-nappy", at: now.addingTimeInterval(-40 * 60), wee: true, poo: true)
        // Step 1 of `11-watch-parity.md`: a phone that understands the new taps, one medicine, a
        // bath yesterday, and the two parents ("Alex" wears this watch; both names are made up).
        state.capabilities = WatchCapability.all
        // The last feed, finished, for "Add to this feed" (`-watchScreen addToFeed`): the left
        // side logged, so it asks Right, Formula and Expressed.
        state.lastFeed = WatchLastFeed(id: "sample-last", start: lastFeed, end: lastFeed.addingTimeInterval(20 * 60),
                                       details: FeedDetails(breast: [BreastSegment(side: .left)]), mine: true)
        state.medicines = [WatchMedicine(name: "Vitamin D", lastGiven: now.addingTimeInterval(-12 * 3600))]
        state.lastBath = now.addingTimeInterval(-26 * 3600)
        state.me = MemberID(rawValue: "sample-alex")
        state.members = [WatchMember(id: MemberID(rawValue: "sample-alex"), name: "Alex", colour: "lavender"),
                         WatchMember(id: MemberID(rawValue: "sample-sam"), name: "Sam", colour: "teal")]
        if UserDefaults.standard.bool(forKey: "sampleMedicines") {
            state.medicines = ["Vitamin D", "Infant paracetamol", "Gaviscon"].map {
                WatchMedicine(name: $0, lastGiven: now.addingTimeInterval(-3 * 3600))
            }
        }
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

    /// The page the app opens on: page two for `asleep` and `awake`, or with `-watchPage 2`;
    /// page three with `-watchPage 3` (add `-sampleMedicines YES` for three medicines).
    static func page() -> WatchPage {
        let number = UserDefaults.standard.integer(forKey: "watchPage")
        if number == 3 { return .today }
        return name == "asleep" || name == "awake" || number == 2 ? .care : .feeds
    }

    /// `-watchScreen logged` (the Logged card after Wee), `pooDetails` (after Poo), `pump`
    /// (Pumping's first question) or `medicines` (the medicine list; add `-sampleMedicines YES`):
    /// the screens a tap opens, for screenshots.
    static var screen: String? { UserDefaults.standard.string(forKey: "watchScreen") }

    static func logged(now: Date = Date()) -> LoggedCard? {
        guard screen == "logged" else { return nil }
        return LoggedCard(id: "sample-tap", entryID: "sample-nappy", title: "Wee logged", at: now, mark: .nappy(wee: true, poo: false))
    }

    static func pooAsk() -> PooAsk? {
        screen == "pooDetails" ? PooAsk(nappyID: "sample-nappy", requestID: nil, card: nil) : nil
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
    /// and dirty nappy, `bath`, or `pooDetails` for a poo and then its colour and consistency):
    /// sends that tap two seconds after the link is up, to test the link with a
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
            case "bath":
                // Step 1 of `11-watch-parity.md`: a new tap, with the phone's answer.
                link.send(.bath(id: UUID().uuidString))
            case "justFinished":
                // Step 2: a feed that just finished, then a side for it, which waits for the feed.
                let id = UUID().uuidString
                link.send(.justFinished(feedID: id, minutesAgo: 20))
                link.sendFeedExtra(.addSide(feedID: id, side: .left), feedID: id)
                link.sendFeedExtra(.addBottle(feedID: id, bottleID: UUID().uuidString, milk: .formula, ml: 40), feedID: id)
            case "pooDetails":
                // A poo, then its details, which wait for the poo on the phone.
                let id = UUID().uuidString
                let poo = link.send(.nappy(nappyID: id, wee: false, poo: true))
                link.send(.pooDetails(nappyID: id, colour: .yellow, consistency: .loose), after: poo)
            default:
                break
            }
        }
    }
}

import SwiftUI

/// `-watchFaceGallery YES`: the big watch face piece (`WatchLastFeedView`, rectangular) as it reads
/// at four moments after the sample's last feed, drawn with the same parts, for screenshots. Full
/// colour only: the simulator can't show a tinted face here.
struct WatchFaceGallery: View {
    let state: WatchState
    @Environment(\.watchLook) private var look

    static var isOn: Bool { UserDefaults.standard.bool(forKey: "watchFaceGallery") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach([60.0, 185, 255, 760], id: \.self) { minutes in
                    if let last = state.lastFeedStart {
                        piece(at: last.addingTimeInterval(minutes * 60), last: last)
                    }
                }
            }
        }
    }

    private func piece(at now: Date, last: Date) -> some View {
        let palette = WatchPalette.of(look)
        return VStack(alignment: .leading, spacing: 2) {
            Text("Last feed \(GlanceText.elapsed(now.timeIntervalSince(last))) ago")
                .font(.system(.headline, design: .rounded).monospacedDigit())
                .foregroundStyle(palette.text)
            if let steps = state.windowSteps(at: now) {
                Text(steps.line(state.clock).main)
                    .font(.system(.body, design: .rounded).monospacedDigit())
                    .foregroundStyle(palette.text)
                WatchWindowTrack(steps: steps, palette: palette, height: 8, bell: false)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.4)))
    }
}
#endif
