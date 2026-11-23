import FeedingCore
import FeedingInsights
import SwiftUI

// Settings › AI insights (step 2 of `docs/planning/12-ai-insights-gauntlet.md`, task AI9): what the
// AI does and what is sent, "not medical advice", each parent's yes and the off switch (D12, S8,
// O2), "What the AI sees" (A8, O8), why the AI couldn't be reached (S12), and the "this was wrong"
// count with Turn back on (A7). The rules are `InsightCards`'; this screen only shows them and
// records a parent's choice on their own phone.

/// Where AI insights stand for the household, as this phone knows it: the yeses and offs in the
/// household's settings and the "wrong" reports. The gate before a call also reads the iCloud
/// share's members (O2); this is what Settings shows.
struct InsightStatus {
    enum State: Equatable {
        case on
        /// This parent hasn't said yes (or the words changed since).
        case waitingForMe
        case waitingForOther
        /// Only one parent is in the household so far.
        case noOtherParent
        case turnedOffByMe
        case turnedOffByOther
        case paused
    }

    let state: State
    let mine: InsightYes?
    let other: MemberID?
    let theirs: InsightYes?
    /// The "this was wrong" reports counting towards a pause now.
    let wrong: Int

    init(data: HouseholdData, me: MemberID?, now: Date) {
        let yeses = data.insightYeses
        let members = data.plainRecords(of: .member).map { MemberID(rawValue: $0.name) }
        let other = members.first { $0 != me }
        self.other = other
        mine = me.flatMap { yeses[$0] }
        theirs = other.flatMap { yeses[$0] }
        wrong = InsightCards.wrongCount(data.wrongReports, now: now)
        func current(_ yes: InsightYes?) -> Bool { yes?.yes == true && yes?.version == InsightCards.consentVersion }
        if wrong >= InsightCards.pauseAfterReports {
            state = .paused
        } else if mine?.yes == false {
            state = .turnedOffByMe
        } else if yeses.values.contains(where: { !$0.yes }) {
            state = .turnedOffByOther
        } else if !current(mine) {
            state = .waitingForMe
        } else if other == nil {
            state = .noOtherParent
        } else if !current(theirs) {
            state = .waitingForOther
        } else {
            state = .on
        }
    }

    /// The other parent's name, or "The other parent".
    func otherName(_ names: [MemberID: String]) -> String {
        other.flatMap { names[$0] } ?? "The other parent"
    }

    /// The word at the right of Settings' row.
    func short(names: [MemberID: String]) -> String {
        switch state {
        case .on: "On"
        case .waitingForMe: theirs?.yes == true ? "Waiting for you" : "Off"
        case .waitingForOther: "Waiting for \(otherName(names))"
        case .noOtherParent: "Waiting"
        case .turnedOffByMe, .turnedOffByOther: "Off"
        case .paused: "Paused"
        }
    }

    /// The sentence at the top of the yes section.
    func sentence(names: [MemberID: String]) -> String {
        let name = otherName(names)
        switch state {
        case .on:
            return "On. The first phone opened each morning makes the card, and both phones show it."
        case .waitingForMe:
            return theirs?.yes == true
                ? "\(name) said yes. Nothing is sent until you say yes too."
                : "Off. Nothing is sent until both of you say yes."
        case .waitingForOther:
            return "You said yes. Nothing is sent until \(name) says yes too, on the other phone."
        case .noOtherParent:
            return "You said yes. Nothing is sent until the other parent joins the household and says yes too."
        case .turnedOffByMe:
            return "Off. You turned AI insights off, so nothing is sent from either phone."
        case .turnedOffByOther:
            return "Off. \(name) turned AI insights off, so nothing is sent from either phone. Only \(name) can turn them back on."
        case .paused:
            return "Paused. \(wrong) cards were reported wrong in 30 days, so nothing is sent until one of you turns AI insights back on."
        }
    }

    /// "Yes · 23 Nov 2026", "Off · 23 Nov 2026" or "Not yet" (a yes to older words counts as not yet).
    static func answer(_ yes: InsightYes?, timeZone: TimeZone) -> String {
        guard let yes else { return "Not yet" }
        let day = PassageDate.text(PlainDate(yes.at, in: timeZone))
        if !yes.yes { return "Off · \(day)" }
        return yes.version == InsightCards.consentVersion ? "Yes · \(day)" : "Not yet"
    }
}

