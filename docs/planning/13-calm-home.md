# A calmer Home (24 Nov 2026)

Parent A found Home "visually quite overwhelming": eight boxes in six colours, buttons in five places, "Last feed" said three times, and summaries that push the useful parts down. People switch off when faced with a busy screen, so Home was redesigned. The mockups are in the gstack design folder, `designs/home-calm-20261124/` (`round1.html` for the phone, `round2-duo.html` and `round3-duo-bold.html` for the open Duo, `approved.json`).

## Decisions

| # | Decision | Choice |
|---|---|---|
| CH1 | Start feed and the small buttons | Start feed (two thirds of the row) asks Now, Just finished or Earlier; Pumping takes the last third. "Just finished" and "Earlier" lose their own buttons. Bottle-only phones list the milks under "Now". |
| CH2 | The phone (and the closed Duo) | Design B, "one calm list": the top tile, then one plain box with a row each for Sleep, Nappy, each medicine and Bath (buttons on the right), then three folded headings, Today, Tonight and Recent, each with a one-line summary, closed at first. |
| CH3 | The top tile | Keeps the time since the last feed and the window bar. Under the bar, a foot: the last feed's chips and "Next ◐ Left". Who did the last feed sits beside "Last feed". The Next side and Last feed tiles go. During a feed the foot shows the feed so far and when the last one started. |
| CH4 | The name | The baby's name and age move up into the top bar, beside Ask and Settings. "Good afternoon" goes. |
| CH5 | Colour | No tinted boxes on Home: colour only on the shapes (pink half-moon, blue bottle, lilac moon, and so on) and the window bar. The top tile turns pink or blue during a feed, as before. |
| CH6 | Folded parts | Today (the 24-hour strip and totals), Tonight (the week of nights) and Recent (the last 24 hours' entries, as History rows) start closed; each phone remembers what is open. Tonight's line and its buttons ("I'll take it", "Ask Sam", "Both phones tonight"), any ask line and any "waiting for the other phone" line always show, never folded. |
| CH7 | The open Duo | The "Book" (round 3, A): the left page is "now" (the top tile, four plain facts with no buttons, Tonight, Start feed and Pumping at the bottom left); the right page is "today", a timeline, with the log buttons along its bottom. Nothing crosses the fold. Closed, in laptop pose or in Split View, Home is the phone page. |
| CH8 | The timeline | Earlier at the top, like a calendar (Parent A, after trying it on the Duo: the mockup had the newest at the top), opening at its end, at now. Sleeps are lilac bars, feeds pink or blue blocks as long as they lasted, each entry beside them as one pill holding its time, details and who did it (Parent A's ask after trying it); the night shaded; the feeding window and backup alarm under "now". The totals line and Tonight stay put above it. A tap opens the entry to change it, as in History. It replaces the Duo's Recent list. |
| CH9 | A poo's Undo card | The card waits until the poo's details panel closes, so its 10 seconds start once the nappy is fully logged, and it names the details ("Poo logged · brown, loose"). Undo in the panel leaves no card. |

## Rules kept

- Every quick log stays one tap (Woke up, Wee, Poo, Both, Given, Bath), with Undo and Change time.
- Facts only: no targets, no verdicts.
- The watch, the widgets, History and Graphs do not change.
- Mornings until 12:00 the "Last night" line shows above the top tile; an ask from the other parent shows at the top until answered.

## Built (24 Nov 2026)

- Phone: `App/Home/HomeView.swift` (the page, the hero's foot, `HomeTitle` in the top bar), `App/Home/CareTiles.swift` (`CareList`, `CareFacts`, `LogDock`), `App/Home/HomeFolds.swift` (`FoldSection`, Tonight, Today, Recent). The Next side, Last feed, This feed, Sleep, Nappy, Medicine, Bath, 24-hour and Nights tiles are gone; `TonightLines` and `DaySummary` hold what the last two said.
- Open Duo: `App/Home/DayColumn.swift` (the right page and `DayTimeline`).
- Two changes from the mockups, found at real sizes:
  - Tonight sits at the top of the Duo's right page, under the totals line, not on the left page: the real top tile is taller than the mockup's, and the left page then fits without scrolling.
  - The timeline stretches where entries crowd (`TimeScale`): with a fixed hour height, labels drifted away from their marks.
- The name in the top bar has no clock of its own: a `TimelineView` inside a toolbar item put SwiftUI into an endless loop (the app showed a blank screen at 100% busy). It is redrawn with the page.
- A poo's Undo card (CH9): `CareLog.nappyFinished`, called when the details panel closes.
- Tap tests: `StartFeedMenuFlowTests` (CH1), `UndoCardFlowTests` (CH9).
- In Little Log build 8 on TestFlight (24 Nov 2026), with History's fix: baths in All and a Baths button.
- Still to check on the phones: the page by day and at 3am, the folded parts opening, and the Book on the real open Duo (book pose and flat).
