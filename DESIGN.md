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
- No red or green verdicts, ever. Green means pumping and nothing else.
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
  - The shape appears on every chip, row, button and chart key for that kind. A chip shows the shape and the number ("◐ 12m", "bottle 30 ml"), so letters such as "L" and "R" are not needed.
- The ring: 11 pt stroke, round caps, `track` behind, `primary` for the time so far (or the breast colour during a feed, with the current side's half-moon in the middle).

## Components

- **Big button** (Start feed, Finish): at least 60 pt tall, full width, `primary`, Fredoka label with an icon. Pressed: scales to 0.97 with a medium haptic. Disabled: 40% opacity.
- **Soft big button** ("Stop · discard"): `surface` background. It always asks "Remove this feed?" before removing anything.
- **Side buttons** (Left, Right, Bottle): 64 pt tall, shape above the label. The current side fills with the breast colour.
- **Tile:** tinted by what it shows (breast tint for Next side, bottle tint for Last feed, plain surface for totals and nights). A small upper-case label, then the value.
- **Chip:** `background` colour on a tile, shape plus number. Never a sentence.
- **Amount wheel** (a bottle's ml, added 16 Nov 2026): the iOS wheel, every 5 ml from 5 to 300 ml, in the `background` colour on the panel, amounts in SF Pro Rounded. Turning it saves nothing: "Save 30 ml" does (the word in Fredoka, the amount in SF Pro Rounded).
- **Window bar:** 12 pt tall. Empty `track`; `primary` fills the time since the last feed; `window` shades the feeding window; a short bar marks now. Under it: "Feeding window 10:25" on the left and a bell with the alarm time on the right.
- **24-hour chart:** one strip (22 pt tall, `track`) across the last 24 hours. Each feed is a block from when it started to when it ended (to now while it runs), at least 3 pt wide, coloured by kind (`*-mark`; bottle above breast for a feed with both), with a key of shapes. Feeds close together sit side by side and touch only if they really overlapped. Under it, three totals: feeds, at the breast, ml from bottles.
- **Nights row:** seven days, each with the on-duty parent's initial in their colour. Tonight has a ring round it. Then "Sam's on tonight" and an "I'll take it" pill.
- **History row:** tinted by kind, time on the left, chips in the middle, the avatar of who logged it on the right.
- Every component has an empty state (for example "No feeds logged yet" with the Start feed button) and a VoiceOver label that reads as a sentence ("Last feed 2 hours 5 minutes ago, at 8:25").

## Day and night

- **Automatic** (the default): the night look runs during the household's night hours (the same hours as the night rota: 21:00 to 07:00 by default) and the day look the rest of the time.
- In Settings, each phone can choose **Automatic**, **Always night**, or **Match iPhone** (follows the phone's own Dark Mode).
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
