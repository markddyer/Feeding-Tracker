import FeedingCore
import SwiftUI

/// The Journal tab (`docs/planning/07-milestones-journal.md`, design review): "a line through
/// time" (D2). A soft brown line down the left with a dot at each age group (D23), newest first;
/// each first has its picture, title, date and who logged it (D30). The soft "Add a first" button
/// is pinned at the bottom (D5), never coral, so it can't be taken for Start feed. With no firsts:
/// the line starts at "Born", one sentence, and the ideas (D13).
struct JournalView: View {
    let me: MemberID
    let babyID: String

    private let model = AppModel.shared
    @State private var adding: FirstEditor.Mode?
    @State private var undo: UndoAction?
    @State private var settingBirthDate = false
    /// "Not now" on the birth-date row hides it on this phone (design review D14).
    @AppStorage("journal.birthDateRowHidden") private var birthDateRowHidden = false

    /// A first's page.
    struct Route: Hashable {
        let id: String
    }

    /// The Firsts list, from the top bar (D7, D42).
    struct FirstsListRoute: Hashable {}

    var body: some View {
        let data = model.store.data
        let zone = data.householdSettings.timeZone
        let today = PlainDate(Date(), in: zone)
        let birth = data.birthDate(babyID: babyID)
        let firsts = Array(data.milestones(babyID: babyID).reversed())
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Journal")
                    .feedText(.title)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 12)
                if birth == nil && !birthDateRowHidden {
                    birthDateRow
                }
                if let notice = allowanceNotice {
                    noticeRow(notice)
                }
                if firsts.isEmpty {
                    emptyLine(birth: birth, today: today)
                } else {
                    line(firsts, birth: birth, zone: zone, today: today)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) { bottom }
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .navigationDestination(for: Route.self) { route in
            FirstPage(id: route.id, me: me, babyID: babyID, onUndo: { undo = $0 })
        }
        .navigationDestination(for: FirstsListRoute.self) { _ in
            FirstsListView(me: me, babyID: babyID, onUndo: { undo = $0 })
        }
        .toolbar {
            // Each has a title and a symbol, so the folded Duo can move them into its side bar (D7).
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: FirstsListRoute()) {
                    Label("Firsts list", systemImage: "list.bullet")
                }
                .tint(Theme.text)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { settingBirthDate = true } label: { Label("Birth date", systemImage: "birthday.cake") }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .tint(Theme.text)
            }
        }
        .sheet(isPresented: $settingBirthDate) { BirthDateEditor(babyID: babyID) }
        .sheet(item: $adding) { mode in
            FirstEditor(mode: mode, me: me, babyID: babyID) { outcome in
                undo = JournalUndo.action(for: outcome, me: me)
            }
        }
        .task(id: undo?.expiresAt) {
            // The bar goes when Undo does (the hold's own deadline).
            guard let expires = undo?.expiresAt else { return }
            try? await Task.sleep(for: .seconds(max(0, expires.timeIntervalSinceNow)))
            if !Task.isCancelled { undo = nil }
        }
    }

    // MARK: Rows above the line

    /// No birth date yet (D14): a soft row, never a pop-up.
    private var birthDateRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add the birth date to see the baby's age on each first.")
                .feedText(.body)
            HStack(spacing: 10) {
                Button("Add") { settingBirthDate = true }
                    .feedText(.smallButton)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Theme.background, in: Capsule())
                Button("Not now") { birthDateRowHidden = true }
                    .feedText(.smallButton)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.text)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.bottom, 14)
    }

    /// The household photo allowance at 80% or full (D41): said here only, never on Home.
    private var allowanceNotice: String? {
        guard let used = model.media.tally?.bytesUsed else { return nil }
        let limit = model.store.data.photoAllowance
        switch AllowanceLevel(used: used, limit: limit) {
        case .fine: return nil
        case .nearlyFull:
            return "Photos have used \(JournalText.bytes(used)) of the household's \(JournalText.bytes(limit)). You can raise it in Settings."
        case .full:
            return "The photo allowance is full: new photos stay on this iPhone, and the words still go. Raise it in Settings, or delete photos."
        }
    }

    private func noticeRow(_ text: String) -> some View {
        Text(text)
            .feedText(.subheadline)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.bottom, 14)
    }

    // MARK: The line

    private func line(_ firsts: [EventSnapshot], birth: PlainDate?, zone: TimeZone, today: PlainDate) -> some View {
        // Groups in order, newest first; a group is the age's own unit, or a month with no birth date.
        var groups: [(group: JournalGroup, firsts: [EventSnapshot])] = []
        for first in firsts {
            let group = JournalGroup(day: PlainDate(first.event.startedAt, in: zone), birthDate: birth)
            if groups.last?.group == group {
                groups[groups.count - 1].firsts.append(first)
            } else {
                groups.append((group, [first]))
            }
        }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 0) {
                    Circle().fill(Theme.textMuted).frame(width: 13, height: 13)
                        .padding(.leading, 2)
                        .frame(width: 24, alignment: .leading)
                        .accessibilityHidden(true)
                    Text(JournalText.heading(entry.group))
                        .feedText(.dayHeading)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.vertical, 6)
                ForEach(entry.firsts) { first in
                    NavigationLink(value: Route(id: first.id)) {
                        row(first, birth: birth, zone: zone, today: today)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 24)
                    .padding(.bottom, 10)
                }
            }
            if let birth {
                bornMark(birth, today: today)
            }
        }
        .background(alignment: .leading) { lineDrawing }
    }

    /// The line itself: `text-muted` at 35%, 3 points, hidden from VoiceOver (D23).
    private var lineDrawing: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Theme.textMuted.opacity(0.35))
            .frame(width: 3)
            .padding(.leading, 7)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
    }

    private func row(_ first: EventSnapshot, birth: PlainDate?, zone: TimeZone, today: PlainDate) -> some View {
        let details = first.payload?.milestone
        let day = PlainDate(first.event.startedAt, in: zone)
        let media = details?.media ?? []
        let name = model.memberNames[first.event.loggedBy]
        let onlyHere = media.contains { onlyOnThisPhone($0) }
        return HStack(alignment: .top, spacing: 10) {
            MediaPicture(id: media.first)
                .frame(width: 104, height: 104)
                .overlay(alignment: .topTrailing) {
                    if media.count > 1 {
                        Text("+\(media.count - 1)")
                            .feedText(.chip)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .padding(6)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(details?.title ?? "")
                    .feedText(.dayHeading)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(JournalText.date(day, today: today))
                    if let name {
                        Text("·")
                        Avatar(name: name, colour: model.memberColours[first.event.loggedBy] ?? .teal, size: 22)
                    }
                }
                .feedText(.smallButton)
                .foregroundStyle(Theme.textMuted)
                if onlyHere {
                    Label(JournalText.onlyOnThisPhone, systemImage: "icloud.slash")
                        .feedText(.small)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(JournalText.spoken(title: details?.title ?? "", age: birth.flatMap { BabyAge(on: day, birthDate: $0) },
                                               day: day, items: media.count, by: name,
                                               status: onlyHere ? JournalText.onlyOnThisPhone : nil))
        .accessibilityAddTraits(.isButton)
    }

    /// A photo still only on this phone: 10 minutes after Save, or at once if sending stopped (D11).
    private func onlyOnThisPhone(_ id: String) -> Bool {
        guard let upload = model.media.uploads.first(where: { $0.id == id }) else { return false }
        return upload.pause != nil || Date().timeIntervalSince(upload.queuedAt) > 600
    }

    private func bornMark(_ birth: PlainDate, today: PlainDate) -> some View {
        HStack(spacing: 8) {
            Circle()
                .strokeBorder(Theme.textMuted, lineWidth: 3)
                .background(Circle().fill(Theme.background))
                .frame(width: 15, height: 15)
                .padding(.leading, 1)
            Text("Born · \(JournalText.date(birth, today: today))")
                .feedText(.smallButton)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    // MARK: Empty

    private func emptyLine(birth: PlainDate?, today: PlainDate) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let birth {
                bornMark(birth, today: today)
            }
            Text(JournalText.emptyLine)
                .feedText(.body)
                .padding(.leading, 24)
            FlowLayout(spacing: 6) {
                ForEach(JournalText.ideas, id: \.self) { idea in
                    Button(idea) { adding = .new(title: idea) }
                        .feedText(.smallButton)
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .frame(minHeight: 44)
                        .background(Theme.surface, in: Capsule())
                        .buttonStyle(.plain)
                }
            }
            .padding(.leading, 24)
        }
        .frame(minHeight: 160, alignment: .top)
        .background(alignment: .leading) { lineDrawing }
    }

    // MARK: The bottom

    private var bottom: some View {
        VStack(spacing: 8) {
            if let undo {
                UndoBanner(action: undo) { self.undo = nil }
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Button { adding = .new(title: nil) } label: {
                HStack(spacing: 9) {
                    SparkleShape().fill(Theme.text).frame(width: 22, height: 22).accessibilityHidden(true)
                    Text(JournalText.addAFirst).feedText(.button)
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(PressStyle())
            .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Theme.background)
    }
}
