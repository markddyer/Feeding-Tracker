# Feeding Tracker: plan v1

*Revised 12 November 2026 after the review gauntlet ([01-review-gauntlet.md](01-review-gauntlet.md)) and the user's answers.*

> **This repository is public.** No personal data goes in it: no names, no feed logs, no photos.
> The baby's and parents' names are typed into the app and stored only in the household's iCloud.
> This document says "Parent A" for the parent who creates the household and "Parent B" for the other.

## Context

- **Baby:** newborn, already born. The midwives advise feeding every 2–4 hours, alongside following hunger cues.
- **Feeding:** mixed. Breastfeeding is being established, but sore nipples are making it hard, so Parent B is expressing milk. Expressed milk goes in a bottle and formula makes up the shortfall. **Breast-side tracking is needed.**
- **People and devices:** two parents, each with their own iPhone and Apple ID. The devices are an iPhone 18 Pro, an iPhone Duo (foldable: 5.4" outer and 7.6" inner screens) and Parent B's iPhone. Apple Watch integration is wanted.
- **Nights:** the parents take turns, flexibly, so the parent who is off gets unbroken sleep.
- **Alerts:** each parent chooses a **loud alarm** or a **gentle nudge** in Settings.
- **Why build:** privacy, control, and adding features as the baby grows.
- **Setup:** paid Apple Developer Program membership and a Mac. Both phones must be able to install the app while it's still in development.

## Product principles

1. **The headline is time since the last feed started.** Alerts are a safety net, not a schedule.
2. **Everything works one-handed in the dark, in one or two taps, and can be undone.**
3. **Two phones, one record.** Whatever one parent logs appears on the other phone.
4. **Failures go the safe way.** A sync delay may cause an unnecessary alert, but should never cause a missing one. See "Why stale data fails safe".
5. **Nothing leaves the household's iCloud.** No analytics, adverts, third-party SDKs or servers.

## The feed window

The midwives' "every 2–4 hours" becomes a window, measured from the **start** of the last feed.

| Time since last feed started | State | What happens |
|---|---|---|
| 0 – 2h | Recently fed | Nothing. |
| 2h | Window opens | Optional gentle nudge: "may be ready to feed; watch for cues". |
| 4h | Window closes | The safety-net alert, in each parent's chosen style. |

- Both times are shared settings, defaulting to the midwives' 2h and 4h. They can be edited when the advice changes.
- The alert can be switched off entirely once the baby is fed fully on demand.
- The wording never says "due", "missed" or "overdue".

## What gets recorded

Events, all with a required start time and an optional end time:

- **Feed.** Any combination of:
  - **Breast:** one or more segments, each Left or Right with an optional duration. Switching sides adds a segment.
  - **Bottle:** one or more, each *expressed milk* or *formula*, with a volume in ml.
  - **Note:** optional.
- **Pump (expressing session):** proposed for phase 1, to be confirmed. Records the time, the side (left, right or both), and ml per side.
- **Later kinds** (phase 3): nappy, sleep, growth, medicine, solids. The data model already allows for them.

## Screens

**Home screen** on a standard phone or the folded Duo, from top to bottom:
1. "Last feed started **1h 40m ago**" with the start time, and a ring showing progress through the window.
2. "Window opens 03:50 · Alert at 05:50".
3. **Suggested next side**: the side not used last. This is only a suggestion.
4. The last feed in brief, for example "L 12m · R 8m · Formula 30 ml, logged by Parent A".
5. The last 24 hours: number of feeds, breast sessions, ml of expressed milk and ml of formula. No targets and no red or green.
6. Tonight's duty: "Parent B is on tonight", with an **"I'll take tonight"** button.
7. A full-width **Start feed** button at the bottom.
   - During a feed, large **Left / Right / Bottle** buttons and **Finish** appear.
   - After Finish come quick ml chips for any bottle, which can be skipped.
   - An Undo banner shows for 10 seconds.

Also on the home screen:
- **"Just finished, started about 10 / 20 / 30 / 45 min ago"**.
- **"Log an earlier feed"**.

**History:** a timeline grouped by day. Entries can be edited and deleted (deletes are soft), and every change goes through `reconcile()`.

**Unfolded iPhone Duo:** two columns, with the home screen on the left and the day's timeline and history on the right. Folding or unfolding must not lose a feed in progress.

