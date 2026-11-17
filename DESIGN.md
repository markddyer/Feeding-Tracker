---
# gstack: design-md-format=spec
name: Feeding Tracker
description: A nursery by day and a nightlight by night. Warm, round and joyful in daylight; the same screen, dimmed and thinned, at 3am.
colors:
  # Day look
  background: "#FFF4E2"
  surface: "#FFE6C7"
  text: "#3A2A1E"
  text-muted: "#745F4E"
  primary: "#FF8E6E"
  on-primary: "#3A1A0E"
  track: "#FFE0BD"
  window: "#FFC9A8"
  breast: "#F07C8F"
  breast-mark: "#D2465F"
  breast-tint: "#FFDDE3"
  bottle: "#5FA8E8"
  bottle-mark: "#2F7BC4"
  bottle-tint: "#DCEEFF"
  pump: "#4FB58C"
  pump-mark: "#23885F"
  pump-tint: "#D6F2E2"
  # Graphs: a second shade beside a kind's mark, and bars that are no kind
  bottle-soft: "#5FA8E8"
  breast-soft: "#F07C8F"
  chart: "#3A2A1E"
  # The strip behind Home's 24-hour chart (the users' choice, 17 Nov 2026)
  chart-strip: "#FCD5AE"
  # Sleep and nappies (06-more-than-feeds.md, 17 Nov 2026)
  sleep: "#8B8FE0"
  sleep-mark: "#5A5EC4"
  sleep-tint: "#E6E6FA"
  sleep-soft: "#8B8FE0"
  wee: "#F0C23B"
  wee-mark: "#8F6D00"
  poo: "#9C6B3E"
  poo-mark: "#7E5128"
  nappy-tint: "#FFF0C8"
  poo-brown: "#8B5A2B"
  poo-yellow: "#D9A521"
  poo-green: "#6E8B3D"
  parent-1: "#F2B33D"
  on-parent-1: "#3A1A0E"
  parent-1-tint: "#FDEBC4"
  parent-2: "#3FA796"
  on-parent-2: "#3A1A0E"
  parent-2-tint: "#D3EFEA"
  # The four other colours a parent can pick ("Your colour")
  lavender: "#A78BDF"
  on-lavender: "#3A1A0E"
  lavender-tint: "#E9E2F7"
  plum: "#9E4F88"
  on-plum: "#FFF4E2"
  plum-tint: "#E7D3E1"
  caramel: "#C99260"
  on-caramel: "#3A1A0E"
  caramel-tint: "#F2E4D7"
  stone: "#9A948C"
  on-stone: "#3A1A0E"
  stone-tint: "#E6E4E2"
  notice: "#E07A2F"
  # Night look
  background-night: "#0A0807"
  surface-night: "#1C1612"
  text-night: "#E8D6C2"
  text-muted-night: "#978472"
  primary-night: "#B9714F"
  on-primary-night: "#120A06"
  track-night: "#231B15"
  window-night: "#4A3022"
  breast-night: "#A85A68"
  breast-tint-night: "#22151A"
  bottle-night: "#4A7299"
  bottle-tint-night: "#141B24"
  pump-night: "#3D7A60"
  pump-tint-night: "#121D17"
  bottle-soft-night: "#6E93BA"
  breast-soft-night: "#C27F8C"
  chart-night: "#978472"
  chart-strip-night: "#2A2119"
  sleep-night: "#6A6DB0"
  sleep-tint-night: "#15152A"
  sleep-soft-night: "#9497D0"
  wee-night: "#9C832F"
  poo-night: "#9A6E48"
  nappy-tint-night: "#1E190C"
  poo-brown-night: "#7A5434"
  poo-yellow-night: "#9C7E2A"
  poo-green-night: "#5E7A3A"
  parent-1-night: "#9C7A30"
  on-parent-1-night: "#120A06"
  parent-1-tint-night: "#221B0E"
  parent-2-night: "#2A695E"
  on-parent-2-night: "#E8D6C2"
  parent-2-tint-night: "#0F1E1B"
  lavender-night: "#68568A"
  on-lavender-night: "#E8D6C2"
  lavender-tint-night: "#17131E"
  plum-night: "#6F375F"
  on-plum-night: "#E8D6C2"
  plum-tint-night: "#180C15"
  caramel-night: "#79583A"
  on-caramel-night: "#E8D6C2"
  caramel-tint-night: "#1B130D"
  stone-night: "#615D58"
  on-stone-night: "#E8D6C2"
  stone-tint-night: "#151513"
  notice-night: "#A0582A"
