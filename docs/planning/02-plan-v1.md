# Feeding Tracker: plan v1 (revision 2)

*Revision 1 was written on 12 November 2026, after the review gauntlet ([01-review-gauntlet.md](01-review-gauntlet.md)) and the user's answers. Revision 2, also 12 November, adds the second review round ([03-review-round-2.md](03-review-round-2.md)): a red team on the alerts across both phones, and a check of the Apple setup. The step-by-step Apple setup is in [04-apple-setup-checklist.md](04-apple-setup-checklist.md).*

> **This repository is public.** No personal data goes in it: no names, no feed logs, no photos.
> The baby's and the parents' names are typed into the app and stored only in the household's iCloud.
> This document says "Parent A" for the parent who creates the household and "Parent B" for the other.

## Context

- **Baby:** a newborn, already born. The midwives advise feeding every 2–4 hours, while also following hunger cues.
- **Feeding:** mixed. Breastfeeding is being established but sore nipples are making it hard, so Parent B is expressing milk. The baby gets expressed milk by bottle, with formula making up the shortfall. **The app must track which breast was used.**
- **People and devices:** two parents, each with their own iPhone and Apple ID. The phones are an iPhone 18 Pro, an iPhone Duo (folding, with a 5.4" outer screen and a 7.6" inner screen) and Parent B's iPhone. Apple Watch integration is wanted.
- **Nights:** the parents take turns, flexibly, so whoever is off gets unbroken sleep.
- **Alerts:** each parent can choose a loud alarm or a gentle nudge in Settings, by day and by night. If no feed is logged 30 minutes after the alert, both phones ring with a loud alarm. See "Alerts on two phones" below.
- **Where:** the United Kingdom. The household time zone defaults to Europe/London, and the "get help" links are the UK ones.
- **Why build:** privacy, control, and adding features as the baby grows.
- **Setup:** paid Apple Developer Program membership and a Mac. Both phones must be able to install the app while it's still being developed.

## Product principles

1. **The headline is time since the last feed started.** Alerts are a safety net, not a schedule.
2. **Everything works one-handed in the dark, in one or two taps, and can be undone.**
3. **Two phones, one record.** Whatever one parent logs appears on the other's phone.
4. **When something fails, alert too much rather than too little.** If the phones disagree or have lost contact, both may ring, but neither should go quiet. Every rule below is designed against this, and the known exceptions are listed.
5. **Nothing leaves the household's iCloud.** No analytics, adverts, third-party SDKs or servers.

## The feed window

The midwives' "every 2–4 hours" becomes a window, measured from the **start** of the last feed.

| Time since last feed started | State | What happens |
|---|---|---|
| 0 – 2h | Recently fed | Nothing. |
| 2h | Window opens | Optional gentle nudge: "may be ready to feed; watch for cues". |
| 4h | Window closes | The safety-net alert (see "Alerts"). |

- Both times are shared settings, defaulting to the midwives' 2h and 4h, and can be changed if the advice changes.
- The alert can be turned off once the baby is fed fully on demand.
- The app never uses the words "due", "missed" or "overdue".

## What gets recorded

Every event has a required start time and an optional end time.

- **Feed:** any combination of the following.
  - **Breast:** one or more segments, each Left or Right, with an optional duration. Switching sides adds a segment.
  - **Bottle:** one or more bottles, each *expressed milk* or *formula*, with the amount in ml.
  - **Note:** optional.
- **Pump (expressing session):** the time, the side (left, right or both) and the ml from each side. *In Phase 1 (the user confirmed this on 14 November 2026).*
- **Later kinds (phase 3):** nappy, sleep, growth, medicine and solids. The data model already allows for them.

## Screens

**The look of every screen** (colours, letters, shapes, tiles, day and night) is set by `DESIGN.md`, and the screen-by-screen redesign is in `05-visual-redesign.md` (both agreed 15 Nov 2026). The list below says *what* the home screen shows; those files say *how* it looks.

