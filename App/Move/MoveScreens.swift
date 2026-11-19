import FeedingCore
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

/// The words for the move's screens (docs/planning/08-going-live.md).
enum MoveText {
    /// "12 feeds, 3 sleeps, 1 first": each kind the file holds, in a fixed order.
    static func counts(_ counts: [EventKind: Int]) -> [String] {
        let kinds: [(EventKind, String, String)] = [
            (.feed, "feed", "feeds"), (.pump, "pumping session", "pumping sessions"), (.sleep, "sleep", "sleeps"),
            (.nappy, "nappy", "nappies"), (.medicine, "medicine given", "medicines given"),
            (.growth, "growth entry", "growth entries"), (.milestone, "first", "firsts"),
        ]
        var lines = kinds.compactMap { kind, one, many in
            counts[kind].flatMap { $0 > 0 ? "\($0) \($0 == 1 ? one : many)" : nil }
        }
        let others = counts.filter { kind, _ in !kinds.contains { $0.0 == kind } }.values.reduce(0, +)
        if others > 0 { lines.append("\(others) other \(others == 1 ? "entry" : "entries")") }
        return lines
    }

    static func media(_ count: Int) -> String { "\(count) \(count == 1 ? "photo or video" : "photos and videos")" }
}

#if FEEDING_DEV
/// Feeding Dev: makes the move file, to save to Files and bring into Feeding on this phone.
struct MoveOutScreen: View {
    private let model = AppModel.shared
    @State private var working: String?
    @State private var made: HouseholdMover.Made?
    /// False when iCloud couldn't be reached just before: the file holds what this phone has.
    @State private var fresh = true
    @State private var problem: String?

    var body: some View {
        List {
            Section {
                Text("Moves everything to Little Log, the real app, on this phone: every entry and first, with their photos and videos, the baby's name and birth date, the medicines, the feed window and the night rota.")
                step(1, "Make the move file here.")
                step(2, "Save it to Files, on this iPhone.")
                step(3, "Open Little Log. In Settings, tap Bring in from Little Log Dev, and choose the file.")
                Text("Your alarm choices stay on each phone: pick them again in Little Log.")
                    .feedText(.subheadline).foregroundStyle(Theme.textMuted)
            }
            .listRowBackground(Theme.surface)

            Section {
                if let working {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(working)
                    }
                } else if let made {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ready: \(made.entries) \(made.entries == 1 ? "entry" : "entries"), \(MoveText.media(made.media)).")
                        if !fresh {
                            Text("iCloud couldn't be reached just now, so the file holds what this phone has: an entry from the other phone may be missing. Make it again on Wi-Fi.")
                                .feedText(.subheadline).foregroundStyle(Theme.textMuted)
                        }
                        if made.leftOut > 0 {
                            Text("\(MoveText.media(made.leftOut)) couldn't be fetched from iCloud, and stay in Little Log Dev. Try again on Wi-Fi to bring them too.")
                                .feedText(.subheadline).foregroundStyle(Theme.textMuted)
                        }
                    }
                    ShareLink(item: made.url) {
                        Label("Save the move file", systemImage: "square.and.arrow.up")
                    }
                    .tint(Theme.text)
                    Button("Make it again") { make() }.tint(Theme.text)
                } else {
                    Button("Make the move file") { make() }.tint(Theme.text)
                }
                if let problem {
                    Text(problem).feedText(.subheadline).foregroundStyle(Theme.textMuted)
                }
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Move to Little Log")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(FormOnScreen())
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // A number: SF Pro Rounded, never Fredoka (DESIGN.md).
            Text("\(number)").feedText(.body).bold().frame(minWidth: 18)
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }

