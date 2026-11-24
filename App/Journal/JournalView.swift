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
    /// The tab's screens, and a first a tapped notice asked for (nil in previews).
    var path: Binding<NavigationPath>?
    var target: Binding<String?>?

    private let model = AppModel.shared
    @State private var adding: FirstEditor.Mode?
    @State private var settingBirthDate = false
    @State private var exporting = false
    /// "Not now" on the birth-date row hides it on this phone (design review D14).
    @AppStorage("journal.birthDateRowHidden") private var birthDateRowHidden = false
    /// A photo taken here wasn't copied to Photos (permission declined): said once (D20).
    @AppStorage(PhotosCopy.declinedKey) private var photosCopyDeclined = false
    @AppStorage(PhotosCopy.failedKey) private var photosCopyFailed = false
    @AppStorage(PhotosCopy.toldKey) private var photosCopyTold = false
    /// The open iPhone Duo: the line on the left, the chosen first's page on the right (D34).
    @State private var selected: String?
    @State private var width: CGFloat = 0
    /// The soft settle and buzz after a first is saved (D21).
    @State private var settlingID: String?
    @State private var settled = true
    @State private var addedCount = 0
    /// Set when the next "Only on this iPhone" mark is due, so the line shows it then (D11).
    @State private var statusNow = Date.distantPast
    @Environment(\.look) private var look
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// A first's page.
    struct Route: Hashable {
        let id: String
    }

    /// The Firsts list, from the top bar (D7, D42).
    struct FirstsListRoute: Hashable {}

    /// Two columns on the open Duo (D34): the inner display (regular width) at 594 points or wider,
    /// held flat, as a book or as a laptop. An `ArrangementView` split only side by side shows one
    /// column when the open Duo stands upright (669 wide), so the width decides (Codex review of
    /// T7 and T8). The closed Duo, tent and Split View are compact width: one column.
    private var twoColumns: Bool { horizontalSizeClass == .regular && width >= 594 }

    /// Sideways with one column (the closed Duo turned): Add moves into the side bar (D34).
    private var addInBar: Bool { verticalSizeClass == .compact && !twoColumns }

    var body: some View {
        HStack(spacing: 0) {
            listColumn
            if twoColumns {
                pageColumn
                    .frame(maxWidth: .infinity)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .navigationDestination(for: Route.self) { route in
            FirstPage(id: route.id, me: me, babyID: babyID)
        }
        .navigationDestination(for: FirstsListRoute.self) { _ in
            FirstsListView(me: me, babyID: babyID)
        }
        .toolbar {
            // Each has a title and a symbol, so the folded Duo can move them into its side bar (D7).
            if addInBar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = .new(title: nil) } label: { Label(JournalText.addAFirst, systemImage: "plus") }
                        .tint(Theme.text)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: FirstsListRoute()) {
                    Label("Firsts list", systemImage: "list.bullet")
                }
                .tint(Theme.text)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { settingBirthDate = true } label: { Label("Birth date", systemImage: "birthday.cake") }
                    Button { exporting = true } label: { Label("Export the journal", systemImage: "square.and.arrow.down") }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .tint(Theme.text)
            }
        }
        .sheet(isPresented: $settingBirthDate) { BirthDateEditor(babyID: babyID) }
        .sheet(isPresented: $exporting) { ExportView(babyID: babyID) }
        .sheet(item: $adding) { mode in
            FirstEditor(mode: mode, me: me, babyID: babyID) { outcome in
                UndoCenter.shared.show(JournalUndo.action(for: outcome, me: me))
                if case .added(let id, _, _) = outcome { settle(id) }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: addedCount)
        .onChange(of: target?.wrappedValue, initial: true) { openTarget() }
        .onChange(of: NotificationTaps.shared.exportRequests, initial: true) {
            if NotificationTaps.shared.takePendingExport() { exporting = true }
        }
        .onChange(of: model.store.data.events.count) { openTarget() }
        // Waits for the width, so it knows whether the open Duo shows two columns.
        .onChange(of: width) { openTarget() }
        .onlyHereRefresh($statusNow)
    }

    /// Opens the first a notice was tapped for (design review D18): on the open Duo in the right
    /// column, otherwise its own page. Its photos move to the front of the downloads. While the
    /// file fills again from iCloud and it isn't here yet, it waits; once it is known to be gone,
    /// the Journal itself shows.
    private func openTarget() {
        guard let target, let id = target.wrappedValue, width > 0 else { return }
        let data = model.store.data
        if let first = data.events[id], first.event.deletedAt == nil {
            target.wrappedValue = nil
            model.media.preferFirst(id)
            if twoColumns {
                selected = id
                path?.wrappedValue = NavigationPath()
            } else {
                path?.wrappedValue = NavigationPath([Route(id: id)])
            }
        } else if !data.isWaitingForICloud(now: Date()) {
            target.wrappedValue = nil
            path?.wrappedValue = NavigationPath()
        }
    }

    /// The new first settles onto the line: a 0.3-second fade and slide by day, with one soft
    /// haptic; at night, or with Reduce Motion, the haptic only (D21).
    private func settle(_ id: String) {
        addedCount += 1
        guard look == .day, !reduceMotion else { return }
        settlingID = id
        settled = false
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeOut(duration: 0.3)) { settled = true }
        }
    }

    /// The open Duo's right-hand column: the chosen first's page, or the newest first's.
    @ViewBuilder
    private var pageColumn: some View {
        let firsts = model.store.data.milestones(babyID: babyID)
        let shown = selected.flatMap { id in firsts.contains { $0.id == id } ? id : nil } ?? firsts.last?.id
        if let shown {
            FirstPage(id: shown, me: me, babyID: babyID, embedded: true)
        } else {
            Text(JournalText.emptyLine)
                .feedText(.body)
                .foregroundStyle(Theme.textMuted)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.background)
        }
    }

    private var listColumn: some View {
        let data = model.store.data
        let zone = data.householdSettings.timeZone
        let today = PlainDate(Date(), in: zone)
        let birth = data.birthDate(babyID: babyID)
        let firsts = Array(data.milestones(babyID: babyID).reversed())
        return ScrollView {
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
                if (photosCopyDeclined || photosCopyFailed) && !photosCopyTold {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(photosCopyDeclined
                             ? "The photo you took wasn't copied to your Photos. It is still in the journal. You can allow copies in iPhone Settings › Privacy › Photos."
                             : "The photo you took couldn't be copied to your Photos. It is still in the journal.")
                            .feedText(.subheadline)
                        Button("OK") { photosCopyTold = true }
                            .feedText(.smallButton)
                            .frame(minHeight: 44)
                            .buttonStyle(.plain)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.bottom, 14)
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
        .background(Theme.background.ignoresSafeArea())
        .undoCenterCard()
        .frame(maxWidth: twoColumns ? width / 2 : .infinity)
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
        // Lazy, so a long journal draws only the pictures on screen.
        return LazyVStack(alignment: .leading, spacing: 0) {
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
                    Group {
                        if twoColumns {
                            // The open Duo: a tap shows the first on the right.
                            Button { selected = first.id } label: { row(first, birth: birth, zone: zone, today: today) }
                                .accessibilityAddTraits(selected == first.id ? .isSelected : [])
                        } else {
                            NavigationLink(value: Route(id: first.id)) {
                                row(first, birth: birth, zone: zone, today: today)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 24)
                    .padding(.bottom, 10)
                    .opacity(first.id == settlingID && !settled ? 0 : 1)
                    .offset(y: first.id == settlingID && !settled ? -12 : 0)
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
        let large = dynamicTypeSize.isAccessibilitySize
        // At the largest text sizes the picture goes on top, full width, and the words under (D35).
        let layout = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return layout {
            MediaPicture(id: media.first, crop: media.first.flatMap { details?.crops[$0] } ?? .middle)
                .overlay(alignment: .bottomLeading) {
                    if let cover = media.first, model.isVideo(cover) { PlayMark(size: 26).padding(6) }
                }
                .frame(width: large ? nil : 104, height: large ? nil : 104)
                .frame(maxWidth: large ? .infinity : nil)
                .aspectRatio(1, contentMode: .fit)
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
            .padding(.top, large ? 0 : 6)
            if !large { Spacer(minLength: 0) }
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
        model.media.onlyHere(id, now: max(statusNow, Date())) != nil
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
                    IdeaButton(idea: idea, fill: Theme.surface) { adding = .new(title: idea) }
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
            if !addInBar {
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
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Theme.background)
    }
}

extension View {
    /// Sets `now` when the next "Only on this iPhone" mark is due (`OnlyHereRule`, D11), so a
    /// screen showing the marks looks again then, not only when something else changes.
    func onlyHereRefresh(_ now: Binding<Date>) -> some View {
        modifier(OnlyHereRefresh(now: now))
    }
}

private struct OnlyHereRefresh: ViewModifier {
    @Binding var now: Date

    func body(content: Content) -> some View {
        let next = AppModel.shared.media.nextOnlyHereChange(now: Date())
        content.task(id: next) {
            guard let next else { return }
            try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow) + 0.5))
            guard !Task.isCancelled else { return }
            now = Date()
        }
    }
}
