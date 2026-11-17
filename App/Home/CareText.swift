import FeedingCore
import Foundation

/// The words for sleep, nappies, medicine and growth (`06-more-than-feeds.md`), kept apart from
/// the views so they can be tested. Facts only: how long, how many, when. Never "due", "missed",
/// "overdue", "should", "normal", or a "next dose" time.
enum CareText {
    // MARK: Sleep

    /// "Asleep", "Awake", or nothing logged yet.
    static func sleepWord(_ state: SleepState) -> String {
        switch state {
        case .asleep: "Asleep"
        case .awake: "Awake"
        case .notLogged: "No sleep logged yet"
        }
    }

    /// The time asleep or awake so far ("1h 20m"), or nil before the first sleep.
    static func sleepElapsed(_ state: SleepState, now: Date) -> String? {
        switch state {
        case .asleep(_, let since), .awake(let since): HomeText.elapsed(max(0, now.timeIntervalSince(since)))
        case .notLogged: nil
        }
    }

    /// The button on the Sleep tile: what the tap logs.
    static func sleepButton(_ state: SleepState) -> String {
        if case .asleep = state { return "Woke up" }
        return "Fell asleep"
    }

    // MARK: Nappies

    /// "wee", "poo", "wee and poo", or "dry".
    static func nappyKind(wee: Bool, poo: Bool) -> String {
        switch (wee, poo) {
        case (true, true): "wee and poo"
        case (true, false): "wee"
        case (false, true): "poo"
        case (false, false): "dry"
        }
    }

    /// What the Undo bar says: "Wee logged", "Wee and poo logged".
    static func nappyLogged(wee: Bool, poo: Bool) -> String {
        "\(nappyKind(wee: wee, poo: poo).capitalizedFirst) logged"
    }

    static func colourName(_ colour: PooColour) -> String {
        switch colour {
        case .brown: "Brown"
        case .yellow: "Yellow"
        case .green: "Green"
        case .other: "Other"
        default: colour.rawValue.capitalizedFirst
        }
    }

    static func consistencyName(_ consistency: PooConsistency) -> String {
        switch consistency {
        case .liquid: "Liquid"
        case .loose: "Loose"
        case .firm: "Firm"
        default: consistency.rawValue.capitalizedFirst
        }
    }

    /// A poo's details in a few words: "yellow, loose", "green", or nil when neither was given.
    static func pooDetails(_ nappy: NappyDetails) -> String? {
        guard nappy.poo else { return nil }
        let parts = [nappy.colour.map { colourName($0).lowercased() },
                     nappy.consistency.map { consistencyName($0).lowercased() }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// A nappy in History: "Poo · yellow, loose", "Wee and poo", "Wee".
    static func nappyLine(_ nappy: NappyDetails) -> String {
        let kind = nappyKind(wee: nappy.wee, poo: nappy.poo).capitalizedFirst
        return pooDetails(nappy).map { "\(kind) · \($0)" } ?? kind
    }

    // MARK: Medicine

    /// When a medicine was last given, on the household's clock: "08:10" today, "Yesterday
    /// 20:00", "15 Nov". Never when the next one is.
    static func lastGiven(_ date: Date, now: Date, in zone: TimeZone) -> String {
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))
        let day = PlainDate(date, in: zone)
        let today = PlainDate(now, in: zone)
        if day == today { return time }
        if day == today.adding(days: -1) { return "Yesterday \(time)" }
        return GraphText.midday(day, in: zone).formatted(Date.FormatStyle(timeZone: zone).day().month(.abbreviated))
    }

    /// "Vitamin D · 1 drop", or the name alone.
    static func medicineLine(_ medicine: MedicineDetails) -> String {
        guard let amount = medicine.amount, !amount.isEmpty else { return medicine.name }
        return "\(medicine.name) · \(amount)"
    }

    // MARK: Growth (the users' choice N: kilograms, with pounds and ounces beside)

    /// "3.85 kg".
    static func kilograms(_ grams: Int) -> String {
        String(format: "%.2f kg", Double(grams) / 1000)
    }

    /// "8 lb 8 oz", rounded to the nearest ounce.
    static func poundsAndOunces(_ grams: Int) -> String {
        let ounces = Int((Double(grams) / 28.349523125).rounded())
        return "\(ounces / 16) lb \(ounces % 16) oz"
    }

    /// "3.85 kg (8 lb 8 oz)".
    static func weight(_ grams: Int) -> String {
        "\(kilograms(grams)) (\(poundsAndOunces(grams)))"
    }

    /// "52.5 cm", from millimetres.
    static func centimetres(_ millimetres: Int) -> String {
        String(format: "%.1f cm", Double(millimetres) / 10)
    }

    /// A growth entry in History: "3.85 kg (8 lb 8 oz) · length 52.5 cm · head 36.0 cm".
    static func growthLine(_ growth: GrowthDetails) -> String {
        var parts: [String] = []
        if let grams = growth.weightGrams { parts.append(weight(grams)) }
        if let length = growth.lengthMM { parts.append("length \(centimetres(length))") }
        if let head = growth.headMM { parts.append("head \(centimetres(head))") }
        return parts.isEmpty ? "Growth" : parts.joined(separator: " · ")
    }

    /// Reads a weight typed in kilograms ("3.85", "3,85", "3.85 kg"). Nil when it isn't a weight
    /// a baby could be (0.3 to 30 kg).
    static func grams(fromKilograms text: String) -> Int? {
        let cleaned = text.lowercased().replacingOccurrences(of: "kg", with: "")
            .replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let kg = Double(cleaned), kg >= 0.3, kg <= 30 else { return nil }
        return Int((kg * 1000).rounded())
    }

    /// Reads a length typed in centimetres ("52.5"). Nil unless 10 to 150 cm.
    static func millimetres(fromCentimetres text: String) -> Int? {
        let cleaned = text.lowercased().replacingOccurrences(of: "cm", with: "")
            .replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let cm = Double(cleaned), cm >= 10, cm <= 150 else { return nil }
        return Int((cm * 10).rounded())
    }

    // MARK: Changing a time

    /// "5 min earlier" for the quick choices on the Change time panel: earlier than the time
    /// logged, which may itself be earlier than now.
    static func minutesEarlier(_ minutes: Int) -> String { "\(minutes) min earlier" }
}
