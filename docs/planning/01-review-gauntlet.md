# Feeding Tracker: planning review gauntlet

*12 November 2026, before any code was written.*

## What was reviewed

The starting idea:

- An iOS app to track a newborn's feeds, carrying on into infancy and beyond.
- Press a button when a feed **finishes**, and the app shows when the next feed is due.
- The feed interval can be set.
- Two parents will use it.
- More features may come later.

It was written up as a "v0" plan before review:
- One screen with a "Feed finished" button.
- The next feed due at finish time plus the interval, with a local notification at that time.
- The interval set between 1h30 and 4h, defaulting to 3h.
- An editable history.
- Built with SwiftUI and SwiftData, iOS 17 or later, on a single phone, with no backend.

## The reviewers

Five independent reviewers each looked at it from a different angle:

| # | Angle | Main concern |
|---|-------|--------------|
| 1 | Caregiver UX and product | The 3am, one-handed, two-parent reality |
| 2 | Feeding domain and safety | NHS, AAP and WHO guidance, and the App Store's rules for health apps |
| 3 | iOS platform and engineering | Notifications, widgets, time handling, and a workflow with no Mac in the loop |
| 4 | Data, sync and multiple caregivers | CloudKit, conflicts, data model, privacy |
| 5 | Devil's advocate | Build or buy, existing apps, effort, when to stop |

---

## Verdict

The core idea holds up, but the v0 plan needs four structural changes before building:

1. **Time from the start of a feed, not the finish.** Three of the five reviewers raised this on their own.
2. **Sharing between the two parents is part of the foundation, not a later feature.** SwiftData can't share data between two Apple IDs, so the storage and sync design has to be chosen now.
3. **A normal notification won't wake a sleeping parent.** A phone on silent stays silent. AlarmKit (iOS 26+) is the native fix, and it's the strongest reason to build a native app rather than a web app.
4. **Show "time since the last feed", and treat the alert as a safety net, not a schedule.** NHS, WHO and AAP all recommend feeding when the baby is hungry rather than by the clock.

There are also two practical requirements: a **paid Apple Developer Program membership ($99/yr)**, and access to a **Mac**, unless all builds go through cloud CI.

---

## Findings everyone agreed on, ranked