**Night UI:**
- Always dark, on true black, with a dim warm accent.
- No white flashes from the launch screen, sheets or keyboard.
- Large tap targets, haptic feedback, and no typing.

**Disclaimer** on first launch and in Settings: "Records feeds; not medical advice. If you're worried, contact your midwife, health visitor or GP. In an emergency, call your local emergency number."

## Alerts on two phones

### Each parent's settings (stored on their own phone)
- **When the window closes**, one of:
  - **Loud alarm**, using AlarmKit. It sounds even with the phone on silent or in a Focus, and also on a paired Apple Watch.
  - **Gentle nudge**, a Time Sensitive notification. It vibrates, appears on the Watch, and respects silent mode.
- **When the window opens:** a gentle nudge, or nothing.

### Who gets alerted
- **Daytime** is a shared setting, defaulting to 07:00–21:00. Both phones alert, each in its owner's chosen style.
- **At night, only the on-duty parent's phone alerts.** The other phone stays silent.
- **The rota alternates nightly from a shared start date.** Each phone calculates the default rota itself, so the two agree even when they can't sync.
- **Changes to the rota can only be claimed, never handed off.**
  - You can take a night ("I'll take tonight").
  - You can ask the other parent to take one, which shows a prompt on their phone.
  - You can't give a night away. Your own alerts carry on until the other parent's claim reaches your phone.
  - *Why:* if a hand-off failed to sync, *nobody* would be woken. With claims only, a sync failure means *both* phones ring, which is annoying but safe.
- **Optional backup, later, off by default:** if no feed has been logged N minutes after the on-duty alert, the off-duty phone alerts too.

### Why stale data fails safe
Each phone schedules its own alerts from the newest feed it knows about, through a single pure function:

`reconcile(events, settings, rota, me, now, calendar) -> [DesiredAlert]`

**The usual case is safe.** If a feed logged on one phone hasn't reached the other yet, the other phone works from an older feed. Its alert therefore fires **early, never late**. Opening the app from that alert triggers a sync and shows "Fed at 01:50 by Parent A; alert moved to 05:50".

**The exception** is deleting the latest feed or moving its start time earlier. Both move the correct alert time earlier, so a phone that hasn't heard about the change alerts late. Mitigations:
1. New feeds are only uploaded once the 10-second undo window has passed, so an undone mistaken tap never leaves the phone.
2. Edits and deletes are rare, and they're usually made by someone who is awake.
3. Sync status is shown on screen.

**When reconcile runs:** on launch, on returning to the foreground, after any local change, when a remote change arrives, during background refresh, when the time or time zone changes, when the duty rota or settings change, and when an alert fires.

**During setup**, the app explains that force-quitting it delays sync, because Apple doesn't deliver silent pushes to an app the user has force-quit.

**Measuring it:** the app keeps local counts of "stale alerts", meaning an alert fired although a newer feed had already been logged elsewhere, and of how long remote changes took to arrive. If these turn out to be a problem, a small push server is the fallback in a later phase.

## Architecture

| Part | Builds on | Contents |
|---|---|---|
| `FeedingCore` (Swift package) | Linux + Apple | Uses only Foundation. Contains: domain types, `reconcile`, feed-window maths, next-side suggestion, 24h summaries, duplicate detection, merge rules, rota calculation, and versioned payload encoding. Tested with Swift Testing, including time-zone and daylight-saving cases. |
| iOS app (iOS 27+) | Xcode | SwiftUI views. SwiftData local store behind a `Store` protocol. `SyncEngine` (CKSyncEngine). `AlertScheduler` adapters for AlarmKit and UNUserNotificationCenter. App Intents. |
| Widget extension | Xcode | AlarmKit countdown presentation. Later: Lock Screen and Home Screen widgets and a Control Center control. |
| watchOS app (phase 2) | Xcode | Start or finish a feed and choose a side from the wrist. A complication showing time since the last feed. |

- **Project generation:** the Xcode project is generated from `project.yml` with XcodeGen, so the agent never edits the `.pbxproj` file by hand.
- **Two app variants, installable side by side:**
  - **Feeding**, from TestFlight, uses CloudKit **Production** and holds the real data.
  - **Feeding Dev** has a different bundle ID and icon and uses CloudKit **Development**, so testing never touches the real data.

