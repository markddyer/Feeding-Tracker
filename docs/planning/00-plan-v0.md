# Feeding Tracker — v0 plan (pre-review)

## The idea (as stated by the user)
An iOS app to track feeding sessions for a newborn, continuing into infancy and possibly beyond.
- Press a button when a feed finishes.
- The app tells you when the next feed is due.
- The feed frequency is configurable.
- "Us": two parents/caregivers will be using it.
- Likely to expand in functionality later (unspecified).

## v0 product scope
- Home screen: one large "Feed finished" button, plus "Next feed due at HH:MM (in Xh Ym)".
- Tapping the button records `finishedAt = now`, computes `nextDue = finishedAt + interval`,
  and schedules a local notification for `nextDue` (replacing any previously scheduled one).
- Settings: feed interval, chosen from 1h30 to 4h00 in 15-minute steps (default 3h).
- History: list of past feeds (newest first), with swipe-to-delete and the ability to edit a time.

## v0 technical approach
- Native iOS app, SwiftUI, minimum iOS 17.
- Persistence: SwiftData, local on-device only.
- Model: `FeedEvent { id: UUID, finishedAt: Date }`; interval stored in UserDefaults.
- Notifications: UNUserNotificationCenter local notifications, no backend.
- Single device at first.
- Distribution: personal install via Xcode, maybe TestFlight later.

## Known constraints
- Development happens with an AI coding agent in a Linux cloud container: no Xcode, no macOS,
  no iOS simulator, no Swift toolchain installed (one could probably be installed for Linux).
  The user will need a Mac with Xcode to build, sign and install the app on their iPhones.
- Whether the user has a paid Apple Developer Program membership is unknown.
- The baby's age or due date is unknown, and so is the user's country.