typography:
  display:
    fontFamily: Fredoka
    fontWeight: 600
    fontSize: 26pt
    letterSpacing: 0em
  number:
    fontFamily: SF Pro Rounded
    fontWeight: 700
    fontSize: 38pt
    letterSpacing: -0.02em
    fontFeature: tnum
  body:
    fontFamily: SF Pro Rounded
    fontSize: 17pt
    lineHeight: 1.35
  label:
    fontFamily: SF Pro Rounded
    fontWeight: 800
    fontSize: 11pt
    letterSpacing: 0.07em
rounded:
  sm: 9px
  md: 14px
  lg: 20px
  xl: 26px
  full: 9999px
spacing:
  xs: 4px
  sm: 8px
  md: 12px
  lg: 16px
  xl: 24px
  2xl: 32px
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.lg}"
  button-soft:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text}"
    rounded: "{rounded.lg}"
  button-small:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text}"
    rounded: "{rounded.md}"
  tile:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.lg}"
  hero-tile:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.xl}"
  chip:
    backgroundColor: "{colors.background}"
    textColor: "{colors.text}"
    rounded: "{rounded.sm}"
  pill:
    backgroundColor: "{colors.background}"
    textColor: "{colors.text}"
    rounded: "{rounded.full}"
---

# Feeding Tracker

## Overview

**Creative North Star:** a nursery by day, a nightlight by night. The day look is warm, round and a little playful, because this is a joyful time. The night look is the same screen with the light turned down, because it is used at 3am beside a sleeping baby and partner.

**Product context:** a personal iPhone app (and later Apple Watch) for two parents to log a newborn's feeds, kept in step through iCloud, with alarms if no feed is logged. Peers looked at: LilSense, Wee Hours, Mango Baby, littlefeed, Huckleberry. Most baby trackers are either cute and bright (dazzling at 3am) or dark and plain (joyless); this app is both, by time of day.

**Mode per surface:** every screen is an Operate surface: quick taps, facts read at a glance. There is no marketing surface.

**Reference sites:** https://reeoo.com/app-screenshot/lilsense-3am-baby-tracker/, https://apps.apple.com/us/app/id6772457183, https://apps.apple.com/app/id1512238725, https://apps.apple.com/app/id1384785720, https://huckleberrycare.com

**Key characteristics:**
- The time since the last feed started is the biggest thing on the home screen, inside a ring.
- Every fact sits in its own tinted tile, with space between tiles. No sentences where a picture will do.
- Each kind of feed has a colour and a shape, so it reads at night and without colour.
- One big button at the bottom (Start feed, or Finish), reachable by thumb.
- At night nothing is bright, and the letters get thinner.

The approved mockup (day and 3am) is `chosen-look.html`, kept outside the repo in this project's gstack design folder (`designs/design-system-20261115/`). Open it in Safari to see SF Pro Rounded.

## Colors

**Strategy:** full palette, used with care. Warm neutrals carry the screen. One coral main button. Three kind colours (breast, bottle, pumping) and two parent colours carry meaning; they never decorate.

**Light or dark:** set by the use scene, not taste. By day the parents are awake, often in daylight, and the app should feel happy: the light look. At night the room is dark and someone is asleep: the night look. The app switches by itself (see "Day and night" below).

