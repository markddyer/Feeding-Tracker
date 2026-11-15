# Feeding Tracker

A personal iOS app (plus a watchOS app later) for two parents to log their newborn's feeds, kept in sync between their two iPhones, with safety-net alerts. The project is in Phase 0: the skeleton, `FeedingCore` (feed window, night rota and `reconcile`, with tests), `project.yml`, `schema.ckdb` and CI exist. The Apple portal setup is done (both App IDs, containers and App Groups, 14 Nov 2026), the Dev schema is loaded, and Feeding Dev installs on both real phones. The spikes ran on 14 Nov 2026 (results in the plan); only the 7-night alarm test is still running. Phase 1 has started with the `FeedingCore` logic; the app's store, sync, alert scheduler and screens come next. The visual redesign (`docs/planning/05-visual-redesign.md`) is under way: steps 1 to 3 of 9 are built.

## Read first
1. `docs/planning/02-plan-v1.md`: **the current plan.** It is the source of truth for design decisions.
2. `docs/planning/04-apple-setup-checklist.md`: Apple portal, App Store Connect and CloudKit setup.
3. `docs/planning/03-review-round-2.md` and `01-review-gauntlet.md` explain *why* the plan looks the way it does. Read them before changing anything in the alert or sync design.
4. `CLAUDE.local.md` (gitignored, if present): personal context for this household.
5. `~/.claude/reference/iphone-duo.md` (on the Mac, shared by every project): Apple's iPhone Duo facts, our advice, and simulator measurements. Read it before any layout work, and add new Duo measurements to it.
6. `DESIGN.md` and `docs/planning/05-visual-redesign.md`: the look of the app (day and night looks, colours, letters, shapes) and the screen-by-screen redesign, agreed 15 Nov 2026.

## Design System
Read DESIGN.md before visual or UI work: it defines the fonts, colours, spacing and look. Ask the user before departing from it. When reviewing or testing UI, flag code that doesn't match DESIGN.md.

## Hard rules
- **The repo is public. Never commit personal data.** That means names, birth dates, feed logs, screenshots with real data, device UDIDs or Apple IDs. Personal context goes in `CLAUDE.local.md`, which is gitignored. Docs refer to "Parent A", "Parent B" and "the baby".
- **No third-party SDKs** for analytics, crash reporting, ads or tracking. All data stays in the household's iCloud.
- **Feed timing is measured from the start of a feed.** Never store a "next due" time. Alerts come from `reconcile()` in `FeedingCore`, which is a pure function. `reconcile` reads only the unencrypted top-level fields.
- **When unsure, alert too much rather than too little.** Any change that could make a phone alert later, or not at all, must follow the acknowledgement rule in the plan.
- **The CloudKit Production schema is permanent.** Change the schema only by editing `schema.ckdb`, and only by adding to it. Never deploy to Production without the user's go-ahead. Never delete a CloudKit zone automatically.
- **AlarmKit has no entitlement.** It needs only `NSAlarmKitUsageDescription`. Don't add a made-up entitlement, because that breaks signing.
- **No user-facing wording that sounds like medical advice.** Avoid "due", "missed", "overdue", "should", targets, and red or green verdicts. Keep the disclaimer.
- Spikes and testing use the **Feeding Dev** variant, which has its own bundle ID, container and App Group. Never point development builds at the production container.

## Layout
- `FeedingCore/`: a Swift package that depends only on Foundation. It holds the domain model, `reconcile`, the rota and night logic, the feed and pump details with versioned payload encoding (`PayloadCoder`), the field-level merge (`merge(local:server:changedLocally:)`), the next-side suggestion, the 24-hour summary and duplicate detection. It must build and pass `swift test` on Linux as well as macOS. Adding a payload field that matters means raising that payload's `currentVersion` (see `VersionedPayload`).
- `project.yml`: the XcodeGen spec for the two variants, `Feeding` and `FeedingDev`. Generate the project with `xcodegen generate` and never hand-edit the generated `Feeding.xcodeproj`. Info.plists and entitlements are generated into `Generated/` (gitignored). The Apple team ID goes in `Config/Local.xcconfig` (gitignored; see the `.example`).
- `schema.ckdb`: the CloudKit schema as text, loaded with `xcrun cktool import-schema`. Validated by `cktool` and imported into the **Dev** container's Development environment on 14 Nov 2026 (the export matched the file). Not in Production: that waits for the spikes and the user's go-ahead.
- `App/`, `Widgets/` (Phase 2), `Watch/` (Phase 2).
- `App/Design/`: `DESIGN.md` in code. Colours with day and night values (`Theme`), the day/night switch (`LookModifier`), text styles (`.feedText(...)`), the feed shapes and the small parts (Tile, Chip, Avatar). `App/Fonts/` holds Fredoka and its licence.

