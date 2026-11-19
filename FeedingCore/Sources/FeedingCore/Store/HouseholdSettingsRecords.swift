import Foundation

// The shared settings, the rota, night claims and the acknowledgement rule, kept as Setting
// records. Each has a fixed record name, so two parents changing different settings never clash,
// and each changes as a whole (the later change wins).

/// A setting's value inside a Setting record's payload.
public struct SettingPayload<Value: Codable & Sendable & Hashable>: VersionedPayload, Hashable {
    public static var currentVersion: Int { 1 }

    public var v: Int
    public var value: Value

    public init(_ value: Value) {
        v = Self.currentVersion
        self.value = value
    }
}

/// The fixed record names of the Setting records.
public enum SettingKey {
    public static let feedWindow = "feedWindow"
    public static let dayHours = "dayHours"
    public static let timeZone = "timeZone"
    public static let rota = "rota"
    public static func night(_ night: PlainDate) -> String { "night-\(night)" }
    public static func change(_ id: String) -> String { "change-\(id)" }
    public static func acknowledgement(_ member: MemberID) -> String { "ack-\(member)" }
    /// "Can you take tonight?", written by the parent who asks (`NightAsk`).
    public static func ask(_ night: PlainDate) -> String { "ask-\(night)" }
    /// "Not tonight", written by the parent who was asked (`NightAskReply`).
    public static func askReply(_ night: PlainDate) -> String { "askReply-\(night)" }
    /// "Both phones tonight" (`BothPhonesNight`).
    public static func bothPhones(_ night: PlainDate) -> String { "both-\(night)" }
}

/// "Seen by Parent B ✓": the changes one parent's phone has received from the other.
public struct Acknowledgement: Hashable, Sendable, Codable {
    public var member: MemberID
    public var seenChangeIDs: [String]

    public init(member: MemberID, seenChangeIDs: [String]) {
        self.member = member
        self.seenChangeIDs = seenChangeIDs
    }
}

/// The inputs `reconcile` needs, read from the household records.
public struct HouseholdState: Hashable, Sendable {
    public var settings: HouseholdSettings
    /// Nil until the rota is set up.
    public var rota: Rota?
    public var claims: [NightClaim]
    /// Every pending change, with `acknowledgedAt` set once the other phone has seen it.
    public var pendingChanges: [PendingChange]
    /// "Both phones tonight", for any night.
    public var bothPhones: [BothPhonesNight] = []
}

extension HouseholdData {
    // MARK: Reading

    public func setting<Value: Codable & Sendable & Hashable>(_ type: Value.Type, _ key: String) -> Value? {
        PayloadCoder.decode(SettingPayload<Value>.self, from: plainRecord(.setting, key)?.payload)?.value
    }

    /// The household settings, with the plan's defaults for anything not set yet.
    public var householdSettings: HouseholdSettings {
        HouseholdSettings(
            window: setting(FeedWindowSettings.self, SettingKey.feedWindow) ?? FeedWindowSettings(),
            dayHours: setting(DayHours.self, SettingKey.dayHours) ?? .standard,
            timeZoneID: setting(String.self, SettingKey.timeZone) ?? "Europe/London")
    }

    public var rota: Rota? { setting(Rota.self, SettingKey.rota) }

    public var nightClaims: [NightClaim] {
        plainRecords(of: .setting).filter { $0.name.hasPrefix("night-") }.compactMap {
            PayloadCoder.decode(SettingPayload<NightClaim>.self, from: $0.payload)?.value
        }
    }

    /// Each parent's acknowledgement, with when it was last written.
    private var acknowledgements: [(ack: Acknowledgement, at: Date)] {
        plainRecords(of: .setting).filter { $0.name.hasPrefix("ack-") }.compactMap { record in
            PayloadCoder.decode(SettingPayload<Acknowledgement>.self, from: record.payload).map { ($0.value, record.modifiedAt) }
        }
    }

    /// Every pending change, marked acknowledged once a parent other than its maker has seen it.
    public var pendingChanges: [PendingChange] {
        let acks = acknowledgements
        return plainRecords(of: .setting).filter { $0.name.hasPrefix("change-") }.compactMap { record in
            guard var change = PayloadCoder.decode(SettingPayload<PendingChange>.self, from: record.payload)?.value else { return nil }
            if change.acknowledgedAt == nil,
               let seen = acks.first(where: { $0.ack.member != change.madeBy && $0.ack.seenChangeIDs.contains(change.id) }) {
                change.acknowledgedAt = seen.at
            }
            return change
        }
        .sorted { ($0.madeAt, $0.id) < ($1.madeAt, $1.id) }
    }

    public var householdState: HouseholdState {
        HouseholdState(settings: householdSettings, rota: rota, claims: nightClaims, pendingChanges: pendingChanges,
                       bothPhones: bothPhonesNights)
    }

    // MARK: Changing

