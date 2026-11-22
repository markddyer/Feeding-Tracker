import Foundation
import Testing
@testable import FeedingInsights

// The danger-sign check and the medicine-question check (task AI3, A2, O2, O3). Each sign is
// written many ways: typed fast, with typos, dictated, and with "not" (which must still open the
// card, as "alert too much" asks).

/// Phrasings that must open the Get help now card, with the sign each must find.
let dangerPhrasings: [(String, DangerSign)] = [
    // A temperature, at any reading or age.
    ("She feels really hot and she's very sleepy", .temperature),
    ("temp is 38.2", .temperature),
    ("Her temperature is 37.9", .temperature),
    ("38C", .temperature),
    ("38 degrees", .temperature),
    ("thermometer says 38.5", .temperature),
    ("he's got a fever", .temperature),
    ("feverish and grumpy", .temperature),
    ("she is burning up", .temperature),
    ("Baby feels very cold", .temperature),
    ("feels cold and clammy", .temperature),
    ("tempurature of 38", .temperature),
    ("Is 37.5 ok", .temperature),
    ("36.1 under the arm", .temperature),
    ("she's boiling", .temperature),
    ("Her temp is high", .temperature),
    ("38°", .temperature),
    ("shivering", .temperature),
    // No wee, at any number of hours.
    ("no wet nappy since lunch", .noWee),
    ("No wee for 6 hours", .noWee),
    ("she hasn't weed all day", .noWee),
    ("hasnt peed since this morning", .noWee),
    ("his nappy is dry", .noWee),
    ("dry nappies all afternoon", .noWee),
    ("Not had a wet nappy since 2", .noWee),
    ("she still hasn't had a wet nappy", .noWee),
    ("no wet nappies today", .noWee),
    ("not weeing much", .noWee),
    ("no proper wet nappy", .noWee),
    ("Nappies are dry", .noWee),
    ("no pee in 12 hours", .noWee),
    ("she isn't wet", .noWee),
    ("He's not peeing", .noWee),
    // Hard to wake.
    ("she's hard to wake", .hardToWake),
    ("I can't wake her up", .hardToWake),
    ("he won't wake for feeds", .hardToWake),
    ("very sleepy and not interested", .hardToWake),
    ("she seems floppy", .hardToWake),
    ("Baby is limp", .hardToWake),
    ("unresponsive", .hardToWake),
    ("not responding to me", .hardToWake),
    ("really drowsy today", .hardToWake),
    ("lethargic all day", .hardToWake),
    ("difficult to wake this morning", .hardToWake),
    ("keeps falling asleep and won't stay awake", .hardToWake),
    ("floppy arms", .hardToWake),
    ("she's so sleepy", .hardToWake),
    ("unusualy sleepy", .hardToWake),
    // Breathing.
    ("she's breathing fast", .breathing),
    ("fast breathing while asleep", .breathing),
    ("he's grunting with every breath", .breathing),
    ("grunting noises", .breathing),
    ("struggling to breathe", .breathing),
    ("he stopped breathing for a second", .breathing),
    ("breathing funny", .breathing),
    ("wheezing", .breathing),
    ("she's gasping", .breathing),
    ("ribs sucking in when she breathes", .breathing),
    ("pauses in breathing", .breathing),
    ("noisy breathing all night", .breathing),
    ("breathing really hard", .breathing),
    ("she can't breathe properly", .breathing),
    ("not breathing", .breathing),
    ("breathin fast", .breathing),
    ("she choked on milk", .breathing),
    // Colour.
    ("she's gone a bit blue", .colour),
    ("blue lips", .colour),
    ("his lips look grey", .colour),
    ("skin looks gray", .colour),
    ("blotchy skin", .colour),
    ("mottled legs", .colour),
    ("very pale", .colour),
    ("looking ashen", .colour),
    ("bluish around the mouth", .colour),
    ("her feet are purple", .colour),
    ("she's not blue but", .colour),
    ("blueish lips", .colour),
    // Rash.
    ("a rash that doesn't fade", .rash),
    ("rash on her tummy", .rash),
    ("spots that dont fade with a glass", .rash),
    ("did the glass test", .rash),
    ("purple spots", .rash),
    ("tiny red spots", .rash),
    ("non-blanching rash", .rash),
    ("pin prick spots", .rash),
    ("bruising on legs", .rash),
    ("rash and a temp", .rash),
    // Cry.
    ("a high-pitched cry", .cry),
    ("high pitched screaming", .cry),
    ("weak cry", .cry),
    ("crying non-stop", .cry),
    ("she won't stop crying", .cry),
    ("inconsolable for 3 hours", .cry),
    ("moaning all the time", .cry),
    ("a strange cry", .cry),
    ("crying constantly", .cry),
    ("screaming for hours", .cry),
    ("whimpering", .cry),
    ("crying for hours and can't settle", .cry),
    // A fit.
    ("I think she had a fit", .fit),
    ("he's having a seizure", .fit),
    ("convulsions", .fit),
    ("her arms were jerking", .fit),
    ("twitching in her sleep", .fit),
    ("went stiff and shaking", .fit),
    ("eyes rolling back", .fit),
    ("is she fitting", .fit),
    ("siezure", .fit),
    ("spasms", .fit),
    // Not feeding.
    ("she's not feeding", .notFeeding),
    ("he won't feed", .notFeeding),
    ("refusing feeds all day", .notFeeding),
    ("refusing the bottle", .notFeeding),
    ("not interested in feeding", .notFeeding),
    ("stopped feeding", .notFeeding),
    ("not drinking her milk", .notFeeding),
    ("won't take any milk", .notFeeding),
    ("not latching at all", .notFeeding),
    ("hardly feeding", .notFeeding),
    ("barely feeding today", .notFeeding),
    ("she's not had a feed since 6", .notFeeding),
    ("too weak to feed", .notFeeding),
    ("not feding", .notFeeding),
    ("refusing to feed", .notFeeding),
    // Jaundice.
    ("her skin looks yellow", .jaundice),
    ("yellow eyes", .jaundice),
    ("the whites of his eyes are yellow", .jaundice),
    ("is she jaundiced", .jaundice),
    ("jaundice", .jaundice),
    ("pale poo", .jaundice),
    ("white poo", .jaundice),
    ("chalky poo", .jaundice),
    ("dark wee", .jaundice),
    ("dark pee in the nappy", .jaundice),
    ("turning yellow", .jaundice),
    ("jaundise", .jaundice),
    // Vomit.
    ("green vomit", .vomit),
    ("she was sick and it was green", .vomit),
    ("vomiting green", .vomit),
    ("projectile vomiting", .vomit),
    ("keeps being sick", .vomit),
    ("can't keep anything down", .vomit),
    ("blood in her vomit", .vomit),
    ("bile in sick", .vomit),
    ("projectle vomit", .vomit),
    ("sick after every feed", .vomit),
    // The soft spot.
    ("her soft spot is bulging", .softSpot),
    ("the fontanelle looks sunken", .softSpot),
    ("bulging fontanelle", .softSpot),
    ("sunken soft spot", .softSpot),
    ("bump on head", .softSpot),
    // Blood.
    ("blood in her poo", .blood),
    ("bloody nappy", .blood),
    ("black poo after day 5", .blood),
    ("she's bleeding", .blood),
    ("red poo", .blood),
    // Injury.
    ("she fell off the sofa", .injury),
    ("he rolled off the bed", .injury),
    ("I dropped her", .injury),
    ("hit his head", .injury),
    ("banged head on the cot", .injury),
    ("she swallowed a button", .injury),
    ("might have swallowed something", .injury),
    ("burnt her hand", .injury),
    ("scalded", .injury),
    ("allergic reaction", .injury),
    ("swollen lips", .injury),
    ("had a fall", .injury),
    // Seriously unwell.
    ("I think something is wrong", .seriouslyUnwell),
    ("she seems seriously ill", .seriouslyUnwell),
    ("very unwell", .seriouslyUnwell),
    ("not herself at all", .seriouslyUnwell),
    ("should I call 111", .seriouslyUnwell),
    ("do I need to call 999", .seriouslyUnwell),
    ("ambulance?", .seriouslyUnwell),
    ("is this an emergency", .seriouslyUnwell),
    ("should we go to A&E", .seriouslyUnwell),
    ("she collapsed", .seriouslyUnwell),
    ("could it be meningitis", .seriouslyUnwell),
    ("sepsis", .seriouslyUnwell),
    ("is she dehydrated", .seriouslyUnwell),
    ("sunken eyes", .seriouslyUnwell),
    ("dry mouth and no tears", .seriouslyUnwell),
    ("cold hands and feet", .seriouslyUnwell),
    ("something not right", .seriouslyUnwell),
    ("not himself today", .seriouslyUnwell),
    ("really unwell", .seriouslyUnwell),
    ("very ill", .seriouslyUnwell),
    // Dictated, run-on and mixed.
    ("she is really hot and floppy and not feeding", .temperature),
    ("she is really hot and floppy and not feeding", .hardToWake),
    ("she is really hot and floppy and not feeding", .notFeeding),
    ("gone a bit blue and grunting", .breathing),
    ("no wet nappy and very sleepy", .noWee),
    ("no wet nappy and very sleepy", .hardToWake),
    ("SHE IS HARD TO WAKE", .hardToWake),
    ("she’s breathing fast", .breathing),
    ("Hasn’t weed since lunch", .noWee),
    ("not feeding well and a temp of 38", .notFeeding),
    ("rash that doesnt fade and a fever", .rash),
    ("rash that doesnt fade and a fever", .temperature),
    ("yellow skin and pale poo", .jaundice),
    ("green sick and floppy", .vomit),
]

