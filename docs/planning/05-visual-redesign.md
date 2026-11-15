# Visual redesign: plan

Agreed with the user on 15 Nov 2026, in a design session with four code mockups, a look at five other baby apps, and two outside design proposals (Codex and a Claude subagent). **`DESIGN.md` at the top of the repo holds the rules: colours, letters, shapes, sizes and motion.** This file says what changes on each screen and the order to build it.

## Why

The user wants the app to look far nicer and happier: fewer sentences, more pictures (rings, bars, charts, shapes), clear space between each fact, and a feel that matches a joyful time with a new baby. The old rule "always dark, on true black" came from a reviewer's suggestion (F10 in `01-review-gauntlet.md`), not from the user, so it is replaced by a day look and a night look.

## Decisions (15 Nov 2026)

- **D1. Look:** "Joyful by day, gentle by night" (mockup A), plus the 24-hour chart from mockup C and the row of nights from mockup D.
- **D2. Day and night:** the night look runs during the household's night hours (the rota's, 21:00 to 07:00 by default). Each phone can choose **Automatic**, **Always night** or **Match iPhone** in Settings.
- **D3. Letters:** Fredoka for headings, names, tile values and button labels. SF Pro Rounded for everything else, and for every time, duration, amount and count, with fixed-width digits. No third typeface.
- **D4. Window:** keep the ring around the main time **and** the window bar under it, with "Feeding window 10:25" and a bell at the alarm time. (Both outside designers suggested one timeline instead, because a filling ring can feel like a countdown. The user chose to keep both. Revisit if it reads as a deadline.)
- **D5. Shapes:** each kind of feed has a shape as well as a colour. Breast is a half-moon whose filled half is the side; bottle is a tall bottle; pumping is two drops.
- **D6. Night letters:** every weight drops one or two steps at night.
- **D7. Stop:** the label becomes "Stop · discard". It still asks "Remove this feed?" first.

## What stays the same

- Alerts, `reconcile()`, the feed window, the rota, sync and the data model. Nothing here changes when a phone alerts.
- The CloudKit schema. The parent colour already exists (`MemberPayload.colour`, a named colour inside the encrypted payload).
- Every rule on wording: no "due", "missed", "overdue" or "should"; no targets; no red or green verdicts; the disclaimer stays.
- The feed ownership, bottle-only, Stop and History rules in `02-plan-v1.md`.

## Screen by screen

