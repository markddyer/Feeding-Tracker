import Foundation
import FeedingCore

// The AI insights' safety checks (`docs/planning/12-ai-insights-gauntlet.md`, step 1, task AI3).
// One word reader serves two jobs (D1):
// - `DangerSigns` reads what a parent types and opens the Get help now card before any AI runs
//   (A2). Like the alarms, it opens the card too often rather than too rarely: it never reads a
//   number of hours or an age, ignores "not", and allows one wrong letter in longer words.
// - `MedicineQuestions` keeps a question about a medicine on the phone: it never goes to the AI
//   (D6, O3).
// - `AnswerCheck` reads what the AI writes for a card. The AI never writes a number: it fills a
//   fixed form that points to facts, and the checker puts the numbers in (A1). Every pattern it
//   claims is checked against the facts (R5), a fall is left out over empty stretches (R6), amounts
//   are left out on days with a missing amount (O6), and only passages and summaries Parent A has
//   checked may appear (R7, D9, D10). Only it can make a `CheckedCard`, the one thing a screen
//   shows.

// MARK: The word reader

/// Text as words: lower case, accents and curly apostrophes folded, apostrophes dropped ("won't"
/// is "wont"), and numbers kept whole ("38.5"). "°" reads as the word "deg".
enum WordReader {
    static func words(_ text: String) -> [String] {
        // Accents folded by a table rather than Foundation's `folding`, which Linux may not have.
        let folded = String(text.lowercased().flatMap { accents[$0] ?? String($0) })
        var words: [String] = []
        var current = ""
        var isNumber = false
        func finish() {
            if !current.isEmpty { words.append(current) }
            current = ""
            isNumber = false
        }
        let characters = Array(folded)
        for (index, character) in characters.enumerated() {
            if character == "'" || character == "\u{2019}" || character == "\u{2018}" { continue }
            if character == "°" {
                finish()
                words.append("deg")
            } else if character.isASCII, character.isNumber {
                if !isNumber { finish() }
                isNumber = true
                current.append(character)
            } else if character == ".", isNumber, index + 1 < characters.count, characters[index + 1].isASCII,
                      characters[index + 1].isNumber {
                current.append(character)
            } else if character.isLetter {
                if isNumber { finish() }
                current.append(character)
            } else {
                finish()
            }
        }
        finish()
        return words
    }

    /// Accented letters as plain ones ("café" reads as "cafe").
    static let accents: [Character: String] = {
        var table: [Character: String] = ["æ": "ae", "œ": "oe", "ß": "ss", "ø": "o", "ð": "d", "þ": "th"]
        let groups = ["a": "àáâãäåāăą", "c": "çćĉċč", "e": "èéêëēĕėęě", "i": "ìíîïĩīĭįı", "n": "ñńņňŉ",
                      "o": "òóôõöōŏő", "u": "ùúûüũūŭůűų", "y": "ýÿŷ", "g": "ĝğġģ", "s": "śŝşš", "z": "źżž", "l": "ĺļľŀł",
                      "r": "ŕŗř", "t": "ţťŧ", "d": "ďđ", "h": "ĥħ", "j": "ĵ", "k": "ķ", "w": "ŵ"]
        for (plain, accented) in groups {
            for letter in accented { table[letter] = plain }
        }
        return table
    }()

    /// True when `word` is `target`, or, for words of 6 or more letters, one letter away from it
    /// (one wrong, missing, extra or swapped letter). Common words that sit one letter from a
    /// danger word ("sitting" and "fitting", "fewer" and "fever") only ever match themselves.
    static func near(_ word: String, _ target: String) -> Bool {
        if word == target { return true }
        guard target.count >= 6, abs(word.count - target.count) <= 1, !exactOnly.contains(word) else { return false }
        return withinOneEdit(Array(word), Array(target))
    }

    /// Everyday words one letter from a danger word.
    static let exactOnly: Set<String> = [
        "sitting", "setting", "getting", "letting", "putting", "fitted", "feeling", "breathe", "seated", "wailing",
        "mailing", "sailing", "bathing", "loading", "reading", "leading", "heading", "seeding", "weeding", "wedding",
        "bleeping", "sleeping", "creeping", "keeping", "smiling", "bumping", "lumping", "dumping", "pumping",
    ]

    private static func withinOneEdit(_ a: [Character], _ b: [Character]) -> Bool {
        if a.count == b.count {
            let differences = a.indices.filter { a[$0] != b[$0] }
            if differences.count <= 1 { return true }
            // Two neighbouring letters swapped.
            return differences.count == 2 && differences[1] == differences[0] + 1
                && a[differences[0]] == b[differences[1]] && a[differences[1]] == b[differences[0]]
        }
        let (long, short) = a.count > b.count ? (a, b) : (b, a)
        var i = 0
        var j = 0
        var skipped = false
        while i < long.count, j < short.count {
            if long[i] == short[j] {
                i += 1
                j += 1
            } else {
                if skipped { return false }
                skipped = true
                i += 1
            }
        }
        return true
    }

    /// True when the phrase's words appear in order in `words`, each within 4 words of the one
    /// before ("no wet nappy" also finds "no proper wet nappy", "sick … green" finds "sick and it
    /// was green").
    static func contains(_ words: [String], phrase: [String], fuzzy: Bool) -> Bool {
        guard let first = phrase.first else { return false }
        func matches(_ word: String, _ target: String) -> Bool { fuzzy ? near(word, target) : word == target }
        for start in words.indices where matches(words[start], first) {
            var position = start
            var found = true
            for target in phrase.dropFirst() {
                let window = (position + 1)..<min(words.count, position + 5)
                guard let next = window.first(where: { matches(words[$0], target) }) else {
                    found = false
                    break
                }
                position = next
            }
            if found { return true }
        }
        return false
    }
}

// MARK: Danger signs

/// The signs on the NHS's urgent list (A2). Any one of them opens the Get help now card.
public enum DangerSign: String, Hashable, Sendable, CaseIterable {
    case temperature
    case noWee
    case hardToWake
    case breathing
    case colour
    case rash
    case cry
    case fit
    case notFeeding
    case jaundice
    case vomit
    case softSpot
    case blood
    case injury
    case seriouslyUnwell
}

public enum DangerSigns {
    /// The danger signs in a parent's words; empty when there are none. Checked before any AI.
    public static func check(_ text: String) -> [DangerSign] {
        let words = WordReader.words(text)
        // Also read with each "isnt" as "is not", "cant" as "can not" and so on, so "she isn't
        // breathing" meets "not breathing" (Codex review of doc 15, step 3, 1). Read both ways: the
        // phrase lists also hold the short forms ("isnt wet").
        let opened = expandingNegatives(words)
        var found: [DangerSign] = []
        for sign in DangerSign.allCases {
            let hit = (phrases[sign] ?? []).contains {
                WordReader.contains(words, phrase: $0, fuzzy: true) || WordReader.contains(opened, phrase: $0, fuzzy: true)
            } || (sign == .temperature && mentionsATemperature(words))
            if hit { found.append(sign) }
        }
        return found
    }

    /// The words with each short negative opened: "isnt" is "is not", "cant" "can not", "wont"
    /// "will not".
    static func expandingNegatives(_ words: [String]) -> [String] {
        let special = ["cant": ["can", "not"], "wont": ["will", "not"], "shant": ["shall", "not"], "aint": ["is", "not"]]
        return words.flatMap { word -> [String] in
            if let opened = special[word] { return opened }
            if word.count > 3, word.hasSuffix("nt"), ["isnt", "arent", "wasnt", "werent", "doesnt", "dont", "didnt", "hasnt",
                                                      "havent", "hadnt", "couldnt", "wouldnt", "shouldnt", "mustnt"].contains(word) {
                return [String(word.dropLast(2)), "not"]
            }
            return [word]
        }
    }