/// Everyday questions that must not open the card.
let ordinaryQuestions = [
    "When did she last feed?",
    "How much did she drink yesterday?",
    "What does the NHS say about wind?",
    "Longest sleep this week?",
    "How many wet nappies today?",
    "Is yellow poo normal for breastfed babies?",
    "How do I bath her?",
    "How often should newborns feed?",
    "She's sitting in her bouncer, is that ok for naps?",
    "Why does she have fewer feeds at night now?",
    "How can I help her fall asleep?",
    "She fell asleep on the breast again",
    "How long should a feed take?",
    "Which side did I start on?",
    "Is it ok to wake her for a feed?",
    "What time did she go down last night?",
    "How much formula for a two week old?",
    "When will she sleep through the night?",
    "What's a good bedtime routine?",
    "How many feeds yesterday compared to the day before?",
    "Tips for burping",
    "How do I know which side to start on?",
    "Can I use a dummy?",
    "When should we start tummy time?",
    "What does the NHS say about cluster feeding?",
    "Is it normal for feeds to be closer together in the evening?",
    "How much expressed milk did we use?",
    "What's the best way to warm a bottle?",
    "She's getting longer stretches of sleep",
    "Draft a question for the health visitor about sleep",
]

@Suite("Danger signs")
struct DangerSignTests {
    @Test func enoughPhrasingsAreTested() {
        #expect(dangerPhrasings.count >= 200)
        #expect(Set(dangerPhrasings.map(\.1)) == Set(DangerSign.allCases))
    }