struct InsightSettingsView: View {
    private let model = AppModel.shared
    private let engine = InsightEngine.shared
    @State private var askingYes = false
    @State private var askingOff = false
    @State private var askingResume = false

    var body: some View {
        let data = model.store.data
        let zone = data.householdSettings.timeZone
        let names = model.memberNames
        let status = InsightStatus(data: data, me: model.me, now: Date())
        List {
            Section {
                Text("AI insights pick out what stands out in your log: a short card each morning on Home, about last night and yesterday, and “This week” on Graphs. Little Log writes every sentence and number. What the AI picked is marked AI.")
            }
            .listRowBackground(Theme.surface)

            // Near the top, so the off switch is quick to reach; the yes asks again with the key facts.
            yesSection(status, names: names, zone: zone)

            if engine.preparing || engine.lastFailure != nil {
                phoneSection(zone: zone)
            }

            Section {
                Text("To make a card, Little Log sends Anthropic, the company that makes the Claude AI, the numbers and times from the last 4 weeks of your log: feeds, sleep, nappies, baths, pumping and weights, with the baby’s age in weeks. It never sends names, notes, medicines, photos or the birth date.")
                NavigationLink {
                    InsightRequestView()
                } label: {
                    Text("What the AI sees")
                }
                .accessibilityIdentifier("whatTheAISees")
            } header: {
                header("What is sent")
            }
            .listRowBackground(Theme.surface)

            Section {
                Text("AI insights are not medical advice. They never say whether the baby is well, or what to do. If you’re worried, contact your midwife, health visitor or GP, or call NHS 111. In an emergency, call 999.")
                NavigationLink {
                    GetHelpNowView()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "phone.fill")
                            .accessibilityHidden(true)
                        Text("Worried? Get help now")
                    }
                }
            } header: {
                header("Not medical advice")
            }
            .listRowBackground(Theme.surface)