    /// A reading from 35 to 43 with a decimal point, or next to "c", "deg", "degrees" or "temp":
    /// any temperature counts, at any age (O2: the NHS's words on the card carry the limits).
    static func mentionsATemperature(_ words: [String]) -> Bool {
        let near = ["c", "deg", "degree", "degrees", "celsius", "centigrade", "temp", "temperature", "thermometer"]
        for (index, word) in words.enumerated() {
            guard let value = Double(word), value >= 35, value < 44 else { continue }
            if word.contains(".") { return true }
            let around = words[max(0, index - 3)..<min(words.count, index + 3)]
            if around.contains(where: { near.contains($0) }) { return true }
        }
        return false
    }

    /// Each sign's phrases, as words (see `WordReader`). Negation is ignored on purpose: "not blue"
    /// still opens the card.
    static let phrases: [DangerSign: [[String]]] = {
        func p(_ list: String...) -> [[String]] { list.map { $0.split(separator: " ").map(String.init) } }
        return [
            .temperature: p("temperature", "temp", "fever", "feverish", "febrile", "hot", "burning up", "boiling",
                            "high temperature", "feels cold", "very cold", "cold to touch", "freezing", "shivering",
                            "thermometer", "clammy", "damp skin", "shivery"),
            .noWee: p("no wee", "no wees", "no pee", "no pees", "no wet", "not weed", "not peed", "hasnt weed",
                      "hasnt peed", "not had a wet", "hasnt had a wet", "not had any wet", "dry nappy", "dry nappies",
                      "nappy dry", "nappies dry", "nappy is dry", "nappies are dry", "not wet", "isnt wet", "arent wet", "no urine", "not urinated",
                      "no wet nappy", "no wet nappies", "stopped weeing", "not weeing", "not peeing", "wont wee",
                      "not had a pee", "hasnt had a pee", "not had a wee", "hasnt had a wee", "had no pee", "had no wee",
                      "not had any pee", "not had any wee", "no pee in", "no wee in", "not done a wee", "not done a pee"),
            // The passive forms too: the NHS's own list says "cannot be woken" (Codex step 4 review, 1).
            .hardToWake: p("hard to wake", "wont wake", "cant wake", "cannot wake", "difficult to wake", "wont wake up",
                           "be woken", "cant be woken", "cannot be woken", "wont be woken", "unable to wake", "not able to wake",
                           "couldnt wake", "could not wake", "can not wake",
                           "not waking", "very sleepy", "really sleepy", "so sleepy", "too sleepy", "unusually sleepy",
                           "floppy", "limp", "unresponsive", "not responding", "doesnt respond", "drowsy", "lethargic",
                           "listless", "keeps falling asleep", "barely awake", "out of it", "not reacting", "no interest",
                           "not interested in anything", "stiff neck", "cant turn head", "not moving arm", "not moving leg",
                           "very agitated"),
            .breathing: p("breathing fast", "fast breathing", "breathing quickly", "rapid breathing", "grunting", "grunts",
                          "grunt", "struggling to breathe", "struggling for breath", "cant breathe", "not breathing",
                          "stopped breathing", "breathing funny", "breathing strange", "breathing weird", "breathless",
                          "wheezing", "wheezy", "gasping", "sucking in", "ribs sucking", "pauses in breathing",
                          "pause in breathing", "apnoea", "apnea", "noisy breathing", "breathing noisy", "flaring",
                          "short of breath", "breathing hard", "laboured breathing", "labored breathing", "choking", "choked",
                          "bleating", "nostrils flaring", "flaring nostrils", "irregular breathing", "breathing irregular",
                          "nodding head", "suck in tummy", "sucking in tummy", "tummy sucking in"),
            .colour: p("blue", "bluish", "grey", "gray", "greyish", "blotchy", "mottled", "pale", "ashen", "purple",
                       "dusky", "white lips", "lips white", "colour change", "changed colour", "turned colour"),
            .rash: p("rash", "spots that dont fade", "doesnt fade", "dont fade", "glass test", "purple spots",
                     "red spots", "non blanching", "blotches", "pin prick", "pinprick", "bruising", "bruises", "peeling",
                     "blistered", "blisters"),
            .cry: p("high pitched", "highpitched", "weak cry", "constant crying", "crying constantly", "crying non stop",
                    "non stop crying", "wont stop crying", "cant stop crying", "screaming non stop", "inconsolable",
                    "screaming for hours", "crying for hours", "moaning", "whimpering", "unusual cry", "strange cry",
                    "different cry", "shrieking", "wailing", "normal cry", "cry sounds different", "cry sounds strange",
                    "cry sounds odd", "cry does not sound", "cry doesnt sound", "continuous cry"),
            .fit: p("fit", "fits", "fitting", "seizure", "seizures", "convulsion", "convulsions", "convulsing",
                    "jerking", "twitching", "shaking", "stiffening", "went stiff", "gone stiff", "eyes rolling",
                    "rolling eyes", "eyes rolled", "spasm", "spasms", "fitted"),
            .notFeeding: p("not feeding", "wont feed", "refusing feeds", "refusing to feed", "refused feeds",
                           "refusing the bottle", "refusing bottles", "refusing the breast", "not eating", "wont eat",
                           "stopped feeding", "not drinking", "wont drink", "not interested in feeding",
                           "not taking feeds", "not taking milk", "wont take", "not latching", "cant feed",
                           "too weak to feed", "feeding less", "hardly feeding", "barely feeding", "not had a feed",
                           "no feeds", "not fed"),
            .jaundice: p("jaundice", "jaundiced", "yellow skin", "skin yellow", "skin is yellow", "yellow eyes",
                         "eyes yellow", "whites of eyes", "looks yellow", "turning yellow", "gone yellow", "yellowish skin",
                         "pale poo", "pale poos", "white poo", "chalky", "grey poo", "clay", "creamy poo", "pale creamy", "dark wee", "dark pee",
                         "dark yellow wee", "dark yellow pee",
                         "dark urine", "brown wee", "orange wee"),
            .vomit: p("green vomit", "green sick", "vomiting green", "sick green", "bile", "bilious", "projectile",
                      "vomiting blood", "blood in vomit", "blood in sick", "keeps being sick", "cant keep anything down",
                      "vomiting everything", "sick after every feed", "vomiting a lot", "throwing up everything",
                      "being sick a lot", "red vomit", "black vomit", "brown vomit", "red sick", "black sick", "brown sick",
                      "swollen tummy", "bloated tummy", "hard tummy"),
            .softSpot: p("soft spot", "fontanelle", "fontanel", "bulging", "sunken", "swollen head", "bump on head"),
            .blood: p("blood", "bloody", "bleeding", "black poo", "red poo", "blood in poo", "blood in nappy",
                      "blood in her nappy", "blood in his nappy"),
            .injury: p("fell off", "fell out", "fell down", "fell from", "had a fall", "fallen off", "fallen out", "rolled off",
                       "dropped her", "dropped him", "dropped the baby", "hit her head",
                       "hit his head", "banged head", "head injury", "swallowed", "poison", "poisoned", "choked",
                       "burn", "burnt", "burned", "scalded", "scald", "allergic reaction", "swelling", "swollen lips",
                       "swollen face", "swollen tongue", "swollen throat", "difficulty swallowing", "cant swallow",
                       "hot swollen joint", "seriously injured"),
            .seriouslyUnwell: p("seriously ill", "very ill", "really ill", "very unwell", "really unwell", "seriously unwell",
                                "something is wrong", "something wrong", "something not right", "not herself", "not himself",
                                "emergency", "ambulance", "999", "111", "a and e", "a e", "dying", "collapsed",
                                "passed out", "fainted", "meningitis", "sepsis", "dehydrated", "dehydration", "cold hands",
                                "cold feet", "cold hands and feet", "sunken eyes", "dry mouth", "no tears", "smelly wee", "smelly pee",
                                "not had a drink"),
        ]
    }()
}

// MARK: Medicine questions

