# Going live: the real app through TestFlight, and the move from Feeding Dev

19 Nov 2026. The parents have used **Feeding Dev** for real since about 16 Nov 2026. They want the
real app, **Feeding**, through TestFlight, so tests never mix with their own entries, and to move
what they entered in Feeding Dev into it.

## Decisions (19 Nov 2026)

| # | Question | Answer |
|---|---|---|
| G1 | Make the CloudKit schema permanent ("deploy to Production"), the journal's photos and videos included? | **A) Yes, all of it.** The parents' go-ahead for the Production deploy that `CLAUDE.md` requires. |
| G2 | What moves from Feeding Dev? | **A) Everything:** feeds, pumping, sleeps, nappies, medicines, growth, firsts with their photos and videos, the baby's name and birth date, the medicine list, the feed window and the night rota. Each parent picks their own alarm choices again on their own phone. |
| G3 | Who does the App Store Connect steps? | **B) Claude, in the parent's own signed-in browser through Aside**, while they watch. |
| G4 | Feeding Dev after the move? | **A) Kept for testing, with its alarms and notices off,** so it never rings next to the real app. The two-phone checks (journal T14) then use made-up data in Feeding Dev. |

## The steps

1. **The code** (no outside effect):
   - Feeding (the real app) syncs, photos and videos included (`AppConfig.syncEnabled`,
     `photosEnabled`), once the schema is in Production.
   - Feeding Dev gets a switch, "Alarms and notices off", for testing beside the real app.
   - **Move to Feeding:** Feeding Dev writes one file with the household's entries, firsts,
     photos and videos, and settings; the real app reads it in. The two parents' Feeding Dev
     identities are matched to their identities in the real app (iCloud user record IDs differ
     between containers).
2. **The schema:** imported into the Production container's Development environment with
   `cktool`, checked, then deployed to Production in the CloudKit Console.
3. **App Store Connect:** the app record (`com.tracker.feeding`), the other parent added as a
   tester, and an internal TestFlight group, "Household", with automatic distribution.
4. **The build:** archived and uploaded to TestFlight.
5. **On the phones:** install the real app from TestFlight on both; the household owner sets up
   the household and invites the other parent; then the move, on the owner's phone.
6. **Only once the real app shows the entries and its alarms are set:** Feeding Dev's alarms and
   notices are turned off on both phones. Until then both apps may alarm (when unsure, alert too
   much rather than too little).

## The name (19 Nov 2026)

The parents chose **Little Log** (from four offered: Milk & Moon, Tag Team, Snug, Little Log). On
the phone: "Little Log", and "Little Log Dev" for the test app (`displayName` in `project.yml`);
in App Store Connect and TestFlight: "Little Log: Baby Diary". The app's own words say "Little Log"
wherever they named the app ("Feeding window" and "Feeding now" are about feeding, and stay). The
code, the targets, the bundle IDs (`com.tracker.feeding`), the iCloud containers and the App Groups
keep "Feeding": they can't change without a new iCloud container, and nobody sees them.

## Done in the Apple accounts (19 Nov 2026, in the parent's own Aside tab)

- **The schema in Production:** `schema.ckdb` imported into `iCloud.com.tracker.feeding`'s
  Development environment with `cktool` (its export matched the file and Feeding Dev's), then
  deployed to Production in the CloudKit Console: 7 record types created (Baby, Event, Media,
  MediaTally, Member, Setting, `cloudkit.share`) and the three roles' grants, nothing removed.
  Production's export then matched the file exactly.
- **App Store Connect:** the app record "Little Log: Baby Diary", iOS, English (UK), bundle ID
  `com.tracker.feeding`, SKU `feeding-tracker`, Full Access (Limited was greyed out with no other
  users on the team).
- **The other parent** invited as a user with the Marketing role (enough to be an internal
  tester), with access to this app only. They accept Apple's email, then install TestFlight.
- **The first build** (build 1, version 0.1.0, commit `c4fedda`) archived and uploaded on 20 Nov
  2026 (the steps are in `CLAUDE.md`, "TestFlight upload"); Apple had it "Ready to Test" within
  minutes.
- **The internal TestFlight group "Household"**, with automatic distribution, holding build 1, with
  the household owner as its tester. **Still to do:** add the other parent once they have accepted
  Apple's invite (they appear in "Add Testers" only then).

## Built (19 Nov 2026)
- **Sync on in Feeding:** `AppConfig.syncEnabled` is true for both apps; photos follow it.
- **Feeding Dev's "Alarms and notices off"** (Settings, "Feeding Dev · this phone", asked before it
  turns on): `Reconciler` then cancels every alarm and alert notification (`AlertScheduler.silenceAll`)
  and sets none; the night-ask and new-first notices are noted as told and not sent. Always off in
  Feeding.
- **The move** (`HouseholdMove`, `MoveFile` in FeedingCore; `HouseholdMover`, `MoveScreens` in the
  app):
  - Feeding Dev, Settings › Move to Feeding: fetches the latest from iCloud and any photo or video
    not on the phone, then writes one file ("Feeding move <date>.feedingmove": the contents as JSON,
    then each photo and video with its thumbnail), to save to Files.
  - Feeding, Settings › Bring in from Feeding Dev: reads the file, shows what is in it and whose
    entries become whose, then brings it in. The photo and video files first, then the entries in
    one checked save, then the photos queue for iCloud behind the feeds.
  - What moves: every entry of the baby not deleted, the baby's name and birth date, the parents'
    colours, the feed window's times, day and night hours, time zone, rota, medicines, photo
    allowance, and feeds marked as two. Not: the Alerts switch (the move never turns alerts off),
    nights taken (they could take a phone off duty before the other phone has them; the parents take
    the night again in Feeding), pending changes, acknowledgements, night asks and their answers,
    "Both phones tonight", the photos share's link, and each parent's alarm choices.
  - IDs: the parent who made the file becomes the parent bringing it in; the other parent becomes
    the other member of the real household, who must have joined first (else nothing changes and
    the screen says so). Refused: a file whose maker has the other parent's name (made on their
    phone), one naming more than two parents, and one with entries this build can't read. Each
    entry comes in as new, to be sent; one already here is left as it is, so bringing the same file
    in twice is safe. The settings come once only (a `moveReceipt` Setting record); a later move
    adds only entries, and photos a first lacked. The window goes through
    `updateHouseholdSettings`, and the rota is always a pending change, so this phone alerts as if on
    duty until the other phone confirms (the acknowledgement rule). A feed keeps Feeding Dev's cap
    from iCloud's time in its start, so the alerts plan from the same moment in both apps.
  - Photos: each goes with the oldest first that names it; the queue is written before the firsts
    are saved (as a first's Save does), and comes off again if the save fails.
- **Codex review** (`gpt-6.2-sol`, high, about 159,000 tokens): 14 findings, all fixed: the
  above, the file read (a list too long, items overlapping or named twice), the file written
  beside its name and put in place only once whole with a space check, a thumbnail made when
  missing, a warning when iCloud couldn't be reached before the file was made, the chosen file
  kept readable until the import ends, a good photo never deleted by a failed copy, test alarms
  and their notices silenced too, and the Done screen telling the parent to keep Feeding Dev's
  alarms on until Feeding may ring.
