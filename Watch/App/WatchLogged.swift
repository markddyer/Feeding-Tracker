import FeedingCore
import SwiftUI

// The screens a tap opens on the watch, step 1 of `docs/planning/11-watch-parity.md`: the
// Logged card (the parents' choice A, 21 Nov 2026: a full screen for a few seconds, with Undo,
// Earlier and who did it), the poo's details, and Pumping. Each fits the screen with no scrolling.

/// What the Logged card shows after a tap.
struct LoggedCard: Identifiable, Equatable {
    enum Mark: Equatable {
        case nappy(wee: Bool, poo: Bool)
        case bath
        case medicine
        case pump
        case asleep
        case awake
    }

    /// The tap's ID, to follow the phone's answer.
    let id: String
    /// The entry the tap logged.
    let entryID: String
    let title: String
    let at: Date
    /// The entry's start, when not the moment of the tap (pumping starts 30 minutes before): what
    /// Earlier names as `expected`.
    var start: Date?
    let mark: Mark
    var canUndo = true
    var canEarlier = true
    var canDoneBy = true
    /// Set on a card that only says what happened to a correction: "Undo not saved".
    var notice: String?

    /// This card again, saying `text`, with nothing to change: for a correction (tap `tap`) the
    /// phone turned down after the card had closed (outside review of step 1, P2).
    func notice(_ text: String, tap: String) -> LoggedCard {
        LoggedCard(id: tap, entryID: entryID, title: title, at: at, start: start, mark: mark, canUndo: false,
                   canEarlier: false, canDoneBy: false, notice: text)
    }

    /// The card's button a correction came from.
    static func correctionName(_ action: WatchAction) -> String {
        switch action {
        case .undo: "Undo"
        case .earlier: "Earlier"
        case .doneBy: "Done by"
        default: "Change"
        }
    }
}

/// "Wee logged at 21:40": Undo and Earlier, who did it, and a round Done that closes it. It closes
/// by itself after a few seconds while nothing else is open. Until the phone has saved the tap it
/// says so ("Waiting for iPhone"); a tap the phone turned down says "Not saved".
struct WatchLoggedScreen: View {
    let card: LoggedCard
    let state: WatchState
    /// Sends a correction after the card's tap; returns the correction's own tap.
    let send: (WatchAction, String) -> String
    let close: () -> Void
    @State private var mode = Mode.main
    @State private var doneBy: MemberID?
    /// The correction sent from this card, followed until the phone answers it (outside review of
    /// step 1, P2): the card stays to say whether it was saved.
    @State private var correction: Sent?
    @Environment(\.watchLook) private var look

    enum Mode { case main, earlier, doneBy }

    struct Sent: Equatable {
        let id: String
        let action: WatchAction
        /// "Undone", "Moved earlier", "Saved".
        let done: String
    }

    /// How long the card stays with nothing tapped.
    static let lifetime: TimeInterval = 6

    var body: some View {
        WatchPageFrame(label: mode == .earlier ? "When was it?" : mode == .doneBy ? "Done by" : "Logged") { metrics in
            switch mode {
            case .main: main(metrics)
            case .earlier: earlier(metrics)
            case .doneBy: whoDidIt(metrics)
            }
        }
        .task(id: CloseTimer(mode: mode, answered: correctionAnswered)) {
            guard mode == .main else { return }
            // A correction's answer shows for a moment, then the card goes.
            try? await Task.sleep(for: .seconds(correctionAnswered ? 1.5 : Self.lifetime))
            if !Task.isCancelled, mode == .main { close() }
        }
    }

    private var palette: WatchPalette { WatchPalette.of(look) }

    private struct CloseTimer: Equatable {
        let mode: Mode
        let answered: Bool
    }

    private var correctionAnswered: Bool {
        guard let correction, let outcome = PhoneLink.shared.result(of: correction.id) else { return false }
        return outcome != .waiting
    }

    /// Nothing more to change: a correction was sent, the tap was turned down, or this card only
    /// says what happened to one.
    private var settled: Bool {
        correction != nil || card.notice != nil || PhoneLink.shared.result(of: card.id) == .refused
    }