/// A question about a medicine: it is answered on the phone, never by the AI (D6, O3).
public struct MedicineQuestion: Hashable, Sendable {
    /// The household's medicine the question names, as written in its list; nil when it names
    /// none of them.
    public var medicine: String?
    /// The question asks when one was last given ("When did she last have Vitamin D?"). The phone
    /// answers that from the log; anything else gets the fixed reply.
    public var asksWhenLastGiven: Bool
}

public enum MedicineQuestions {
    static let medicineWords = [
        "medicine", "medicines", "medication", "medications", "calpol", "paracetamol", "ibuprofen", "nurofen",
        "dose", "doses", "dosage", "dosing", "vitamin", "vitamins", "drops", "gripe", "infacol", "colief", "gaviscon",
        "antibiotic", "antibiotics", "syrup", "suppository", "prescription", "prescribed", "medicated", "tablet",
        "teething gel", "gel", "inhaler", "mg",
    ]

    /// Nil when the question isn't about a medicine. `medicines` is the household's list
    /// (`HouseholdData.medicines`).
    public static func check(_ text: String, medicines: [String]) -> MedicineQuestion? {
        let words = WordReader.words(text)
        let named = medicines.first { name in
            let nameWords = WordReader.words(name)
            return !nameWords.isEmpty && WordReader.contains(words, phrase: nameWords, fuzzy: true)
        }
        let general = medicineWords.contains { word in
            WordReader.contains(words, phrase: word.split(separator: " ").map(String.init), fuzzy: true)
        }
        guard named != nil || general else { return nil }
        // Only a question that looks back gets the logged time; one that looks ahead ("When can I
        // give …?", "… again?", "How much …?") or is unclear gets the fixed reply (step 3 X4: the
        // app never times a dose, A5).
        let looksBack = words.contains { lookingBack.contains($0) }
        let looksAhead = words.contains { lookingAhead.contains($0) }
        return MedicineQuestion(medicine: named, asksWhenLastGiven: named != nil && looksBack && !looksAhead)
    }

    static let lookingBack: Set<String> = ["last", "did", "was", "were", "given", "gave", "had", "since"]
    static let lookingAhead: Set<String> = [
        "can", "could", "should", "shall", "will", "would", "may", "might", "next", "again", "until", "till", "safe",
        "allowed", "ok", "okay", "much", "many", "often", "dose", "doses", "more", "another", "before", "after",
    ]
}

// MARK: - The answer checker

/// What a fact or pattern measures. A closed list: the AI can only point to these.
public enum Measure: String, Hashable, Sendable, Codable, CaseIterable {
    // A day's (or, where it says so, a night's).
    case feeds, breastFeeds, bottleFeeds, bottleML, pumpSessions, pumpedML
    case sleep, daySleep, nightSleep
    case wees, poos, baths
    case longestGap, shortestGap
    // A night's.
    case slept, longestSleep, longestSleepStart, wakeUps
    // The latest weight, and its change since the one before.
    case weight, weightChange

    enum Unit { case count, seconds, ml, time, grams, gramsChange }

    var unit: Unit {
        switch self {
        case .feeds, .breastFeeds, .bottleFeeds, .pumpSessions, .wees, .poos, .baths, .wakeUps: .count
        case .sleep, .daySleep, .nightSleep, .longestGap, .shortestGap, .slept, .longestSleep: .seconds
        case .bottleML, .pumpedML: .ml
        case .longestSleepStart: .time
        case .weight: .grams
        case .weightChange: .gramsChange
        }
    }

    /// The kind of entry it is about, for its NHS passages.
    public var kind: InsightKind {
        switch self {
        case .feeds, .breastFeeds, .bottleFeeds, .bottleML, .longestGap, .shortestGap: .feed
        case .pumpSessions, .pumpedML: .pump
        case .sleep, .daySleep, .nightSleep, .slept, .longestSleep, .longestSleepStart, .wakeUps: .sleep
        case .wees, .poos: .nappy
        case .baths: .bath
        case .weight, .weightChange: .weight
        }
    }
}

/// Where a fact is: a day, a night (named by its evening), or the latest weight.
public enum FactScope: Hashable, Sendable, Codable {
    case yesterday
    case lastNight
    case day(PlainDate)
    case night(PlainDate)
    case latest
}

/// A fact the AI points to. The checker reads its value from the facts sheet and writes it in.
public struct FactRef: Hashable, Sendable, Codable {
    public var scope: FactScope
    public var measure: Measure

    public init(_ scope: FactScope, _ measure: Measure) {
        self.scope = scope
        self.measure = measure
    }
}

/// A sentence the AI writes, with "{1}", "{2}" and so on where the facts go, in order.
public struct ProposedLine: Hashable, Sendable, Codable {
    public var template: String
    public var facts: [FactRef]

    public init(_ template: String, facts: [FactRef] = []) {
        self.template = template
        self.facts = facts
    }
}

/// The shapes of pattern the checker can check (R5). A pattern of another shape is left out.
public enum PatternShape: String, Hashable, Sendable, Codable, CaseIterable {
    /// The measure's average over `recent` is higher (or lower) than over `earlier`.
    /// Placeholders: {recent}, {earlier}.
    case higher, lower
    /// `recent` is one day or night, the most (or least) of the stretch `earlier`, which holds it.
    /// Placeholders: {value}, {when}, {days}.
    case most, least
    /// Every day or night of `recent` (3 or more) rose (or fell) from the one before.
    /// Placeholders: {days}.
    case risingRun, fallingRun
    /// Every day or night of `recent` (3 or more) was within 15% of their average.
    /// Placeholders: {low}, {high}, {days}.
    case steady
    /// On most of the nights of `recent` with a bath that evening, the night's longest sleep began
    /// within 2 hours after the bath (measure `longestSleep`). Placeholders: {count}, {of}.
    case comesAfter

    var isFall: Bool { self == .lower || self == .least || self == .fallingRun }
}

/// Some days, or some nights named by their evenings, first to last.
public struct DateSpan: Hashable, Sendable, Codable {
    public var first: PlainDate
    public var last: PlainDate

    public init(_ first: PlainDate, _ last: PlainDate) {
        self.first = first
        self.last = last
    }

    var dates: [PlainDate] {
        guard last >= first else { return [] }
        return (0...last.days(since: first)).map { first.adding(days: $0) }
    }
}

/// A pattern the AI found, in the fixed form, with its sentence.
public struct PatternClaim: Hashable, Sendable, Codable {
    public var shape: PatternShape
    public var measure: Measure
    /// Nights (named by their evenings) rather than days.
    public var nights: Bool
    public var recent: DateSpan
    public var earlier: DateSpan?
    public var template: String

    public init(_ shape: PatternShape, _ measure: Measure, nights: Bool = false, recent: DateSpan, earlier: DateSpan? = nil,
                template: String) {
        self.shape = shape
        self.measure = measure
        self.nights = nights
        self.recent = recent
        self.earlier = earlier
        self.template = template
    }
}

/// An NHS passage the AI picks for the card, with one of its checked summaries, by ID.
public struct PassageChoice: Hashable, Sendable, Codable {
    public var passageID: String
    public var summaryID: String?

    public init(_ passageID: String, summary: String? = nil) {
        self.passageID = passageID
        summaryID = summary
    }
}

/// Everything the AI fills in for a card: its fixed form.
public struct CardProposal: Hashable, Sendable, Codable {
    public var lines: [ProposedLine]
    public var patterns: [PatternClaim]
    public var passages: [PassageChoice]
    /// The AI's own "needs help now" flag: a second net behind the danger-sign check (A2).
    public var needsHelpNow: Bool

    public init(lines: [ProposedLine], patterns: [PatternClaim] = [], passages: [PassageChoice] = [],
                needsHelpNow: Bool = false) {
        self.lines = lines
        self.patterns = patterns
        self.passages = passages
        self.needsHelpNow = needsHelpNow
    }
}

