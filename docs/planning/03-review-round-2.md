# Review round 2: plan v1 (revision 1)

*12 November 2026. Two independent reviewers looked at plan v1 revision 1. Their findings have been added to plan v1 revision 2. Sources come from the reviewers' web research. Many are reports on Apple's developer forums that Apple hasn't confirmed.*

## Red team: alerts on two phones

Each scenario leads to one or more of these outcomes:
- (a) A needed alert is missed or comes late.
- (b) The off-duty parent is woken for nothing.
- (c) Feeds are lost or duplicated.
- (d) The two phones disagree about who is on duty.

| # | Scenario | Outcome | Change made in revision 2 |
|---|---|---|---|
| S1 | **AlarmKit alarms come late or not at all on a phone left locked overnight**: about 13 minutes late, for 1 in 3–5 alarms, on iOS 26 through 27 RC, reproduced with Apple's sample ([846063](https://developer.apple.com/forums/thread/846063)). Other reports: stray alarms at midnight ([820388](https://developer.apple.com/forums/thread/820388)); alarms lost after an iOS update ([809398](https://developer.apple.com/forums/thread/809398)); two alarms in the same minute both silent ([855535](https://developer.apple.com/forums/thread/855535)); calendar-based alarms rolling over to the next day ([797618](https://developer.apple.com/forums/thread/797618)); alarms from hidden or locked apps failing silently ([FAQ](https://developer.apple.com/forums/thread/797158)). | a | The main alert is scheduled three ways: an alarm at the exact time, plus a Time Sensitive notification, plus a follow-up alarm 10 minutes later. Everything is rescheduled on launch and after an iOS update. Setup tells parents not to hide or lock the app. The spike becomes 7 or more overnight runs. |
| S2 | The on-duty parent has chosen "gentle nudge". Sleep Focus or the Watch absorbs it, and at night no other phone alerts. | a | At night, the on-duty alert is always the loud alarm. This is pending the user's confirmation. |
| S3 | **Hand-offs come back in another form.** Undoing a claim, changing the rota start date, shortening the window or turning alerts back on can each leave nobody alerting if the other phone's sync is delayed. Apple can delay background pushes ([docs](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)). | a | The acknowledgement rule: such changes stay pending until the other phone confirms them, and until then the phone that made the change alerts as if on duty, using the stricter settings. Claims can only be undone before they upload. |
| S4 | **It isn't defined which date a night belongs to.** At midnight the rota flips, clock changes break the arithmetic, and a phone in another time zone disagrees. | d → a/b | A night is named by the local date it starts on, in a stored household time zone. Day or night is decided by when the alert fires. Tests cover the edge cases. |
| S5 | **A field-level merge can't work with a single `modifiedAt` and an encrypted blob.** Parent A corrects a feed's start time, Parent B adds 30 ml from an old copy, and the correction is lost. | c → a | Each phone tracks which fields it changed and merges those over the server copy. `reconcile` reads only the top-level fields. A feed's start time is capped at the server's creation time for the record. |
| S6 | A feed waits out its 10-second undo window while the phone is locked, and doesn't upload until morning, because CKSyncEngine sends on the system's schedule ([WWDC23](https://wwdcnotes.com/documentation/wwdc23-10188-sync-to-icloud-with-cksyncengine/)). | c → b | The feed is saved immediately. Going to the background ends the undo window and sends straight away in a background task. A push triggers an explicit fetch and reconcile. |
| S7 | At the start of the morning, a phone that hasn't caught up wakes a parent who is having a lie-in, or misses the first daytime alert. | b | Last night's rules stay in force until the off-duty parent opens the app or their "lie in until" time passes. |
| S8 | **The owner's iCloud is full.** Every upload fails, so each phone sees only its own feeds ([quotaExceeded](https://developer.apple.com/documentation/cloudkit/ckerror/quotaexceeded)). | c, b | A specific red warning on both phones, and a storage check during setup. |
| S9 | **Signing out of iCloud or revoking the share wipes the local data**, so `reconcile` schedules nothing. Automatic clean-up has deleted a live shared zone in another app ([822913](https://developer.apple.com/forums/thread/822913)). | a | When data unexpectedly disappears, the app keeps the last alerts and shows "sync broken". Zones are never deleted automatically. |
| S10 | A claim arrives late after the other parent is asleep; AlarmKit fires a stray midnight alarm. | b | Accepted and documented. |

Claims in revision 1 that were wrong or unverified:
- **"Fails early, never late" was wrong.** S3, S5, a phone clock running fast, and S7 can all make an alert late or missing.
- **"Reconcile runs when an alert fires" isn't reliable.** On iOS 27 the app may only learn about a fired alarm at the next unlock ([844479](https://developer.apple.com/forums/thread/844479)).
- **It's unverified whether a background push can schedule AlarmKit alarms.** This is now part of spike 2.
- **It's unverified whether the iPhone still rings while the Watch is worn.** This is now part of spike 1.

What held up:
- Timing from the start of a feed.
- Never storing a "next due" time.
- The single pure `reconcile`.
- One record per night for claims.
- Changing the daytime hours.
- The on-duty parent logging feeds on their own phone.
- Data living on Apple's servers, so it doesn't matter if the owner's phone is off.
- CKSyncEngine catching up when the app launches.
- Alarms surviving a reboot or force-quit.

## Apple setup fact-check

The corrections below are now in the plan. The exact steps are in [04-apple-setup-checklist.md](04-apple-setup-checklist.md).

1. **Don't run the CloudKit spike on TestFlight.** TestFlight always uses Production, where the schema becomes permanent ([842909](https://developer.apple.com/forums/thread/842909), [deploying the schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema)). Spike on Feeding Dev instead, and deploy only the final schema.
2. **Feeding Dev needs its own iCloud container and App Group.** When two apps share a container, share links can open the wrong app ([767676](https://developer.apple.com/forums/thread/767676)). A shared App Group would also give both apps the same local store. Manage the schema as text with `cktool` ([text schema](https://developer.apple.com/documentation/cloudkit/integrating-a-text-based-schema-into-your-workflow)).
3. **The encrypted `payload` field must be declared encrypted from its first import**, because encryption can't be added to an existing field later ([encryptedValues](https://developer.apple.com/documentation/cloudkit/ckrecord/encryptedvalues)).
4. **AlarmKit has no entitlement.** It needs only `NSAlarmKitUsageDescription` and a call to `requestAuthorization()`. Some AI-generated code invents an entitlement, and that breaks signing ([797950](https://developer.apple.com/forums/thread/797950)). A widget extension is needed only for countdown presentations. Alarms ring until dismissed, and any hardware button dismisses them.
5. **Accepting a share needs extra setup:** `CKSharingSupported`, plus a scene delegate that handles both the share callback and a cold launch from a share link. Parent B's phone must also write using the shared-database zone ID ([762572](https://developer.apple.com/forums/thread/762572)). Apple has no sample combining CKSyncEngine with a shared database.
6. **Tooling:**
   - Xcode 27.2 ships Swift 6.4 and needs macOS Tahoe 26.6 or later on Apple silicon ([Xcode support](https://developer.apple.com/support/xcode/)).
   - GitHub's `xcode-27` runner is free for public repos ([GitHub changelog](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available)).
   - XcodeGen 2.46 writes the classic project format.
7. **Time Sensitive notifications** need a capability but no approval from Apple ([docs](https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive)).
8. **iPhone Duo:**
   - There's no API for folded versus unfolded. Use size classes and `NavigationSplitView`.
   - On the outer screen, toolbars move to the side.
   - Build with the iOS 27.1 SDK or later.
   - Most extensions can't run in the Duo simulator ([guide](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo), [Xcode 27.1 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes)).
   - *Corrected 14 November 2026, against the shared Duo notes on the Mac:* iOS 27.1 **does** report the hinge and the fold (`onHingeChange`, `reservedRegions`), but Apple says to lay out from size classes and use those only for effects. For two columns that must both stay visible, Apple's container is `ArrangementView`, not `NavigationSplitView`. The plan now says so.
9. **Watch:**
   - watchOS 27 runs on Series 9–12, SE 3 and Ultra 2–4 ([9to5Mac](https://9to5mac.com/2026/06/19/watchos-27-drops-support-for-five-apple-watch-models-heres-why/)).
   - Use WatchConnectivity rather than CloudKit sync on the watch ([737126](https://developer.apple.com/forums/thread/737126)).
10. **TestFlight:**
    - The internal tester can have the Marketing role, limited to this app.
    - An individual account can add up to 50 users ([TestFlight](https://developer.apple.com/testflight/), [adding users](https://developer.apple.com/help/app-store-connect/manage-your-team/add-and-edit-users)).
    - Builds expire after 90 days.

**Not verified:**
- That internal TestFlight builds skip review. Only third-party sources say so.
- Whether there's a real limit on how many alarms AlarmKit allows.
- Whether CKSyncEngine on the watch works with a shared database.
- XcodeGen's compatibility with Xcode 27.
- The exact labels in iOS 27's Settings.
- Whether CloudKit-only encryption counts as exempt for export compliance.
