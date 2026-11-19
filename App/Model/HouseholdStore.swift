import FeedingCore
import Foundation
import Observation

/// The phone's own copy of the household, kept in one file in the App Group, so widgets and the
/// watch can read it later. Every change is written at once. The rules live in `HouseholdData`.
@MainActor
@Observable
final class HouseholdStore {
    private(set) var data = HouseholdData()
    /// Shown to the parents when the file couldn't be used.
    private(set) var problem: String?

    /// Called after each change made on this phone, so sync can send it.
    @ObservationIgnored var onLocalChange: (@MainActor () -> Void)?
    /// Called after any change, from this phone or from sync, so the alerts are worked out again.
    @ObservationIgnored var onDataChange: (@MainActor () -> Void)?
    @ObservationIgnored private let fileURL: URL?
    /// False when a newer app version wrote the file: it must never be overwritten.
    @ObservationIgnored private var canSave = true

    convenience init() {
        let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupID)
        self.init(fileURL: folder?.appendingPathComponent("household.json"))
    }

    /// The store kept in `fileURL`. Tests pass a stand-in file, and `alarmsSet` so the real
    /// App Group's alarm list is never read.
    init(fileURL: URL?, alarmsSet: (() -> Bool)? = nil) {
        self.fileURL = fileURL
        guard let fileURL else {
            problem = "The app's shared folder is missing, so nothing can be saved."
            canSave = false
            return
        }
        do {
            if let loaded = try HouseholdFile.load(from: fileURL) {
                data = loaded
                // Step 0 (CEO review D18): what a newer build wrote and this one can't read is kept.
                let kept = loaded.keptEvents.count + loaded.keptPlainRecords.count + loaded.keptParts.count
                if kept > 0 { SyncLog.add("file: kept \(kept) entries this build can't read") }
            } else if (alarmsSet ?? Self.alarmsWereSet)() {
                // No file, yet alarms were set from one: it went missing. Wait for iCloud as for
                // an unreadable file, so no alert already set is cancelled (Codex review of T3 and T4).
                SyncLog.add("file: missing, with alarms set; waiting for iCloud")
                data.waitingForICloudSince = Date()
                save()
            }
        } catch HouseholdFile.LoadError.newerFormat {
            problem = "A newer version of the app saved this phone's data. Update the app to use it."
            canSave = false
            data.waitingForICloudSince = Date()
        } catch {
            // Keep the unreadable file for a look later, start empty, and let iCloud fill it again.
            let aside = fileURL.deletingLastPathComponent()
                .appendingPathComponent("household-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            problem = "This phone's saved data couldn't be read. It will come back from iCloud."
            // Until it has (a day at most), no alert already set is cancelled (CEO review D18).
            data.waitingForICloudSince = Date()
            save()
        }
    }

    /// True when the alert scheduler remembers alarms it set (`AlertScheduler.scheduledAlarms`).
    private static func alarmsWereSet() -> Bool {
        guard let saved = UserDefaults(suiteName: AppConfig.appGroupID)?.data(forKey: "scheduledAlarms"),
              let alarms = try? JSONDecoder().decode([ScheduledAlarm].self, from: saved) else { return false }
        return !alarms.isEmpty
    }

    /// A change made on this phone. It is saved and handed to sync. A change that changes nothing
    /// is ignored, so nothing can loop.
    @discardableResult
    func change<T>(_ body: (inout HouseholdData) -> T) -> T {
        let before = data
        let result = body(&data)
        guard data != before else { return result }
        save()
        onLocalChange?()
        onDataChange?()
        return result
    }

    /// A change the parent is told is saved only once it is on this phone (the Journal's Save,
    /// eng OV3, task T17): the file is written first. If the write fails, the change is put back,
    /// nothing is sent, and `saved` is false, so the form stays open and says so. A change that
    /// changes nothing counts as saved. Feeds keep `change`, which never holds a feed back.
    func changeChecked<T>(_ body: (inout HouseholdData) -> T) -> (result: T, saved: Bool) {
        let before = data
        let result = body(&data)
        guard data != before else { return (result, true) }
        guard canSave, let fileURL else {
            data = before
            return (result, false)
        }
        do {
            try HouseholdFile.save(data, to: fileURL, options: .completeFileProtectionUntilFirstUserAuthentication)
        } catch {
            data = before
            SyncLog.add("file: a first couldn't be saved on this phone; put back: \(type(of: error))")
            return (result, false)
        }
        onLocalChange?()
        onDataChange?()
        return (result, true)
    }

    /// A change that came from sync. It is saved, but doesn't start another upload by itself.
    func applySync(_ body: (inout HouseholdData) -> Void) {
        let before = data
        body(&data)
        guard data != before else { return }
        save()
        onDataChange?()
    }

    private func save() {
        guard canSave, let fileURL else { return }
        do {
            try HouseholdFile.save(data, to: fileURL, options: .completeFileProtectionUntilFirstUserAuthentication)
        } catch {
            problem = "Couldn't save on this phone: \(error.localizedDescription)"
        }
    }
}