**Rules:**
- Kind colours: pink is breast, blue is bottle, green is pumping. Each has three tokens. `*-tint` fills a tile or row. The plain token (`breast`, `bottle`, `pump`) fills a big area such as the selected side button. `*-mark` draws small shapes, chart bars and lines, because it is deep enough to read on the light tiles (3:1 or better). At night the plain night token does both jobs.
- Parent colours: each parent picks a colour in Settings ("Your colour") from six: `parent-1` (sunflower) and `parent-2` (teal), the defaults, then `lavender`, `plum`, `caramel` and `stone`. They are stored by name in the Member record ("sunflower", "teal", "lavender", "plum", "caramel", "stone"). They mark who logged a feed and who is on each night. Use `on-*` for the initial on an avatar. None is red or green, a feed colour or the coral button.
- The window: `track` is the empty bar and ring; `primary` fills the time so far; `window` shades the feeding window.
- `notice` is only for problems with the app (sync failed). It is a muted orange, never red, and never says anything about the baby.
- Sleep and nappies (17 Nov 2026) use the same three jobs: periwinkle is sleep (`sleep`, `sleep-mark`, `sleep-tint`); yellow is wee (`wee`, `wee-mark`) and brown is poo (`poo`, `poo-mark`), both on one `nappy-tint`. Medicine and growth have no colour of their own: their shapes use `text-muted`.
- No red or green verdicts, ever. Green means pumping and nothing else. The one exception is a poo's colour: `poo-brown`, `poo-yellow` and `poo-green` show the colour a parent picked, as a small swatch, always beside its word ("Green"). They are facts, never a verdict, and never colour anything else.
- Night colours are dimmed copies of the day colours, not new hues, so the screen feels the same.
- Contrast, checked 15 Nov 2026: text on background 12.6:1 (day) and 14.1:1 (night); muted text 4.8:1 or better on every background and tile; coral button text 7.0:1 (day) and 5.2:1 (night); kind marks 3.5:1 or better against every tile. The initial on every parent colour is 4.5:1 or better in both looks. Check again after any colour change.

## Typography

Two typefaces, each with one job:

