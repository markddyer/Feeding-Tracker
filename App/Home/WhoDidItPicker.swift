import FeedingCore
import SwiftUI

/// "Who did it" in an editor (DD8): both parents side by side, picture and name, the chosen one
/// filled in their colour. A worked-out answer has a dashed outline and a line asking to confirm
/// it (7A). One tap chooses; Save keeps it. Feeds, pumping, nappies, medicines, baths and sleeps
/// ("Settled by" and "Got up"); not growth or firsts.
struct WhoDidItPicker: View {
    let sides: ShareSides
    /// Who it counts for now, and whether a parent chose it (false: worked out).
    let shown: WhoDidIt.Answer?
    let onPick: (MemberID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach([sides.left, sides.right].compactMap { $0 }, id: \.self) { member in
                    button(member)
                }
            }
            if let shown, !shown.saved {
                Text(EditorWhoText.workedOut)
                    .feedText(.small)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.vertical, 4)
    }

    private func button(_ member: MemberID) -> some View {
        let chosen = shown?.member == member
        let colour = sides.colour(member)
        let name = sides.name(member)
        return Button { onPick(member) } label: {
            HStack(spacing: 8) {
                Avatar(name: name, colour: colour, size: 26)
                    .workedOutRing(chosen && !(shown?.saved ?? true))
                Text(name)
                    .feedText(.smallButton)
                    .lineLimit(1)
                    .foregroundStyle(chosen ? Theme.onParentMark : Theme.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(chosen ? colour.mark : Theme.background, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue(chosen ? (shown?.saved == false ? "Chosen, probably" : "Chosen") : "")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// The words of the editors' "Who did it" sections (DD8, 7A).
enum EditorWhoText {
    static let doneBy = "Who did it"
    static let settledBy = "Settled by"
    static let gotUp = "Got up"
    static let workedOut = "Worked out from the log: tap to confirm or change."

    static func loggedBy(_ name: String) -> String { "Logged by \(name)." }
}
