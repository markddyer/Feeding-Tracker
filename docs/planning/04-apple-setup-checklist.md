# Apple setup checklist

Every identifier below uses the app's ID, `com.tracker.feeding` (the user's choice, 14 November 2026). The same IDs are in `project.yml`. Bundle IDs aren't secret, so that's fine.

⚠️ Bundle IDs and iCloud container IDs must be unique across all of Apple, and an iCloud container can never be deleted. So register the App ID `com.tracker.feeding` **first**. If Apple says it's already taken, stop and choose another prefix before creating anything else.

Steps are in order. Steps marked **(Phase 2)** can wait.

## 1. Mac
- [ ] An Apple silicon Mac running **macOS Tahoe 26.6 or later**.
- [ ] **Xcode 27.2**, with the iOS 27.2 and watchOS 27.2 platforms.
- [ ] The **iPhone Duo simulator**. It has its own runtime (7.8 GB), separate from the ordinary iOS 27.2 one, which refuses to create a Duo. Keep both. Install it with `xcodebuild -downloadPlatform iOS -buildVersion 24B91016s`, then add the device in Device Hub (+ → iPhone → iPhone Duo). This command installs the runtime even with `-exportPath`, so don't import an exported copy afterwards.
- [ ] `brew install xcodegen` (version 2.46 or later).
- [ ] Sign in to Xcode with your Apple Account (Settings → Accounts).
- [ ] Turn on Developer Mode on your own iPhones: Settings → Privacy & Security → Developer Mode.

## 2. developer.apple.com: Certificates, Identifiers & Profiles
- [ ] Accept any outstanding agreements.
- [ ] **iCloud Containers:**
  - `iCloud.com.tracker.feeding`
  - `iCloud.com.tracker.feeding.dev`
- [ ] **App Groups:**
  - `group.com.tracker.feeding`
  - `group.com.tracker.feeding.dev`
- [ ] **App IDs:**

| App ID | Capabilities |
|---|---|
| `com.tracker.feeding` | iCloud (CloudKit → `iCloud.com.tracker.feeding`), Push Notifications, App Groups (`group.com.tracker.feeding`), Time Sensitive Notifications |
| `com.tracker.feeding.dev` | The same, but with `iCloud.com.tracker.feeding.dev` and `group.com.tracker.feeding.dev` |
| `com.tracker.feeding.widgets` and `com.tracker.feeding.dev.widgets` **(Phase 2)** | App Groups (the matching group) |
| `com.tracker.feeding.watchkitapp` and `com.tracker.feeding.dev.watchkitapp` **(Phase 2)** | App Groups. The watch app's ID must start with the iPhone app's ID. |

- [ ] **Devices:** Xcode registers your own iPhones and Watch automatically. Register Parent B's iPhone too, so it can run **Feeding Dev** during the spikes. You'll need its UDID, which shows when the phone is connected to the Mac (Finder or Xcode → Devices).
- [ ] **Not** an AlarmKit entitlement. There isn't one. AlarmKit needs only an Info.plist usage string, and adding a made-up entitlement breaks signing.