/// A pattern the AI chose for a card: its fixed form only. The app writes its sentence (step 2 D9).
public struct PatternChoice: Hashable, Sendable, Codable {
    public var shape: PatternShape
    public var measure: Measure
    /// Nights (named by their evenings) rather than days.
    public var nights: Bool
    public var recent: DateSpan
    public var earlier: DateSpan?

    public init(_ shape: PatternShape, _ measure: Measure, nights: Bool = false, recent: DateSpan, earlier: DateSpan? = nil) {
        self.shape = shape
        self.measure = measure
        self.nights = nights
        self.recent = recent
        self.earlier = earlier
    }
}

/// Everything the AI chooses for a card (step 2 D9, Codex's O1): which facts and patterns to show,
/// in what order, and a checked summary for each offered NHS passage. It writes no words: every
/// sentence on a card is the app's (`CardWording`), so a true number can never sit in a false
/// sentence.
public struct CardChoices: Hashable, Sendable, Codable {
    public var facts: [FactRef]
    public var patterns: [PatternChoice]
    public var passages: [PassageChoice]

    public init(facts: [FactRef], patterns: [PatternChoice] = [], passages: [PassageChoice] = []) {
        self.facts = facts
        self.patterns = patterns
        self.passages = passages
    }
}

/// An NHS passage on a checked card, with the summary chosen for it, if any.
public struct CheckedPassage: Hashable, Sendable {
    public let passage: Passage
    public let summary: PassageSummary?
}

/// A card the checker passed: the only thing a screen may show of the AI's words. Only
/// `AnswerCheck` can make one.
public struct CheckedCard: Hashable, Sendable {
    public let lines: [String]
    public let patterns: [String]
    public let passages: [CheckedPassage]
    public let needsHelpNow: Bool
    /// The facts sheet it was made from: a newer revision means it is made again (O4).
    public let factsRevision: UInt64
    /// On a card (step 2), the fact behind each of `lines` and the pattern behind each of
    /// `patterns`, in the same order: the card shows each under its day or night and opens its
    /// graph. Empty for Ask's answers.
    public let factRefs: [FactRef]
    public let patternChoices: [PatternChoice]

    fileprivate init(lines: [String], patterns: [String], passages: [CheckedPassage], needsHelpNow: Bool,
                     factsRevision: UInt64, factRefs: [FactRef] = [], patternChoices: [PatternChoice] = []) {
        self.lines = lines
        self.patterns = patterns
        self.passages = passages
        self.needsHelpNow = needsHelpNow
        self.factsRevision = factsRevision
        self.factRefs = factRefs
        self.patternChoices = patternChoices
    }
}

/// Why the checker turned a card down. After a second turn-down the app shows plain fact cards.
public struct Rejection: Hashable, Sendable {
    public enum Reason: Error, Hashable, Sendable {
        /// A number, a number word or a unit in the AI's own words (A1).
        case number(String)
        /// A clock time, a weekday, a month or a "tonight" in the AI's own words.
        case dateOrTime(String)
        /// A word on the banned list: a verdict, urgency, people to call, a medicine or dose, a
        /// cause, a target, blame or a prediction.
        case banned(String)
        case unknownPlaceholder(String)
        /// A fact the sheet doesn't have, or a measure that doesn't belong to its scope.
        case unknownFact
        case unknownPassage(String)
        case unknownSummary(String)
        /// A pattern whose days aren't all on the sheet, or don't fit its shape.
        case patternSpan
        /// A pattern the facts don't bear out (R5).
        case patternUntrue
        /// A day or night in a pattern about amounts has a bottle, pump or nappy with no amount or
        /// unread details (O6).
        case incompleteDays
        /// A fall across a day or night with a long stretch of nothing logged (R6).
        case emptyStretch
        /// Its numbers would read the same when written, so the sentence would read as untrue.
        case readsTheSame
        case tooLong
        case tooMany
    }

    public var part: String
    public var reason: Reason
}

public enum AnswerVerdict: Hashable, Sendable {
    case accepted(CheckedCard)
    /// Turned down. The AI's "needs help now" flag is passed on all the same (O2).
    case rejected([Rejection], needsHelpNow: Bool)
}

public enum AnswerCheck {
    static let maxLines = 3
    static let maxPatterns = 3
    static let maxPassages = 2
    static let maxLength = 240
    /// A fall is left out across a day with an empty stretch this long, or a night with one this
    /// long (R6): a forgotten entry looks like this.
    static let longEmptyDay: TimeInterval = 6 * 3600
    static let longEmptyNight: TimeInterval = 4 * 3600
    /// How close after the bath a night's longest sleep must begin for "comes after".
    static let afterBath: TimeInterval = 2 * 3600

    /// Checks the AI's card against the facts sheet it was made from. `checks` are Parent A's
    /// passage checks; `timeZone` is the household's, for writing times.
    public static func accept(_ proposal: CardProposal, facts: InsightFacts, checks: PassageChecks,
                              timeZone: TimeZone) -> AnswerVerdict {
        var problems: [Rejection] = []
        func reject(_ part: String, _ reason: Rejection.Reason) { problems.append(Rejection(part: part, reason: reason)) }

        if proposal.lines.isEmpty || proposal.lines.count > maxLines { reject("lines", .tooMany) }
        if proposal.patterns.count > maxPatterns { reject("patterns", .tooMany) }
        if proposal.passages.count > maxPassages { reject("passages", .tooMany) }

        var lines: [String] = []
        for (index, line) in proposal.lines.enumerated() {
            let part = "line \(index + 1)"
            let values = line.facts.map { value($0, in: facts, timeZone: timeZone) }
            if values.contains(where: { $0 == nil }) { reject(part, .unknownFact) }
            let names = Dictionary(uniqueKeysWithValues: values.enumerated().map { ("\($0.offset + 1)", $0.element ?? "") })
            switch fill(line.template, with: names) {
            case .success(let text): lines.append(text)
            case .failure(let reason): reject(part, reason)
            }
        }

        var patterns: [String] = []
        for (index, claim) in proposal.patterns.enumerated() {
            let part = "pattern \(index + 1)"
            switch check(claim, facts: facts, timeZone: timeZone) {
            case .success(let names):
                switch fill(claim.template, with: names) {
                case .success(let text): patterns.append(text)
                case .failure(let reason): reject(part, reason)
                }
            case .failure(let reason): reject(part, reason)
            }
        }

        let patternKinds = Set(proposal.patterns.map(\.measure.kind))
        let allowed: [Passage] = facts.today.map { today in
            NHSPassages.choose(kinds: facts.kindsLogged.union(patternKinds), ageInDays: facts.ageInDays,
                               breastfeeds: facts.days.contains { $0.breastFeeds > 0 },
                               bottleFeeds: facts.days.contains { $0.bottleFeeds > 0 },
                               checks: checks, today: today, limit: Int.max)
        } ?? []
        var passages: [CheckedPassage] = []
        for choice in proposal.passages {
            guard let passage = allowed.first(where: { $0.id == choice.passageID }) else {
                reject("passage", .unknownPassage(choice.passageID))
                continue
            }
            var summary: PassageSummary?
            if let summaryID = choice.summaryID {
                summary = facts.today.flatMap { today in
                    NHSPassages.checkedSummaries(of: passage, checks: checks, today: today).first { $0.id == summaryID }
                }
                if summary == nil { reject("passage", .unknownSummary(summaryID)) }
            }
            passages.append(CheckedPassage(passage: passage, summary: summary))
        }

        guard problems.isEmpty else { return .rejected(problems, needsHelpNow: proposal.needsHelpNow) }
        return .accepted(CheckedCard(lines: lines, patterns: patterns, passages: passages,
                                     needsHelpNow: proposal.needsHelpNow, factsRevision: facts.revision))
    }

    // MARK: A card from the AI's choices (step 2 D9)

