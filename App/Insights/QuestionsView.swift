import FeedingCore
import FeedingInsights
import SwiftUI

/// Ask (AI insights step 3; the look "Ask: A, a chat with bubbles", picked 22 Nov 2026): a sheet
/// from Home's top bar. Before the first question, suggestions and "Worried right now?" with Call
/// 999 and Call 111. Each question gets a bubble kept apart in parts (A4): "From your log" (the
/// app's words), the AI's up to 2 sentences marked as AI (step 3 D2 B), the NHS's exact words,
/// then "AI · not medical advice". A danger sign gets the Get help now card in place of an answer.
/// Questions stay on this phone for 24 hours (`QuestionLog`).
struct QuestionsView: View {
    @Environment(\.dismiss) private var dismiss
    private let model = AppModel.shared
    private let engine = InsightEngine.shared
    private let log = QuestionLog.shared
    @State private var typed = ""
    @FocusState private var typing: Bool

    static let suggestions = ["How many feeds last night?", "When was her last nappy?", "What does the NHS say about wind?",
                              "Longest sleep this week?"]

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let shown = log.shown(now: max(context.date, Date()))
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            header
                            if shown.isEmpty { beforeAsking }
                            ForEach(shown) { question in
                                QuestionBubble(text: question.text)
                                AnswerBubble(question: question, onSendAgain: { sendAgain(question) })
                            }
                            if engine.askingQuestion { MakingBubble() }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: shown.count) { withAnimation { reader.scrollTo("end", anchor: .bottom) } }
                    .onChange(of: engine.askingQuestion) { withAnimation { reader.scrollTo("end", anchor: .bottom) } }
                    .onAppear { reader.scrollTo("end", anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
            .foregroundStyle(Theme.text)
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Theme.text)
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
        .onAppear { log.removeExpired() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Ask")
                .feedText(.title)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
            }
            .accessibilityLabel("Close")
        }
    }

    /// Before asking (the mockup's "Before asking"): what Ask is, suggestions, and "Worried right now?".
    private var beforeAsking: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask about your log, or what the NHS says. Your questions stay on this phone.")
                .feedText(.body)
            WrapLayout(spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button { send(suggestion) } label: {
                        Text(suggestion)
                            .feedText(.smallButton)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(Theme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("askSuggestion")
                }
            }
            // The buttons sit on the page, not in the tile: Call 111's `surface` would vanish on a
            // `surface` tile (as on Get help now, they stand on the background).
            VStack(alignment: .leading, spacing: 10) {
                Tile(label: "Worried right now?") {
                    Text("If something seems seriously wrong, don't wait for an answer here.")
                        .feedText(.body)
                }
                CallButtons()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("askWorried")
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask about the baby or your log…", text: $typed, axis: .vertical)
                .feedText(.body)
                .lineLimit(1...4)
                .focused($typing)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
                .submitLabel(.send)
                .onSubmit { send(typed) }
                .accessibilityIdentifier("questionField")
            Button { send(typed) } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .frame(width: 44, height: 44)
            }
            .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty || engine.askingQuestion)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("sendQuestion")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.background.ignoresSafeArea(edges: .bottom))
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !engine.askingQuestion else { return }
        typed = ""
        Task { await engine.ask(question) }
    }

    /// "Send again" on a question that couldn't reach the AI: it goes again as new, and the failed
    /// one goes. Never sent again by itself (Q10).
    private func sendAgain(_ question: KeptQuestion) {
        guard !engine.askingQuestion else { return }
        log.remove(question.id)
        Task { await engine.ask(question.text) }
    }
}

/// The parent's question, at the right.
private struct QuestionBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .feedText(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 40)
            .accessibilityLabel("You asked: \(text)")
            .accessibilityIdentifier("questionBubble")
    }
}

/// "Making…" while the AI answers.
private struct MakingBubble: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Making…").feedText(.small).foregroundStyle(Theme.textMuted)
            AIMark()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("The AI is answering")
    }
}