**Home screen** (standard phone, or the Duo folded), from top to bottom:
1. "Last feed **1h 40m** ago, at 01:50", with a ring showing progress through the window.
2. A bar for the window: "Feeding window 03:50", and a bell with the alarm time, 05:50.
3. **Suggested next side**: the side not used last. It's only a suggestion.
4. A summary of the last feed, for example "L 12m · R 8m · Formula 30 ml, logged by Parent A".
5. The last 24 hours: number of feeds, number of breast sessions, ml of expressed milk and ml of formula. No targets and no red or green colouring.
6. Tonight's duty: "Parent B is on tonight", with an **"I'll take tonight"** button and a "seen by Parent B ✓" status.
7. A full-width **Start feed** button at the bottom.
   - During a feed it changes to large **Left / Right / Bottle** buttons, **Finish**, and a narrower **Stop**.
   - **Stop** (the user's decision, 15 Nov 2026) is for a feed started by mistake. It asks "Remove this feed?" first, because Stop and Finish sound alike, and then removes the feed so nothing is logged. It stays for the whole feed, so starting a feed has no Undo bar.
   - Only the parent who started the feed gets those buttons, because only they know what the feed is (the user's decision, 14 Nov 2026, after the first two-phone test). The other parent's phone shows "Parent A started this feed" and one **Finish for Parent A** button, for when Parent A is busy. Parent A's phone then offers to add the sides and bottles, for 2 hours or until answered. History shows "finished by Parent B".
   - After Finish comes an amount wheel for any bottle, which can be skipped (an iOS wheel since 16 Nov 2026, the user's choice; it was quick ml buttons before).
   - **How you feed** (the user's decision, 14 Nov 2026): each parent chooses on their own phone, once in setup and later in Settings: **Breast and bottle** or **Bottle only**. Bottle only: Start feed asks "Expressed milk or Formula?" and the feed starts with that bottle; there are no Left and Right buttons anywhere on that phone; after Finish comes only the amount wheel. It changes only that phone's buttons, never the shared log.
   - The other parent is always called by name ("logged by Parent B"), never "the other parent", once their phone has joined.
   - Other taps (a side, a bottle, Finish, "Just finished") get an Undo banner for 10 seconds.
   - It is an ordinary button in the screen's content, not a toolbar item, and it is pinned to the bottom so it stays visible without scrolling. On the Duo folded, the system puts a side bar about 84 pt wide down the right edge, which leaves 382 pt for content. Held sideways, the outer screen is short, so the rest of the home screen scrolls behind the pinned button.

Also on the home screen:
- **"Just finished, started about 10 / 20 / 30 / 45 min ago"**.
- **"Log an earlier feed"**.

**Sync status** is shown wherever it matters: "Synced 1 min ago", or a muted orange banner (never red) for problems such as the S8 and S9 cases in round 2.

**History:** a timeline grouped by day. Entries can be edited, and deleting one hides it rather than removing it from iCloud. A deleted entry doesn't show in History at all (the user's decision, 15 Nov 2026), so Delete needs a swipe and then a tap, never a full swipe. Every change goes through `reconcile()`.

**Toolbar buttons** (Settings, History and the like) use the system toolbar, `.toolbar` inside a `NavigationStack`. Each has a title and a symbol. The system then moves them into the Duo's side bar by itself. No hand-built bars: the system doesn't move those.

**The Duo unfolded:** two columns, with the home screen on the left and, on the right, the last 24 hours (chart and totals), the week's nights and the recent feeds (see `05-visual-redesign.md`).
- Use `ArrangementView` with `.split.axes(.horizontal)`, inside the `NavigationStack` (iOS 27.1). This is Apple's container for two views where neither may be hidden. It shows both side by side on the inner screen, and only the home screen on the outer screen. When the phone is partly folded like a book, each column gets its own half.
- Not `NavigationSplitView`. It is built for a list and its detail, and on a tall, wide screen it can hide the first column behind a button. Apple also says not to put an `ArrangementView` inside one.
- Lay out from size classes, not from the hinge. iOS 27.1 does report the hinge (`onHingeChange`) and the fold (`reservedRegions(kind: .division)`), but Apple says to use those for effects only.
- When the phone stands partly folded like a laptop, the fold runs across the middle of the screen. Keep the big buttons (Start feed, Left, Right, Bottle, Finish) at the bottom, away from the fold. Scrolling lists don't need to avoid it.
- Split View can make the app phone-narrow (about 385 pt) on the inner screen, with the side bar on either edge. The layout must still work there.
- A feed in progress is kept in the data store, not only on screen, so folding or unfolding can't lose it.
- Build with the iOS 27.1 SDK or later, with iOS 27.1 as the minimum, because `ArrangementView` and the side-bar controls need 27.1.
- The full Duo notes (Apple's facts, our advice and simulator measurements) are in the shared file `~/.claude/reference/iphone-duo.md` on the Mac.

**Day and night looks** (the user's decision, 15 Nov 2026; this replaces "always dark", which came from reviewer finding F10, not from the user):
- A warm, joyful **day look** and a dim **night look** of the same screens. The rules and colours are in `DESIGN.md`.
- The night look runs during the household's night hours (the rota's, 21:00 to 07:00 by default). Each phone can choose Automatic, Always day (added 16 Nov 2026), Always night or Match iPhone in Settings.
- No white flashes at night from sheets, pickers or the keyboard: the app sets its colour scheme to match the look. The launch screen is always dark, because it can't know the time.
- At night, thinner letters, dim colours, fades only, and haptics in place of animation.
- The background runs edge to edge (`ignoresSafeArea`), under the Duo's side bar too, so no lighter strip shows. Buttons stay inside the safe area.
- Large tap targets, haptic feedback, and no typing.

**Disclaimer** on first launch and in Settings: "Records feeds; not medical advice. If you're worried, contact your midwife, health visitor or GP, or call NHS 111. In an emergency, call 999."

## Alerts on two phones

### Alert styles
- **Loud alarm:** an AlarmKit alarm scheduled for an exact date and time. It sounds even when the phone is on silent or in a Focus mode, rings until dismissed, and is mirrored to a paired Apple Watch.
- **Gentle nudge:** a Time Sensitive notification. It vibrates, shows on the Watch and respects silent mode.

### Each parent's settings (stored on their own phone)
- **Daytime alert when the window closes:** loud alarm or gentle nudge.
- **Nudge when the window opens:** gentle nudge or off.
- **Night alert when the window closes, while on duty:** loud alarm or gentle nudge. The user chose on 14 November 2026 to let each parent choose this, as long as the backup alarm below rings on both phones. A gentle nudge can be silenced by Sleep Focus or go only to the Watch, and the backup alarm is what catches that.

### Belt and braces for the main alert
AlarmKit has open reports of alarms going off late or not at all on phones left locked overnight. These cover iOS 26 to 27 and reproduce with Apple's own sample. So the alert at the close of the window is scheduled in layers:
1. **When the window closes:** the parent's chosen style. A loud alarm is an AlarmKit alarm plus a Time Sensitive notification at the same moment. A gentle nudge is the notification only.
2. **10 minutes later:** a follow-up in the same style.
3. **30 minutes after the window closes: the backup alarm.** A loud AlarmKit alarm on **both** phones, by day and by night, whatever each parent chose. The 30 minutes is a shared setting. Each phone schedules it from its own data, so it still rings when the phones have lost contact.

No two alarms on one phone land in the same minute. Every layer is cancelled once a feed is logged, because a new feed restarts the window.

The app reschedules everything when it launches and whenever the iOS version has changed. Parents are told during setup never to hide or Face ID–lock the app, because Apple says alarms from such apps silently fail.

### Who gets alerted
- **Daytime is a shared setting**, defaulting to 07:00–21:00. During the day both phones alert, each in its owner's style.
- **At night only the on-duty phone alerts at first.** The off-duty phone stays silent until the backup alarm, 30 minutes after the window closes.
- **Defining "a night":** a night is named by the local calendar date it **starts** on, in a stored **household time zone**. It runs from the night-start time that day to the day-start time the next morning. Whether an alert is a day or night alert depends on **when it fires**, not on what time it is when it's scheduled. Tests cover 21:00, midnight, the clocks changing, and a phone in another time zone.
- **The rota alternates nightly from a shared start date**, stored as a plain date. Each phone works the rota out for itself, so both agree even when sync is down.
- **Changes are claims, not hand-offs.**
  - You can take a night ("I'll take tonight").
  - You can ask the other parent to take one, which shows a prompt on their phone. **Built 15 Nov 2026** (the user's choice: a card and an ordinary notification). The parent on duty taps "Ask Sam to take it" in the Nights tile. With no rota yet (nobody on, both phones alert), either parent can ask, with "Ask Sam to take tonight" beside "I'll take tonight" (the user's choice, 15 Nov 2026, after the first phone test showed no button); nothing changes for alerts until the answer is yes. The other parent's Home shows a card, "Alex asks you to take tonight", with "I'll take it" (an ordinary claim) and "Not tonight", and their phone shows an ordinary notification (not an alarm, not Time Sensitive). The asker stays on duty until the answer is yes, so an ask never changes who alerts and `reconcile` never reads it. The asker sees "You asked Sam… You stay on until Sam says yes", then "Sam said not tonight" or simply "Sam's on tonight", with a notification for either answer. Undo takes an ask back, even after it has reached the other phone. After "Not tonight" there is no asking again that night; "I'll take it" stays in the Nights tile if the other parent changes their mind. Only tonight can be asked for. Known limit: the notification needs iCloud's silent push to wake the app, which iOS can delay, so the card (there whenever the app opens) is the sure part. Records: `ask-<night>` (written by the asker) and `askReply-<night>` (written by the asked parent), both Setting records, so no schema change. Logic and tests: `FeedingCore/Sources/FeedingCore/Rota/NightAsk.swift`, `NightAskTests`; notifications: `App/Alerts/NightAskNotifier.swift`.
  - **First phone test, 15 Nov 2026 (no rota):** the ask, its notification and "I'll take it" worked between the two phones. Three fixes came from it the same evening. (1) **"Both phones tonight"** (the user's choice: there was no way to give a taken night back). When a claim decides tonight, either parent can tap it, and both phones alert that night. It only adds alerting: the phone that had the night stays on, and the other comes on when it hears. So it needs no acknowledgement, unlike taking a claim back. A later claim decides the night again, and it closes an open ask. Undo after "I'll take it", once the claim has left the phone, now does the same (before, it did nothing). Record: `both-<night>`, a Setting record, so no schema change. Logic and tests: `FeedingCore/Sources/FeedingCore/Rota/BothPhones.swift`, `BothPhonesTests`. (2) The card's two answers are large buttons (the small pills were hard to hit). (3) A tap on an ask notification seemed to do nothing. Now it opens Home at the top, where the card is (`App/Alerts/NotificationTaps.swift`); the cause on the phone is not known.
  - You can't give a night away.
  - A claim can be undone only until it has uploaded.
- **The acknowledgement rule:** some changes could make a phone alert later or not at all, or could make the other phone alert earlier than it knows to. Examples are undoing a claim, changing the rota start date, shortening the window, or turning alerts back on.
  - Such a change is **pending** until the other phone confirms it has seen it ("seen by Parent B ✓").
  - Until then, the phone that made the change alerts **as if it were on duty**, using the **stricter** of the old and new settings.
  - This stops a delayed sync from leaving nobody on duty.
- **Morning:** the off-duty parent's phone keeps last night's rules until that parent opens the app or their own "lie in until" time passes. A phone that hasn't caught up can't ring someone who is still asleep.
- **The backup alarm is on by default and in Phase 1** (the user's choice, 14 November 2026). It replaces the earlier idea of an optional backup that was off by default. It follows the main alert: turning alerts off turns it off too.

### How each phone decides its alerts
Each phone schedules its own alerts from the newest data it holds, using one pure function:

`reconcile(events, settings, rota, pendingChanges, me, now, calendar) -> [DesiredAlert]`

- It reads **only the unencrypted top-level fields** (`startedAt`, `kind`, `deletedAt`, `babyID`), never the encrypted payload. A feed therefore still counts if the payload can't be read or comes from a newer app version.
- To guard against a phone clock running fast, a feed's start time is capped at the server's creation time for its record, plus one minute.
- **When it runs:** at launch, on return to the foreground, after any local change, after an explicit fetch triggered by a push, during background refresh, when the clock or time zone changes, and when the rota, settings or iOS version change.
- **When it doesn't run:** an alarm going off doesn't trigger it. On iOS 27 the app may only hear about a fired alarm the next time it runs.
- **Applying the output:** notifications use fixed identifiers, so applying the output is repeatable. AlarmKit has no update call, so the new alarm is scheduled before the old one is cancelled, using different IDs. Only one reconcile runs at a time. If alarm permission is denied or the alarm limit is reached, notifications are used instead.

### Known limits (accepted and documented)
- A phone that hasn't received a newer feed will alert **early**. Opening the app syncs it and shows "Fed at 01:50 by Parent A; alert moved".
- A claim made after the other parent has fallen asleep may arrive late. In that case both phones ring.
- The backup alarm can wake the off-duty parent when a feed was logged on the other phone but hasn't reached this phone within 30 minutes of the window closing. This is accepted, because it errs towards alerting. Uploading a feed as soon as the app goes to the background keeps it rare.
- AlarmKit sometimes fires a stray alarm at midnight. The app can't prevent this.
- Whether the iPhone still rings when the Watch is being worn needs testing. In iOS 26.4 the Clock app gained an "Always Play on iPhone" option for this case.

## Architecture

| Part | Builds on | Contents |
|---|---|---|
| `FeedingCore` Swift package | Linux and Apple | Foundation only. Domain types, `reconcile`, feed-window maths, next-side suggestion, 24-hour summaries, duplicate detection, field-level merge, the rota and night calculation, the pending-change and acknowledgement rule, and versioned payload encoding. Tested with Swift Testing. |
| iOS app (iOS 27.1 SDK+, iOS 27.1 minimum) | Xcode 27.2 | SwiftUI views. The local store is one JSON file in the App Group (`HouseholdData` in `FeedingCore`, so its rules are tested on Linux too); the user chose this over SwiftData on 14 November 2026, because a year of feeds is about 2 MB and a file is simpler to test and to share with widgets and the watch. `SyncEngine` built on CKSyncEngine. `AlertScheduler` adapters for AlarmKit and UNUserNotificationCenter. App Intents. A scene delegate that accepts shares. |
| Widget extension (phase 2) | Xcode | Lock Screen and Home Screen widgets and a Control Center control, plus AlarmKit countdown screens if they're wanted. Fixed-time alarms that only alert don't need it. |
| watchOS app (phase 2) | Xcode | Start and finish feeds and choose a side from the wrist, plus a complication. Data comes from the phone over **WatchConnectivity**; the watch doesn't run its own CloudKit sync. Needs watchOS 27, which supports Series 9–12, SE 3 and Ultra 2–4. |

- **Project file:** the Xcode project is generated from `project.yml` with XcodeGen 2.46 or later. Xcode 27.2's new text-based `.xcproj` format is an option to look at later.
- **Two variants, installable side by side:**
  - **Feeding** is installed via TestFlight, uses CloudKit **Production**, the `iCloud.<id>` container and the `group.<id>` App Group, and holds the real data.
  - **Feeding Dev** has its own bundle ID, icon, **CloudKit container and App Group**, and uses CloudKit Development. Separate containers stop share links opening the wrong app. Separate App Groups stop Dev from touching the real local data.

## Data and sync

- **Sharing:**
  - Parent A creates a **Household** zone in their private iCloud database.
  - Parent A shares the **whole zone** with a single CKShare (needs iOS 15 or later) and sends the invite through Messages.
  - Parent B accepts the invite. Their phone syncs from its shared database and writes using the **shared-database zone ID, which includes the owner's name**.
  - Each phone runs a CKSyncEngine: Parent A's on the private database, Parent B's on the shared database.
  - Accepting needs `CKSharingSupported = YES` and a scene delegate that handles both `windowScene(_:userDidAcceptCloudKitShareWith:)` and a cold launch (`connectionOptions.cloudKitShareMetadata`).
  - There's also an in-app "paste invite link" fallback.
- **Schema:**
  - It is kept as a text file, `schema.ckdb`, committed to the repo and loaded into Development with `xcrun cktool import-schema`.
  - Deploying it to Production is done by hand in the CloudKit Console, **only when it's final** (see Phase 0).
  - Once in Production, record types and fields can never be deleted or renamed, and encryption can't be added to an existing field. So `payload` is declared `ENCRYPTED BYTES` from the very first import.
  - After each deploy, export both environments and compare them.
- **Record types:**
  - `Baby`: payload (name and birth date), archivedAt.
  - `Member`: payload (display name and colour).
  - `Event`: babyID, kind, startedAt, endedAt, timeZoneID, loggedBy, createdAt, modifiedAt, deletedAt, schemaVersion, and payload (details and note).
  - `Setting`: key, modifiedAt, payload. Record names are fixed (`feedWindow`, `rota`, `night-2026-11-13`, `ack-<memberID>`, …) so that different keys can't clash.
- **Conflicts:**
  - Each phone records **which fields it changed locally**. When the server reports `serverRecordChanged`, only those fields are applied on top of the server's copy, with a version for each field inside the payload. The rest of the server's copy is kept, so a correction made on the other phone isn't overwritten.
  - Deletes are soft: the record is hidden, not removed.
  - Duplicate feeds are those for the same baby, starting within 5 minutes of each other, logged by different parents. They're shown merged, with an undo.
    - **Built 15 Nov 2026 (the user's choice):** the screens show the feed logged first; the copy is left out of Home, History, the Duo column, the totals and the chart. The first feed's History row says "Logged on both phones"; its edit form shows the copy and "They were two feeds", which saves a `distinct-<id>-<id>` Setting record so both phones show both again (also a swipe right on the row). When both parents tap Start feed at once, both phones show the first feed as running, and each phone finishes its own hidden copy when the first feed finishes (only its own records, so the phones never edit the same one). `reconcile` still reads every feed, so a merge never moves an alert; Home's "at 16:15" and the bell follow the alerts, so they can show the copy's start when it is the later one.
- **Upload timing:**
  - A feed is saved locally at once and uploaded once its 10-second undo window ends.
  - If the app goes into the background, the undo window ends immediately and the upload is sent straight away inside a background task.
  - When a push arrives, the app fetches the changes explicitly and runs `reconcile` within the roughly 30 seconds it's allowed.
- **Failure guards:**
  - **Parent A's iCloud is full.** Every upload fails. Both phones show a specific red warning, and storage is checked during setup.
  - **Data suddenly empty or unknown.** For example, after signing out of iCloud or the share being revoked. The app keeps the last scheduled alerts and shows "sync broken".
  - **Zones are never deleted automatically.**
- **Compatibility:** older app versions skip event kinds and payload versions they don't recognise. `reconcile` still works because it uses only top-level fields.
- **Privacy:**
  - Payloads go in `encryptedValues`. Top-level timestamps and kinds aren't encrypted, so that `reconcile` works. This is a deliberate trade-off: CloudKit still encrypts them at rest.
  - File protection is `completeUntilFirstUserAuthentication`.
  - No third-party SDKs.
  - "Delete all data" removes the zone and the share.
  - A setting keeps the baby's name off Lock Screen notifications.

## Getting it onto both phones

- **Spikes and development:** use **Feeding Dev**, installed straight from Xcode. Parent B's iPhone is registered as a development device.
- **Real use:** **Feeding**, through **TestFlight internal testing**.
  - Parent B is an App Store Connect user with the **Marketing** role, limited to this app, and is in the "Household" internal group.
  - Builds expire after 90 days.
  - TestFlight always uses CloudKit Production, so the schema must be deployed before the first TestFlight build.
- Upload from the Mac with Archive → Distribute → TestFlight Internal Only. This can be automated later.
- The full setup steps are in [04-apple-setup-checklist.md](04-apple-setup-checklist.md).

## Workflow

| Who | Does |
|---|---|
| Claude Code on the Mac (from now on) | Writes the code, runs `swift test`, builds with `xcodebuild` (simulators, including the Duo), keeps `project.yml` and `schema.ckdb` up to date. The Duo simulator needs its own runtime (see the checklist). Command-line tools can't fold it: that needs the pose buttons in Xcode's Device Hub. |
| GitHub Actions (free for a public repo) | Runs the core tests on Linux, and builds every target on the `xcode-27` macOS runner. |
| You | Install on the physical devices and archive and upload to TestFlight. Work through the device checklist. Most app extensions can't run in the Duo simulator, so widgets are tested in an ordinary iPhone simulator or on a phone, and their Duo look on the real Duo. AlarmKit is tested on the real phones (spike 1). |

**Device checklist:**
- Silent switch on.
- Sleep Focus on.
- Locked overnight.
- Watch on the wrist, with the phone left across the room.
- App force-quit.
- Low Power Mode on.
- Airplane mode on, then reconnect.
- Both phones, in both directions.
- Fold and unfold the Duo during a feed. Also partly fold it, like a book and like a laptop, and use the app in Split View.
- Change the time zone.
- iCloud nearly full.
- Update iOS with alarms already scheduled.

## Phases

### Phase 0: foundations and spikes
- **You:** do the Apple setup in [04-apple-setup-checklist.md](04-apple-setup-checklist.md).
- **Claude Code:** creates the repo skeleton, `FeedingCore` with tests, `project.yml`, `schema.ckdb` and CI.
- **Spikes,** all on **Feeding Dev**:
  1. **AlarmKit overnight test:** at least 7 nights on a locked phone. Log when each alarm and backup notification was due and when it actually went off. Check whether the phone rings when the Watch is being worn. This can run while Phase 1 is being built.
     - **Quick daytime checks on the real Duo, 14 Nov 2026 (iOS 27.2):** an alarm alone and an alarm with a Time Sensitive notification at the same second both rang on time on a locked phone and kept sounding until Stop (30 seconds or more). **The notification does not silence the alarm.** The alarm's Stop button ran the app's own code with the phone locked and cancelled a second alarm before it rang.
     - **Overlapping alarms:** an earlier run set eight alarms and eight notifications within 42 seconds by repeated taps. The alarm then went quiet while still on screen, and each alarm needed its own Stop. So the rule that no two alarms on one phone land in the same minute matters, and the test screen now allows one quick test at a time.
     - **An alarm nobody stops:** it rang for over 3 minutes. Its follow-up alarm started on top of it at its set time. The sound did not break, and the screen looked the same, so the parent could not tell. The one Stop the parent remembers pressing landed on the follow-up; the first alarm's Stop ran 4 seconds later (a second quick press, or iOS stopping both: unknown).
     - **A notification that arrives while an alarm already rings** (as a follow-up's notification would): the alarm kept sounding until Stop, 1 minute 32 seconds after it started. The notification did not show over the alarm screen and did not silence it. So the quiet alarm in the first run came from the pile of overlapping alarms, not from a notification. The user judged this good enough on 14 Nov 2026: an alarm that rings until someone stops it is what matters.
     - **Still to test:** how long an unstopped alarm rings in the end (over 3 minutes so far; the layers cover a longer sleep), and the overnight runs.
  2. **CloudKit sharing:** create the zone and send the invite. Check that a record reaches Parent B's phone within seconds, including when the app has been force-quit. **Also check whether a background push lets the app schedule or cancel AlarmKit alarms.**
     - **First run, 14 Nov 2026** (Feeding Dev, CKSyncEngine on Parent A's private database and Parent B's shared database, iOS 27.2 on an iPhone Duo and an iPhone 18 Pro, CloudKit Development): the zone-wide share went through Messages, and tapping the link opened Feeding Dev and joined on the first try (`windowScene(_:userDidAcceptCloudKitShareWith:)`, app already running).
     - **Every record reached the other phone 1 to 3 seconds after the tap**, open or locked in the background, each time through a push and an explicit fetch. Parent B's writes with the shared zone ID reached Parent A in 1 second.
     - **Yes: a background push lets the app set and cancel AlarmKit alarms.** With Parent B's phone locked and the app in the background, a "ring in 2 minutes" record arrived in 1 to 2 seconds and the alarm was set at once; it rang on time. A cancel sent 4 seconds after another ring arrived in 2 seconds and removed that alarm; it did not ring.
     - **Swiped-away app: the push still got through, but slower.** In the first try a ring still arrived in 2 seconds and rang. In a rerun with launch notes, the app was opened, swiped away and the phone locked. A ping then started a fresh app process 9 seconds after it was sent, and it arrived 10 seconds after the tap. iOS is not known to do this for a swiped-away app, so treat it as one good result on iOS 27.2, not a promise. The plan does not depend on it: alarms already set still ring, and the app reschedules at launch.
     - The spike writes only fields already in `schema.ckdb`. Saving the share adds the system type `cloudkit.share` to the Development schema. Before deploying, export Development and compare it with `schema.ckdb`.
  3. **Duo:** fold and unfold during a fake feed, first in the Duo simulator (the Closed, Partially Open and Open buttons in Device Hub), then on the real Duo. In each pose, log the window size, the safe-area insets and the fold region, and add them to the shared Duo notes marked MEASURED. **Done on the real Duo, 14 Nov 2026:** every pose is in the shared notes. The fake feed's start time held through every fold. The side bar is 84 pt wide wherever it shows and goes away in the laptop pose. `ArrangementView` showed the second column only at 951 pt wide (book and open flat).
- **Done when:** all the spikes have passed, the schema is final, and it has been deployed to Production.

### Phase 1: two-phone MVP
Everything above. **Done when:** a week of real use on TestFlight with no missed alerts, and the stale-alert counter is acceptable.

### Phase 2: glanceable and wrist
- A "Log feed" App Intent, used by a Control Center control, the Action Button and Siri.
- A Lock Screen widget.
  - **Built 16 Nov 2026** (the user's order: these first, then the watch app, then the graphs, then TestFlight). Three actions: "Start feed", "Finish feed", and a "Start or finish a feed" switch for Control Center, the Lock Screen's corners and the Action Button (on while a feed runs). Siri and Spotlight get "Start a feed in Feeding" and "Finish the feed in Feeding" with no setting up. Start begins a feed with nothing chosen and does nothing while a feed runs; Finish finishes the running feed, whoever started it (as "Finish for Sam" does), and the details panel then opens on Home, as after Finish in the app. **Every action runs in the app's own process**, woken in the background (`allowedExecutionTargets` `[.main]`, new in iOS 27, plus `LiveActivityIntent`, which Apple documents as running in the app's process from a widget), so it saves, sets this phone's alarms and goes to the other phone like a tap in the app; it is sent at once, as there is no Undo bar outside the app. If the system ever ran one in the widget extension instead, it says "Open Feeding…" rather than seeming to work. The Lock Screen widget comes in three sizes: "1 hour, 40 minutes" over "Last feed · window 05:00" (or "12 minutes" over "Feed running, from 04:28"), the ring with "1:40" in it, and one line above the clock. It reads the household file in the App Group, and the app reloads it only when a feed starts, finishes or changes. Code: `Shared/FeedIntents.swift`, `Shared/LastFeedWidgetView.swift`, `Widgets/`, `App/Model/QuickFeedRunner.swift`; logic and tests: `FeedingCore/Sources/FeedingCore/Insights/QuickFeed.swift`, `QuickFeedTests`, `AppTests/GlanceTests.swift`. **First phone test, 16 Nov 2026:** the Control Center button started a feed. The parent found that the Lock Screen widget had no button, and that a bottle-only phone wasn't asked "Formula or expressed milk?", as it is in the app. **Changed the same day (the user's choice):** a Control Center button asks, when added, which bottle it starts (Formula, Expressed milk or Choose later), so a bottle-only parent can add one per milk; the Lock Screen widget's rectangular size has buttons ("Formula" and "Expressed" on a bottle-only phone, "Start feed" otherwise, "Finish feed" while a feed runs), which run in the app like the control; Siri takes "Start a formula feed in Feeding" and, on a bottle-only phone, asks "Formula or expressed milk?" when no milk is named. The app copies this phone's "How you feed" into the App Group (`widgets.bottleOnly`) for the widget. **Checked on the phone, 16 Nov 2026:** on a bottle-only phone, "Start a feed in Feeding Dev" made Siri ask "Formula or expressed milk?", as planned. **Decided 16 Nov 2026 (the user's choice, A of three):** Start and Finish work on a locked phone with no Face ID (`authenticationPolicy` `.alwaysAllowed` on all three actions), for one tap with a baby in arms. The parent was told the cost first: a stray Start (a pocket, a visitor) moves the next alarm later until someone taps "Stop · discard". Face ID for both, and Face ID for Start only, were the other choices. Logging a feed this way is the same as in the app, so the acknowledgement rule (for shared settings and the rota) doesn't apply. **Grey wide widget, found and fixed 16 Nov 2026:** on the Duo the wide size showed the grey stand-in a few minutes after each reload, while the round size drew. The phone's log (a sysdiagnose) showed why: when the Lock Screen asked for a new look, iOS drew each of the widget's 90 prepared minutes in about 8 looks, the widget reported success, and then the saved timeline file was missing ("unable to find or unarchive file for key"), so iOS fell back to the stand-in. The round size drew its 169 minutes in the same 8 looks and loaded, so the buttons make each wide moment too big. **The user's choices (A and A):** the time goes on its own first line, as the words cut off on one line (the Duo's wide widget is 157 × 73.5 points); and the wide size prepares one moment, with iOS's own self-updating time ("1 hour, 40 minutes", not "1h 40m"), so it is never out of date and its file stays small. Keeping "1h 40m" with 30 prepared minutes was the other choice: iOS limits how often a widget may ask for more, and 30 might still have been too big. The round and one-line sizes keep a moment a minute.
- The watch app.
  - **Built 16 Nov 2026**, after the parent chose from side-by-side mockups (kept outside the repo, in the gstack design folder `designs/watch-app-20261116/`): **B) Big number** for the main screen (not a ring), **A) a black background by day as well as at night**, **A) the bottle amount on the Digital Crown after Finish**, and **A) a double tap presses the big button**. One screen, no title: "LAST FEED", the time since the last feed started in big numbers, the window bar with "Window 05:00" and the bell, and Start feed (Formula and Expressed on a bottle-only watch; the double tap presses the milk used last). During this parent's own feed: the time running, Left and Right (not for a bottle-only parent), Finish, and "Stop · discard" lower down, which asks first. During the other parent's feed: "Finish for Sam", soft and with no double tap. After Finish with a bottle that has no amount: "How much formula?", 5 to 300 ml in 5 ml steps on the crown, starting at the last bottle's amount; Save saves it and Done skips it. Two watch face pieces: "Last feed" (round, corner, wide and one line, with the Lock Screen widget's words) and "Start feed", a bottle.
  - **Start feed on the watch face** (asked for the same day): a tap opens Feeding on "Formula or expressed?" on a bottle-only watch, with Formula, Expressed milk and, lower down, Not now; the feed starts from the moment of the tap, however long the answer takes. On any other watch the feed starts at once, as Start feed in the app does. A feed already running is shown, and nothing starts. Unanswered for 10 minutes, the question goes and no feed is logged, because a feed nobody confirmed would move the alarms later. A watch face piece can only open its app, so the question is in the app (`WatchState.faceStart`; the link is `com.tracker.feeding.dev.watch://start-feed`). Checked in the paired simulators with `-watchFaceTapTest YES` (the simulator can't open the link by command): a bottle-only phone made the watch ask; a breast-and-bottle phone's watch started the feed, and the phone showed it at the same minute.
  - **How it talks to the phone:** WatchConnectivity only, as planned; the watch has no iCloud of its own. The phone sends a `WatchState` whenever something the watch shows changes (and an instant watch face update when a feed starts or finishes, from a small daily allowance). A tap on the watch goes to the phone as a `WatchRequest` carrying the moment of the tap; the phone applies it as the same tap in the app would (`applyWatch`), then sets its alarms and sends it to the other phone, like a Lock Screen action. **The watch picks the IDs** of a feed and its bottle, so a tap kept while the phone is out of reach can still be finished and given an amount, and a tap that arrives twice changes nothing. Out of reach, the watch shows the tap at once with "Sends when your phone is near", and the system delivers it later; a start from before a feed logged since is dropped rather than showing a feed running for hours. The phone tells the watch which taps it has handled, so they stop showing as waiting. The alarms already ring on the watch: AlarmKit and Time Sensitive notifications are mirrored by the system, so the watch app sets none.
  - **Checked 16 Nov 2026** in a paired iPhone 18 Pro and Apple Watch Series 10 (42 mm) simulator: the watch showed the phone's last feed and window; a start sent from the watch (`-watchSendTest start`) showed as a running feed on the phone at the same second; a finish from the watch ended it on both, and the phone opened its details panel. Every screen fits the 42 mm watch. A first run crashed when the phone's reply arrived (a Swift isolation check on WatchConnectivity's own queue); fixed before saving. Code: `Watch/`, `App/Model/WatchRelay.swift`; logic and tests: `FeedingCore/Sources/FeedingCore/Watch/WatchState.swift`, `WatchStateTests`. **Changed 16 Nov 2026, after the first try on the real watch (the user's choices):** Start feed on the watch face shows a stopwatch and the running feed's timer while this parent's feed runs, and a tap on it finishes the feed and asks for the bottle's amount (`WatchFaceButton`, tested in `WatchStateTests`; the link names the feed, so a face that is a little behind can't finish a different one). During the other parent's feed it shows their timer, and a tap only opens the app, so ending their feed takes a second tap on "Finish for Sam". The amount screen answered nothing: the crown needs its box selected, and nothing selected it; it now takes the crown when it opens, and has − and + buttons for a finger. Checked in the paired simulators with `-watchFaceTapTest finish`: the face's Finish ended a running formula feed on the phone too, and the watch asked "How much formula?". **Still to check on the real watches:** the double tap, the crown, the watch face pieces (above all a tap on Start feed), a tap with the phone out of reach, and the app being woken on the phone by a watch tap.
- A polished Duo unfolded layout.
- CSV and JSON export.
- **Graphs** (chosen 14 Nov 2026), drawn with Apple's Swift Charts, so no third-party code. They read the events already stored, so they show every feed back to the first one. No schema change.
  - Feeds per day.
  - Bottle millilitres per day, split into formula and expressed milk.
  - Time between feed starts.
  - Minutes on each breast side per day.
  - Millilitres pumped per day.
  - Facts only, like the home screen: no target lines, no "normal" bands, and no red or green. One colour for each kind of milk.
  - The small 24-hour chart on the home screen is not this: it is part of the visual redesign (`05-visual-redesign.md`). The graphs here are a full screen of them, and they use the colours and shapes in `DESIGN.md`.
  - **Decided 16 Nov 2026** (the user's choices from side-by-side mockups, kept outside the repo in the gstack design folder `designs/graphs-20261116/`):
    - **Three tabs: Home, History, Graphs.** The parent asked for the graphs one tap from the main screen, as a tab. History moves from the top of Home into the tab bar; Settings stays as the gear at the top of Home. On the folded Duo, iOS puts the tab bar in the bar down the right-hand side.
    - **A) One long page:** every graph in its own tile, one under the other, with a 7 days / 4 weeks / All switch at the top. A graph with nothing to show in the chosen time is left out (a bottle-only phone sees no breast-side graph). Today's bar is lighter, as the day isn't over.
    - **Time between feeds, B):** each day is a soft bar from its shortest gap to its longest, with a dot for the middle gap (half were shorter, half longer). Not a dot per gap (crowded over weeks) or an average line (hides the night stretch).
    - **Bottles, A) two blues:** each day's bar is its total ml, formula in deep blue at the bottom and expressed milk in light blue above. Not blue and pink, as pink means a feed at the breast.
    - **Breast sides, A):** two bars a day, left in deep pink and right in light pink, keyed with the half-moons. Not left up and right down.
    - Feeds per day are plain bars in a neutral colour (no kind), and pumping is green.
    - Days run midnight to midnight in the household's time zone.
  - **Built 16 Nov 2026.** `graphDays` (in `FeedingCore/Sources/FeedingCore/Insights/Graphs.swift`, tested in `GraphTests`) turns the visible feeds and pumps into one fact sheet per day: feeds, formula and expressed ml, minutes on each side (a side still running adds nothing yet), pumped ml and sessions, and every gap between feed starts, kept under the day the later feed started (so a day's first gap starts at the feed before, even outside the range). The range starts no earlier than the first feed or pump, so a new household sees no empty days. A feed logged on both phones counts once; deleted feeds, other babies and anything after now (a clock set back) are left out. Gaps are real elapsed time, so a clock change makes no gap an hour longer or shorter. The screen is `App/Graphs/GraphsView.swift` (Swift Charts, Apple's), with its words in `GraphText` (tested in `GraphTextTests`); the tabs are in `App/ContentView.swift`. On the unfolded Duo, when the page is wide enough for two 340 pt tiles, the tiles go two across. **Checked 16 Nov 2026** in the iPhone 18 Pro simulator with a made-up week and month (`-sampleWeek`), by day and at night, and with the accessibility audit (`testGraphs`): at the largest text size the day names ran into each other, so the chart's words now stop growing at xLarge (VoiceOver reads each bar); the keys moved under the tile labels so a long label isn't squeezed.

### Phase 3: growing with her
- Pumping statistics and a record of the expressed-milk stash.
- Nappies, sleep, weight, and medicine or vitamin reminders.
- Solids from about 6 months.
- Summaries for the health visitor.
- An interface for more than one baby.