## Commands
- Core tests: `swift test --package-path FeedingCore`
- App build: `xcodegen generate`, then `xcodebuild build -project Feeding.xcodeproj -scheme FeedingDev -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
- App tests (CloudKit record mapping, including a check that every field written is in `schema.ckdb`), in the simulator: `xcodebuild test -project Feeding.xcodeproj -scheme FeedingDev -destination 'platform=iOS Simulator,name=iPhone 18 Pro'`. Not in CI yet.
- Screens in the simulator with a made-up day (Feeding Dev only): launch with `-sampleData YES`, plus `-sampleFeedInProgress YES` for a feed running; add `-setup.disclaimerSeen YES -setup.inviteOffered YES -setup.permissionsAsked YES -setup.feedingStyle breastAndBottle` to skip setup (or `bottleOnly`, to see a bottle-only parent's buttons). Sample data loads only into an empty store, so uninstall the app first to start again. For the look: `-look.setting alwaysNight` for night; `-look.setting matchPhone` plus `xcrun simctl ui <device> appearance light` for day. `-designGallery YES` opens the design pieces page. In zsh, pass the flags as an array (`ARGS=(...)`, then `"${ARGS[@]}"`): a plain string reaches the app as one word.
- Sync log from a real phone (Feeding Dev only; record names and errors, no feed details): `xcrun devicectl device copy from --device <device id> --domain-type appGroupDataContainer --domain-identifier group.com.tracker.feeding.dev --source Library/Caches/sync-log.txt --destination sync-log.txt`. Only `Library/` in the App Group can be copied this way; `household.json` at its top can't.
- Real phone: build with `-destination 'id=<device id>' -allowProvisioningUpdates`, then `xcrun devicectl device install app` and `xcrun devicectl device process launch --terminate-existing com.tracker.feeding.dev`. The phone must be unlocked. A phone that is new to the developer account also needs `-allowProvisioningDeviceRegistration`, or the build fails with "isn't registered in your developer account".
## Toolchain
- Xcode 27.2 with Swift 6.4, on macOS Tahoe 26.6 or later.
- Deployment target iOS 27.1, built with the iOS 27.1+ SDK so the iPhone Duo is fully supported (`ArrangementView` and the side-bar controls need 27.1).
- CI runs on GitHub Actions: Linux `swift test` for `FeedingCore`, and the `xcode-27` macOS runner builds every target.
- Git branch: `claude/focused-hamilton-47r7qx`.

## Testing
- Unit tests use Swift Testing, in `FeedingCore`. They must cover these time edge cases: clock changes in both directions, 30-minute time zone offsets, travel, the clock being set back, midnight, and the 21:00 night boundary.
- Simulators include the iPhone Duo, which needs its own simulator runtime (`xcodebuild -downloadPlatform iOS -buildVersion 24B91016s`). `simctl` can't fold it; folding needs the pose buttons in Device Hub. Most app extensions can't run in the Duo simulator, so test widgets in an ordinary iPhone simulator. AlarmKit needs the user's real devices. The device checklist is in the plan.

## Decisions made (14 Nov 2026)
- **Night alerts:** each parent chooses a loud alarm or a gentle nudge, by day and by night. If no feed is logged 30 minutes after the window closes, a **loud backup alarm rings on both phones**, day or night. It is on by default and in Phase 1. Details are in the plan, under "Belt and braces".
- **Pump logging is in Phase 1.**
- **Bundle ID:** `com.tracker.feeding`; the Dev variant is `com.tracker.feeding.dev`. It isn't registered with Apple yet, so it may still turn out to be taken.
- **United Kingdom:** the household time zone defaults to Europe/London. "Get help" means the midwife, health visitor or GP, NHS 111, and 999 in an emergency.
- **Watches:** both run watchOS 27. The models are in `CLAUDE.local.md`.

## Open decisions (ask the user)
- None right now.