/// What a question got. An AI answer is checked against this phone's log each time it is shown
/// (X8): a fact whose entry was deleted goes, and nothing that fails the checks is ever shown.
private struct AnswerBubble: View {
    let question: KeptQuestion
    let onSendAgain: () -> Void
    private let model = AppModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("answerBubble")
    }

    @ViewBuilder
    private var content: some View {
        let zone = model.store.data.householdSettings.timeZone
        switch question.kind {
        case .helpNow:
            HelpNowInChat()
        case .lastGiven:
            Tile(label: "From your log") {
                Text(lastGivenLine(zone: zone)).feedText(.body)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("fromYourLog")
        case .medicineReply:
            FixedReply(text: InsightQuestions.medicineReply)
        case .closed:
            FixedReply(text: InsightQuestions.closedReply)
            NavigationLink {
                InsightSettingsView()
            } label: {
                Text("Settings › AI insights")
                    .feedText(.subheadline)
                    .underline()
                    .frame(minHeight: 44, alignment: .leading)
            }
        case .couldNotAsk:
            FixedReply(text: "Couldn't reach the AI. Your question wasn't answered.")
            HStack(spacing: 10) {
                Button(action: onSendAgain) {
                    Text("Send again")
                        .feedText(.smallButton)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Theme.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("askSendAgain")
                CallLink(number: "111", label: "Call NHS 1 1 1")
            }
        case .asked:
            asked(zone: zone)
        }
    }

    @ViewBuilder
    private func asked(zone: TimeZone) -> some View {
        let checked: CheckedAnswer? = question.answer.flatMap { answer in
            guard let babyID = model.baby?.name,
                  case .accepted(let checked) = InsightQuestions.accept(answer, offered: question.offered,
                                                                        data: model.store.data, babyID: babyID,
                                                                        now: Date(), leaveOut: true)
            else { return nil }
            return checked
        }
        if question.peopleLine {
            FixedReply(text: InsightQuestions.peopleLine)
            ForEach(peoplePassages, id: \.id) { passage in
                NHSCardBox(passage: passage, summary: nil)
            }
        }
        if let checked, !checked.lines.isEmpty {
            Tile(label: "From your log") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(checked.lines, id: \.self) { Text($0).feedText(.body) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("fromYourLog")
        }
        if let checked, !checked.sentences.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(checked.sentences, id: \.self) { Text($0).feedText(.body) }
                AIMark()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Written by AI: " + checked.sentences.joined(separator: " "))
            .accessibilityIdentifier("aiSentences")
        }
        if let checked {
            ForEach(checked.passages, id: \.passage.id) { item in
                NHSCardBox(passage: item.passage, summary: item.summary)
            }
        }
        if checked?.cannotAnswer ?? true {
            FixedReply(text: InsightQuestions.cannotAnswerLine)
        }
        Text(InsightQuestions.footer)
            .feedText(.subheadline)
            .foregroundStyle(Theme.textMuted)
        WrongReportButton()
    }

    /// The NHS pages the people line brings, only once ticked (step 3 D6 A).
    private var peoplePassages: [Passage] {
        let data = model.store.data
        let today = PlainDate(Date(), in: data.householdSettings.timeZone)
        return InsightQuestions.peoplePassages.compactMap { id in
            guard let passage = NHSPassages.passage(id),
                  NHSPassages.isChecked(passage.id, copied: passage.copied, checks: data.passageChecks, today: today)
            else { return nil }
            return passage
        }
    }

    /// "Vitamin D: last logged at 09:05 today.", from the log now (D6, X4).
    private func lastGivenLine(zone: TimeZone) -> String {
        let data = model.store.data
        guard let babyID = model.baby?.name,
              let name = MedicineQuestions.check(question.text, medicines: data.medicines)?.medicine else {
            return InsightQuestions.medicineReply
        }
        guard let at = data.lastGiven(name, babyID: babyID, now: Date()) else { return "No \(name) logged." }
        return "\(name): last logged at \(QuestionWording.when(at, Date(), zone))."
    }
}

/// One of the app's fixed lines.
private struct FixedReply: View {
    let text: String

    var body: some View {
        Text(text).feedText(.body)
    }
}

/// The Get help now card in the chat, in place of an answer (A2): the NHS's urgent list word for
/// word, with Call 999 and Call 111. No AI, works with no signal.
private struct HelpNowInChat: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Get help now")
                .feedText(.dayHeading)
                .accessibilityAddTraits(.isHeader)
            NHSPassageTile(passage: NHSPassages.urgent)
            CallButtons()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("askHelpNow")
    }
}

/// Call 999 and Call 111, as on Get help now: side by side, or one above the other at large text.
struct CallButtons: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { call999; call111 }
            VStack(spacing: 10) { call999; call111 }
        }
    }

    private var call999: some View {
        BigButton(title: "Call", prominent: true, amount: "999") { call("999") }
            .accessibilityLabel("Call 9 9 9")
    }

    private var call111: some View {
        BigButton(title: "Call", prominent: false, amount: "111") { call("111") }
            .accessibilityLabel("Call NHS 1 1 1")
    }

    private func call(_ number: String) {
        guard let url = URL(string: "tel:\(number)") else { return }
        openURL(url)
    }
}

/// A small call link, beside "Send again".
private struct CallLink: View {
    let number: String
    let label: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = URL(string: "tel:\(number)") { openURL(url) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "phone.fill").foregroundStyle(Theme.backup).accessibilityHidden(true)
                Text("Call \(number)").feedText(.smallButton)
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