## Data and sync

- **Sharing model:**
  - Parent A creates a **Household** zone in their private iCloud database.
  - Parent A shares the **whole zone** with one zone-wide CKShare, sending the invitation through Messages.
  - Parent B accepts it, and their phone syncs from its shared database.
  - CKSyncEngine runs on the private database for Parent A and on the shared database for Parent B.
- **Record types.** Once deployed to production they are permanent, so there are only a few of them, and fields that may change live inside an encrypted, versioned JSON payload.
  - `Baby`: payload (name and birth date), archivedAt.
  - `Member`: payload (display name and colour).
  - `Event`: babyID, kind, startedAt, endedAt, timeZoneID, loggedBy, createdAt, modifiedAt, deletedAt, schemaVersion, and payload (details and note).
  - `Setting`: key, modifiedAt, payload. Record names are fixed (`feedWindow`, `rota`, `duty-2026-11-13`, …) so that changes to different settings never clash.
- **Conflicts:**
  - The most recent change wins, field by field, using `modifiedAt`.
  - Deletes are soft.
  - Duplicate feeds are those for the same baby, starting within 5 minutes of each other, logged by different parents. They're shown merged, with an undo.
- **Compatibility:** older app versions skip any event kind or payload version they don't recognise.
- **Privacy:**
  - Every payload is stored in `encryptedValues`.
  - File protection is `completeUntilFirstUserAuthentication`.
  - No third-party SDKs.
  - "Delete all data" removes the zone and the share.
  - A setting keeps the baby's name off Lock Screen notifications.

## Getting it onto both phones during development

- Create the App Store Connect app record and use **TestFlight internal testing**.
- Add Parent B as an App Store Connect user with a limited role, and as an internal tester. Internal builds don't need Apple's beta review. Each build expires after 90 days.
- TestFlight builds always use **CloudKit Production**, so the schema must be deployed to Production before the first build that syncs. After that, changes can only add to it.
- Upload builds from the Mac (Xcode → Archive → Distribute → TestFlight). CI can automate this later if it gets tedious.

## Workflow

| Who | Does |
|---|---|
| Agent (cloud container) | Writes the code. Runs `swift test` for `FeedingCore` on Linux. Keeps `project.yml` up to date. Pushes to the development branch. |
| GitHub Actions (free for a public repo) | Runs the Linux core tests and a macOS build of every target. |
| You, on the Mac | `git pull`, `xcodegen generate`, run on your devices, archive and upload to TestFlight, and go through the device checklist. |

**Device checklist:**
- Silent switch on.
- Sleep Focus on.
- Phone locked for over an hour.
- Watch on the wrist.
- App force-quit.
- Low Power Mode on.
- Airplane mode, then reconnect.
- Both phones, in both directions.
- Duo folded and unfolded mid-feed.
- Changing the time zone.

## Phases

### Phase 0: foundations and spikes
- **You:** set up the Apple side (the exact checklist will follow).
- **Agent:**
  - The repo skeleton.
  - `FeedingCore` with its tests.
  - `project.yml`.
  - CI.
  - A small spike app.
- **Spikes on the real phones:**
  1. **AlarmKit:** an alarm 2 minutes ahead. Does it sound with the silent switch on, in Sleep Focus, on a locked phone, and on the Watch?
  2. **CloudKit share:** Parent A creates the zone and invites Parent B. Does a test record appear on Parent B's phone within seconds? What happens when the app has been force-quit?
- **Done when:** a TestFlight build on both phones passes both spikes.

### Phase 1: two-phone MVP
Everything in the sections above: the feed window, recording, screens, two-phone alerts, data and sync. **Done when:** a week of real use with no missed alerts.

### Phase 2: glanceable and wrist
- A "Log feed" App Intent, used by a Control Center control, the Action Button and Siri.
- A Lock Screen widget showing time since the last feed and the next side.
- The watch app.
- Polishing the unfolded Duo layout.
- CSV and JSON export.

### Phase 3: growing with her
- Pumping statistics and a stock of expressed milk.
- Nappies, sleep, weight, and medicine or vitamin reminders.
- Solids from about 6 months.
- Summaries for the health visitor.
- An interface for more than one baby.
