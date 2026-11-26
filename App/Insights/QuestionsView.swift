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
    private let siri = SiriQuestions.shared
    private let voice = ReadAloud.shared
    @State private var typed = ""
    @FocusState private var typing: Bool
    /// Stop pressed while a Siri answer was still coming: it shows, unread, with "Read again".
    @State private var stopWaiting = false

    /// Ask is on screen: a Siri question opens nothing more (AI insights step 4).
    @MainActor static var isOpen = false
    /// A Siri question's reply is read only if it comes within this time of the question: the
    /// slowest answer (10 s) and an open form's wait, but never a reply found hours later.
    static let readWithin: TimeInterval = 3 * 60

    static let suggestions = ["How many feeds last night?", "When was her last nappy?", "What does the NHS say about wind?",
                              "Longest sleep this week?"]

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let shown = log.shown(now: max(context.date, Date()))
                // The oldest reply still to be read first, one at a time (Codex step 4 review, 9).
                let unread = shown.first(where: \.waitsToBeRead)
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            header
                            if shown.isEmpty { beforeAsking }
                            ForEach(shown) { question in
                                QuestionBubble(text: question.text, viaSiri: question.viaSiri == true)
                                    .id(question.id)
                                AnswerBubble(question: question, onSendAgain: { sendAgain(question) })
                            }
                            if engine.askingQuestion { MakingBubble() }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    // A tap stops the voice; a scroll doesn't. A button tapped stops it and does its job
                    // (step 4 design D12 A).
                    .simultaneousGesture(TapGesture().onEnded { voice.stop() })
                    .onChange(of: shown.count) {
                        guard shown.last?.viaSiri != true else { return }
                        withAnimation { reader.scrollTo("end", anchor: .bottom) }
                    }
                    .onChange(of: engine.askingQuestion) {
                        guard !siri.isWaiting else { return }
                        withAnimation { reader.scrollTo("end", anchor: .bottom) }
                    }
                    .onAppear { reader.scrollTo(unread?.id ?? "end", anchor: unread == nil ? .bottom : .top) }
                    // A Siri question's reply, once it shows: at its top, then read aloud, once (design
                    // D10 A); the next waits until the voice has finished or been stopped.
                    .onChange(of: unread?.id, initial: true) { readNext(shown, reader: reader) }
                    .onChange(of: voice.state) { readNext(shown, reader: reader) }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    readingBar
                    inputBar
                }
            }
            .foregroundStyle(Theme.text)
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Theme.text)
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
        .onAppear {
            Self.isOpen = true
            log.removeExpired()
        }
        // Leaving Ask cancels a reading (design D10 A).
        .onDisappear {
            Self.isOpen = false
            voice.clear()
        }
    }

    /// Reads the oldest reply still to be read, unless the voice is busy with one.
    private func readNext(_ shown: [KeptQuestion], reader: ScrollViewProxy) {
        guard let question = shown.first(where: \.waitsToBeRead) else { return }
        if case .reading = voice.state { return }
        withAnimation { reader.scrollTo(question.id, anchor: .top) }
        log.markRead(question.id)
        // Only a reply that has just come, to a question asked since Ask last closed: one found
        // later stays silent (leaving Ask cancels a reading, the one still coming included).
        let fresh = Date().timeIntervalSince(question.askedAt) < Self.readWithin && question.askedAt > voice.silencedBefore
        if stopWaiting || !fresh {
            stopWaiting = false
            return
        }
        voice.read(AnswerBubble.spoken(question, model: model), for: question.id)
    }

    /// The reading bar, above the text box, for a Siri question only (step 4 design D4 A, D10 A, D12 A).
    @ViewBuilder
    private var readingBar: some View {
        if case .reading = voice.state {
            ReadingBar(title: voice.volumeOff ? "Volume is off" : "Reading aloud",
                       detail: voice.volumeOff ? "Turn the volume up to hear it" : "Tap Stop, or tap anywhere",
                       button: .stop) { voice.stop() }
        } else if siri.isWaiting, !stopWaiting {
            ReadingBar(title: "Waiting for the answer…", detail: "It will be read out", button: .stop) { stopWaiting = true }
        } else if case .stopped = voice.state {
            ReadingBar(title: "Stopped", detail: nil, button: .readAgain) { voice.readAgain() }
        }
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

/// The parent's question, at the right; "Asked with Siri" under a spoken one.
private struct QuestionBubble: View {
    let text: String
    var viaSiri = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(text)
                .feedText(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            if viaSiri {
                Text("Asked with Siri")
                    .feedText(.subheadline)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viaSiri ? "You asked with Siri: \(text)" : "You asked: \(text)")
        .accessibilityIdentifier("questionBubble")
    }
}

/// The bar that says what the voice is doing, with Stop or Read again (step 4 design D4 A, D12 A).
private struct ReadingBar: View {
    enum Button { case stop, readAgain }
    let title: String
    let detail: String?
    let button: Button
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(Theme.textMuted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).feedText(.smallButton)
                if let detail {
                    Text(detail).feedText(.subheadline).foregroundStyle(Theme.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            SwiftUI.Button(action: action) {
                HStack(spacing: 7) {
                    if button == .stop {
                        RoundedRectangle(cornerRadius: 2).frame(width: 11, height: 11)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(button == .stop ? "Stop" : "Read again").feedText(.smallButton)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .foregroundStyle(button == .stop ? Theme.onPrimary : Theme.text)
                .background(button == .stop ? Theme.primary : Theme.background, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(button == .stop ? "Stop reading aloud" : "Read the answer again")
            .accessibilityIdentifier(button == .stop ? "stopReading" : "readAgain")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .frame(minHeight: 56)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("readingBar")
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
        case .parentHelp:
            HelpNowInChat(passage: NHSPassages.passage(InsightQuestions.parentHelpPassage) ?? NHSPassages.urgent)
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
        case .couldNotAsk, .stopped:
            FixedReply(text: question.kind == .stopped ? InsightQuestions.stoppedReply
                                                       : "Couldn't reach the AI. Your question wasn't answered.")
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

    /// The answer as the screen shows it now: checked against this phone's log (X8).
    static func checked(_ question: KeptQuestion, model: AppModel) -> CheckedAnswer? {
        question.answer.flatMap { answer in
            guard let babyID = model.baby?.name,
                  case .accepted(let checked) = InsightQuestions.accept(answer, offered: question.offered,
                                                                        data: model.store.data, babyID: babyID,
                                                                        now: Date(), leaveOut: true)
            else { return nil }
            return checked
        }
    }

    /// What is read aloud for a Siri question's reply: the screen's own words, short
    /// (`InsightQuestions.spoken`; step 4 D3 A, D8 A, D10 B).
    static func spoken(_ question: KeptQuestion, model: AppModel) -> String {
        let zone = model.store.data.householdSettings.timeZone
        return InsightQuestions.spoken(question.kind, checked: checked(question, model: model),
                                       lastGiven: lastGivenLine(question, model: model, zone: zone),
                                       helpTitle: NHSPassages.passage(InsightQuestions.parentHelpPassage)?.title)
    }

    @ViewBuilder
    private func asked(zone: TimeZone) -> some View {
        let checked = Self.checked(question, model: model)
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
        Self.lastGivenLine(question, model: model, zone: zone)
    }

    static func lastGivenLine(_ question: KeptQuestion, model: AppModel, zone: TimeZone) -> String {
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
    /// The baby's urgent list, or, when the AI pressed the button on a question about how a parent
    /// feels, the NHS's urgent help for mental health (step 3 D13 A).
    var passage: Passage = NHSPassages.urgent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Get help now")
                .feedText(.dayHeading)
                .accessibilityAddTraits(.isHeader)
            NHSPassageTile(passage: passage)
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