### F1. Measure the interval from the start of a feed (MUST-FIX) (reviewers 1, 2, 5)
- **Guidance:** AAP says newborns nurse "every 2 hours from the start of the feeding to the next feeding" ([AAP](https://www.healthychildren.org/English/ages-stages/baby/feeding-nutrition/Pages/How-Often-and-How-Much-Should-Your-Baby-Eat.aspx)). KidsHealth also counts from the start of a feed. AAP gives about 4 hours at night as the longest a newborn should go without feeding ([AAP](https://www.healthychildren.org/English/ages-stages/baby/breastfeeding/Pages/How-Often-to-Breastfeed.aspx)).
- **Failure case:** a 50-minute night feed ends at 02:00 with a 3-hour setting. The alert goes at 05:00, which is 3h50 after the feed started. A sleepy newborn goes past 4 hours.
- **Fix:**
  - Store `startedAt`, which is required, and `endedAt`, which is optional.
  - Keep one big button: the first tap means "started", the second means "finished".
  - For anyone who only remembers at the end, offer "Just finished, started about 10/20/30/45 minutes ago".
  - Label the setting "start to start".

### F2. Show time since the last feed, and make the alert a safety net (MUST-FIX) (reviewers 2, 1)
- **Guidance:** NHS says "You do not need a feeding schedule… Feed your baby as often as they want" ([NHS](https://www.nhs.uk/baby/breastfeeding-and-bottle-feeding/breastfeeding/the-first-few-days/)). WHO says to feed "as often as the child wants, day and night" ([WHO](https://www.who.int/news-room/fact-sheets/detail/infant-and-young-child-feeding)).
- **Failure case:** the baby shows hunger cues at 1h40. The screen says "due in 1h20", so a tired parent soothes the baby instead of feeding.
- **Fix:**
  - The main display reads "Last feed started 1h40m ago (01:50)".
  - The alert means "no feed logged for X hours".
  - Avoid "due", "missed" and "overdue" in the wording.
  - Let the gap be set separately for day and night.
  - Allow the alert to be switched off, since after about a month a well-gaining baby is usually fed when hungry and not woken.

### F3. Mistakes will be routine, and v0 handles none of them (MUST-FIX) (reviewers 1, 3)
- **Failure cases:**
  - A double tap, from fumbling or from both parents tapping.
  - A forgotten tap.
  - A late tap.
  - Editing or deleting the latest feed in History. The alarm keeps its old time, because v0 only reschedules when the button is pressed.
- **Fix:**
  - A big Undo for about 10 seconds after logging.
  - A warning when a feed was logged in the last ~20 minutes.
  - "Log an earlier feed" on the home screen.
  - **One pure function**, `reconcile(events, settings, now, timeZone) → desired alerts`. Call it on every add, edit or delete, when the app opens or comes back to the foreground, and when the time or time zone changes.

### F4. "Us" means sync, and SwiftData can't share data between two Apple IDs (MUST-FIX) (reviewers 4, 5, 3)
- **Fact:** SwiftData syncs with CloudKit only through the user's private database. Sharing between different Apple IDs is still unsupported in iOS 27 ([Apple forums](https://developer.apple.com/forums/thread/756721), [WWDC26 notes](https://wwdcnotes.com/documentation/wwdc26-274-whats-new-in-swiftdata/)).
- **Options:**
  - **(a) CKSyncEngine (iOS 17+).** One parent owns a "Household" record zone and shares it with a CKShare. SwiftData stays as a local store only. This is more code, but the sync logic is explicit and its tricky parts can be unit-tested.
  - **(b) NSPersistentCloudKitContainer with two stores, following Apple's sample.** This is less code, but it's a black box, and unexplained sync failures have been reported.
  - **Reviewer 4 recommends (a).** Sync bugs here can only be debugged on two physical phones with a Mac, so explicit sync logic is safer.
- **Requires:** the paid Developer Program, because a free account has no CloudKit and no push.

### F5. Alerts reaching the other parent's phone are not guaranteed (MUST-FIX for design) (reviewers 4, 5)
- **Fact:** CloudKit tells the other phone about a change with a silent background push. Apple doesn't guarantee these, throttles them, and doesn't deliver them to an app the user has force-quit ([Apple](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)).
- **Failure case:** A logs a feed at 01:50 and B's phone never hears about it. B gets a stale alarm and misses the right one.
- **Fix:**
  - Never store "next due". Each phone works it out from the latest synced feed.
  - Reschedule at every chance: when the app opens, when it comes back to the foreground, during background refresh, and when a change arrives.
  - Show "last synced" and "logged by" on screen.
  - Test on two real phones with the app force-quit and with Low Power Mode on.
- **Fallback:** a small push server that sends the alert at the due time. That means running a backend.
- **Synthesis note:** if the parents take night shifts, the parent on duty usually logs the feeds themselves. In that case the phone that logs the feed owns the alarm, and sync matters only at handover, when both phones have had time to catch up. That makes F5 much less serious, and it's why the question about how you split the nights matters.

### F6. Plain local notifications won't wake anyone (MUST-FIX) (reviewer 3)
- **Fact:** with the phone on silent, normal and Time Sensitive notifications make no sound. Critical alerts need Apple's approval, which a personal app won't get.
- **AlarmKit** (iOS 26+) alarms get through Focus and silent mode, and also go off on a paired Apple Watch ([Apple](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit)). It needs its own permission and a usage description, and a countdown display needs a widget extension.
- **Fix:**
  - Use AlarmKit for the "wake me" alert.
  - Keep a normal notification as the quieter option, with a "Log feed" action on it.
  - **Prove on a real phone that it works before building anything else.**
- This is the decisive argument for native over the web-app alternative reviewer 5 suggested, because a web app can't get through silent mode.

### F7. Signing and distribution are blockers (MUST-FIX) (reviewers 3, 5)
- **A free personal team doesn't work here:**
  - Apps expire after 7 days, so they stop launching on day 8, perhaps at 3am.
  - It allows only 3 devices: two iPhones plus one Watch fills it.
  - It allows only 10 App IDs a week, and the app, widget and watch app each need one.
  - There's no CloudKit, push, Time Sensitive or TestFlight ([Apple](https://developer.apple.com/support/compare-memberships/)).
- **Fix:**
  - The paid Developer Program, at $99/yr.
  - Install through TestFlight internal testing, with the second parent added to the team. Builds expire after 90 days, so plan regular uploads.
  - Builds come from a Mac, or from GitHub Actions macOS runners or Xcode Cloud.
  - Xcode 27 needs macOS Tahoe 26.6 or later.

### F8. Raise the minimum iOS version to 26 (MUST-FIX) (reviewer 3)
- AlarmKit needs iOS 26 and Control Center controls need iOS 18. 79% of active iPhones were on iOS 26 by June 2026, and only two known phones need supporting. Set the minimum to whatever both phones run, and at least 26.

### F9. Settings and the data model need to be shared and ready for growth (MUST-FIX) (reviewers 4, 2, 3)
- **v0 problems:**
  - The interval in UserDefaults applies to one phone only, so the two phones disagree.
  - Widgets and intents can't see it unless it lives in a shared App Group.
  - Once deployed, the CloudKit production schema is **permanent**: fields can't be renamed or deleted, and encryption can't be added to an existing field later.
- **Recommended model**, reviewer 4's proposal with reviewer 2's feeding detail added:
  - **Baby:** `id`, `name` (encrypted), `birthDate?`, `alertSettings` (day/night gap, on/off), `archivedAt?`.
  - **Event:** a generic log entry, with these fields:
    - `id` (UUID) and `babyID`.
    - `kind`: `feed` now; `nappy`, `sleep`, `pump`, `solids`, `growth` and `medicine` later.
    - `startedAt` and `endedAt?`.
    - `timeZoneID`.
    - `createdAt` and `modifiedAt`.
    - `loggedBy`.
    - `deletedAt?`, which makes deletes soft, so a delete and an edit made on different phones don't clash.
    - `schemaVersion`.
    - `note?` (encrypted).
    - `details`: encrypted JSON in SI units. For feeds, this holds the type (breast L/R/both, expressed, formula), the side, and the volume in ml.
  - Data volumes are tiny, about 20,000 events in three years, so all totals can be worked out in memory.
  - `babyID` on every event means twins or a sibling need only UI work later, with no migration.

### F10. Night-friendly UI (SHOULD) (reviewer 1)
- Dark at all times on true black, with dim warm accents.
- No white flashes from launch screens, alerts or the keyboard.
- A full-width button at the bottom, reachable by thumb.
- Haptic confirmation.
- No typing and no small tap targets.

### F11. What the 3am screen shows (SHOULD) (reviewers 1, 2)
In priority order:
1. Time since the last feed started.
2. The clock time of the next alert.
3. The next breast side, if breastfeeding. This is the most-asked 3am question.
4. Who logged the last feed.
5. The number of feeds in the last 24 hours, with no red or green judgement. 8–12 a day is normal early on, according to NHS and AAP.

### F12. Wording and disclaimer (MUST-FIX) (reviewer 2)
- Apple guideline 1.4.1 says health-related apps should remind users to check with a doctor.
- Add this line on first launch and in Settings: "Records feeds; not medical advice. If you're worried, contact your midwife, health visitor or doctor. In an emergency, call your local emergency number."
- Avoid targets and words like "should" or "on track".
- Don't build warning-sign logic in. The thresholds depend on age and country, and they could either falsely reassure or cause alarm.

### F13. Engineering workflow when the agent has no Mac (MUST-FIX) (reviewer 3)
- **What can't compile on Linux:** SwiftUI, SwiftData, AlarmKit, notifications and widgets.
- **Pure Swift package core:** the reconcile, interval, dedupe and merge logic, plus formatting rules. It depends only on Foundation, is tested with Swift Testing, and is built on Linux with a matching Swift version (Swift 6.4, installed with `swiftly`) and tzdata.
- **The Xcode project** is generated from a text spec with XcodeGen or Tuist, so the agent never edits Xcode's project file by hand.
- **GitHub Actions CI:**
  - It runs `swift test` on Linux and builds for the simulator on the `xcode-27` macOS image.
  - That's the agent's only feedback on the app layer.
  - Public repos are free. Private repos get about 190 macOS minutes a month on the free allowance.
- **Done by the user, on their Mac and phones:** signing, Developer Mode, and a device checklist covering Focus and Sleep, silent mode, reboot, and changing time zone.

### F14. Time handling (SHOULD) (reviewer 3)
- Store exact moments in time only.
- Schedule either relative to now or with an explicit time zone.
- Tests cover:
  - both daylight-saving changes
  - Lord Howe Island's 30-minute shift
  - travel across time zones
  - the clock being set back, which can leave a feed in the "future"
  - grouping by day around midnight

### F15. One "Log feed" App Intent drives all the quick-access surfaces (SHOULD/LATER) (reviewer 3)
- **One intent drives:**
  - the widget button
  - the Control Center and Lock Screen control
  - the Action Button
  - Siri and Shortcuts
- **Lock Screen countdown:** a widget can show one. Live Activities are capped at 8 hours and add little alongside an AlarmKit countdown.

### F16. Privacy (SHOULD) (reviewer 4)
- No third-party SDKs: no analytics, crash reporting or ads.
- Encrypt the name, notes and details fields.
- Use the "complete until first unlock" file protection level, because overnight sync runs while the phone is locked.
- "Delete all data" removes the CloudKit zone and the share as well.
- Consider leaving the baby's name out of notification text on the Lock Screen.

### F17. Exports and backups (SHOULD) (reviewer 4)
- Sync isn't a backup: a mistaken delete reaches both phones.
- v1 offers a CSV export (time in UTC and local, baby, kind, duration, logged by) and a full JSON export through the share sheet.

---

## Where the reviewers disagreed

| Question | Positions | Recommendation |
|---|---|---|
| Build at all? | Reviewer 5 says start by using an existing app, because free options already sync between two parents. Huckleberry is mature, but its privacy label says data is used to track and health data is linked to the user. One Baby is new, says "Data Not Collected", and has no ratings yet. | **Build, but use an existing app as a stopgap** if the baby is already here. A personal app's real advantages are privacy, no ads or upsells, exactly your workflow, and room to extend it. |
| Native app or home-screen web app? | Reviewer 5 suggested a home-screen web app with a push server, since it needs no Mac and no $99. | **Native.** Only AlarmKit gets through silent mode, and iOS web push is reported to be unreliable. |
| Sync engine | CKSyncEngine (explicit, more code) or NSPersistentCloudKitContainer (less code, black box). | **CKSyncEngine**, decided at the start of phase 2. |
| Who gets the alert | Both phones, or only the on-duty parent's. | **A user decision.** See the questions. |

## Suggested phases (draft, depends on the answers below)

0. **Decisions and a spike (1–2 evenings).**
   - Confirm the Mac, $99/yr and iOS versions.
   - Create the App ID and the TestFlight setup.
   - Run an **AlarmKit spike on a real phone**, proving the alarm wakes you on silent and in Sleep Focus.
   - Set up the repo: the Swift package core with Linux tests, the XcodeGen spec, and GitHub Actions CI.
1. **Single-phone MVP, with the data model built for sync.**
   - Start and finish logging, plus the "started about N minutes ago" option.
   - Undo, duplicate warning, and logging an earlier feed.
   - Editable history, using `reconcile()`.
   - Time since the last feed.
   - AlarmKit safety-net alert with separate day and night gaps.
   - The 24-hour count.
   - Breast side, bottle and volume.
   - Night UI and the disclaimer.
   - Usable straight away with one shared bedside phone, or in shifts.
2. **Two phones.**
   - Shared CloudKit zone via CKSyncEngine.
   - Logged-by, the last-synced indicator, and duplicate merging.
   - On-duty alert routing.
   - CSV and JSON export.
3. **Glanceable surfaces.** The Log Feed App Intent, a widget and a Control Center control, the Action Button, and a Lock Screen countdown.
4. **Later.**
   - An Apple Watch app.
   - Nappies, sleep, pumping, growth, solids and medicine.
   - Several babies in the UI.
   - Charts and a summary for the doctor.

Rough effort, from reviewer 5, for a parent plus an AI agent:
- **Single-phone native app:** about 1 day of code, plus 0.5–2 days of signing and CI setup.
- **Two-phone sync with reliable alerts:** 1–3 weeks of evenings, with high uncertainty.

**When to stop or switch to an existing app** (reviewer 5):
- There's no installable build on both phones after 3 evenings of phase 0 and 1.
- An alert is missed twice in one week.
- After a week side by side, you still reach for the commercial app.
- A clinician moves you to feeding on demand, which removes the need for alerts.

## Open questions for the user

1. **Baby:** born yet, and if so how old? Premature, or any jaundice or weight-loss concerns? Has a midwife or doctor set a specific "wake to feed every X hours" plan?
2. **Feeding:** breast, expressed milk, formula, or a mix?
3. **Setup:** do you have a Mac, and which macOS? Will you pay $99/yr for the Developer Program? Which iPhones and iOS versions do you each have, and any Apple Watches? Separate Apple IDs?
4. **Nights:** do you take shifts with one parent on duty, or are you both up? Should the alert wake only the on-duty parent, or both?
5. **Alert style:** a loud alarm that gets through silent mode, or a gentle nudge?
6. **Why build:** privacy, owning your data, the exact workflow, enjoying the project? Would you use an existing app as a stopgap?
7. **Scope:** only ever for yourselves, or possibly the App Store one day? Is the GitHub repo public or private? That decides the CI cost.
8. **Country:** decides which official "when to get help" links the app shows.

*Citations come from the individual reviewers' web research on 12 November 2026. The most important facts, such as start-to-start timing, no SwiftData sharing, AlarmKit, and the free-account limits, were found by more than one reviewer or match well-established platform behaviour. Version numbers and statistics should be re-checked when they matter.*