    private func sendCorrection(_ action: WatchAction, done: String) {
        correction = Sent(id: send(action, card.id), action: action, done: done)
        mode = .main
    }

    @ViewBuilder
    private func main(_ metrics: WatchMetrics) -> some View {
        WatchHero {
            VStack(alignment: .leading, spacing: 0) {
                Text(card.title).watchText(.button).foregroundStyle(palette.text).lineLimit(2).minimumScaleFactor(0.7)
                Text("at \(Text(state.clock(card.at)).foregroundStyle(palette.text))")
                    .watchText(.line).foregroundStyle(palette.textMuted)
                status
            }
        } button: {
            Button(action: close) {
                VStack(spacing: 2) {
                    mark.frame(height: 16)
                    Text("Done").watchText(.side)
                }
                .foregroundStyle(palette.text)
                .frame(width: metrics.round, height: metrics.round)
                .background(palette.surface, in: Circle())
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
        }
        Spacer(minLength: 3)
        HStack(spacing: metrics.gap) {
            if card.canUndo, !settled, state.understands(WatchCapability.undo) {
                wide("Undo", metrics) { sendCorrection(.undo(id: card.entryID), done: "Undone") }
            }
            if card.canEarlier, !settled, state.understands(WatchCapability.earlier) {
                wide("Earlier", metrics) { mode = .earlier }
            }
        }
        Spacer(minLength: 3)
        if card.canDoneBy, !settled, state.understands(WatchCapability.doneBy), let members = state.members, members.count > 1 {
            let who = doneBy ?? state.me
            let name = who == state.me ? "you" : members.first { $0.id == who }?.name ?? "you"
            WatchBigButton(title: "Done by \(name) ›", prominent: false, compact: true) { mode = .doneBy }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let notice = card.notice {
            Text(notice).watchText(.hint).foregroundStyle(palette.primary)
        } else if let correction {
            switch PhoneLink.shared.result(of: correction.id) {
            case .refused?:
                Text("\(LoggedCard.correctionName(correction.action)) not saved").watchText(.hint).foregroundStyle(palette.primary)
            case .applied?, .unchanged?:
                Text(correction.done).watchText(.hint).foregroundStyle(palette.textMuted)
            case nil, .waiting?:
                Text("Waiting for iPhone").watchText(.hint).foregroundStyle(palette.textMuted)
            }
        } else {
            tapStatus
        }
    }

    @ViewBuilder
    private var tapStatus: some View {
        switch PhoneLink.shared.result(of: card.id) {
        case .refused?:
            Text("Not saved").watchText(.hint).foregroundStyle(palette.primary)
        case nil, .waiting?:
            Text("Waiting for iPhone").watchText(.hint).foregroundStyle(palette.textMuted)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch card.mark {
        case .nappy(let wee, let poo): NappyMark(wee: wee, poo: poo, size: 14, weeColour: palette.wee, pooColour: palette.poo)
        case .bath: Image(systemName: "bathtub.fill").foregroundStyle(palette.bottle)
        case .medicine: Image(systemName: "pills.fill").foregroundStyle(palette.textMuted)
        case .pump: DropsShape().fill(palette.textMuted).frame(width: 14, height: 14)
        case .asleep: MoonShape().fill(palette.sleep).frame(width: 14, height: 14)
        case .awake: Image(systemName: "sun.max.fill").foregroundStyle(palette.wee)
        }
    }

    private func wide(_ title: String, _ metrics: WatchMetrics, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .watchText(.button)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.tileHeight)
                .foregroundStyle(palette.text)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    /// 5, 10, 20 or 30 minutes earlier: for a tap made late.
    @ViewBuilder
    private func earlier(_ metrics: WatchMetrics) -> some View {
        Spacer(minLength: 2)
        let rows = [[5, 10], [20, 30]]
        VStack(spacing: metrics.gap) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: metrics.gap) {
                    ForEach(row, id: \.self) { minutes in
                        wide("\(minutes) min earlier", metrics) {
                            sendCorrection(.earlier(id: card.entryID, minutes: minutes, expected: card.start ?? card.at),
                                           done: "Moved \(minutes) min earlier")
                        }
                        .accessibilityLabel("\(minutes) minutes earlier")
                    }
                }
            }
        }
        Spacer(minLength: 2)
        WatchBigButton(title: "Back", prominent: false, compact: true) { mode = .main }
    }

