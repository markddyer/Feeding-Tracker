import Foundation

/// The morning AI card for the watch's fourth page, "Last night" (AI insights step 4, D4 A; design
/// D2 B, D8 A, D9 A, D16 B; D11 A). Plain lines the phone writes from what Home shows: the watch
/// only draws them and never calls a model. It travels under its own key in the application
/// context and in the answer to the watch's check, never in the watch face's transfer or the file
/// the face reads (Y6), and it never goes on the face (F6).
public struct WatchCard: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Sendable {
        /// The card is current: the facts with the AI mark, and the card screen.
        case card
        /// Paused, couldn't reach the AI, or no card today: the facts alone, no AI mark.
        case factsOnly
    }

    /// One of page 4's three night facts (design D8 A), written by the phone from the log.
    public struct Fact: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Sendable { case sleep, feeds, nappies }
        public var kind: Kind
        /// "3h 10m" or "4"; nil only for sleep when none was logged ("No sleep logged").
        public var number: String?
        /// "longest sleep logged", "feeds logged", "nappies logged", or "No sleep logged".
        public var words: String
        /// VoiceOver's words: "Longest sleep logged, 3 hours 10 minutes".
        public var spoken: String

        public init(kind: Kind, number: String?, words: String, spoken: String) {
            self.kind = kind
            self.number = number
            self.words = words
            self.spoken = spoken
        }
    }

    /// One part of the card screen (design D16 B): "Last night" or "Yesterday".
    public struct Section: Codable, Hashable, Sendable {
        public var title: String
        public var lines: [String]
        public var patterns: [String]

        public init(title: String, lines: [String], patterns: [String]) {
            self.title = title
            self.lines = lines
            self.patterns = patterns
        }
    }

    public var mode: Mode
    /// For facts only, the one line why: "Paused. iPhone says why.", "Couldn't reach the AI.
    /// iPhone says why." or "No card today.".
    public var why: String?
    /// The three facts; empty when nothing was logged last night ("Nothing logged last night.").
    public var facts: [Fact]
    /// The card screen's parts; empty for facts only.
    public var sections: [Section]
    /// Yesterday's medicine chips, as the phone's card shows them ("Vitamin D · 09:05").
    public var medicines: [String]
    /// When the card was made ("Made at 07:12"); nil for facts only.
    public var madeAt: Date?
    /// The end of the card's day: after it the watch drops the page even if the phone can't say
    /// so (F11).
    public var ends: Date

    public init(mode: Mode, why: String? = nil, facts: [Fact], sections: [Section] = [], medicines: [String] = [],
                madeAt: Date? = nil, ends: Date) {
        self.mode = mode
        self.why = why
        self.facts = facts
        self.sections = sections
        self.medicines = medicines
        self.madeAt = madeAt
        self.ends = ends
    }

    /// Whether the page may show at `now`: only before the card's day ends.
    public func isCurrent(at now: Date) -> Bool { now < ends }

    /// The watch's VoiceOver sentence for page 4 (design D20 A).
    public var spokenPage: String {
        let head = mode == .card ? "Last night, picked by AI." : "Last night, facts only."
        let body = facts.isEmpty ? "Nothing logged last night." : facts.map { $0.spoken + "." }.joined(separator: " ")
        return [head, body, mode == .card ? "Opens the card." : (why ?? "")].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
