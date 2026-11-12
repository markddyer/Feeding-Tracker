# Feeding Tracker

A personal iOS app (plus a watchOS app later) for two parents to log their newborn's feeds, kept in sync between their two iPhones, with safety-net alerts. The project is still in planning: no app code exists yet. The next step is Phase 0.

## Read first
1. `docs/planning/02-plan-v1.md`: **the current plan.** It is the source of truth for design decisions.
2. `docs/planning/04-apple-setup-checklist.md`: Apple portal, App Store Connect and CloudKit setup.
3. `docs/planning/03-review-round-2.md` and `01-review-gauntlet.md` explain *why* the plan looks the way it does. Read them before changing anything in the alert or sync design.
4. `CLAUDE.local.md` (gitignored, if present): personal context for this household.

## Hard rules
- **The repo is public. Never commit personal data.** That means names, birth dates, feed logs, screenshots with real data, device UDIDs or Apple IDs. Personal context goes in `CLAUDE.local.md`, which is gitignored. Docs refer to "Parent A", "Parent B" and "the baby".
- **No third-party SDKs** for analytics, crash reporting, ads or tracking. All data stays in the household's iCloud.
- **Feed timing is measured from the start of a feed.** Never store a "next due" time. Alerts come from `reconcile()` in `FeedingCore`, which is a pure function. `reconcile` reads only the unencrypted top-level fields.
- **When unsure, alert too much rather than too little.** Any change that could make a phone alert later, or not at all, must follow the acknowledgement rule in the plan.
- **The CloudKit Production schema is permanent.** Change the schema only by editing `schema.ckdb`, and only by adding to it. Never deploy to Production without the user's go-ahead. Never delete a CloudKit zone automatically.
- **AlarmKit has no entitlement.** It needs only `NSAlarmKitUsageDescription`. Don't add a made-up entitlement, because that breaks signing.
- **No user-facing wording that sounds like medical advice.** Avoid "due", "missed", "overdue", "should", targets, and red or green verdicts. Keep the disclaimer.
- Spikes and testing use the **Feeding Dev** variant, which has its own bundle ID, container and App Group. Never point development builds at the production container.

## Layout (planned)
- `FeedingCore/`: a Swift package that depends only on Foundation. It holds the domain model, `reconcile`, the rota and night logic, merging and summaries. It must build and pass `swift test` on Linux as well as macOS.
- `project.yml`: the XcodeGen spec. Generate the project with `xcodegen generate` and never hand-edit the generated `.xcodeproj`.
- `schema.ckdb`: the CloudKit schema as text, loaded with `xcrun cktool import-schema`.
- `App/`, `Widgets/` (Phase 2), `Watch/` (Phase 2).

## Toolchain
- Xcode 27.2 with Swift 6.4, on macOS Tahoe 26.6 or later.
- Deployment target iOS 27, built with the iOS 27.1+ SDK so the iPhone Duo is fully supported.
- CI runs on GitHub Actions: Linux `swift test` for `FeedingCore`, and the `xcode-27` macOS runner builds every target.
- Git branch: `claude/focused-hamilton-47r7qx`.

## Testing
- Unit tests use Swift Testing, in `FeedingCore`. They must cover these time edge cases: clock changes in both directions, 30-minute time zone offsets, travel, the clock being set back, midnight, and the 21:00 night boundary.
- Simulators include the iPhone Duo. App extensions and AlarmKit can't be checked properly in the Duo simulator, so those need the user's real devices. The device checklist is in the plan.

## Open decisions (ask the user)
- At night, should the on-duty alert always be the loud alarm? This is recommended, and the user's confirmation is pending.
- Should pump (expressing) logging be in Phase 1?
- The bundle ID prefix (the checklist uses `com.example.feeding` as a placeholder).
- Which household time zone to use, and the country, which decides which "get help" links to show.
- Which Apple Watch models the household has. watchOS 27 needs Series 9 or later, SE 3, or Ultra 2 or later.