    /// The household's parents, each with their colour.
    @ViewBuilder
    private func whoDidIt(_ metrics: WatchMetrics) -> some View {
        Spacer(minLength: 2)
        let members = state.members ?? []
        VStack(spacing: metrics.gap) {
            ForEach(members, id: \.id) { member in
                let chosen = (doneBy ?? state.me) == member.id
                Button {
                    doneBy = member.id
                    sendCorrection(.doneBy(id: card.entryID, member: member.id), done: "Saved")
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(WatchPalette.parent(member.colour, look: look)).frame(width: 12, height: 12)
                        Text(member.id == state.me ? "\(member.name) (you)" : member.name)
                            .watchText(.button).lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                        if chosen { Image(systemName: "checkmark").foregroundStyle(palette.primary) }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: metrics.small ? 40 : 46)
                    .foregroundStyle(palette.text)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        Spacer(minLength: 2)
        WatchBigButton(title: "Back", prominent: false, compact: true) { mode = .main }
    }
}

// MARK: - Poo details

/// After Poo or Both: the colour, then the consistency, each with Skip, as the phone asks
/// (`CareTiles`, the users' choice Q).
struct WatchPooDetailsScreen: View {
    let done: (PooColour?, PooConsistency?) -> Void
    @State private var colour: PooColour?
    @State private var askingConsistency = false
    @Environment(\.watchLook) private var look

    var body: some View {
        WatchPageFrame(label: askingConsistency ? "Consistency" : "Colour") { metrics in
            let palette = WatchPalette.of(look)
            Spacer(minLength: 2)
            if askingConsistency {
                VStack(spacing: metrics.gap) {
                    ForEach(PooConsistency.known, id: \.self) { consistency in
                        choice(CareText.consistencyName(consistency).capitalized, swatch: nil, metrics: metrics, palette: palette) {
                            done(colour, consistency)
                        }
                    }
                }
            } else {
                let rows = [[PooColour.brown, .yellow], [.green, .other]]
                VStack(spacing: metrics.gap) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: metrics.gap) {
                            ForEach(row, id: \.self) { item in
                                choice(item == .other ? "Other" : CareText.colourName(item).capitalized,
                                       swatch: swatch(item), metrics: metrics, palette: palette) {
                                    colour = item
                                    askingConsistency = true
                                }
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 2)
            WatchBigButton(title: "Skip", prominent: false, compact: true) {
                if askingConsistency { done(colour, nil) } else { askingConsistency = true }
            }
        }
    }

    private func swatch(_ colour: PooColour) -> Color? {
        switch colour {
        case .brown: Color(hex: 0x8B5A2B)
        case .yellow: Color(hex: 0xD9A521)
        case .green: Color(hex: 0x6E8B3D)
        default: nil
        }
    }

    private func choice(_ title: String, swatch: Color?, metrics: WatchMetrics, palette: WatchPalette,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let swatch { RoundedRectangle(cornerRadius: 3).fill(swatch).frame(width: 12, height: 12) }
                Text(title).watchText(.side).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.small ? 38 : 44)
            .foregroundStyle(palette.text)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pumping

/// Pumping just done: Left, Right or Both, then each side's amount on the Digital Crown (an amount
/// may be left out), as the phone's Pumping.
struct WatchPumpScreen: View {
    let start: Int
    let done: (PumpSide, Int?, Int?) -> Void
    let cancel: () -> Void
    @State private var side: PumpSide?
    @State private var left: Int?
    @State private var askingRight = false
    @Environment(\.watchLook) private var look

    var body: some View {
        if let side {
            let current = side == .right || askingRight ? "Right" : "Left"
            WatchAmountPicker(title: side == .both ? "\(current): how much?" : "How much?", start: start,
                              noneTitle: "No amount") { ml in
                switch side {
                case .left: done(.left, ml, nil)
                case .right: done(.right, nil, ml)
                case .both:
                    if askingRight { done(.both, left, ml) } else {
                        left = ml
                        askingRight = true
                    }
                }
            }
            .id(askingRight)
        } else {
            WatchPageFrame(label: "Pumped from") { metrics in
                let palette = WatchPalette.of(look)
                Spacer(minLength: 2)
                WatchTileRow(metrics: metrics) {
                    WatchTile(title: "Left", metrics: metrics) {
                        Image(systemName: "circle.lefthalf.filled")
                    } action: { side = .left }
                    WatchTile(title: "Right", metrics: metrics) {
                        Image(systemName: "circle.righthalf.filled")
                    } action: { side = .right }
                    WatchTile(title: "Both", metrics: metrics) {
                        DropsShape().fill(palette.textMuted).frame(width: 15, height: 15)
                    } action: { side = .both }
                }
                Spacer(minLength: 2)
                WatchBigButton(title: "Not now", prominent: false, compact: true, action: cancel)
            }
        }
    }
}

// MARK: - An amount on the Digital Crown

/// An amount on the Digital Crown, every 5 ml from 5 to 300, with − and + for a finger. Turning
/// saves nothing; Save does. The other button closes with no amount.
struct WatchAmountPicker: View {
    let title: String
    var noneTitle = "Done"
    let done: (Int?) -> Void
    @State private var crown: Double
    @State private var saved = 0
    /// The amount box takes the crown as soon as the screen opens. Without this, nothing had it,
    /// so the crown did nothing (found on the real watch, 16 Nov 2026).
    @FocusState private var crownFocused: Bool
    @Environment(\.watchLook) private var look

    init(title: String, start: Int, noneTitle: String = "Done", done: @escaping (Int?) -> Void) {
        self.title = title
        self.noneTitle = noneTitle
        self.done = done
        _crown = State(initialValue: Double(min(300, max(5, (start / 5) * 5))))
    }

    private var ml: Int { Int(crown.rounded()) }

    var body: some View {
        let palette = WatchPalette.of(look)
        VStack(alignment: .leading, spacing: 8) {
            Text(title).watchText(.label).foregroundStyle(palette.textMuted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(ml)").watchText(.amount).contentTransition(.numericText(value: crown))
                Text("ml").watchText(.line)
                Spacer(minLength: 0)
                Image(systemName: "digitalcrown.horizontal.arrow.counterclockwise")
                    .foregroundStyle(palette.primary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(palette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.primary, lineWidth: 2))
            .focusable()
            .focused($crownFocused)
            .digitalCrownRotation($crown, from: 5, through: 300, by: 5, sensitivity: .low, isContinuous: false,
                                  isHapticFeedbackEnabled: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue("\(ml) millilitres")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: crown = min(300, crown + 5)
                case .decrement: crown = max(5, crown - 5)
                @unknown default: break
                }
            }
            HStack(spacing: 8) {
                AmountStepButton(symbol: "minus", label: "5 millilitres less", enabled: ml > 5) { crown = max(5, crown - 5) }
                AmountStepButton(symbol: "plus", label: "5 millilitres more", enabled: ml < 300) { crown = min(300, crown + 5) }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                WatchBigButton(title: noneTitle, prominent: false, compact: true) { done(nil) }
                    .frame(maxWidth: 76)
                    .accessibilityLabel("\(noneTitle), with no amount")
                WatchBigButton(title: "Save", bottle: true, doubleTap: true, compact: true) {
                    saved += 1
                    done(ml)
                }
                .accessibilityLabel("Save \(ml) millilitres")
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        .onAppear { crownFocused = true }
    }
}

/// − or + under the amount: a soft round-ended button with the symbol in coral.
struct AmountStepButton: View {
    let symbol: String
    let label: String
    let enabled: Bool
    let action: () -> Void
    @Environment(\.watchLook) private var look

    var body: some View {
        let palette = WatchPalette.of(look)
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: look == .night ? .semibold : .bold))
                .foregroundStyle(palette.primary)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(palette.surface, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }
}