### Home, no feed running
Top to bottom (see the mockup's "1. Home"):
1. A greeting by time of day ("Good morning", "Good afternoon", "Good evening"; "Night" with a moon in the night look), the baby's name in Fredoka, and an age chip ("12 days") if a birth date is set. History and Settings stay as toolbar buttons.
2. **Hero tile:** the ring (time so far through the window) beside "Last feed / **2h 05m** / ago, at 8:25". The main time is the biggest thing on screen.
3. **Window bar:** time so far, the shaded window, a mark for now. "Feeding window 10:25" on the left; a bell and "12:25" on the right. This replaces "Window opens 10:25 · Alert at 12:25". If alerts are off, the bar shows no bell and the label says "Alerts off".
4. **Two tiles side by side:** Next side (the half-moon and "Left") and Last feed (chips: "◐ 12m", "◑ 8m", bottle "30 ml"). A bottle-only phone still shows Next side, so that parent can say which side is next.
5. **Last 24 hours tile:** the chart (one bar per feed, coloured and keyed by shape), then three totals: feeds, at the breast, ml from bottles. Pumping shows as a fourth total only if there was any.
6. **Nights tile:** seven days (five nights back, tonight, and tomorrow night, as in the approved mockup) with the on-duty parent's initial in their colour, tonight ringed; "Sam's on tonight" and an "I'll take it" pill; the "waiting for Sam's phone to see your change" line stays, as a small note under it.
7. **Pinned at the bottom:** Start feed (with the bottle icon) and three small buttons: Just finished, Earlier, Pumping.

### Home, a feed running
- The hero tile turns breast-tinted (or bottle-tinted for a bottle feed). The ring shows the current side's half-moon in the middle; the main time is the running clock ("12:04", SF Pro Rounded with fixed-width digits) and "started 10:30" under it.
- A "This feed" tile with chips for each side so far and any bottle ("◐ 8m", "◑ 4:02 running").
- Bottom: Left / Right / Bottle with their shapes (the current side filled), then "Stop · discard" beside a wider Finish.
- On a bottle-only phone: the bottle shape and kind in the hero, no side buttons, and only "Stop · discard" and Finish.
- On the other parent's phone: the same hero with "Started by Sam", and one "Finish for Sam" button.

### After Finish (the details panel)
- A tile with the feed's chips, then the questions as big chips: "Which bottle?" (Expressed milk, Formula, each with the bottle shape) and the amount (30, 60, 90, 120 ml). Each choice goes once it is made, as now.
- A bottle-only phone closes the panel by itself after the amount, as now.

### History
- A big "History" title in Fredoka; day headings ("Today", "Yesterday") in Fredoka.
- One tinted row per feed or pumping session: the time on the left (SF Pro Rounded, fixed-width digits), chips with shapes in the middle, the avatar of who logged it on the right. "Finished by Sam" shows as a second small avatar.
- Swipe then tap to delete, as now.

### Earlier feed and editing a feed
- Keep the form, but use the new colours, shapes in the side and bottle rows, and SF Pro Rounded numbers.

### Settings
- New "Look" row: Automatic, Always night, Match iPhone.
- New "Your colour": six named swatches; the two defaults are sunflower and teal. It is saved in this parent's Member record, so both phones see it.
- The rest keeps its order, restyled.

### Setup
- The same tile style. "How do you feed?" shows the half-moon and bottle shapes on its two choices.

### The Duo unfolded
- Left column: greeting, hero, window bar, Next side and Last feed tiles, and the pinned buttons.
- Right column (replaces today's plain list in `DayTimelineView`): the Last 24 hours tile, the Nights tile, and the recent feeds as History rows.
- The big buttons stay at the bottom of the left column, away from the fold.

### Banners and the launch screen
- Sync problems: a `notice` banner (muted orange), never red.
- Undo banner: a `surface` pill with the message and "Undo".
- **The launch screen stays dark** (`background-night`) in both looks. It can't know the time; a dark flash by day is harmless, a light one at night is not.

## Wording changes

| Today | New |
|---|---|
| "Last feed started" / "1h 40m ago" / "at 08:25" | "Last feed" / "2h 05m" / "ago, at 8:25" |
| "Window opens 10:25 · Alert at 12:25" | Bar: "Feeding window 10:25" and a bell with "12:25" |
| "Feed in progress" | "Feeding now" |
| "Next side: Left (a suggestion)" | Next side tile: half-moon and "Left" (VoiceOver: "Suggested next side: left") |
| "L 12m · R 8m · Formula 30 ml, logged by Parent A" | Chips with shapes, and the parent's avatar |
| "6 feeds · 4 at the breast · 90 ml expressed · 120 ml formula" | Chart and three totals |
| "Parent B is on tonight" / "I'll take tonight" | Nights row, "Sam's on tonight", "I'll take it" |
| "Stop" | "Stop · discard" |

## New pieces to build

1. **Theme:** day and night token sets from `DESIGN.md`, chosen by a small `Look` value (day or night) in the SwiftUI environment. `Theme.swift` keeps its names where it can, so most views change little.
2. **Look resolver** (in `FeedingCore`, so it is tested on Linux too): given the setting (Automatic, Always night, Match iPhone), the household's `DayHours`, its time zone, the time now and the phone's own colour scheme, it returns day or night. It also gives the next time the look changes, so the screen switches on time.
3. **Fonts:** bundle Fredoka (SIL Open Font License, from Google Fonts; keep its licence file beside it) and register it in `project.yml` (`UIAppFonts`). Text styles: `.feedTitle`, `.feedButton`, `.feedNumber` and so on, each using `relativeTo:` for Dynamic Type, and night weights.
4. **Shapes:** `SideShape` (using `circle.lefthalf.filled` / `circle.righthalf.filled`), `BottleShape` and `DropsShape`, with VoiceOver labels.
5. **Components:** `BigButton` (already exists; restyle), `Tile`, `Chip`, `WindowBar`, `WindowRing` (already exists; restyle), `DayChart` (Swift Charts or simple bars; Apple's, so no third-party code), `NightsRow`, `Avatar`, `HistoryRow`.
6. **Facts for the new pictures:** add to `HomeFacts` the feeds of the last 24 hours with their kind and start time (for the chart), and who is on duty for each of the 7 nights (five back, tonight and tomorrow, for the nights row), plus the baby's age in days.
7. **Settings:** the Look setting (per phone, in `@AppStorage`) and "Your colour" (in the Member record).

## Build order

Each step ends with the app building, its tests passing, and a simulator screenshot in both looks.

1. Theme tokens, the Look resolver with its tests, and `.preferredColorScheme` set from the look. Nothing else changes yet, but the app can already switch looks.
2. Fonts and text styles. Fredoka bundled; numbers switched to SF Pro Rounded with fixed-width digits.
3. Shapes and the small components (Chip, Tile, Avatar).
4. Home, no feed running (with the chart and the nights row).
5. Home, a feed running, and the details panel after Finish.
6. History, and the Earlier feed and edit form.
7. Settings (Look, Your colour) and Setup.
8. The Duo's second column.
9. A full pass of checks (below), then the two phones.

**Progress (15 Nov 2026):** steps 1 to 3 are built. The colours are in `App/Design/Theme.swift`, the Look resolver in `FeedingCore/Sources/FeedingCore/Time/Look.swift` (with `LookTests`), the text styles in `App/Design/Typography.swift`, the shapes in `App/Design/Shapes.swift`, and Tile, Chip and Avatar in `App/Design/Components.swift`. Feeding Dev's Tests menu has "Design pieces" to see them in both looks. Two things learned: the app-wide `.fontDesign(.rounded)` swaps a custom font for SF Pro Rounded, so Fredoka text turns it off; and the first builds saved the default parent colour as "amber", which now reads as sunflower.

**Progress (15 Nov 2026, later):** step 4 is built: Home with no feed running, in `App/Home/HomeView.swift`, with its words in `App/Home/HomeText.swift` (tested in `AppTests/HomeTextTests.swift`). The facts behind the pictures are in `FeedingCore/Sources/FeedingCore/Insights/HomeInsights.swift` (tested in `HomeInsightsTests`): the greeting's part of the day (from the rota's hours, so it agrees with the night look), the baby's age in days, the chart's feeds (the same stretch as the totals), the nights row (with no rota, a night nobody took shows an empty dashed circle; the alerts still count this phone as on duty) and the day of the week. New shared parts: `TileRow`, `FlowLayout`, `PillButton`, `PressStyle` and `EmptyAvatar` in `Components.swift`. Choices made on the way: the age chip uses `surface`, not the mockup's pumping green, because green means pumping and nothing else; a chart bar is 16 to 40 points tall by the feed's length (up to 45 minutes), and a feed with breast and bottle shows both colours; the sample day's parents are "Alex" and "Sam", so the avatars differ. 

**Progress (15 Nov 2026, step 5):** Home with a feed running and the details panel are built. The hero takes the feed's tint and colour (`RunningFeed` in `HomeView.swift`, tested in `AppTests/HomeTextTests.swift`), with the side being fed (or the bottle) in the ring, the running clock and "started 10:30" ("by Sam" on the other phone; "Formula · " first for a bottle feed). "This feed" shows a chip per side and bottle, with a live clock on the side being fed. The bottom holds `SideButton`s (Left, Right, Bottle) and "Stop · discard" beside a wider Finish; the other parent's phone has only "Finish for Sam" (its old explaining sentence is gone; the hero says who started the feed). The details panel shows the feed's chips, then its questions as big `ChoiceChip`s with shapes ("Add to this feed", "Which bottle?", "How much formula?"). A bottle with no amount yet now shows its kind on its chip ("Formula"). When a feed starts the ring empties with a 0.3 second animation by day, and stays still at night and with Reduce Motion. For step 9: at the largest text sizes the pinned buttons (and the details panel) can fill most of the screen, and Stop and Finish can differ in height. Next is step 6, History and the edit form.

## Checks

- **Tests (FeedingCore):** the Look resolver at 20:59 and 21:00, across midnight, at 06:59 and 07:00, with a changed rota, after a clock change in both directions, in another time zone, and with each setting. The chart and nights facts at the edges (no feeds, feeds just over 24 hours old, a deleted feed, a night with no rota).
- **App tests:** the age chip, the greeting by time, and that every number view uses the number style.
- **Contrast:** recheck every pair in `DESIGN.md` if a colour changes.
- **Dynamic Type:** every screen at the largest accessibility size, in both looks. Tiles stack; nothing is cut off.
- **VoiceOver:** the ring, the bar, the shapes, the chart and the nights row read as sentences.
- **Reduce Motion:** fades only.
- **Night:** nothing white anywhere, including sheets, pickers, the keyboard and the launch screen.
- **Duo:** 382, 385, 594, 669 and 951 pt (see `~/.claude/reference/iphone-duo.md`).
- **Real phones:** the day look in daylight, the night look in a dark room, and the switch at 21:00.

## Where it fits

This is the next piece of Phase 1, before the remaining Phase 1 screens (duplicate feeds, "Ask the other parent to take a night"), so those are built in the new look from the start. The 24-hour chart on Home is part of this work; the full graphs screen stays in Phase 2. Widgets and the watch app (Phase 2) follow `DESIGN.md` too.
