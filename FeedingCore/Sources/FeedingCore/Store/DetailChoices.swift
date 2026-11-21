import Foundation

// What the "Add to this feed" panel still asks after Finish (or after logging a finished feed):
// the sides not logged, the kinds of bottle not logged, then each bottle's amount. Shared by the
// phone's panel (`FeedDetailsPanel`) and the watch's (`11-watch-parity.md`, W-D1), so both ask the
// same questions.

/// Which questions the details panel still asks. Each choice goes once it is made, so a second
/// tap can't log the same side or bottle twice. Anything more is added in History.
public struct DetailChoices: Equatable, Sendable {
    /// Sides not logged yet.
    public let sides: [BreastSide]
    /// Kinds of bottle not logged yet.
    public let milks: [MilkKind]
    /// Bottles still waiting for their amount.
    public let unmeasured: [Bottle]

    public init(_ details: FeedDetails, bottleOnly: Bool) {
        let loggedSides = Set(details.breast.map(\.side))
        let loggedMilks = Set(details.bottles.map(\.milk))
        unmeasured = details.bottles.filter { $0.ml == nil }
        if bottleOnly {
            // One bottle, chosen at Start feed or here, then its amount.
            sides = []
            milks = details.bottles.isEmpty ? MilkKind.allCases : []
        } else {
            sides = BreastSide.allCases.filter { !loggedSides.contains($0) }
            milks = MilkKind.allCases.filter { !loggedMilks.contains($0) }
        }
    }

    /// Nothing left to ask, so the panel closes by itself.
    public var isComplete: Bool { sides.isEmpty && milks.isEmpty && unmeasured.isEmpty }
}
