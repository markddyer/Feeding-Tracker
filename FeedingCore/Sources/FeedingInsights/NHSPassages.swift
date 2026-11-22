import Foundation
import FeedingCore

// The NHS passages (`docs/planning/12-ai-insights-gauntlet.md`, step 1, task AI4). Each is a
// section of an NHS web page, copied word for word from the page itself (never through a tool that
// summarises it), with the page's link and the date it was copied. The NHS website's terms
// (3.6(a)) allow an unchanged copy that is not refreshed every 7 days when it says "Information
// from the NHS website" and "as at" the date copied, links to its page, is clearly apart from the
// app's own words, and the app says once, somewhere prominent, that the content is under the Open
// Government Licence. Nothing may suggest the NHS endorses the app (3.11), so no NHS logo.
//
// Each passage carries one or more short summaries, drafted by the AI ahead of time and checked by
// Parent A with the passage (R7, D9 of the engineering review). A passage or summary is offered
// only once Parent A has checked it, and again within 90 days (D10). Passages are picked by the
// kinds logged and the baby's age, never by comparing a logged number with the NHS's (A3, O8).

/// What a passage is about. One closed list, shared by the chooser and the answer checker.
public enum InsightTopic: String, Hashable, Sendable, Codable, CaseIterable {
    case urgentHelp
    case enoughMilk
    case nappies
    case weight
    case feedingOften
    case bottleFeeding
    case sickAfterFeeds
    case expressing
    case nightAndDay
    case sleepNeeds
    case disturbedNights
    case sleepChanges
    case safeSleep
    case crying
    case jaundice
    case parentsMood

    /// The topics a card about `kind` may show.
    public static func topics(for kind: InsightKind) -> [InsightTopic] {
        switch kind {
        case .feed: [.feedingOften, .enoughMilk, .bottleFeeding, .sickAfterFeeds]
        case .nappy: [.nappies, .jaundice]
        case .sleep: [.sleepNeeds, .nightAndDay, .sleepChanges, .disturbedNights, .safeSleep]
        case .weight: [.weight]
        case .pump: [.expressing]
        case .bath, .first: []
        }
    }
}

/// A passage written for one way of feeding, offered only to a household that logs it, so a
/// bottle-only household is never nudged towards breastfeeding (A8).
public enum PassageFeeding: String, Hashable, Sendable, Codable {
    case breastfeeding
    case bottleFeeding
}

/// A short general summary of what a passage covers, drafted by the AI ahead of time and checked
/// by Parent A. Marked AI on screen, never credited to the NHS.
public struct PassageSummary: Hashable, Sendable, Identifiable {
    public let id: String
    public let words: String

    public init(id: String, words: String) {
        self.id = id
        self.words = words
    }
}

/// A section of an NHS web page, word for word.
public struct Passage: Hashable, Sendable, Identifiable {
    public let id: String
    /// The NHS page's title, as on the page.
    public let page: String
    public let url: String
    /// The section's words, exactly as on the page. A line starting "## " or "### " is a heading,
    /// and "- " starts a list item; picture credits are left out.
    public let words: String
    /// The date it was copied from the page: the "as at" date.
    public let copied: PlainDate
    public let topics: [InsightTopic]
    /// The baby's ages, in days, it is offered for; nil for any age.
    public let ageInDays: ClosedRange<Int>?
    public let feeding: PassageFeeding?
    /// The NHS's urgent list, for the Get help now card. Never picked for a card.
    public let isUrgent: Bool
    public let summaries: [PassageSummary]

    public init(id: String, page: String, url: String, topics: [InsightTopic], ageInDays: ClosedRange<Int>?,
                feeding: PassageFeeding?, isUrgent: Bool, summaries: [PassageSummary], words: String,
                copied: PlainDate = NHSPassages.copied) {
        self.id = id
        self.page = page
        self.url = url
        self.words = words
        self.copied = copied
        self.topics = topics
        self.ageInDays = ageInDays
        self.feeding = feeding
        self.isUrgent = isUrgent
        self.summaries = summaries
    }

