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

    init() {
        let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupID)
        fileURL = folder?.appendingPathComponent("household.json")
        guard let fileURL else {
            problem = "The app's shared folder is missing, so nothing can be saved."
            canSave = false
            return
        }
        do {
            if let loaded = try HouseholdFile.load(from: fileURL) {
                data = loaded
            }
        } catch HouseholdFile.LoadError.newerFormat {
            problem = "A newer version of the app saved this phone's data. Update the app to use it."
            canSave = false
        } catch {
            // Keep the unreadable file for a look later, start empty, and let iCloud fill it again.
            let aside = fileURL.deletingLastPathComponent()
                .appendingPathComponent("household-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            problem = "This phone's saved data couldn't be read. It will come back from iCloud."
        }
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