            Section {
                HStack {
                    Text("In the last 30 days")
                    Spacer(minLength: 8)
                    Text("\(status.wrong)")
                        .foregroundStyle(Theme.textMuted)
                }
                .accessibilityElement(children: .combine)
            } header: {
                header("Cards reported wrong")
            } footer: {
                Text("Each card has a “This was wrong” button. Two in 30 days pause AI insights on both phones until one of you turns them back on, which starts the count again.")
                    .foregroundStyle(Theme.textMuted)
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("AI insights")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("AI insights").feedText(.dayHeading).accessibilityAddTraits(.isHeader)
            }
        }
        .alert("Use AI insights?", isPresented: $askingYes) {
            Button("Yes") { sayYes(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Once both of you say yes, Little Log sends the numbers and times from your log to Anthropic, the company that makes the Claude AI, to make each card. Never names, notes or medicines. AI insights are not medical advice.")
        }
        .alert("Turn off AI insights?", isPresented: $askingOff) {
            Button("Turn off", role: .destructive) { sayYes(false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nothing is sent from either phone until you say yes again.")
        }
        .alert("Turn AI insights back on?", isPresented: $askingResume) {
            Button("Turn back on") {
                model.store.change { $0.resumeInsights(now: Date()) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The count of cards reported wrong starts again.")
        }
    }

    /// Where it stands, each parent's answer, and this parent's yes or off.
    private func yesSection(_ status: InsightStatus, names: [MemberID: String], zone: TimeZone) -> some View {
        let mineCurrent = status.mine?.yes == true && status.mine?.version == InsightCards.consentVersion
        return Section {
            Text(status.sentence(names: names))
                .accessibilityIdentifier("insightStatus")
            answerRow("You", status.mine, zone: zone)
            if status.other != nil {
                answerRow(status.otherName(names), status.theirs, zone: zone)
            }
            if status.state == .paused {
                Button {
                    askingResume = true
                } label: {
                    Text("Turn back on after the pause").fontWeight(.semibold)
                }
                .foregroundStyle(Theme.text)
                .disabled(model.me == nil)
                .accessibilityIdentifier("insightResume")
            }
            Button {
                if mineCurrent { askingOff = true } else { askingYes = true }
            } label: {
                Text(mineCurrent ? "Turn off AI insights"
                     : status.mine?.yes == false ? "Turn AI insights back on" : "Yes, use AI insights")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(Theme.text)
            .disabled(model.me == nil)
            .accessibilityIdentifier(mineCurrent ? "insightOff" : "insightYes")
        } header: {
            header("Both of you")
        } footer: {
            Text("Nothing is sent until both of you say yes, each on your own phone. Either of you can turn it off at any time, and then nothing is sent from either phone.")
                .foregroundStyle(Theme.textMuted)
        }
        .listRowBackground(Theme.surface)
    }

    private func answerRow(_ who: String, _ yes: InsightYes?, zone: TimeZone) -> some View {
        HStack {
            Text(who)
            Spacer(minLength: 8)
            Text(InsightStatus.answer(yes, timeZone: zone))
                .foregroundStyle(Theme.textMuted)
        }
        .accessibilityElement(children: .combine)
    }

    /// This phone getting ready after a yes, or why the AI couldn't be reached (S12), in plain words.
    private func phoneSection(zone: TimeZone) -> some View {
        Section {
            if engine.preparing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Getting this phone ready…")
                }
                .accessibilityElement(children: .combine)
            } else if let failure = engine.lastFailure {
                VStack(alignment: .leading, spacing: 4) {
                    Text(engine.lastFailureAt.map { "Couldn’t reach the AI since \(Self.since($0, zone: zone))." }
                         ?? "Couldn’t reach the AI.")
                    Text(Self.reason(failure))
                        .feedText(.subheadline)
                        .foregroundStyle(Theme.textMuted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("insightFailure")
            }
        } header: {
            header("This phone")
        } footer: {
            Text("Until then, the cards show the facts from your log, with no AI.")
                .foregroundStyle(Theme.textMuted)
        }
        .listRowBackground(Theme.surface)
    }

    /// "07:10" today, or "22 Nov 2026, 07:10".
    static func since(_ date: Date, zone: TimeZone, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: date)
        let day = PlainDate(date, in: zone)
        return day == PlainDate(now, in: zone) ? time : "\(PassageDate.text(day)), \(time)"
    }

    static func reason(_ failure: InsightFailure) -> String {
        switch failure {
        case .noSignal:
            "No signal, or Anthropic couldn’t be reached. Little Log tries again the next time Home or Graphs opens."
        case .couldNotConnect:
            "This phone couldn’t prove to Anthropic that it runs Little Log from the App Store or TestFlight."
        case .unavailable:
            "The AI isn’t available now. It may be busy, or this month’s spending limit may be reached."
        case .turnedDown:
            "The AI’s choices didn’t pass Little Log’s checks, twice in a row."
        case .noKey:
            "This build of Little Log has no way to reach the AI."
        }
    }

    private func sayYes(_ yes: Bool) {
        guard let me = model.me else { return }
        model.store.change { $0.setInsightYes(yes, member: me, now: Date()) }
        if yes { Task { await engine.prepare() } }
    }

    private func header(_ title: String) -> some View {
        Text(title).feedText(.label).foregroundStyle(Theme.textMuted)
    }
}

/// "What the AI sees" (A8, O8): exactly what a card would send now, the instructions then the log's
/// numbers, from the same code that sends it (`InsightCards.preview`, `prompt`).
struct InsightRequestView: View {
    private let model = AppModel.shared
    @State private var kind: CardKind = .morning

    var body: some View {
        let data = model.store.data
        let request = InsightCards.preview(kind, data: data, babyID: model.baby?.name ?? "", now: Date())
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Card", selection: $kind) {
                    Text("Morning card").tag(CardKind.morning)
                    Text("This week").tag(CardKind.week)
                }
                .pickerStyle(.segmented)
                if let request {
                    Text("Exactly what Little Log would send for this card now: the instructions, then the numbers from your log in JSON, a plain data format. It is sent without the spaces and line breaks added here for reading. Times are in the household’s time zone.")
                        .feedText(.subheadline)
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 4)
                    Tile {
                        Text(InsightCards.readablePrompt(request, timeZone: data.householdSettings.timeZone))
                            // Fixed-width, as the log is JSON. The app sets `.fontDesign(.rounded)`
                            // for all text, which swaps this font too, so it is cleared here.
                            .font(.system(.footnote, design: .monospaced))
                            .fontDesign(nil)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("insightRequest")
                    }
                } else {
                    Text(kind == .morning
                         ? "Nothing to send yet. The first morning card comes after a night is logged."
                         : "Nothing to send yet. “This week” needs at least 3 days logged in a week, Monday to Sunday.")
                        .feedText(.subheadline)
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("What the AI sees")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("What the AI sees").feedText(.dayHeading).accessibilityAddTraits(.isHeader)
            }
        }
    }
}