    private func make() {
        guard let me = model.me, let baby = model.baby else {
            problem = "Set up Little Log Dev first."
            return
        }
        problem = nil
        made = nil
        working = "Getting the latest from iCloud…"
        Task {
            let before = model.sync.lastFetchAt
            await model.sync.fetchNow()
            let fetched = model.sync.lastFetchAt
            fresh = fetched != nil && fetched != before
            let files = MediaFiles.appGroup()
            do throws(HouseholdMover.MakeFailure) {
                let result = try await HouseholdMover.make(model.store.data, babyID: baby.name, me: me, files: files,
                                                           free: { files?.freeSpace() ?? 0 }, now: Date()) { ids in
                    working = ids.isEmpty ? "Making the file…" : "Getting photos and videos…"
                    let missing = await model.media.fetchForExport(ids) { done in
                        working = "Getting photos and videos: \(done) of \(ids.count)"
                    }
                    working = "Making the file…"
                    return missing
                }
                made = result
            } catch {
                problem = switch error {
                case .notEnoughSpace: "Not enough space on this iPhone for the move file. Free up some space, then try again."
                case .couldNotWrite: "The move file couldn't be made. Try again."
                }
            }
            working = nil
        }
    }
}
#endif

/// A file chosen in Files, read while anything holds it: access ends when the last holder lets
/// go, so an import still running after its screen has gone keeps reading (Codex review).
final class ChosenFile: @unchecked Sendable {
    let url: URL
    private let accessing: Bool

    init(_ url: URL) {
        self.url = url
        accessing = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if accessing { url.stopAccessingSecurityScopedResource() }
    }
}

/// Feeding: brings in the move file Feeding Dev made on this phone.
struct MoveInScreen: View {
    private let model = AppModel.shared
    @State private var choosing = false
    @State private var chosen: (file: ChosenFile, reader: MoveFile.Reader)?
    @State private var working: String?
    @State private var brought: HouseholdMover.Brought?
    @State private var problem: String?
    /// True once this phone may ring for Feeding: alarms and notifications both allowed.
    @State private var alertsReady = false