    /// The credit the NHS's terms ask for (3.6(a)): "Information from the NHS website", as at the
    /// date copied (DD/MM/YY).
    public var attribution: String {
        let two = { (n: Int) in n < 10 ? "0\(n)" : "\(n)" }
        return "Information from the NHS website, as at \(two(copied.day))/\(two(copied.month))/\(two(copied.year % 100))"
    }
}

/// The checks Parent A has made: each passage's and summary's ID, with the day it was last checked
/// against its NHS page. Kept by the app as a household setting.
public typealias PassageChecks = [String: PlainDate]

public enum NHSPassages {
    /// When the passages below were copied from the NHS website.
    public static let copied = PlainDate(year: 2026, month: 11, day: 22)!
    /// A passage or summary must be checked again after this many days (D10).
    public static let checkEveryDays = 90
    /// The statement the NHS's terms ask for, shown once somewhere prominent (Settings).
    public static let licenceStatement = "Information from the NHS website is licensed under the Open Government Licence v3.0"
    public static let licenceURL = "https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/"

    public static var all: [Passage] { library }

    /// The NHS's urgent list, for the Get help now card. Shown whether or not it has been checked:
    /// the call buttons matter most, and the list is listed for checking like the rest.
    public static var urgent: Passage { library.first { $0.isUrgent }! }

    public static func passage(_ id: String) -> Passage? { library.first { $0.id == id } }

    /// True when Parent A checked this ID against its page on or after the copy date, within 90 days.
    public static func isChecked(_ id: String, copied: PlainDate, checks: PassageChecks, today: PlainDate) -> Bool {
        guard let checked = checks[id] else { return false }
        return checked >= copied && checked <= today && today.days(since: checked) <= checkEveryDays
    }

    /// The passages and summaries waiting for Parent A's check: never checked, checked before the
    /// copy, or checked more than 90 days ago. The Settings list flags them.
    public static func needsChecking(_ checks: PassageChecks, today: PlainDate) -> [String] {
        library.flatMap { passage in
            ([passage.id] + passage.summaries.map(\.id)).filter {
                !isChecked($0, copied: passage.copied, checks: checks, today: today)
            }
        }
    }

    /// The passages a card may show: about the kinds logged, for the baby's age (any-age passages
    /// only, with no birth date), for the ways the baby feeds, and checked by Parent A. Never chosen
    /// by a number. A few at most, turning with the day so the same few don't always show; the same
    /// on both phones for the same day.
    public static func choose(kinds: Set<InsightKind>, ageInDays: Int?, breastfeeds: Bool, bottleFeeds: Bool,
                              checks: PassageChecks, today day: PlainDate, limit: Int) -> [Passage] {
        let topics = Set(kinds.flatMap(InsightTopic.topics(for:)))
        let candidates = library.filter { passage in
            guard !passage.isUrgent, !topics.isDisjoint(with: passage.topics) else { return false }
            if let ages = passage.ageInDays {
                guard let ageInDays, ages.contains(ageInDays) else { return false }
            }
            switch passage.feeding {
            case .breastfeeding?: guard breastfeeds else { return false }
            case .bottleFeeding?: guard bottleFeeds else { return false }
            case nil: break
            }
            return isChecked(passage.id, copied: passage.copied, checks: checks, today: day)
        }
        .sorted { $0.id < $1.id }
        guard !candidates.isEmpty, limit > 0 else { return [] }
        let start = ((day.days(since: copied) % candidates.count) + candidates.count) % candidates.count
        return (0..<min(limit, candidates.count)).map { candidates[(start + $0) % candidates.count] }
    }

    /// The passages for a card made from `facts`: the kinds logged yesterday and last night, and
    /// whether any breastfeed or bottle was logged in the 4 weeks. Only whether a kind was logged
    /// counts, never how much (O8).
    public static func choose(for facts: InsightFacts, checks: PassageChecks, limit: Int) -> [Passage] {
        guard let today = facts.today else { return [] }
        return choose(kinds: facts.kindsLogged, ageInDays: facts.ageInDays,
                      breastfeeds: facts.days.contains { $0.breastFeeds > 0 },
                      bottleFeeds: facts.days.contains { $0.bottleFeeds > 0 },
                      checks: checks, today: today, limit: limit)
    }