The project's `project.yml` will set these Info.plist keys and capabilities, so you don't add them by hand:
- `CKSharingSupported = YES`
- `NSAlarmKitUsageDescription`
- `ITSAppUsesNonExemptEncryption = NO` (confirmed 16 Nov 2026: the app uses only Apple's own encryption, iCloud's HTTPS and CloudKit's encrypted fields, which is exempt)

Also in place for the first upload (16 Nov 2026):
- **Privacy manifest:** `Shared/PrivacyInfo.xcprivacy`, built into the app and the widget extension. No tracking and no data collected (the feeds stay in the household's iCloud, which the developer can't read). The one API Apple asks a reason for is UserDefaults: `CA92.1` and `1C8F.1` (App Group).
- **Release build:** the `Feeding` scheme builds in Release for a real iPhone, without the Dev-only code.
- [x] **App icon** (17 Nov 2026): the baby's head on coral (`tools/app-icon.svg`), for the phone and the watch, with a "DEV" band on Feeding Dev's. See "App icon" in `DESIGN.md`; `swift tools/make-app-icons.swift tools/app-icon.svg` makes all four.
- Background Modes → Remote notifications

## 3. CloudKit Console (icloud.developer.apple.com)
- [ ] `xcrun cktool save-token --type management`, run once on the Mac.
- [ ] Check the draft schema first: `xcrun cktool validate-schema --team-id <your team ID> --container-id iCloud.com.tracker.feeding.dev --environment development --file schema.ckdb`.
- [ ] **Dev container:** `xcrun cktool import-schema --container-id iCloud.com.tracker.feeding.dev --environment development --file schema.ckdb`.
- [ ] **Production container, only when the schema is final** (after the Phase 0 spikes):
  1. Import the same file into the production container's **Development** environment.
  2. In the CloudKit Console, open the container and choose **Deploy Schema Changes…**. Check the changes, then deploy.
  3. Export the schemas of both environments and compare them.

  ⚠️ Once a schema is in Production, record types and fields can never be removed or renamed, and encryption can't be added to an existing field.

## 4. App Store Connect (appstoreconnect.apple.com)
- [ ] **Apps → + → New App:**
  - Platform: iOS.
  - Name: something unique on the store. The name on the Home Screen can be different.
  - Bundle ID: `com.tracker.feeding`.
  - SKU: any value.
  - User Access: **Limited Access**.
  - Don't create a record for the Dev variant.
- [ ] **Users and Access → +:**
  - Add Parent B with the **Marketing** role, limited to this app, with no access to reports or certificates.
  - The invite expires after 3 days.
- [ ] After the first upload (Xcode → Product → Archive → Distribute App → **TestFlight Internal Only**):
  1. In TestFlight, create an internal group called **"Household"** with **automatic distribution** turned on.
  2. Add yourself and Parent B to it.
  3. Each build expires after 90 days.

- [x] An App Store Connect API key for TestFlight uploads (23 Nov 2026): **Users and Access › Integrations › App Store Connect API › Team Keys**, role **Admin** (App Manager can't use the cloud distribution certificate). Its file goes in `~/.appstoreconnect/private_keys/`, and its key ID and issuer ID in the gitignored `Config/Local.xcconfig` (`ASC_KEY_ID`, `ASC_ISSUER_ID`). Uploads then need no Xcode sign-in, which runs out hours after each sign-in for a command-line upload.

## 5. Parent B's iPhone
- [ ] Update to **iOS 27.1 or later**. That is the app's minimum.
- [ ] Accept the App Store Connect invite email.
- [ ] Install **TestFlight**, open the invite on the iPhone, and install the app.
- [ ] Allow **Notifications**, **Time Sensitive** notifications (for the app, and for Sleep Focus) and **Alarms**.
- [ ] Keep **Background App Refresh** turned on, and stay signed in to iCloud.
- [ ] **Don't hide or Face ID–lock the app, and don't force-quit it.** AlarmKit alarms from hidden or locked apps fail silently, and a force-quit app gets no sync pushes.
- [ ] Open the household invite in Messages and accept it. If the link doesn't open the app, paste it into the app's "Join household" screen instead.

## 6. Your own iPhones and Watch
- [ ] The same permissions as Parent B: notifications, Time Sensitive and alarms.
- [ ] Check that each Watch is supported by watchOS 27. That means Series 9–12, SE 3 or Ultra 2–4. Series 8 or earlier, SE 2 and Ultra 1 are **not** supported.
- [ ] Check that the household owner's iCloud has some free storage. If it fills up, sync stops for both of you.

## 7. AI insights: App Attest and the Claude Console (23 Nov 2026)
`docs/planning/12-ai-insights-gauntlet.md`, D2 and S10. The phones reach Claude with Apple's App Attest (each install proves it is the real app) and a client ID, with no key in the app.
- [x] Claude Console (platform.claude.com), **Settings › App integrations › Create app integration**: name "Little Log", workspace "Little Log" (it can't be changed later), the Apple team ID, and both bundle IDs, `com.tracker.feeding` and `com.tracker.feeding.dev` (one integration takes up to 32). Its client ID (`clid_…`, not a secret) goes in the gitignored `Config/Local.xcconfig` as `CLAUDE_CLIENT_ID`.
- [x] Claude Console, **API keys**: a key for the simulator only, in `Config/Local.xcconfig` as `CLAUDE_DEV_API_KEY`. A phone build never carries it (check the built app's `Info.plist`: `ClaudeDevAPIKey` is empty).
- [x] Claude Console: the "Little Log" workspace's spend limit, £10 a month (D11). Set by Parent A on 22 Nov 2026.
- [x] App Attest capability on both App IDs: `project.yml` gives both variants the entitlement `com.apple.developer.devicecheck.appattest-environment` = `production`, and automatic signing (`-allowProvisioningUpdates`) adds the capability to the App ID. `production` in a build from Xcode too, so it is the same as TestFlight (S10).
- [x] Check from a real phone, with a made-up week and no yes: Little Log Dev › Home's Tests menu › **AI connection test**, or launch with `-aiConnectionCheck YES`, then read the "ai-check:" lines in the sync log (see `CLAUDE.md`). On the Duo, 23 Nov 2026: App Attest passed in 2.2 s and a card was made in 3.5 s.
- [x] Little Log (TestFlight build 5 or later): each parent's **Yes** in Settings › AI insights runs App Attest at once; a failure shows under "This phone". Both yeses made on 23 Nov 2026, and the first real card was made on Parent A's Duo that afternoon.
