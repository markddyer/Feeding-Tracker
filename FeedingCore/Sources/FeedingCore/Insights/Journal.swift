import Foundation

// The facts the Journal shows (`docs/planning/07-milestones-journal.md`): the baby's age at each
// first, how the line through time is grouped, and the Firsts list. Facts only: never a typical
// age, never "late" or "early".

/// The baby's age on a day, as completed time on the household's calendar (journal plan, "The
/// baby's age"). It is worked out each time it is shown and never stored, so correcting the birth
/// date corrects every age.
public enum BabyAge: Hashable, Sendable {
    /// The birth date itself (design review D33: "Day of birth", which stays true when read later).
    case dayOfBirth
    /// 1 to 13 days.
    case days(Int)
    /// From 2 weeks to under 3 months, in whole weeks.
    case weeks(Int)
    /// From 3 months to under 2 years, in whole months.
    case months(Int)
    /// From 2 years: whole years, and the whole months past them.
    case years(Int, months: Int)

    /// Nil before the birth date.
    public init?(on day: PlainDate, birthDate: PlainDate) {
        let days = day.days(since: birthDate)
        guard days >= 0 else { return nil }
        // A month is complete on the same day of the month. A birth day the month doesn't have
        // (the 31st, or 29 February) completes on the 1st of the next month.
        let months = (day.year - birthDate.year) * 12 + (day.month - birthDate.month) - (day.day < birthDate.day ? 1 : 0)
        switch (days, months) {
        case (0, _): self = .dayOfBirth
        case (..<14, _): self = .days(days)
        case (_, ..<3): self = .weeks(days / 7)
        case (_, ..<24): self = .months(months)
        default: self = .years(months / 12, months: months % 12)
        }
    }

    /// The age at `date`, a moment, on the household's calendar. Nil before the birth date.
    public init?(at date: Date, birthDate: PlainDate, in timeZone: TimeZone) {
        self.init(on: PlainDate(date, in: timeZone), birthDate: birthDate)
    }

    /// "Day of birth", "5 days", "8 weeks", "7 months", "2 years 3 months".
    public var words: String {
        func count(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }
        switch self {
        case .dayOfBirth: return "Day of birth"
        case .days(let n): return count(n, "day")
        case .weeks(let n): return count(n, "week")
        case .months(let n): return count(n, "month")
        case .years(let years, let months):
            return months == 0 ? count(years, "year") : "\(count(years, "year")) \(count(months, "month"))"
        }
    }
}

/// A group on the Journal's line through time. The groups use the age's own unit; with no birth
/// date, calendar months.
public enum JournalGroup: Hashable, Sendable {
    case age(BabyAge)
    case month(year: Int, month: Int)

    /// The group of a first on `day`.
    public init(day: PlainDate, birthDate: PlainDate?) {
        if let birthDate, let age = BabyAge(on: day, birthDate: birthDate) {
            self = .age(age)
        } else {
            self = .month(year: day.year, month: day.month)
        }
    }
}

/// One row of the Firsts list (X2, D9; design review D42).
public struct FirstsListRow: Hashable, Sendable, Identifiable {
    /// The first's event ID: a tap opens its page.
    public var id: String
    public var title: String
    public var date: PlainDate
    /// Nil with no birth date.
    public var age: BabyAge?

    /// "Rolled over · 5 months · 3 Mar", with the year when it isn't `today`'s year; with no
    /// birth date, "Rolled over · 3 Mar".
    public func line(today: PlainDate) -> String {
        ([title] + [age?.words].compactMap { $0 } + [Self.words(date, withYear: date.year != today.year)])
            .joined(separator: " · ")
    }

    /// "3 Mar 2027", or "3 Mar".
    public static func words(_ date: PlainDate, withYear: Bool) -> String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let dayAndMonth = "\(date.day) \(months[date.month - 1])"
        return withYear ? "\(dayAndMonth) \(date.year)" : dayAndMonth
    }
}

extension HouseholdData {
    /// The Firsts list: each first of `babyID` with its date and the baby's age at it, oldest
    /// first, on the household's calendar.
    public func firstsList(babyID: String) -> [FirstsListRow] {
        let timeZone = householdSettings.timeZone
        let birth = birthDate(babyID: babyID)
        return milestones(babyID: babyID).map { first in
            let day = PlainDate(first.event.startedAt, in: timeZone)
            return FirstsListRow(id: first.id, title: first.payload?.milestone?.title ?? "", date: day,
                                 age: birth.flatMap { BabyAge(on: day, birthDate: $0) })
        }
    }
}

extension [FirstsListRow] {
    /// The whole list as text, for "Copy as text": one line per first, oldest first. Every date
    /// has its year, as the text is read later and elsewhere (the red book, a check).
    public var copiedText: String {
        map { row in
            ([row.title] + [row.age?.words].compactMap { $0 } + [FirstsListRow.words(row.date, withYear: true)])
                .joined(separator: " · ")
        }.joined(separator: "\n")
    }
}