    static let maxFacts = 6

    /// Checks the AI's choices for a card and writes every sentence from the app's own wording.
    /// `offered` are the passages chosen by code for this card (O6): only they may appear, each
    /// still ticked, a `shownWith` partner with its lead, never both of a "not with" pair.
    ///
    /// `leaveOut` false (making a card): any problem turns the whole card down, so the AI tries
    /// again. `leaveOut` true (showing a stored card on a later look, or on the other phone): a
    /// fact or pattern that no longer holds on this phone's log is left out on its own (R5, O3),
    /// and the card is turned down only when nothing is left.
    /// `allowNoFacts` (Ask, step 3): an answer may hold only NHS passages and the AI's sentences.
    public static func accept(_ choices: CardChoices, offered: [String], facts: InsightFacts, checks: PassageChecks,
                              timeZone: TimeZone, leaveOut: Bool = false, allowNoFacts: Bool = false,
                              today: PlainDate? = nil) -> AnswerVerdict {
        var problems: [Rejection] = []
        func reject(_ part: String, _ reason: Rejection.Reason) { problems.append(Rejection(part: part, reason: reason)) }

        if !allowNoFacts && choices.facts.isEmpty && choices.patterns.isEmpty { reject("facts", .tooMany) }
        if choices.facts.count > maxFacts { reject("facts", .tooMany) }
        if choices.patterns.count > maxPatterns { reject("patterns", .tooMany) }
        if choices.passages.count > maxPassages { reject("passages", .tooMany) }
        if Set(choices.facts).count != choices.facts.count || Set(choices.patterns).count != choices.patterns.count {
            reject("facts", .tooMany)
        }

        var lines: [String] = []
        var factRefs: [FactRef] = []
        for (index, ref) in choices.facts.enumerated() {
            if let sentence = CardWording.fact(ref, facts: facts, timeZone: timeZone) {
                lines.append(sentence)
                factRefs.append(ref)
            } else if !leaveOut {
                reject("fact \(index + 1)", .unknownFact)
            }
        }

        var patterns: [String] = []
        var patternChoices: [PatternChoice] = []
        for (index, choice) in choices.patterns.enumerated() {
            let claim = PatternClaim(choice.shape, choice.measure, nights: choice.nights, recent: choice.recent,
                                     earlier: choice.earlier, template: "")
            switch check(claim, facts: facts, timeZone: timeZone) {
            case .success(let names):
                patterns.append(CardWording.pattern(choice, names: names, facts: facts))
                patternChoices.append(choice)
            case .failure(let reason):
                if !leaveOut { reject("pattern \(index + 1)", reason) }
            }
        }

        var passages: [CheckedPassage] = []
        // A household with nothing logged before today has no sheet day: Ask passes today's date.
        let today = facts.today ?? today
        for choice in choices.passages {
            guard offered.contains(choice.passageID), let passage = NHSPassages.passage(choice.passageID), let today,
                  NHSPassages.isChecked(passage.id, copied: passage.copied, checks: checks, today: today) else {
                if !leaveOut { reject("passage", .unknownPassage(choice.passageID)) }
                continue
            }
            var summary: PassageSummary?
            if let summaryID = choice.summaryID {
                summary = NHSPassages.checkedSummaries(of: passage, checks: checks, today: today).first { $0.id == summaryID }
                if summary == nil && !leaveOut { reject("passage", .unknownSummary(summaryID)) }
            }
            passages.append(CheckedPassage(passage: passage, summary: summary))
        }
        // A passage that must come with another (`shownWith`) goes if its partner can't come; a
        // "not with" pair never shows together (step 2 D6): the later one goes.
        let shownIDs = Set(passages.map(\.passage.id))
        passages.removeAll { item in
            guard let partner = NHSPassages.shownWith[item.passage.id], !shownIDs.contains(partner) else { return false }
            if !leaveOut { reject("passage", .unknownPassage(partner)) }
            return true
        }
        var kept: [CheckedPassage] = []
        for item in passages {
            if kept.contains(where: { NHSPassages.notTogether($0.passage.id, item.passage.id) }) {
                if !leaveOut { reject("passage", .unknownPassage(item.passage.id)) }
                continue
            }
            kept.append(item)
        }

        if leaveOut, !allowNoFacts, lines.isEmpty, patterns.isEmpty { reject("facts", .unknownFact) }
        guard problems.isEmpty else { return .rejected(problems, needsHelpNow: false) }
        return .accepted(CheckedCard(lines: lines, patterns: patterns, passages: kept, needsHelpNow: false,
                                     factsRevision: facts.revision, factRefs: factRefs, patternChoices: patternChoices))
    }

    // MARK: The AI's own words

