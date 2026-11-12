# Apple setup checklist

Every identifier below uses the placeholder `com.example.feeding`. Before you start, choose your own reverse-DNS prefix, for example one based on a domain you own, and use it everywhere `com.example` appears. Keep the real IDs in `project.yml`. Bundle IDs aren't secret, so that's fine.

Steps are in order. Steps marked **(Phase 2)** can wait.

## 1. Mac
- [ ] An Apple silicon Mac running **macOS Tahoe 26.6 or later**.
- [ ] **Xcode 27.2**, with the iOS 27.2 and watchOS 27.2 platforms and the **iPhone Duo** simulator.
- [ ] `brew install xcodegen` (version 2.46 or later).
- [ ] Sign in to Xcode with your Apple Account (Settings → Accounts).
- [ ] Turn on Developer Mode on your own iPhones: Settings → Privacy & Security → Developer Mode.

## 2. developer.apple.com: Certificates, Identifiers & Profiles
- [ ] Accept any outstanding agreements.
- [ ] **iCloud Containers:**
  - `iCloud.com.example.feeding`
  - `iCloud.com.example.feeding.dev`
- [ ] **App Groups:**
  - `group.com.example.feeding`
  - `group.com.example.feeding.dev`
- [ ] **App IDs:**

| App ID | Capabilities |
|---|---|
| `com.example.feeding` | iCloud (CloudKit → `iCloud.com.example.feeding`), Push Notifications, App Groups (`group.com.example.feeding`), Time Sensitive Notifications |
| `com.example.feeding.dev` | The same, but with `iCloud.com.example.feeding.dev` and `group.com.example.feeding.dev` |
| `com.example.feeding.widgets` and `com.example.feeding.dev.widgets` **(Phase 2)** | App Groups (the matching group) |
| `com.example.feeding.watchkitapp` and `com.example.feeding.dev.watchkitapp` **(Phase 2)** | App Groups. The watch app's ID must start with the iPhone app's ID. |

- [ ] **Devices:** Xcode registers your own iPhones and Watch automatically. Register Parent B's iPhone too, so it can run **Feeding Dev** during the spikes. You'll need its UDID, which shows when the phone is connected to the Mac (Finder or Xcode → Devices).
- [ ] **Not** an AlarmKit entitlement. There isn't one. AlarmKit needs only an Info.plist usage string, and adding a made-up entitlement breaks signing.

The project's `project.yml` will set these Info.plist keys and capabilities, so you don't add them by hand:
- `CKSharingSupported = YES`
- `NSAlarmKitUsageDescription`
- `ITSAppUsesNonExemptEncryption = NO` (still to be confirmed)
- Background Modes → Remote notifications

## 3. CloudKit Console (icloud.developer.apple.com)
- [ ] `xcrun cktool save-token --type management`, run once on the Mac.
- [ ] **Dev container:** `xcrun cktool import-schema --container-id iCloud.com.example.feeding.dev --environment development --file schema.ckdb`.
- [ ] **Production container, only when the schema is final** (after the Phase 0 spikes):
  1. Import the same file into the production container's **Development** environment.
  2. In the CloudKit Console, open the container and choose **Deploy Schema Changes…**. Check the changes, then deploy.
  3. Export the schemas of both environments and compare them.

  ⚠️ Once a schema is in Production, record types and fields can never be removed or renamed, and encryption can't be added to an existing field.

## 4. App Store Connect (appstoreconnect.apple.com)
- [ ] **Apps → + → New App:**
  - Platform: iOS.
  - Name: something unique on the store. The name on the Home Screen can be different.
  - Bundle ID: `com.example.feeding`.
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

## 5. Parent B's iPhone
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