    /// A passage's summaries Parent A has checked.
    public static func checkedSummaries(of passage: Passage, checks: PassageChecks, today: PlainDate) -> [PassageSummary] {
        passage.summaries.filter { isChecked($0.id, copied: passage.copied, checks: checks, today: today) }
    }

    // The passages, generated from the NHS pages as copied on 22 November 2026.
    static let library: [Passage] = [
        Passage(id: "urgent-help", page: #"When to get urgent medical help for babies and children under 5"#, url: "https://www.nhs.uk/baby/health/when-to-get-urgent-medical-help-for-babies-and-children-under-5/",
                topics: [.urgentHelp], ageInDays: nil, feeding: nil, isUrgent: true,
                summaries: [PassageSummary(id: "urgent-help-s1", words: #"This NHS list covers the signs in a baby that need a 999 call or a trip to A&E, and when to call NHS 111."#)],
                words: #"""
                ## Immediate action required: Call 999 or go to A&E if:
                A baby or child under 5 years old:
                - has swollen lips, tongue or throat with difficulty swallowing or talking
                - is breathing very fast or has difficulty breathing – they may make grunting noises or suck in their tummy when they breathe
                - has blue, grey, pale or blotchy (mottled) skin, lips or tongue – on black or brown skin, this may be easier to see on the palms of their hands or soles of their feet
                - has skin that feels cold or damp (clammy) to touch
                - has a rash that does not fade when you press it
                - has a very high temperature – 38C or higher in babies under 3 months old, or 39C or higher in babies 3 to 6 months old
                - has a very low temperature – less than 36C, or feels cold to touch or is shivery
                - has a weak, high-pitched or continuous cry
                - has fainted, is difficult to wake, or cannot be woken
                - has not had a pee in the past 12 hours
                - is having a seizure (fit)
                ### Important: Trust your instincts
                Get immediate medical help if your child is unwell and you think there's something seriously wrong.
                Keep checking for new or changing symptoms when they’re unwell, even during the night.
                ## Urgent advice: Call NHS 111 if:
                - you’re worried about any of your child’s symptoms or do not know what to do
                """#),
        Passage(id: "enough-milk-signs", page: #"Breastfeeding: is my baby getting enough milk?"#, url: "https://www.nhs.uk/baby/breastfeeding-and-bottle-feeding/breastfeeding-problems/enough-milk/",
                topics: [.enoughMilk], ageInDays: nil, feeding: .breastfeeding, isUrgent: false,
                summaries: [PassageSummary(id: "enough-milk-signs-s1", words: #"This NHS page lists signs during and after a breastfeed that a baby is getting milk."#)],
                words: #"""
                ## Signs your baby is getting enough milk
                - Your baby starts feeds with a few rapid sucks followed by long, rhythmic sucks and swallows with occasional pauses.
                - You can hear and see your baby swallowing.
                - Your baby's cheeks stay rounded, not hollow, during sucking.
                - They seem calm and relaxed during feeds.
                - Your baby comes off the breast on their own at the end of feeds.
                - Their mouth looks moist after feeds.
                - Your baby appears content and satisfied after most feeds.
                - Your breasts feel softer after feeds.
                - Your nipple looks more or less the same after feeds – not flattened, pinched or white.
                - You may feel sleepy and relaxed after feeds.
                """#),
        Passage(id: "feeding-well-signs", page: #"Breastfeeding: is my baby getting enough milk?"#, url: "https://www.nhs.uk/baby/breastfeeding-and-bottle-feeding/breastfeeding-problems/enough-milk/",
                topics: [.enoughMilk, .nappies, .weight], ageInDays: 0...56, feeding: .breastfeeding, isUrgent: false,
                summaries: [PassageSummary(id: "feeding-well-signs-s1", words: #"This NHS page describes other signs that breastfeeding is going well in the first weeks, including weight, poos and wet nappies."#)],
                words: #"""
                ## Other signs your baby is feeding well
                - Your baby gains weight steadily after the first 3 to 4 days – it's normal for babies to lose some of their birth weight in the first 3 to 4 days.
                - They appear healthy and alert when they're awake.
                - From the fourth day, they should do at least 2 soft, yellow poos the size of a £2 coin every day for the first few weeks.
                - From day 5 onwards, wet nappies should start to become more frequent, with at least 6 heavy, wet nappies every 24 hours. In the first 48 hours, your baby is likely to have only 2 or 3 wet nappies.
                It can be hard to tell if disposable nappies are wet. To get an idea, take an unused nappy and add 2 to 4 tablespoons of water. This will give you an idea of what to look and feel for.
                """#),
        Passage(id: "feeding-how-often", page: #"Breastfeeding: the first few days"#, url: "https://www.nhs.uk/baby/breastfeeding-and-bottle-feeding/breastfeeding/the-first-few-days/",
                topics: [.feedingOften], ageInDays: 0...56, feeding: .breastfeeding, isUrgent: false,
                summaries: [PassageSummary(id: "feeding-how-often-s1", words: #"This NHS page is about how often babies breastfeed in the first weeks, and the early signs that a baby is hungry."#)],
                words: #"""
                ## How often should I feed my baby?
                In the first week, your baby may want to feed very often. It could be every 1 to 3 hours in the first few days.
                Feed your baby as often as they want and for as long as they want. They'll begin to have fewer, but longer feeds after a few days.
                As a very rough guide, your baby should feed at least 8 to 12 times, or more, every 24 hours during the first few weeks.
                It's fine to feed your baby whenever they are hungry, when your breasts feel full or if you just want to have a cuddle.
                It's not possible to overfeed a breastfed baby.
                When your baby is hungry they may:
                - get restless
                - suck their fist or fingers
                - make murmuring sounds
                - turn their head and open their mouth (rooting)
                It's best to try and feed your baby during these early feeding cues as a crying baby is difficult to feed.
                """#),
        Passage(id: "milk-supply", page: #"Breastfeeding: the first few days"#, url: "https://www.nhs.uk/baby/breastfeeding-and-bottle-feeding/breastfeeding/the-first-few-days/",
                topics: [.feedingOften, .enoughMilk], ageInDays: 0...56, feeding: .breastfeeding, isUrgent: false,
                summaries: [PassageSummary(id: "milk-supply-s1", words: #"This NHS page explains how milk supply builds up in the first days, and why night feeds matter for it."#)],
                words: #"""
                ## Building up your milk supply
                Around 2 to 4 days after birth you may notice that your breasts become fuller. This is often referred to as your milk coming in.
                Your milk will vary according to your baby's needs. Each time your baby feeds, your body knows to make more milk for the next feed. The amount of milk you make will increase or decrease depending on how often your baby feeds.
                Feed your baby as often as they want and for as long as they want. This is called responsive feeding. In other words, responding to your baby's needs. It's also known as on-demand or baby-led feeding.
                In the beginning, it can feel like you're doing nothing but feeding. But gradually you and your baby will get into a pattern and the amount of milk you produce will settle down.
                It's important to breastfeed at night because this is when you produce more hormones (prolactin) to build up your milk supply.
                In the early weeks, before you and your baby have become comfortable with breastfeeding, topping up with formula milk or giving your baby a dummy can lower your milk supply.
                Speak to a midwife or health visitor if you are worried about breastfeeding or you think your baby is not getting enough milk.
                They might suggest giving your baby some expressed breast milk along with breastfeeding.
                """#),
        Passage(id: "bottle-guided", page: #"Bottle feeding advice"#, url: "https://www.nhs.uk/baby/breastfeeding-and-bottle-feeding/bottle-feeding/advice/",
                topics: [.bottleFeeding], ageInDays: nil, feeding: .bottleFeeding, isUrgent: false,
                summaries: [PassageSummary(id: "bottle-guided-s1", words: #"This NHS advice is about following a baby's lead with bottle feeds, winding, and throwing away unused milk."#)],
                words: #"""
                ### Be guided by your baby
                All babies are different. Your baby will know how much milk they need. Some want to feed more often than others. Just follow your baby's lead.
                Feed your baby when they seem hungry and do not worry if they do not finish the bottle.
                ### Winding your baby
                Your baby may take short breaks during a feed and may sometimes need to burp.
                When your baby has had enough milk, hold them upright and gently rub or pat their back to bring up any wind.
                ### Throw away unused milk
                Throw away any unused formula or breast milk after you've finished bottle feeding your baby.
                Only make up the feed when needed – one feed at a time.
                """#),
        Passage(id: "bottle-settle-sick", page: #"Bottle feeding advice"#, url: "https://www.nhs.uk/baby/breastfeeding-and-bottle-feeding/bottle-feeding/advice/",
                topics: [.bottleFeeding, .sickAfterFeeds], ageInDays: nil, feeding: .bottleFeeding, isUrgent: false,
                summaries: [PassageSummary(id: "bottle-settle-sick-s1", words: #"This NHS page answers common questions about babies not settling, or bringing up milk, after bottle feeds."#)],
                words: #"""
                ## Your questions about bottle feeding
                ### Why does my baby not settle after feeds?
                If your baby swallows air while bottle feeding, they may feel uncomfortable and cry.
                After a feed, hold your baby upright against your shoulder or propped forward on your lap. Gently rub their back so any trapped air can find its way out.
                Your baby may sometimes only burp up a small amount of air.
                ### Why is my baby sometimes sick after feeds?
                It's normal for babies to bring up a little milk during or just after a feed. This is called posseting, regurgitation or reflux.
                Keep a muslin square handy just in case.
                Check that the hole in your baby's teat is not too big. Drinking milk too quickly can make your baby sick.
                Do not force them to take more milk than they want during a feed. This may be distressing for your baby and can lead to overfeeding.
                Sitting your baby upright on your lap after a feed may help.
                If it happens a lot, or your baby is violently sick, seems to be in pain or you're worried for any other reason, talk to your health visitor or GP.
                """#),
        Passage(id: "storing-milk", page: #"Expressing and storing breast milk"#, url: "https://www.nhs.uk/baby/breastfeeding-and-bottle-feeding/breastfeeding/expressing-breast-milk/",
                topics: [.expressing], ageInDays: nil, feeding: nil, isUrgent: false,
                summaries: [PassageSummary(id: "storing-milk-s1", words: #"This NHS page explains how long expressed breast milk keeps in the fridge and freezer."#)],
                words: #"""
                ## Storing breast milk
                You can store breast milk in a sterilised container or in special breast milk storage bags:
                - in the back of the fridge for up to 8 days at 4C or lower (you can buy fridge thermometers online) – if you're not sure of the temperature of your fridge, or it runs between 5C to 10C, use it within 3 days
                - for 2 weeks in the ice compartment of a fridge
                - for up to 6 months in a freezer, if it's -18C or lower
                Breast milk that's been cooled in the fridge can be carried in a cool bag with ice packs for up to 24 hours.
                Storing breast milk in small quantities will help avoid waste. If you're freezing it, make sure you label and date it first.
                """#),
        Passage(id: "night-and-day", page: #"Helping your baby to sleep"#, url: "https://www.nhs.uk/baby/caring-for-a-newborn/helping-your-baby-to-sleep/",
                topics: [.nightAndDay], ageInDays: nil, feeding: nil, isUrgent: false,
                summaries: [PassageSummary(id: "night-and-day-s1", words: #"This NHS advice is about helping a baby learn that night-time is different from the day."#)],
                words: #"""
                ## How can I get my baby used to night and day?
                It's a good idea to teach your baby that night-time is different from daytime from the start. During the day, open curtains, play games and do not worry too much about everyday noises when they sleep.
                At night, you might find it helpful to:
                - keep the lights down low
                - not talk much and keep your voice quiet
                - put your baby down as soon as they've been fed and changed
                - not change your baby unless they need it
                - not play with your baby
                Your baby will gradually learn that night-time is for sleeping.
                """#),
        Passage(id: "newborn-sleep", page: #"Helping your baby to sleep"#, url: "https://www.nhs.uk/baby/caring-for-a-newborn/helping-your-baby-to-sleep/",
                topics: [.sleepNeeds], ageInDays: 0...90, feeding: nil, isUrgent: false,
                summaries: [PassageSummary(id: "newborn-sleep-s1", words: #"This NHS page describes how much newborn babies sleep, and why they wake in the night."#)],
                words: #"""
                ## How much sleep does your baby need?
                Just as with adults, babies' and children's sleep patterns vary. From birth, some babies need more or less sleep than others. The list below shows the average amount of sleep babies and children need during a 24-hour period, including daytime naps.
                ### Newborn sleep needs
                Most newborn babies are asleep more than they are awake. Their total daily sleep varies, but can be around 18 hours. Babies will wake during the night because they need to be fed. Being too hot or too cold can also disturb their sleep.
                """#),
        Passage(id: "disturbed-nights", page: #"Helping your baby to sleep"#, url: "https://www.nhs.uk/baby/caring-for-a-newborn/helping-your-baby-to-sleep/",
                topics: [.disturbedNights], ageInDays: nil, feeding: nil, isUrgent: false,
                summaries: [PassageSummary(id: "disturbed-nights-s1", words: #"This NHS advice is about coping with broken nights, and sharing night-time care between parents."#)],
                words: #"""
                ## Coping with disturbed nights
                Newborn babies invariably wake up repeatedly in the night for the first few months, and disturbed nights can be very hard to cope with.
                If you have a partner, ask them to help. If you're formula feeding, encourage your partner to share the feeds. If you're breastfeeding, ask your partner to take over the early morning changing and dressing so you can go back to sleep.
                Once you're into a good breastfeeding routine, your partner could occasionally give a bottle of expressed breast milk during the night. If you're on your own, you could ask a friend or relative to stay for a few days so you can get some sleep.
                """#),
        Passage(id: "sleep-changes", page: #"Helping your baby to sleep"#, url: "https://www.nhs.uk/baby/caring-for-a-newborn/helping-your-baby-to-sleep/",
                topics: [.sleepChanges], ageInDays: nil, feeding: nil, isUrgent: false,
                summaries: [PassageSummary(id: "sleep-changes-s1", words: #"This NHS advice explains that babies' sleep patterns change as they grow, and where to get help."#)],
                words: #"""
                ## Dealing with baby sleep pattern changes
                All babies change their sleep patterns.
                Be prepared to change routines as your baby grows and enters different stages. And remember, growth spurts, teething and illnesses can all affect how your baby sleeps.
                If your baby is having problems sleeping or you need more advice about getting into a routine, speak to your health visitor.
                """#),
        Passage(id: "safe-sleep-do", page: #"Sudden infant death syndrome (SIDS)"#, url: "https://www.nhs.uk/baby/caring-for-a-newborn/sudden-infant-death-syndrome-sids/",
                topics: [.safeSleep], ageInDays: nil, feeding: nil, isUrgent: false,
                summaries: [PassageSummary(id: "safe-sleep-do-s1", words: #"This NHS list sets out the steps to follow at every sleep to lower the risk of sudden infant death syndrome."#)],
                words: #"""
                ## How to reduce the risk of sudden infant death syndrome (SIDS)
                There are things you can do to lower the risk of sudden infant death syndrome (SIDS). Follow this advice whenever your baby is sleeping.
                If your baby was born prematurely, follow the advice for safer sleep for a year from their due date not the date they were born.
                ### Do
                always place your baby on their back to sleep in the feet-to-foot position – this means with their feet at the bottom of the cot, Moses basket or pram
                move your baby onto their back if they roll (until they can roll onto their front and back again by themselves)
                place your baby in a separate cot or Moses basket in the same room as you for every sleep for at least the first 6 months
                use a firm, flat mattress
                keep your baby's cot clear of anything that could cover their face and head – do not use pillows, duvets, cot bumpers, loose blankets, soft toys or anything to keep your baby in place, like pods or nests
                breastfeed your baby if you can – breastmilk protects your baby from infections and diseases
                think about using a dummy to settle your baby to sleep – some research suggests this can help lower the risk of SIDS
                make sure your baby is up to date with their routine NHS vaccinations – these provide protection against childhood illnesses that may increase the risk of SIDS
                """#),
        Passage(id: "safe-sleep-dont", page: #"Sudden infant death syndrome (SIDS)"#, url: "https://www.nhs.uk/baby/caring-for-a-newborn/sudden-infant-death-syndrome-sids/",
                topics: [.safeSleep], ageInDays: nil, feeding: nil, isUrgent: false,
                summaries: [PassageSummary(id: "safe-sleep-dont-s1", words: #"This NHS list sets out the things to avoid to lower the risk of sudden infant death syndrome."#)],
                words: #"""
                ### Don't
                do not sleep on a sofa or in an armchair with your baby
                do not smoke when you're pregnant or around your baby after they're born, and do not let anyone smoke in the same room as your baby
                do not share a bed with your baby if they were born prematurely (before 37 weeks of pregnancy) or if they weighed less than 2.5kg or 5.5lb when they were born
                do not share a bed with your baby if you or your partner smoke, drink alcohol or take drugs or medicine that makes you feel sleepy (drowsy)
                do not let your baby get too hot or too cold – make sure that your baby's room is between 16C to 20C
                do not let your baby stay in a car seat for too long – it's ok for your baby to fall asleep in a car seat while you are travelling, but take your baby out of the car seat as soon as you get to where you're going
                """#),
        Passage(id: "calm-crying", page: #"Soothing a crying baby"#, url: "https://www.nhs.uk/baby/caring-for-a-newborn/soothing-a-crying-baby/",
                topics: [.crying], ageInDays: nil, feeding: nil, isUrgent: false,
                summaries: [PassageSummary(id: "calm-crying-s1", words: #"This NHS page suggests ways to comfort a crying baby."#)],
                words: #"""
                ## How to calm a crying baby
                Try some of the following ways to comfort your baby. Some may work better than others:
                - If you're breastfeeding, let your baby suckle at your breast.
                - Having some gentle noise in the background may help distract your baby.
                - Hold your baby or put them in a sling so they're close to you. Move about gently, sway and dance, talk to them and sing. Find out more about safe babywearing on the RoSPA website
                - Rock your baby backwards and forwards in the pram, or go out for a walk or a drive. But if they fall asleep during a drive, take them out of their car seat as soon as possible and put them on a firm, flat surface to sleep.
                - Find something for them to listen to or look at. This could be music on the radio, a rattle, or a mobile above the cot.
                - Try stroking your baby's back gently up and down while you're holding them against you or they're lying face down on your lap.
                - Try a warm bath. This calms some babies instantly, but makes others cry even more.
                - Sometimes too much rocking and singing can keep your baby awake. You might find lying them down after a feed will help.
                For more ideas, ask your health visitor for advice.
                """#),
        Passage(id: "crying-colic", page: #"Soothing a crying baby"#, url: "https://www.nhs.uk/baby/caring-for-a-newborn/soothing-a-crying-baby/",
                topics: [.crying], ageInDays: 0...150, feeding: nil, isUrgent: false,
                summaries: [PassageSummary(id: "crying-colic-s1", words: #"This NHS page describes excessive crying and colic, and how hard it can be for parents."#)],
                words: #"""
                ## If your baby cries constantly
                There are several reasons why a baby may cry excessively.
                It can be exhausting if you have tried everything and nothing seems to comfort your baby.
                ### Colic
                Excessive crying could be a sign that your baby has colic. This sometimes happens in babies who are under 5 months old. Everyone agrees that colic exists, but nobody knows what causes it.
                Some doctors think it's a kind of stomach cramp. The crying sounds miserable and distressed, and stops for a moment or two, then starts up again, which suggests it could be caused by waves of stomach pain.
                The crying can go on for some hours. There may be little you can do except try to comfort your baby and wait for the crying to pass.
                """#),
        Passage(id: "jaundice-signs", page: #"Jaundice in babies"#, url: "https://www.nhs.uk/conditions/jaundice-in-babies/",
                topics: [.jaundice, .nappies], ageInDays: 0...28, feeding: nil, isUrgent: false,
                summaries: [PassageSummary(id: "jaundice-signs-s1", words: #"This NHS page describes how jaundice shows in newborn babies, and when to ask for an urgent appointment or call NHS 111."#)],
                words: #"""
                ## Symptoms of jaundice in babies
                The main symptom of jaundice in babies is their eyes or skin look yellow.
                You may notice yellow:
                - in the whites of their eyes
                - on their skin – this usually starts on the face and head and can spread to the rest of the body
                - under their tongue or inside their cheeks
                The yellow can be easier to see in bright light or sunlight. Pressing gently on the tip of your baby’s nose or forehead may also make the yellow easier to see.
                It can be harder to see yellow on black or brown skin.
                For most babies with jaundice, the yellow is most noticeable when they’re around 3 days old. It usually takes around 2 weeks for the jaundice to go.
                ## Urgent advice: Ask for an urgent GP or midwife appointment or call NHS 111 if:
                Your baby is over 24 hours old and:
                - you think they have jaundice
                - they’ve been diagnosed with jaundice and it’s not getting better, or is getting worse
                - their pee is dark yellow or brown or their poo is a pale creamy colour (keep a sample of poo to show a midwife or doctor)
                """#),
        Passage(id: "postnatal-depression", page: #"Postnatal depression"#, url: "https://www.nhs.uk/mental-health/conditions/postnatal-depression/",
                topics: [.parentsMood], ageInDays: nil, feeding: nil, isUrgent: false,
                summaries: [PassageSummary(id: "postnatal-depression-s1", words: #"This NHS page lists the signs of postnatal depression, which can affect either parent, and where to get help."#)],
                words: #"""
                ## Symptoms of postnatal depression
                Symptoms of postnatal depression include:
                - low mood
                - finding it hard to enjoy anything
                - feeling hopeless or that you cannot cope
                - feeling guilty or worthless, or that you're a bad parent
                - feeling fearful, anxious, or worrying all the time
                - feeling restless or irritable
                - difficulty sleeping, even when you get time to rest
                - difficulty concentrating or making decisions
                - difficult feelings about, or difficulty bonding with your baby
                - thoughts of suicide, harming yourself or your baby
                Symptoms can begin while you're pregnant, soon after birth, or up to a year after your baby is born.
                ### If you're not sure it's postnatal depression
                Feeling down, anxious or irritable for a few days after your baby is born is very common. This is sometimes called the baby blues, and it usually goes away within 2 weeks of the birth. But if it continues, gets worse or you're struggling to cope, it's important to get help.
                Fathers and partners can also have depression after having a baby.
                ## Non-urgent advice: Speak to your GP, midwife or health visitor if:
                - you think you might have postnatal depression
                It's important to get help even if you only have some of the signs. You're more likely to get better with treatment.
                """#),
        Passage(id: "feeding-sick-help", page: #"Bottle feeding advice"#, url: "https://www.nhs.uk/baby/breastfeeding-and-bottle-feeding/bottle-feeding/advice/",
                topics: [.bottleFeeding], ageInDays: nil, feeding: .bottleFeeding, isUrgent: false,
                summaries: [PassageSummary(id: "feeding-sick-help-s1", words: #"This NHS advice says where to find help and support with bottle feeding."#)],
                words: #"""
                ## Help with bottle feeding
                Talk to your midwife, health visitor or other mothers who have bottle fed if you need help and support.
                You'll find the phone number for your health visitor in your baby's personal health record (red book).
                """#),
    ]
}

extension InsightFacts {
    /// The day the sheet was made: the day after yesterday, or after last night's evening.
    public var today: PlainDate? { (yesterday?.date ?? lastNight?.evening)?.adding(days: 1) }

    /// The kinds logged yesterday or last night.
    public var kindsLogged: Set<InsightKind> {
        var kinds: Set<InsightKind> = []
        if let day = yesterday {
            if day.feeds > 0 { kinds.insert(.feed) }
            if day.pumpSessions > 0 { kinds.insert(.pump) }
            if day.sleepSeconds > 0 { kinds.insert(.sleep) }
            if day.wees + day.poos + day.nappiesWithUnreadDetails > 0 { kinds.insert(.nappy) }
            if !day.baths.isEmpty { kinds.insert(.bath) }
            if day.weightsLogged > 0 { kinds.insert(.weight) }
            if day.firstsAdded > 0 { kinds.insert(.first) }
        }
        if let night = lastNight {
            if night.feeds > 0 { kinds.insert(.feed) }
            if night.sleptSeconds > 0 { kinds.insert(.sleep) }
            if night.wees + night.poos > 0 { kinds.insert(.nappy) }
        }
        return kinds
    }
}