    @Test(arguments: dangerPhrasings.indices)
    func eachPhrasingOpensTheCard(_ index: Int) {
        let (text, sign) = dangerPhrasings[index]
        #expect(DangerSigns.check(text).contains(sign), "\"\(text)\" should find \(sign)")
    }

    @Test(arguments: ordinaryQuestions)
    func everydayQuestionsDont(_ text: String) {
        #expect(DangerSigns.check(text).isEmpty, "\"\(text)\" found \(DangerSigns.check(text))")
    }

    @Test func negationStillOpensTheCard() {
        #expect(DangerSigns.check("she's not blue").contains(.colour))
        #expect(DangerSigns.check("no fever").contains(.temperature))
    }

    @Test func aTemperatureIsANumberNearItsWords() {
        #expect(DangerSigns.check("38.4").contains(.temperature))
        #expect(DangerSigns.check("38 c").contains(.temperature))
        #expect(!DangerSigns.check("she drank 40 ml").contains(.temperature))
        #expect(!DangerSigns.check("she is 38 days old").contains(.temperature))
    }
}

@Suite("The word reader")
struct WordReaderTests {
    @Test func foldsAndSplits() {
        #expect(WordReader.words("She’s 38.5°C, WON'T feed!") == ["shes", "38.5", "deg", "c", "wont", "feed"])
        #expect(WordReader.words("A&E") == ["a", "e"])
        #expect(WordReader.words("café") == ["cafe"])
    }

    @Test func oneLetterAwayOnlyForLongerWords() {
        #expect(WordReader.near("breathin", "breathing"))
        #expect(WordReader.near("siezure", "seizure"))
        #expect(WordReader.near("jaundise", "jaundice"))
        #expect(!WordReader.near("fewer", "fever"))
        #expect(!WordReader.near("sitting", "fitting"))
        #expect(!WordReader.near("blue", "glue"))
    }
}

@Suite("Medicine questions stay on the phone")
struct MedicineQuestionTests {
    let medicines = ["Vitamin D", "Calpol"]

    @Test func aMedicineByName() {
        let question = MedicineQuestions.check("When did she last have vitamin D?", medicines: medicines)
        #expect(question == MedicineQuestion(medicine: "Vitamin D", asksWhenLastGiven: true))
    }

    @Test func anyOtherMedicineQuestionGetsTheFixedReply() {
        #expect(MedicineQuestions.check("Can I give Calpol again?", medicines: medicines)
                == MedicineQuestion(medicine: "Calpol", asksWhenLastGiven: false))
        #expect(MedicineQuestions.check("How much paracetamol for a baby?", medicines: medicines)
                == MedicineQuestion(medicine: nil, asksWhenLastGiven: false))
        #expect(MedicineQuestions.check("what dose of infacol", medicines: []) != nil)
    }

    @Test func otherQuestionsAreNotMedicineQuestions() {
        for text in ordinaryQuestions {
            #expect(MedicineQuestions.check(text, medicines: medicines) == nil, "\"\(text)\"")
        }
    }
}