    var body: some View {
        List {
            Section {
                Text("Brings in the move file made in Little Log Dev on this phone: every entry and first, with their photos and videos, and the household's settings. Entries already here are left as they are.")
            }
            .listRowBackground(Theme.surface)

            if let chosen, brought == nil {
                preview(chosen.reader.move)
            }

            Section {
                if let working {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(working)
                    }
                } else if let brought {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Done: \(brought.entries) \(brought.entries == 1 ? "entry" : "entries") and \(MoveText.media(brought.media)) are in. They go to iCloud and to the other phone now.")
                        if brought.alreadyHere > 0 {
                            Text("\(brought.alreadyHere) were here already, and were left as they are.")
                                .feedText(.subheadline).foregroundStyle(Theme.textMuted)
                        }
                        if brought.mediaLeftOut > 0 {
                            Text("\(MoveText.media(brought.mediaLeftOut)) couldn't be brought in.")
                                .feedText(.subheadline).foregroundStyle(Theme.textMuted)
                        }
                        // Feeding Dev stays loud until Feeding can ring on this phone (Codex review).
                        Text(alertsReady
                             ? "Check Home and History, and that Home shows the next alert. Only then, in Little Log Dev's Settings, turn its alarms and notices off."
                             : "Little Log can't ring on this phone yet: allow its alarms and notifications in the iPhone's Settings. Keep Little Log Dev's alarms on until then.")
                            .feedText(.subheadline).foregroundStyle(Theme.textMuted)
                    }
                } else if let chosen {
                    Button("Bring them in") { bringIn(chosen) }
                        .tint(Theme.text)
                        .disabled(model.store.data.moveProblem(chosen.reader.move, me: model.me) != nil)
                    Button("Choose another file") { choosing = true }.tint(Theme.text)
                } else {
                    Button("Choose the move file") { choosing = true }.tint(Theme.text)
                }
                if let problem {
                    Text(problem).feedText(.subheadline).foregroundStyle(Theme.textMuted)
                }
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        // On the list itself, never on a section (the picker pitfall of 19 Nov 2026).
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { open(url) }
        }
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Bring in from Little Log Dev")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(FormOnScreen())
        .task(id: brought) {
            let notices = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            alertsReady = model.reconciler.alarmsAllowed && notices == .authorized
        }
    }

    @ViewBuilder
    private func preview(_ move: HouseholdMove) -> some View {
        let data = model.store.data
        let me = model.me
        let names = model.memberNames
        let devOther = move.otherParents.sorted { $0.rawValue < $1.rawValue }.first
        let other = me.flatMap { data.otherMember(than: $0) }
        Section {
            ForEach(MoveText.counts(move.counts), id: \.self) { Text($0) }
            if !move.media.isEmpty { Text(MoveText.media(move.media.count)) }
            Text("Entries by \(move.names[move.madeBy] ?? "you") in Little Log Dev become yours.")
                .feedText(.subheadline).foregroundStyle(Theme.textMuted)
            if let devOther, let other {
                Text("Entries by \(move.names[devOther] ?? "the other parent") become \(names[other].map { "\($0)'s" } ?? "the other parent's").")
                    .feedText(.subheadline).foregroundStyle(Theme.textMuted)
            }
            if let problem = data.moveProblem(move, me: me) {
                Text(MoveText.problem(problem, maker: move.names[move.madeBy], other: devOther.flatMap { move.names[$0] }))
            }
        } header: {
            Text("In the file").feedText(.label).foregroundStyle(Theme.textMuted)
        }
        .listRowBackground(Theme.surface)
    }

    private func open(_ url: URL) {
        chosen = nil
        problem = nil
        brought = nil
        let file = ChosenFile(url)
        working = "Reading the file…"
        Task {
            do {
                let reader = try await Task.detached(priority: .userInitiated) { try MoveFile.Reader(url: file.url) }.value
                chosen = (file, reader)
            } catch {
                problem = (error as? MoveFile.Problem) == .newerVersion
                    ? "This file is from a newer Little Log Dev. Update Little Log, then try again."
                    : "This isn't a move file from Little Log Dev, or it isn't on this iPhone yet. Choose the file whose name starts \"Little Log move\", saved On My iPhone."
            }
            working = nil
        }
    }

    private func bringIn(_ chosen: (file: ChosenFile, reader: MoveFile.Reader)) {
        guard let me = model.me, let files = MediaFiles.appGroup() else { return }
        problem = nil
        working = "Bringing in…"
        let media = model.media
        let ids = chosen.reader.move.media.map(\.id)
        // Held like an editor's new photos, so the photo clean-up never takes one before its first is in.
        for id in ids { media.holdDraft(id) }
        Task {
            // The file stays readable until this is done, even if the screen goes.
            let file = chosen.file
            defer {
                for id in ids { media.releaseDraft(id) }
                working = nil
                withExtendedLifetime(file) {}
            }
            do throws(HouseholdMover.Failure) {
                brought = try await HouseholdMover.bringIn(chosen.reader, store: model.store, files: files, me: me,
                                                           uploaded: Set(media.byteSizes().keys),
                                                           queued: Set(media.uploads.map(\.id)), free: files.freeSpace(),
                                                           now: Date(), queue: { media.add($0) }, unqueue: { media.unqueue($0) })
                self.chosen = nil
            } catch {
                problem = switch error {
                case .problem(let problem): MoveText.problem(problem, maker: chosen.reader.move.names[chosen.reader.move.madeBy],
                                                             other: nil)
                case .notEnoughSpace: "Not enough space on this iPhone. Free up some space, then try again."
                case .notOnPhone: "Couldn't save on this phone. Nothing was changed. Try again, or free up some space."
                case .notQueued: "The photos couldn't be set to go to iCloud. Nothing was changed. Try again, or free up some space."
                }
            }
        }
    }
}

extension MoveText {
    /// Why the move can't come in, in the parents' words.
    static func problem(_ problem: MoveProblem, maker: String?, other: String?) -> String {
        switch problem {
        case .notSetUp:
            "Finish setting up Little Log first."
        case .otherParentMissing:
            "\(other ?? "The other parent") hasn't joined this household in Little Log yet. Send the invite from Settings, then bring the file in once they have joined."
        case .madeOnOtherPhone:
            "This file was made on \(maker.map { "\($0)'s" } ?? "the other parent's") phone. Bring it in on that phone, so each parent's entries stay theirs."
        case .unclearParents:
            "This file names more than two parents, so it can't tell whose entries are whose."
        case .unreadableEntries:
            "Some entries in this file are from a newer Little Log Dev. Update Little Log, then try again."
        }
    }
}