    /// Puts the values in place of the placeholders, after checking the AI's own words.
    static func fill(_ template: String, with values: [String: String]) -> Result<String, Rejection.Reason> {
        if template.count > maxLength { return .failure(.tooLong) }
        var own = ""
        var filled = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            own += rest[..<open]
            filled += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else { return .failure(.unknownPlaceholder("{")) }
            let name = String(rest[rest.index(after: open)..<close])
            guard let value = values[name] else { return .failure(.unknownPlaceholder(name)) }
            own += " "
            filled += value
            rest = rest[rest.index(after: close)...]
        }
        own += rest
        filled += rest
        if own.contains("}") { return .failure(.unknownPlaceholder("}")) }
        if let problem = wordProblem(own) { return .failure(problem) }
        return .success(filled.trimmingCharacters(in: .whitespaces))
    }

    /// The first problem with the AI's own words, if any.
    static func wordProblem(_ text: String) -> Rejection.Reason? {
        if let digit = text.first(where: { $0.isNumber }) { return .number(String(digit)) }
        let words = WordReader.words(text)
        if let word = words.first(where: numberWords.contains) { return .number(word) }
        if let word = words.first(where: dateWords.contains) { return .dateOrTime(word) }
        for phrase in banned where WordReader.contains(words, phrase: phrase, fuzzy: false) {
            return .banned(phrase.joined(separator: " "))
        }
        return nil
    }

    static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
        "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty",
        "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "dozen", "dozens", "twice", "thrice",
        "half", "quarter", "once", "double", "triple", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth",
        "ninth", "tenth", "couple", "several", "few", "pair",
        // Units: an amount is written by the app, never by the AI.
        "ml", "mls", "millilitre", "millilitres", "oz", "ounce", "ounces", "kg", "kilo", "kilos", "gram", "grams", "pound",
        "pounds", "lb", "lbs", "hour", "hours", "hr", "hrs", "minute", "minutes", "min", "mins", "percent",
    ]

    static let dateWords: Set<String> = [
        "midnight", "noon", "midday", "oclock", "am", "pm", "tonight", "tomorrow",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november",
        "december",
    ]

    /// Words the AI may never write. Each group is a decision: verdicts and targets (A3, D5),
    /// urgency and people to call (A2: fixed code does that), medicines and doses (A5, D6),
    /// causes and diagnoses (D5: Anthropic's usage policy), blame (D9), predictions (A10), and
    /// crediting the NHS (A4).
    static let banned: [[String]] = {
        let phrases = [
            // Verdicts and targets.
            "normal", "abnormal", "fine", "ok", "okay", "healthy", "unhealthy", "unwell", "ill", "sick", "poorly",
            "going well", "feeding well", "doing well", "sleeping well", "well fed", "enough", "plenty", "too few",
            // How a baby is, the calm way (Codex step 4 review, 6).
            "appears well", "appear well", "looks well", "look well", "seems well", "seem well", "is well", "are well",
            "thriving", "thrive", "all is well",
            "too many", "too much", "too little", "low", "high", "below", "above", "average", "typical", "expected",
            "usual", "usually", "good", "bad", "poor", "great", "excellent", "perfect", "reassuring", "worrying",
            "worry", "worried", "concern", "concerning", "should have", "needs more", "needs to", "recommended",
            "recommend", "target", "goal", "guideline", "on track", "behind", "ahead", "missed", "overdue", "due",
            // Urgency and people: fixed code shows these, never the AI.
            "urgent", "urgently", "emergency", "immediately", "straight away", "right away", "asap", "call", "ring",
            "phone", "contact", "doctor", "gp", "midwife", "health visitor", "nurse", "pharmacist", "hospital",
            "a e", "ambulance", "see someone", "get help", "seek",
            // Medicines and doses.
            "dose", "doses", "dosage", "medicine", "medicines", "medication", "calpol", "paracetamol", "ibuprofen",
            "vitamin", "drops", "mg",
            // Causes and diagnoses.
            "infection", "colic", "reflux", "jaundice", "dehydrated", "dehydration", "allergy", "allergic",
            "intolerance", "tongue tie", "teething", "growth spurt", "cluster feeding", "regression", "illness",
            "condition", "symptom", "symptoms", "diagnose", "diagnosis", "sign of", "signs of", "caused by",
            "because", "due to", "means", "probably", "likely", "maybe", "might be", "could be", "suggests",
            "indicates", "hungry", "hunger", "tired", "overtired", "uncomfortable", "pain", "wind",
            // Blame between the parents.
            "fair", "unfair", "more than you", "did most", "your turn", "lazy",
            // Predictions.
            "will sleep", "will feed", "will wake", "next feed", "expect",
            // Crediting the NHS: only the passages, with their credit.
            "nhs",
        ]
        return phrases.map { WordReader.words($0) }
    }()

    // MARK: Facts

    /// A fact's value, written as the app writes it; nil when the sheet doesn't have it.
    static func value(_ ref: FactRef, in facts: InsightFacts, timeZone: TimeZone) -> String? {
        number(ref, in: facts).map { write($0, unit: ref.measure.unit, timeZone: timeZone) }
    }

    static func number(_ ref: FactRef, in facts: InsightFacts) -> Double? {
        switch ref.scope {
        case .yesterday: facts.yesterday.flatMap { dayValue(ref.measure, $0) }
        case .day(let date): facts.days.first { $0.date == date }.flatMap { dayValue(ref.measure, $0) }
        case .lastNight: facts.lastNight.flatMap { nightValue(ref.measure, $0) }
        case .night(let evening): facts.nights.first { $0.evening == evening }.flatMap { nightValue(ref.measure, $0) }
        case .latest:
            switch ref.measure {
            case .weight: facts.weights.last.map { Double($0.grams) }
            case .weightChange:
                facts.weights.count >= 2 ? Double(facts.weights[facts.weights.count - 1].grams
                                                  - facts.weights[facts.weights.count - 2].grams) : nil
            default: nil
            }
        }
    }

    static func dayValue(_ measure: Measure, _ day: DayFacts) -> Double? {
        switch measure {
        case .feeds: Double(day.feeds)
        case .breastFeeds: Double(day.breastFeeds)
        case .bottleFeeds: Double(day.bottleFeeds)
        case .bottleML: Double(day.formulaML + day.expressedML)
        case .pumpSessions: Double(day.pumpSessions)
        case .pumpedML: Double(day.pumpedML)
        case .sleep: day.sleepSeconds
        case .daySleep: day.daySleepSeconds
        case .nightSleep: day.nightSleepSeconds
        case .wees: Double(day.wees)
        case .poos: Double(day.poos)
        case .baths: Double(day.baths.count)
        case .longestGap: day.feedGaps.max()
        case .shortestGap: day.feedGaps.min()
        default: nil
        }
    }

    static func nightValue(_ measure: Measure, _ night: NightFacts) -> Double? {
        switch measure {
        case .feeds: Double(night.feeds)
        case .wees: Double(night.wees)
        case .poos: Double(night.poos)
        case .slept: night.sleptSeconds
        case .longestSleep: night.longestSleep?.seconds
        case .longestSleepStart: night.longestSleep?.from.timeIntervalSince1970
        case .wakeUps: Double(night.wakeUps)
        case .longestGap: night.feedGaps.max()
        default: nil
        }
    }

    /// A value as the app writes it: "9", "3h 10m", "150 ml", "23:40", "4.12 kg", "+180 g".
    static func write(_ value: Double, unit: Measure.Unit, timeZone: TimeZone) -> String {
        switch unit {
        case .count:
            return "\(Int(value.rounded()))"
        case .seconds:
            let minutes = Int((value / 60).rounded())
            let hours = minutes / 60
            let rest = minutes % 60
            if hours == 0 { return "\(rest)m" }
            return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
        case .ml:
            return "\(Int(value.rounded())) ml"
        case .time:
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let parts = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: value))
            let two = { (n: Int) in n < 10 ? "0\(n)" : "\(n)" }
            return "\(two(parts.hour ?? 0)):\(two(parts.minute ?? 0))"
        case .grams:
            let hundredths = Int((value / 10).rounded())
            let fraction = hundredths % 100
            return "\(hundredths / 100).\(fraction < 10 ? "0" : "")\(fraction) kg"
        case .gramsChange:
            let grams = Int(value.rounded())
            return grams >= 0 ? "+\(grams) g" : "-\(-grams) g"
        }
    }

    // MARK: Patterns

    /// Checks a pattern against the facts; on success, its placeholders' values.
    static func check(_ claim: PatternClaim, facts: InsightFacts, timeZone: TimeZone) -> Result<[String: String], Rejection.Reason> {
        let unit = claim.measure.unit
        guard unit != .time, unit != .grams, unit != .gramsChange else { return .failure(.patternSpan) }
        let recentDates = claim.recent.dates
        let earlierDates = claim.earlier?.dates ?? []
        guard !recentDates.isEmpty else { return .failure(.patternSpan) }

        func series(_ dates: [PlainDate]) -> [Double]? {
            var values: [Double] = []
            for date in dates {
                let scope: FactScope = claim.nights ? .night(date) : .day(date)
                guard let value = number(FactRef(scope, claim.measure), in: facts) else { return nil }
                values.append(value)
            }
            return values
        }
        let involved = Array(Set(recentDates + earlierDates)).sorted()
        guard let recent = series(recentDates), let earlier = series(earlierDates), series(involved) != nil else {
            return .failure(.patternSpan)
        }
        // Amounts and nappies only from days whose every entry has its amount and details (O6).
        if !claim.nights, involved.contains(where: { date in
            facts.days.first { $0.date == date }.map { day in incomplete(day, for: claim.measure) } ?? true
        }) {
            return .failure(.incompleteDays)
        }
        // A fall only across days and nights with no long stretch of nothing logged (R6).
        if claim.shape.isFall, involved.contains(where: { hasLongEmptyStretch($0, nights: claim.nights, facts: facts) }) {
            return .failure(.emptyStretch)
        }
        let write = { (value: Double) in AnswerCheck.write(value, unit: unit, timeZone: timeZone) }
        let mean = { (values: [Double]) in values.reduce(0, +) / Double(values.count) }

        switch claim.shape {
        case .higher, .lower:
            guard !earlier.isEmpty, let last = earlierDates.last, last < recentDates[0] else { return .failure(.patternSpan) }
            let (now, before) = (mean(recent), mean(earlier))
            guard claim.shape == .higher ? now > before : now < before else { return .failure(.patternUntrue) }
            guard write(now) != write(before) else { return .failure(.readsTheSame) }
            return .success(["recent": write(now), "earlier": write(before)])
        case .most, .least:
            guard recentDates.count == 1, earlierDates.count >= 3, earlierDates.contains(recentDates[0]) else {
                return .failure(.patternSpan)
            }
            let value = recent[0]
            let others = zip(earlierDates, earlier).filter { $0.0 != recentDates[0] }.map(\.1)
            let holds = claim.shape == .most ? others.allSatisfy { value > $0 } : others.allSatisfy { value < $0 }
            guard holds else { return .failure(.patternUntrue) }
            return .success(["value": write(value), "when": when(recentDates[0], nights: claim.nights, facts: facts),
                             "days": "\(earlierDates.count)"])
        case .risingRun, .fallingRun:
            guard recent.count >= 3 else { return .failure(.patternSpan) }
            let steps = zip(recent, recent.dropFirst())
            let holds = claim.shape == .risingRun ? steps.allSatisfy { $1 > $0 } : steps.allSatisfy { $1 < $0 }
            guard holds else { return .failure(.patternUntrue) }
            return .success(["days": "\(recent.count)"])
        case .steady:
            guard recent.count >= 3 else { return .failure(.patternSpan) }
            let average = mean(recent)
            guard average > 0, let low = recent.min(), let high = recent.max(), high - low <= average * 0.15 else {
                return .failure(.patternUntrue)
            }
            return .success(["low": write(low), "high": write(high), "days": "\(recent.count)"])
        case .comesAfter:
            guard claim.nights, claim.measure == .longestSleep else { return .failure(.patternSpan) }
            var withBath = 0
            var after = 0
            for evening in recentDates {
                guard let baths = facts.days.first(where: { $0.date == evening })?.baths, !baths.isEmpty,
                      let night = facts.nights.first(where: { $0.evening == evening }) else { continue }
                withBath += 1
                if let began = night.longestSleepBegan,
                   baths.contains(where: { began >= $0 && began.timeIntervalSince($0) <= afterBath }) {
                    after += 1
                }
            }
            guard withBath >= 2, after * 2 > withBath else { return .failure(.patternUntrue) }
            return .success(["count": "\(after)", "of": "\(withBath)"])
        }
    }

    /// A day with an entry missing its amount or details, for this measure (O6).
    static func incomplete(_ day: DayFacts, for measure: Measure) -> Bool {
        switch measure {
        case .bottleML: day.bottlesWithoutAmount > 0 || day.feedsWithUnreadDetails > 0
        case .breastFeeds, .bottleFeeds: day.feedsWithUnreadDetails > 0
        case .pumpedML: day.pumpsWithoutAmount > 0
        case .wees, .poos: day.nappiesWithUnreadDetails > 0
        default: false
        }
    }

    static func hasLongEmptyStretch(_ date: PlainDate, nights: Bool, facts: InsightFacts) -> Bool {
        if nights {
            return (facts.nights.first { $0.evening == date }?.longestEmptyStretch?.seconds ?? 0) >= longEmptyNight
        }
        return (facts.days.first { $0.date == date }?.longestEmptyStretch?.seconds ?? 0) >= longEmptyDay
    }

    /// A day or night as the app writes it: "Sunday" or "Sunday night" within the last week, and
    /// "18 November" (or "the night of 18 November") before that.
    static func when(_ date: PlainDate, nights: Bool, facts: InsightFacts) -> String {
        let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
                      "November", "December"]
        if let today = facts.today, today.days(since: date) <= 7 {
            return weekdays[date.weekday - 1] + (nights ? " night" : "")
        }
        let written = "\(date.day) \(months[date.month - 1])"
        return nights ? "the night of \(written)" : written
    }
}