- **Fredoka** (Google Fonts, SIL Open Font License; bundled as a font file, which is not an SDK) for headings, the baby's name, tile values such as "Left", and button labels. Round and chubby: this is where the joy lives.
- **SF Pro Rounded** (Apple's own, `.fontDesign(.rounded)`) for everything else, and for **every time, duration, amount and count**, always with `.monospacedDigit()`. Fredoka's digits are not all the same width ("11:11" is 70 px wide and "00:00" is 100 px at 40 px), so a ticking timer in Fredoka would wobble. Never set a number in Fredoka.

Sizes (all scale with Dynamic Type, using `relativeTo:`):

| Use | Face | Size and weight (day) | Night weight | Dynamic Type style |
|---|---|---|---|---|
| Main time ("2h 05m", "12:04") | SF Pro Rounded | 38 pt bold | medium | `.largeTitle` |
| Screen title, baby's name | Fredoka | 26 pt semibold | regular | `.title` |
| Big button label | Fredoka | 20 pt semibold | regular | `.title3` |
| Tile value ("Left") | Fredoka | 19 pt semibold | regular | `.title3` |
| Day heading in History | Fredoka | 18 pt semibold | regular | `.headline` |
| Totals ("8", "240") | SF Pro Rounded | 22 pt bold | medium | `.title2` |
| Body, bar labels | SF Pro Rounded | 15-17 pt regular | regular | `.body`, `.subheadline` |
| Chips ("12m", "30 ml") | SF Pro Rounded | 12.5 pt heavy | semibold | `.caption` |
| Tile labels ("NEXT SIDE") | SF Pro Rounded | 11 pt heavy, upper case, +0.07 em | semibold | `.caption2` |

At night every weight drops one or two steps (see the table), so fewer pixels light up in a dark room.

## Layout

- One column on the phone and on the folded Duo (382 and 385 pt). A 16 pt gutter. Tiles are 10-12 pt apart.
- **Three tabs** (the user's choice, 16 Nov 2026): Home, History and Graphs, in the system tab bar (on the folded Duo, iOS puts it in the bar down the right-hand side). The chosen tab is in `text`, not coral. Settings is the gear at the top of Home.
- Home, top to bottom: greeting and name, the hero tile (ring and main time), the window bar, two tiles side by side (Next side; Last feed), the 24-hour tile (chart and three totals), the Nights tile (the week's rota and "I'll take it"). Start feed and the three small buttons are pinned to the bottom; the rest scrolls behind them.
- During a feed the bottom holds Left / Right / Bottle (three equal buttons) and, below them, "Stop · discard" (150 pt wide) beside a wider Finish.
- Unfolded Duo (594 pt and wider): the left column is the operating column (hero, window, next side, last feed and the buttons); the right column holds the 24-hour tile, the Nights tile and the recent feeds. The big buttons stay at the bottom of the left column, away from the fold.
- Leading alignment everywhere. Nothing is centred except labels inside buttons.

## Elevation & Depth

Flat. No shadows, glows, gradients or blur. Depth comes from tint: background, then tile, then chip (which uses the background colour again, so it reads as a hole in the tile). Never a tile inside a tile.

## Shapes

- Radii: chips 9 pt; small buttons 14 pt; tiles and big buttons 20 pt; the hero tile 26 pt; pills and avatars fully round. An inner corner is the outer corner minus the gap.
- **A shape for each kind of feed:**
  - Breast: a half-moon (`circle.lefthalf.filled` / `circle.righthalf.filled`). The filled half is the side.
  - Bottle: a tall baby bottle, drawn as a SwiftUI `Shape`.
  - Pumping: two drops, drawn as a SwiftUI `Shape`.
  - Sleep: a crescent moon. Wee: one drop. Poo: a soft swirl. Both: the drop and the swirl side by side. Medicine: a spoon. Growth: a line going up. On the Lock Screen's Sleep and nappy widget, Fell asleep is a closed eye and Woke up an open eye (the users' ask, 17 Nov 2026: the words didn't fit). All are SwiftUI `Shape`s in `Shared/FeedShapes.swift`.
  - The shape appears on every chip, row, button and chart key for that kind. A chip shows the shape and the number ("◐ 12m", "bottle 30 ml"), so letters such as "L" and "R" are not needed.
- The ring: 11 pt stroke, round caps, `track` behind, `primary` for the time so far (or the breast colour during a feed, with the current side's half-moon in the middle).

## Components

- **Big button** (Start feed, Finish): at least 60 pt tall, full width, `primary`, Fredoka label with an icon. Pressed: scales to 0.97 with a medium haptic. Disabled: 40% opacity.
- **Soft big button** ("Stop · discard"): `surface` background. It always asks "Remove this feed?" before removing anything.
- **Side buttons** (Left, Right, Bottle): 64 pt tall, shape above the label. The current side fills with the breast colour.
- **Tile:** tinted by what it shows (breast tint for Next side, bottle tint for Last feed, plain surface for totals and nights). A small upper-case label, then the value.
- **Chip:** `background` colour on a tile, shape plus number. Never a sentence.
- **Outside the app** (added 16 Nov 2026): the Lock Screen widget and the control are drawn by iOS in one tint, so they have no colours of their own, except the control's `primary` tint when on. SF Pro Rounded with fixed-width digits, the same "1h 40m" as Home ("1:40" in the small circle), the same facts-only words, and the SF Symbols `waterbottle` (no feed running) and `stopwatch` (a feed running). The wide Lock Screen widget puts the time on its own first line ("1 hour, 40 minutes", or "12 minutes" while a feed runs) and the words under it ("Last feed · window 05:00", or "Feed running, from 04:28"), then its buttons: "Last feed 1h 40m ago" on one line was cut off on the iPhone Duo, and iOS sets the widget's width. Its time is iOS's own self-updating format, so it reads "1 hour, 40 minutes" rather than Home's "1h 40m": with a prepared moment for every minute, the widget's saved file grew too big on the Duo and iOS showed a grey stand-in (the user's choices, 16 Nov 2026). A Control Center button set to one milk shows a letter instead, because a small button shows only its icon: `f.circle.fill` for Formula and `e.circle.fill` for Expressed milk (the user's choice, 16 Nov 2026).
- **Apple Watch** (added 16 Nov 2026, the user's choices from side-by-side mockups):
  - **A black background by day as well as at night.** This departs from the phone's cream day background on purpose: Apple's advice for watches, so the screen's edge disappears into the watch and nothing is bright when a wrist is lifted. By day the watch uses `#2A1F18` for buttons and tiles, `#FFF4E2` for text, `#BFA995` for muted text, `#3A2C22` for the empty bar and `#7A4A35` for the window, with the phone's day coral and feed colours. At night it uses the phone's night colours on black, and every weight drops as on the phone. Contrast, checked 16 Nov 2026: text on black 19.3:1 (day) and 14.8:1 (night); muted text on a button 7.1:1 and 5.0:1; coral button text 7.0:1 and 5.2:1; the selected side's label 6.0:1 and 3.4:1 (the phone's night side button, large text).
  - **One screen, no title** (on a 41 or 42 mm watch a title takes a row of its own). Big number, not a ring: a "LAST FEED" label, the time in SF Rounded at 38 pt, the window bar (8 pt tall) with "Window 05:00" and the bell, then one big coral button, 50 pt tall with a 20 pt radius, Fredoka label. During a feed: the time running, Left and Right (46 pt, the half-moon above the word, the side being fed in the breast colour), Finish, and "Stop · discard" lower down. The other parent's feed shows a dot in their colour and a soft "Finish for Sam".
  - **The amount on the Digital Crown** after Finish: the number at 40 pt in a coral outline, 5 to 300 ml in 5 ml steps, a soft Done and a coral Save. The box takes the crown as soon as the screen opens. Under it, soft − and + buttons (34 pt tall, the symbol in coral) change it by 5 ml a tap, for a finger (the user's choice, 16 Nov 2026: on the real watch the box answered nothing to a finger).
  - **Double tap** presses the main coral button (Start feed, Finish, Save), never "Finish for Sam".
  - **The watch face** draws the pieces in its own colours: the Lock Screen widget's words, a ring with "1:40", and Start feed, a bottle with "Start" under it. A tap on Start feed opens "Formula or expressed?" on a bottle-only watch: the same label and two coral buttons, "Feed from 05:12" above them, and a soft "Not now" lower down. While this parent's feed runs, Start feed becomes a stopwatch with the feed's timer ("12:34", kept running by the watch), and a tap finishes the feed and opens the amount; during the other parent's feed it shows their timer and a tap only opens the app on "Finish for Sam" (the user's choices, 16 Nov 2026).
- **Amount wheel** (a bottle's ml, added 16 Nov 2026): the iOS wheel, every 5 ml from 5 to 300 ml, in the `background` colour on the panel, amounts in SF Pro Rounded. Turning it saves nothing: "Save 30 ml" does (the word in Fredoka, the amount in SF Pro Rounded).
- **Window bar:** 12 pt tall. Empty `track`; `primary` fills the time since the last feed; `window` shades the feeding window; a short bar marks now. Under it: "Feeding window 10:25" on the left and a bell with the alarm time on the right.
- **24-hour chart:** one strip (22 pt tall, `chart-strip`, with no line round it) across the last 24 hours. Each feed is a block from when it started to when it ended (to now while it runs), at least 3 pt wide, coloured by kind (`*-mark`; bottle above breast for a feed with both), with a key of shapes. Feeds close together sit side by side and touch only if they really overlapped. Under it, three totals: feeds, at the breast, ml from bottles.
- **Nights row:** seven days, each with the on-duty parent's initial in their colour. Tonight has a ring round it. Then "Sam's on tonight" and an "I'll take it" pill.
- **History row:** tinted by kind, time on the left, chips in the middle, the avatar of who logged it on the right.
- **Graphs tab** (the user's choices from side-by-side mockups, 16 Nov 2026): one long page under a big "Graphs" title and a 7 days / 4 weeks / All switch, one tile per graph, each 140 pt tall, left out when it has nothing to show. Feeds each day: bars in `chart`. Bottles each day: one bar per day, formula in `bottle-mark` at the bottom and expressed milk in `bottle-soft` above, with the day's total over it. Time between feeds: a soft bar (`chart` at 30%) from the day's shortest gap to its longest, with a `chart` dot for the middle gap. Breast each day: two bars per day, left in `breast-mark` and right in `breast-soft`, keyed with the half-moons. Pumped each day: bars in `pump-mark`. Today's bar is at 45% (the day isn't over). For a week the numbers sit on the bars and every day is named ("Tue" … "Today"); for longer, the amounts go up the right side and about five days are named ("26 Oct"). A key, when needed, has its own line under the tile's label. The chart's words stop growing at the xLarge text size, so seven day names still fit; VoiceOver reads each day and its numbers. By day `bottle-soft` and `breast-soft` are the plain kind colours (about 2:1 on the tile; they always sit on or beside the 3:1 mark, with a key); at night they are lighter than the mark (3:1 or better on the tile).
- Every component has an empty state (for example "No feeds logged yet" with the Start feed button) and a VoiceOver label that reads as a sentence ("Last feed 2 hours 5 minutes ago, at 8:25").

## Day and night

- **Automatic** (the default): the night look runs during the household's night hours (the same hours as the night rota: 21:00 to 07:00 by default) and the day look the rest of the time.
- In Settings, each phone can choose **Automatic**, **Always day** (added 16 Nov 2026, the user's choice), **Always night**, or **Match iPhone** (follows the phone's own Dark Mode).
- The app sets `.preferredColorScheme` to match the look, so sheets, pickers and the keyboard follow it and nothing flashes white at night.
- The change is a 0.3 second cross-fade, never a flash.

## Do's and Don'ts

- Do: put every time, duration and amount in SF Pro Rounded with fixed-width digits.
- Do: give each kind of feed its shape as well as its colour, everywhere it appears.
- Do: show facts as pictures first (ring, bar, chart, shapes, avatars) and keep words to labels.
- Do: check contrast and Dynamic Type (up to the largest accessibility size) on every screen, in both looks.
- Do: keep the night look dim: no white, no bright fills, thinner letters, fades only.
- Don't: use "due", "missed", "overdue" or "should", or show targets, scores or red/green verdicts.
- Don't: add a third typeface, or set a number in Fredoka.
- Don't: use shadows, glows, gradients or a tile inside a tile.
- Don't: use a photo or real name of the family anywhere in the code or pictures; the code is public.
- Don't: show who fed more as a score; the parent colours show who, never a comparison.

## Motion

- **Approach:** gentle by day, still at night.
- **Easing:** enter ease-out, exit ease-out, move ease-in-out.
- **Duration:** micro 80 ms (button press), short 200 ms (chips appearing), medium 300 ms (ring and bar changes, the day/night cross-fade).
- **Night:** fades only, no movement, haptics in place of animation. Respect Reduce Motion at all times.
- **The one authored moment:** when a feed is logged, the ring empties and starts again from zero with a soft haptic. At night, the haptic only.

## App icon
- **The baby's head on coral**, chosen on 17 Nov 2026 "for now": the sleeping baby's face from the icon rounds, with its curl, on `primary` coral that is a little lighter at the top. Picture N on colour G in round six (`app-icon-20261116/feeding-icon-choices.html` in the gstack design folder).
- It is softly shaded (a light glow, a soft shadow under the head), unlike the flat screens. That is on purpose: the screens stay flat. The face's colours are the picture's own, not the tokens above, so don't "fix" them to match.
- The picture: `tools/app-icon.svg`. Files: `App/Assets.xcassets` (phone) and `Watch/App/Assets.xcassets` (watch). Each has `AppIcon` (Feeding) and `AppIcon-Dev` (Feeding Dev: the same picture with a `text`-brown band along the bottom and "DEV" in Fredoka, in cream).
- Made with `swift tools/make-app-icons.swift tools/app-icon.svg`. Quick Look draws the SVG at 1024 × 1024; the script writes all four icons with no transparency. It also takes a PNG, and fills dark rounded-off corners with the colour next to them (iOS and watchOS round the corners themselves). The watch's copy is full size, as the head sits well inside the watch's circle. To change the icon, edit the SVG (or give a new picture) and run it again.
- No dark or tinted version is supplied yet.

## Decisions Log
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-11-15 | Initial design system created | Created by /design-consultation from four code mockups, research on five baby apps, and independent proposals from Codex and a Claude subagent. The user chose look A ("Joyful by day, gentle by night") with look C's 24-hour chart and look D's row of nights. |
| 2026-11-15 | Day and night looks replace "always dark" | The always-dark rule came from a reviewer suggestion (F10 in the review gauntlet), not the user. The user wants the app to feel joyful; the night look keeps the 3am safety. |
| 2026-11-15 | Fredoka for headings and buttons; SF Pro Rounded for everything else and every number | The user asked for few fonts and for every time to look the same. Fredoka's digits are not fixed-width. |
| 2026-11-15 | Keep both the ring and the window bar | The user's choice. Both outside designers suggested a single timeline instead, because a filling ring can feel like a countdown. Revisit if it reads as a deadline. |
| 2026-11-15 | A shape for each kind of feed; thinner letters at night; "Stop · discard" | Ideas from the outside designers, chosen by the user. |
| 2026-11-15 | Deeper "mark" shades for shapes and chart bars; darker muted text | Contrast fixes found while writing this file: the first pastel shades were under 3:1 for shapes and 4.5:1 for small text. |
| 2026-11-15 | Four more parent colours: lavender, plum, caramel and stone | The user picked them from eight on a day/3am page (`parent-colours-20261115/colour-choices.html` in the gstack design folder). Purples, a brown and a grey, because every other hue is a feed colour, the coral button, or red or green. Night values are dimmed copies, tuned so the initial reads at 4.5:1. |
| 2026-11-15 | The 24-hour chart shows each feed as a block as long as it lasted, on one strip | The 8 pt bars ran into each other when feeds came close together. The user chose this (option C) from four on a day/3am page (`chart-overlap-20261115/chart-options.html` in the gstack design folder): true to the clock, so gaps show as gaps. The blocks are 3.4:1 or better on the strip. |
| 2026-11-15 | Night teal darkened from #2C6E63 to #2A695E | Found by the colour test in build step 9: the initial on teal read at 4.2:1 at night, under 4.5:1. The user chose a slightly darker teal over keeping it. |
| 2026-11-15 | The age chip uses `surface`; top-bar buttons use `text` | Found while building: the mockup's green age chip broke "green means pumping", and coral text on the cream background was hard to read. Coral stays for switches and the main button. |
| 2026-11-16 | Three tabs, and the Graphs tab | The user asked for the graphs one tap from the main screen, as a tab, and chose Home, History and Graphs; then layout A (one long page), the time between feeds as shortest-to-longest bars with the middle gap (B), two blues for formula and expressed milk (A), and left and right bars side by side (A), from `graphs-20261116/graph-options.html` in the gstack design folder. New tokens `bottle-soft`, `breast-soft` and `chart`. |
| 2026-11-17 | The app icon is the user's own picture, for now | The user supplied it after six rounds of icon ideas (`app-icon-20261116/feeding-icon-choices.html` in the gstack design folder). It shows more than feeding (sleep, growth), as the user wants the app to grow with the family. Feeding Dev adds a "DEV" band so the two apps are easy to tell apart. |
| 2026-11-17 | The app icon is the baby's head on coral, for now | The user found that their own picture did not work as an icon once it was on the phone and watch. The user chose the head on its own on coral (N on G from round six) in its place. It is now an SVG in the repo, so it can be changed and made again. |
| 2026-11-17 | The 24-hour chart's strip: a deeper peach, with no edge | The `track` strip was hard to tell from its card. Plain white by day was tried first, at Parent B's request (commit `89f444f`), but once both parents saw it on their phones they didn't like it. They then chose D (deeper, with a thin edge) from four on a day/3am page (`chart-strip-20261117/strip-options.html` in the gstack design folder), and after seeing it on the phones (commit `c20849b`) asked for the edge to go: option B on that page. New token `chart-strip`, as deep as the strip can go with the blocks still 3:1 or better. Don't add white or an edge again without asking. |
| 2026-11-17 | Colours and shapes for sleep and nappies | Accepted by the users with round two of `more-than-feeds-20261117/round2.html` (gstack design folder). Two changes from the mockup, for contrast: `wee-mark` is #8F6D00 (the mockup's #A77F00 was 2.7:1 on the 24-hour strip), and night sleep is #6A6DB0 (#575A9A was 2.5:1). The poo colour swatches are the one place green appears outside pumping, always with their word. |
