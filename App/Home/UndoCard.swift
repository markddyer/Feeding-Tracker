import FeedingCore
import SwiftUI

/// The Undo card (`docs/planning/09-who-does-what.md`, design DD7 and 5B; the parents' ask): every
/// Undo in the app, near the top of the screen, bigger, in the system's Liquid Glass. Line one: who
/// did it with its swap (where it applies), what was logged, and a × that closes it at once; line
/// two: Change time (where it applies) and Undo, each at least 44 points tall; a thin line shows the
/// 10 seconds running out, by day and by night (5B). It goes at its own deadline, and VoiceOver
/// reads it out when it comes.
///
/// This departs from DESIGN.md's flat surfaces and still night look by the parents' choice (D7, 5B).
struct UndoCard: View {
    let action: UndoAction
    var onChangeTime: ((TimeChange) -> Void)?
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let swap = action.swap {
                    UndoSwapButton(swap: swap)
                }
                Text(action.message)
                    .feedText(.body)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(width: 34, height: 34)
                        .background(.fill.tertiary, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close")
            }
            HStack(spacing: 8) {
                if let change = action.changeTime, let onChangeTime {
                    Button("Change time") {
                        onChangeTime(change)
                        dismiss()
                    }
                    .buttonStyle(UndoCardButtonStyle())
                }
                Button(action.canUndo ? "Undo" : "OK") {
                    if action.canUndo { action.perform() }
                    dismiss()
                }
                .buttonStyle(UndoCardButtonStyle())
            }
            UndoCountdown(expiresAt: action.expiresAt)
        }
        .foregroundStyle(Theme.text)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .accessibilityElement(children: .contain)
        .task(id: action.id) {
            AccessibilityNotification.Announcement("\(action.message). Undo is available.").post()
            // Gone at the real deadline (journal review OV9), not at the screen's next redraw.
            try? await Task.sleep(for: .seconds(max(0, action.expiresAt.timeIntervalSinceNow)))
            if !Task.isCancelled { dismiss() }
        }
    }
}

extension View {
    /// The Undo card floating just under the status bar, over the content (DD7).
    func undoCard(_ action: UndoAction?, onChangeTime: ((TimeChange) -> Void)? = nil,
                  dismiss: @escaping (UndoAction) -> Void) -> some View {
        overlay(alignment: .top) {
            if let action {
                UndoCard(action: action, onChangeTime: onChangeTime) { dismiss(action) }
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(action.id)
            }
        }
        .animation(.easeOut(duration: 0.25), value: action?.id)
    }
}

/// Line two's big buttons.
private struct UndoCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .feedText(.smallButton)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(.fill.tertiary.opacity(configuration.isPressed ? 2 : 1), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// The 10 seconds running out (5B: it moves by day and by night).
private struct UndoCountdown: View {
    let expiresAt: Date

    var body: some View {
        TimelineView(.animation) { context in
            let left = max(0, min(1, expiresAt.timeIntervalSince(context.date) / HouseholdData.undoWindow))
            Capsule()
                .fill(.fill.tertiary)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(Theme.text.opacity(0.5)).frame(width: proxy.size.width * left)
                    }
                }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

/// Who did it, in their colour, with the swap arrows: one tap gives it to the other parent (X1).
/// Woke up shows and swaps who got up. Read from the store each time, by the page's own rule
/// (`WhoDidIt.answer`), so the card and the page never disagree.
struct UndoSwapButton: View {
    let swap: UndoSwap
    private let model = AppModel.shared

    var body: some View {
        let data = model.store.data
        let names = model.memberNames
        let colours = model.memberColours
        if let snapshot = data.events[swap.eventID]?.snapshot, let me = model.me {
            let current = swap.gotUp ? (snapshot.event.validGotUp ?? snapshot.event.loggedBy)
                : WhoDidIt.answer(for: snapshot, breastfeeder: data.breastfeeder).member
            let other = names.keys.sorted().first { $0 != current }
            Button {
                guard let other else { return }
                model.store.change { data in
                    if swap.gotUp {
                        data.setGotUp(swap.eventID, to: other, by: me, now: Date())
                    } else {
                        data.setDoneBy(swap.eventID, to: other, by: me, now: Date())
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Avatar(name: names[current] ?? "?", colour: colours[current] ?? .stone, size: 30)
                    if other != nil {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .padding(4)
                .padding(.trailing, other != nil ? 6 : 0)
                .background(.fill.tertiary, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .disabled(other == nil)
            .accessibilityLabel(UndoCardText.swapLabel(current: names[current], other: other.flatMap { names[$0] },
                                                       gotUp: swap.gotUp))
        }
    }
}

/// The card's spoken words (DD5).
enum UndoCardText {
    /// "Done by Alex. Double-tap to change to Sam." / "Got up: Alex. Double-tap to change to Sam."
    static func swapLabel(current: String?, other: String?, gotUp: Bool) -> String {
        let who = current ?? "the other parent"
        let first = gotUp ? "Got up: \(who)." : "Done by \(who)."
        guard let other else { return first }
        return "\(first) Double-tap to change to \(other)."
    }
}