// MARK: - The app's own wording for a card (step 2 D9)

/// Every sentence on a card, written by the app from the AI's choices: one fixed wording per
/// measure and per pattern shape, each with "logged" (R6), so a number always sits beside the
/// words that say what it counts, and a pattern's direction is the one the checker found.
public enum CardWording {
    /// A fact's sentence: "4 feeds logged last night." Nil when the sheet has no such fact.
    public static func fact(_ ref: FactRef, facts: InsightFacts, timeZone: TimeZone) -> String? {
        guard let number = AnswerCheck.number(ref, in: facts) else { return nil }
        let value = AnswerCheck.write(number, unit: ref.measure.unit, timeZone: timeZone)
        let one = Int(number.rounded()) == 1
        if ref.scope == .latest {
            switch ref.measure {
            case .weight: return "Latest weight logged: \(value)."
            case .weightChange: return "Change since the weight logged before it: \(value)."
            default: return nil
            }
        }
        guard let when = scope(ref.scope, facts: facts) else { return nil }
        switch ref.measure {
        case .feeds: return "\(value) \(one ? "feed" : "feeds") logged \(when)."
        case .breastFeeds: return "\(value) \(one ? "breastfeed" : "breastfeeds") logged \(when)."
        case .bottleFeeds: return "\(value) bottle \(one ? "feed" : "feeds") logged \(when)."
        case .bottleML: return "\(value) from bottles logged \(when)."
        case .pumpSessions: return "\(value) pumping \(one ? "session" : "sessions") logged \(when)."
        case .pumpedML: return "\(value) pumped and logged \(when)."
        case .sleep, .slept: return "\(value) of sleep logged \(when)."
        case .daySleep: return "\(value) of daytime sleep logged \(when)."
        case .nightSleep: return "\(value) of night-time sleep logged \(when)."
        case .wees: return "\(value) wet \(one ? "nappy" : "nappies") logged \(when)."
        case .poos: return "\(value) \(one ? "poo" : "poos") logged \(when)."
        case .baths: return "\(value) \(one ? "bath" : "baths") logged \(when)."
        case .longestGap: return "Longest gap between feed starts logged \(when): \(value)."
        case .shortestGap: return "Shortest gap between feed starts logged \(when): \(value)."
        case .longestSleep: return "Longest sleep logged \(when): \(value)."
        case .longestSleepStart: return "The longest sleep logged \(when) began at \(value)."
        case .wakeUps: return "\(value) \(one ? "wake-up" : "wake-ups") logged \(when)."
        case .weight, .weightChange: return nil
        }
    }

    /// A pattern's sentence, from the values the checker found (`AnswerCheck.check`).
    public static func pattern(_ choice: PatternChoice, names: [String: String], facts: InsightFacts) -> String {
        let per = choice.nights ? "night" : "day"
        let noun = self.noun(choice.measure)
        let recent = span(choice.recent, nights: choice.nights, facts: facts)
        switch choice.shape {
        case .higher, .lower:
            let direction = choice.shape == .higher ? "rose" : "fell"
            let earlier = choice.earlier.map { span($0, nights: choice.nights, facts: facts) } ?? ""
            return "\(noun) per \(per) \(direction): \(names["recent"] ?? "") on average over \(recent), "
                + "against \(names["earlier"] ?? "") over \(earlier)."
        case .most, .least:
            let when = AnswerCheck.when(choice.recent.first, nights: choice.nights, facts: facts)
            let stretch = choice.earlier.map { span($0, nights: choice.nights, facts: facts) } ?? recent
            return "\(noun) \(when): \(names["value"] ?? ""), \(superlative(choice.measure, most: choice.shape == .most)) "
                + "of \(stretch)."
        case .risingRun, .fallingRun:
            let direction = choice.shape == .risingRun ? "rose" : "fell"
            return "\(noun) per \(per) \(direction) every \(per) over \(recent)."
        case .steady:
            return "\(noun) per \(per) stayed between \(names["low"] ?? "") and \(names["high"] ?? "") over \(recent)."
        case .comesAfter:
            return "On \(names["count"] ?? "") of the \(names["of"] ?? "") nights with a bath logged over \(recent), "
                + "the night's longest sleep logged began within 2 hours after the bath."
        }
    }

    /// "last night", "yesterday", "on Sunday", "on the night of 18 November".
    static func scope(_ scope: FactScope, facts: InsightFacts) -> String? {
        switch scope {
        case .yesterday: return facts.yesterday == nil ? nil : "yesterday"
        case .lastNight: return facts.lastNight == nil ? nil : "last night"
        case .day(let date):
            return date == facts.yesterday?.date ? "yesterday" : "on " + AnswerCheck.when(date, nights: false, facts: facts)
        case .night(let evening):
            return evening == facts.lastNight?.evening ? "last night" : "on " + AnswerCheck.when(evening, nights: true, facts: facts)
        case .latest: return nil
        }
    }

