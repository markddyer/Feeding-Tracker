import AppIntents
import FeedingCore
import Foundation

// The fixed lists Siri can hear (`docs/planning/15-hands-free-siri.md`): a phrase or an answer can
// hold a word from one of these, never a free number. Built into the phone app, the widget
// extension and the watch app, so the phone's and the watch's Siri hear the same words.

/// The bottle Siri or a shortcut names: "Start a formula feed".
enum MilkChoice: String, AppEnum {
    case formula
    case expressed

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Bottle"
    static let caseDisplayRepresentations: [MilkChoice: DisplayRepresentation] = [
        .formula: DisplayRepresentation(title: "Formula", synonyms: ["formula milk"]),
        .expressed: DisplayRepresentation(title: "Expressed milk", synonyms: ["expressed"]),
    ]

    var kind: MilkKind { self == .formula ? .formula : .expressed }

    init(_ kind: MilkKind) {
        self = kind == .formula ? .formula : .expressed
    }
}

/// The sides of a breastfeed, said after Finish. "Not sure" saves none.
enum SidesChoice: String, AppEnum {
    case left
    case right
    case leftThenRight
    case rightThenLeft
    case notSure

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sides"
    static let caseDisplayRepresentations: [SidesChoice: DisplayRepresentation] = [
        .left: DisplayRepresentation(title: "Left", synonyms: ["left side", "the left"]),
        .right: DisplayRepresentation(title: "Right", synonyms: ["right side", "the right"]),
        .leftThenRight: DisplayRepresentation(title: "Left then right",
                                              synonyms: ["left and right", "both", "both sides", "left, then right"]),
        .rightThenLeft: DisplayRepresentation(title: "Right then left", synonyms: ["right and left", "right, then left"]),
        .notSure: DisplayRepresentation(title: "Not sure", synonyms: ["skip", "don't know", "I don't know"]),
    ]

    var sides: VoiceSides? {
        switch self {
        case .left: .left
        case .right: .right
        case .leftThenRight: .leftThenRight
        case .rightThenLeft: .rightThenLeft
        case .notSure: nil
        }
    }
}

/// A nappy said to Siri: "Log a dirty nappy".
enum NappyKindChoice: String, AppEnum {
    case wee
    case poo
    case both

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Nappy"
    static let caseDisplayRepresentations: [NappyKindChoice: DisplayRepresentation] = [
        .wee: DisplayRepresentation(title: "Wee", synonyms: ["wet nappy", "wet", "wee nappy"]),
        .poo: DisplayRepresentation(title: "Poo", synonyms: ["dirty nappy", "dirty", "poo nappy", "poop", "pooey nappy"]),
        .both: DisplayRepresentation(title: "Wee and poo", synonyms: ["both", "wet and dirty", "wet and dirty nappy"]),
    ]

    var wee: Bool { self != .poo }
    var poo: Bool { self != .wee }
}

/// A poo's colour, from the app's list (`PooColour.known`), or Skip.
enum PooColourChoice: String, AppEnum {
    case yellow
    case green
    case brown
    case pale
    case other
    case skip

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Colour"
    static let caseDisplayRepresentations: [PooColourChoice: DisplayRepresentation] = [
        .yellow: "Yellow",
        .green: "Green",
        .brown: "Brown",
        .pale: DisplayRepresentation(title: "Pale", synonyms: ["white", "chalky", "pale or white"]),
        .other: DisplayRepresentation(title: "Other", synonyms: ["another colour", "something else"]),
        .skip: DisplayRepresentation(title: "Skip", synonyms: ["not sure", "don't know", "no"]),
    ]

    var colour: PooColour? {
        switch self {
        case .yellow: .yellow
        case .green: .green
        case .brown: .brown
        case .pale: .pale
        case .other: .other
        case .skip: nil
        }
    }
}

/// A poo's texture, from the app's list (`PooConsistency.known`), or Skip.
enum PooTextureChoice: String, AppEnum {
    case liquid
    case loose
    case firm
    case skip

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Texture"
    static let caseDisplayRepresentations: [PooTextureChoice: DisplayRepresentation] = [
        .liquid: DisplayRepresentation(title: "Liquid", synonyms: ["runny", "watery"]),
        .loose: DisplayRepresentation(title: "Loose", synonyms: ["soft", "seedy"]),
        .firm: DisplayRepresentation(title: "Firm", synonyms: ["hard", "solid"]),
        .skip: DisplayRepresentation(title: "Skip", synonyms: ["not sure", "don't know", "no"]),
    ]

    var consistency: PooConsistency? {
        switch self {
        case .liquid: .liquid
        case .loose: .loose
        case .firm: .firm
        case .skip: nil
        }
    }
}

/// Siri's amount question, the same on the phone and the watch. It takes the intent's own
/// parameter, as Siri fills that.
enum SiriAmount {
    /// The amount, read back for a "yes" before it counts (V2). A second "no", or no amount from 5 to
    /// 300 ml in three tries, gives nil: nothing is saved for it.
    /// An amount already given (from the Shortcuts app) is read back too (Codex review of doc 15, 5).
    static func ask(_ parameter: IntentParameter<Int?>, milk: MilkKind, baby: String, given: Int? = nil) async throws -> Int? {
        var noes = 0
        if let given, VoiceLog.isAmount(given) {
            if try await parameter.requestConfirmation(for: given, dialog: IntentDialog(stringLiteral: SiriText.isThatRight(given, milk))) {
                return given
            }
            noes += 1
        }
        for _ in 0..<3 {
            let said = try await parameter.requestValue(IntentDialog(stringLiteral: SiriText.howMuch(milk, baby: baby)))
            guard VoiceLog.isAmount(said) else { continue }
            if try await parameter.requestConfirmation(for: said, dialog: IntentDialog(stringLiteral: SiriText.isThatRight(said, milk))) {
                return said
            }
            noes += 1
            if noes == 2 { return nil }
        }
        return nil
    }
}