    /// Saves a setting changed on this phone.
    public mutating func putSetting<Value: Codable & Sendable & Hashable>(_ value: Value, key: String, now: Date) {
        put(PlainRecord(type: .setting, name: key, modifiedAt: now, payload: try? PayloadCoder.encode(SettingPayload(value))))
    }

    /// Changes the household settings. A change that could make the other phone alert later than
    /// it should, until it has the change, is recorded as pending: until the other phone confirms
    /// it, this phone alerts as if on duty, with the stricter of the old and new settings.
    public mutating func updateHouseholdSettings(by member: MemberID, now: Date, _ change: (inout HouseholdSettings) -> Void) {
        let old = householdSettings
        var new = old
        change(&new)
        guard new != old else { return }
        if new.window != old.window { putSetting(new.window, key: SettingKey.feedWindow, now: now) }
        if new.dayHours != old.dayHours { putSetting(new.dayHours, key: SettingKey.dayHours, now: now) }
        if new.timeZoneID != old.timeZoneID { putSetting(new.timeZoneID, key: SettingKey.timeZone, now: now) }
        if Self.needsAcknowledgement(from: old, to: new) {
            addPendingChange(previousSettings: old, by: member, now: now)
        }
    }

    /// True when the other phone, still on `old`, could alert later than `new` asks, or decide
    /// day and night differently.
    static func needsAcknowledgement(from old: HouseholdSettings, to new: HouseholdSettings) -> Bool {
        old.stricter(with: new) != old || old.dayHours != new.dayHours || old.timeZoneID != new.timeZoneID
    }

    /// Sets or changes the rota. Always pending: it can change who is on duty tonight.
    public mutating func setRota(_ rota: Rota, by member: MemberID, now: Date) {
        guard rota != self.rota else { return }
        let hadRota = self.rota != nil
        putSetting(rota, key: SettingKey.rota, now: now)
        if hadRota { addPendingChange(previousSettings: nil, by: member, now: now) }
    }

    /// "I'll take tonight". Taking a night only adds alerting, so it isn't pending.
    public mutating func claimNight(_ night: PlainDate, by member: MemberID, now: Date) {
        putSetting(NightClaim(night: night, member: member, claimedAt: now), key: SettingKey.night(night), now: now)
    }

    /// Undoes a claim, which is allowed only until it has been sent. Returns false after that.
    @discardableResult
    public mutating func undoClaim(_ night: PlainDate, by member: MemberID) -> Bool {
        let key = "\(PlainRecordType.setting.rawValue)/\(SettingKey.night(night))"
        guard let stored = plainRecords[key], stored.systemFields == nil,
              PayloadCoder.decode(SettingPayload<NightClaim>.self, from: stored.record.payload)?.value.member == member
        else { return false }
        plainRecords[key] = nil
        return true
    }

    /// Also used by the move from Feeding Dev, for the rota it brings (`bringIn`).
    mutating func addPendingChange(previousSettings: HouseholdSettings?, by member: MemberID, now: Date) {
        let id = UUID().uuidString
        let change = PendingChange(id: id, madeBy: member, madeAt: now, previousSettings: previousSettings)
        putSetting(change, key: SettingKey.change(id), now: now)
    }

    /// Records that this phone has seen every change the other parent made, so their phone can
    /// stop alerting as if on duty. Changes nothing when there is nothing new to confirm.
    public mutating func acknowledgeChanges(by member: MemberID, now: Date) {
        let others = pendingChanges.filter { $0.madeBy != member }.map(\.id)
        let current = setting(Acknowledgement.self, SettingKey.acknowledgement(member))?.seenChangeIDs ?? []
        let missing = others.filter { !current.contains($0) }
        guard !missing.isEmpty else { return }
        // Only the IDs still in the household need keeping.
        let kept = (current + missing).filter { others.contains($0) }
        putSetting(Acknowledgement(member: member, seenChangeIDs: kept), key: SettingKey.acknowledgement(member), now: now)
    }

    /// The pending changes made on this phone that are still waiting for the other phone.
    public func unacknowledgedChanges(by member: MemberID) -> [PendingChange] {
        pendingChanges.filter { $0.madeBy == member && $0.acknowledgedAt == nil }
    }
}

extension HouseholdState {
    /// The roster for `reconcile`. With no rota set up yet, this phone counts as on duty every
    /// night, so nothing goes quiet before the parents have chosen. On a "Both phones tonight"
    /// night it counts as on duty too, whoever had taken the night.
    public func roster(for me: MemberID) -> DutyRoster {
        let both = Set(bothPhones.map(\.night)).compactMap { bothPhonesInForce(night: $0) }
        let bothNights = Set(both.map(\.night))
        let claims = claims.filter { !bothNights.contains($0.night) }
            + both.map { NightClaim(night: $0.night, member: me, claimedAt: $0.at) }
        return DutyRoster(rota: rota ?? Rota(startDate: PlainDate(year: 2026, month: 1, day: 1)!, firstOnDuty: me, secondOnDuty: me),
                          claims: claims)
    }
}