    /// "the 4 days to Sunday", "the 7 nights to Sunday night".
    static func span(_ span: DateSpan, nights: Bool, facts: InsightFacts) -> String {
        let count = span.dates.count
        let unit = nights ? (count == 1 ? "night" : "nights") : (count == 1 ? "day" : "days")
        return "the \(count) \(unit) to \(AnswerCheck.when(span.last, nights: nights, facts: facts))"
    }

    static func noun(_ measure: Measure) -> String {
        switch measure {
        case .feeds: "Feeds logged"
        case .breastFeeds: "Breastfeeds logged"
        case .bottleFeeds: "Bottle feeds logged"
        case .bottleML: "Milk from bottles logged"
        case .pumpSessions: "Pumping sessions logged"
        case .pumpedML: "Milk pumped and logged"
        case .sleep, .slept: "Sleep logged"
        case .daySleep: "Daytime sleep logged"
        case .nightSleep: "Night-time sleep logged"
        case .wees: "Wet nappies logged"
        case .poos: "Poos logged"
        case .baths: "Baths logged"
        case .longestGap: "The longest gap between feed starts logged"
        case .shortestGap: "The shortest gap between feed starts logged"
        case .longestSleep: "The longest sleep logged"
        case .longestSleepStart: "The longest sleep's start logged"
        case .wakeUps: "Wake-ups logged"
        case .weight: "Weight logged"
        case .weightChange: "Weight change logged"
        }
    }

    static func superlative(_ measure: Measure, most: Bool) -> String {
        switch measure.unit {
        case .seconds: most ? "the longest" : "the shortest"
        case .ml: most ? "the most" : "the least"
        default: most ? "the most" : "the fewest"
        }
    }
}

// MARK: - Ask's answers (step 3)

/// An answer to a typed question that the checker passed: the only thing Ask's screen may show of
/// the AI's answer. Only `AnswerCheck` can make one.
public struct CheckedAnswer: Hashable, Sendable {
    /// "From your log": the app's sentences for the facts the AI chose (the last 7 days and
    /// nights, the latest weight, today so far).
    public let lines: [String]
    /// Up to 2 sentences of general information written by the AI (step 3 D2 B), each checked.
    public let sentences: [String]
    public let passages: [CheckedPassage]
    public let needsHelpNow: Bool
    /// The log and the NHS passages here can't answer it: the fixed line to people shows.
    public let cannotAnswer: Bool
    public let topic: QuestionTopic

    fileprivate init(lines: [String], sentences: [String], passages: [CheckedPassage], needsHelpNow: Bool,
                     cannotAnswer: Bool, topic: QuestionTopic) {
        self.lines = lines
        self.sentences = sentences
        self.passages = passages
        self.needsHelpNow = needsHelpNow
        self.cannotAnswer = cannotAnswer
        self.topic = topic
    }
}

public enum QuestionVerdict: Hashable, Sendable {
    case accepted(CheckedAnswer)
    /// Turned down. The AI's "needs help now" flag is passed on all the same (O2, Q9).
    case rejected([Rejection], needsHelpNow: Bool)
}

extension AnswerCheck {
    static let maxSentences = 2

    /// Checks the AI's answer to a typed question and writes every log sentence from the app's
    /// own wording. Facts and passages go through the cards' checks (`accept(_ choices:)`); today's
    /// facts through `QuestionWording`; the AI's own sentences through `sentenceProblem`.
    /// `leaveOut` true (the last try, and showing a kept answer again, X8): a part that fails is
    /// left out on its own; nothing that fails is ever shown.
    public static func accept(_ answer: QuestionAnswer, offered: [String], facts: InsightFacts, today: TodaySoFar,
                              checks: PassageChecks, names: [String], medicines: [String], timeZone: TimeZone,
                              leaveOut: Bool = false) -> QuestionVerdict {
        var problems: [Rejection] = []
        func reject(_ part: String, _ reason: Rejection.Reason) { problems.append(Rejection(part: part, reason: reason)) }

        if answer.facts.count + answer.today.count > maxFacts || Set(answer.today).count != answer.today.count {
            if !leaveOut { reject("facts", .tooMany) }
        }
        let choices = CardChoices(facts: Array(answer.facts.prefix(maxFacts)), patterns: [], passages: answer.passages)
        var lines: [String] = []
        var passages: [CheckedPassage] = []
        switch accept(choices, offered: offered, facts: facts, checks: checks, timeZone: timeZone, leaveOut: leaveOut,
                      allowNoFacts: true, today: PlainDate(today.asOf, in: timeZone)) {
        case .accepted(let checked):
            lines = checked.lines
            passages = checked.passages
        case .rejected(let more, _):
            problems += more
        }
        for (index, measure) in answer.today.prefix(maxFacts).enumerated() {
            if let line = QuestionWording.today(measure, today, timeZone: timeZone) {
                lines.append(line)
            } else if !leaveOut {
                reject("today \(index + 1)", .unknownFact)
            }
        }

        // gstack-shortcut(dec-0d90be60): word lists can't catch a calm sentence with no banned word,
        // upgrade when a parent reports a wrong or reassuring answer, a model test finds one, or
        // before another family uses the app.
        if answer.sentences.count > maxSentences && !leaveOut { reject("sentences", .tooMany) }
        var sentences: [String] = []
        for (index, sentence) in answer.sentences.prefix(maxSentences).enumerated() {
            let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let problem = sentenceProblem(text, names: names, medicines: medicines) {
                if !leaveOut { reject("sentence \(index + 1)", problem) }
            } else {
                sentences.append(text)
            }
        }

        guard problems.isEmpty else { return .rejected(problems, needsHelpNow: answer.needsHelpNow) }
        let nothing = lines.isEmpty && sentences.isEmpty && passages.isEmpty
        return .accepted(CheckedAnswer(lines: lines, sentences: sentences, passages: passages,
                                       needsHelpNow: answer.needsHelpNow, cannotAnswer: answer.cannotAnswer || nothing,
                                       topic: answer.topic))
    }

    /// The first problem with one of the AI's own sentences in Ask (step 3 D2 B, Q8, Q11): what
    /// the cards' checks refuse (digits, number and clock words, verdicts, people to call,
    /// medicines, causes, blame, predictions, crediting the NHS), and also words about this baby,
    /// the household's names and medicine names, and every medicine word the medicine check knows.
    // gstack-shortcut(dec-0d90be60): word lists can't catch a calm sentence with no banned word,
    // upgrade when a parent reports a wrong or reassuring answer, a model test finds one, or before
    // another family uses the app.
    static func sentenceProblem(_ text: String, names: [String], medicines: [String]) -> Rejection.Reason? {
        if text.count > maxLength { return .tooLong }
        if let problem = wordProblem(text) { return problem }
        let words = WordReader.words(text)
        for phrase in aboutTheBaby where WordReader.contains(words, phrase: phrase, fuzzy: false) {
            return .banned(phrase.joined(separator: " "))
        }
        for name in names + medicines + MedicineQuestions.medicineWords {
            let phrase = WordReader.words(name)
            if !phrase.isEmpty, WordReader.contains(words, phrase: phrase, fuzzy: false) { return .banned(name) }
        }
        return nil
    }

    /// General information is about babies, never this one (D2 B: "nothing about this baby").
    static let aboutTheBaby: [[String]] = [
        "she", "he", "her", "him", "his", "hers", "shes", "hes", "herself", "himself", "your baby", "your babys",
        "the baby", "the babys", "your little one", "your son", "your daughter", "your newborn",
        // "This child appears well." (Codex step 4 review, 6.)
        "this baby", "this babys", "this child", "this childs", "the child", "the childs", "your child", "your childs",
        "this newborn", "this little one",
    ].map { $0.split(separator: " ").map(String.init) }
}
