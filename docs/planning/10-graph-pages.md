# A graph's own page (21 Nov 2026)

## The ask

Parent A, after the "who does what" phone check: "I'd like the graphs to be a little bit more interactive. So when I go into the reports, I then can tap on a graph and get the information behind them … such as timings and other information related to the event."

## Decided

From `graph-taps-20261121/round1.html` in the gstack design folder (made-up data, Day and 3am looks):

- **C: each graph opens its own page.** Chosen over A (the day's list slides up over the Graphs tab) and B (a bubble with the day's totals, then the list). C has the most room, makes changing the day easy (thin bars on 4 weeks are hard to hit), and works like "Who did what".
- **The lists as drawn (A),** with the change since the weight before.

## What it does

- Every graph tile has a ›. A tap on a day's bar, a day's row of the daily rhythm or a weight's dot opens the page on that day (or weight). A tap anywhere else on the tile, or on the ›, opens it on today (the latest weight).
- The page: the same 7 days / 4 weeks / All switch as the tab (the daily rhythm has none: it shows one day's row and can go back to the first day logged), the graph bigger with the picked day at full strength, ‹ › to change the day, the day's totals as chips, then the entries.
- The entries are exactly what the day's bar counts, oldest first, in History's rows, each opening its editor:

| Graph | Totals | Each entry |
|---|---|---|
| Feeds each day | feeds, breast time, bottle ml, shortest to longest gap | the feed, with "To 01:03 · 25m" |
| Bottles each day | ml, formula ml, expressed ml | each feed with a bottle |
| Time between feeds | shortest, middle, longest | each gap, from one feed's start to the next ("Thu 22:21 · to 1:15 · 2h 54m"), "Longest" under the longest |
| Breast each day | left, right, feeds | each feed with the breast |
| Pumped each day | ml, sessions | each session |
| Daily rhythm | asleep, feeds, nappies | the day in time order: sleeps, feeds, nappies |
| Asleep per day | asleep, night, day | each sleep from its real start, with "9m of it on Friday" when it runs over midnight |
| Nappies per day | nappies, wees, poos | each nappy, with the poo's colour and texture |
| Weight | latest weight, how many | every weight, newest first, with "+ 140 g since 12 Nov" |

- Facts only, as on the tab: no "normal", no targets, no red or green. The weight change is a plain difference ("+ 140 g", "− 220 g"), never "gain" or "loss".
- Two columns on the open Duo (594 pt or wider): the graph on the left, the entries on the right.
- VoiceOver: each graph is one button per day ("Tuesday 17 November: 8 feeds"); it does what a tap on that bar does. On the page the picked day is marked selected.

## How

- `FeedingCore/Sources/FeedingCore/Insights/GraphDetails.swift`: `graphDayDetails` (a day's feeds, bottle feeds, breastfeeds, pumping and gaps), `RhythmDay.entries` (a day in time order), `weights` (with the change since the one before), and `feedGaps`, which `graphDays` now uses too, so a bar and its list can't disagree. `RhythmSleep` gained `spanStart` and `spanEnd` (the whole sleep). Nothing here changes what is stored or synced, and `reconcile` is untouched.
- `App/Graphs/GraphCharts.swift`: the charts, shared by the tiles and the pages (`FeedGraphChart`, `RhythmGraphChart`, `ChartDayTap`, `GraphKey`, `GraphAxes`). `App/Graphs/GraphPage.swift`: the page. `WeightChart` is in `RhythmTiles.swift`.
- Feeding Dev screenshots: `-openScreen graphPage -graphPage feeds` (or `bottles`, `gaps`, `breast`, `pumped`, `rhythm`, `asleep`, `nappies`, `weight`), with `-graphPageDay 1` for yesterday.

## Tests

- Core (`GraphDetailsTests`): every day's list against its bars (count, ml, breast time, pumping, gaps), across midnight, both clock changes and a half-hour time zone; the rhythm's order; the weight changes.
- Tap tests (`GraphPageFlowTests`): a tile opens its page on today, ‹ goes back, the list has as many feeds as the total, a bar on the page picks its day, a row opens its editor, and a bar on the tab opens the page on that bar's day.
- The accessibility audit has `testGraphPages`. Its notes on the per-day buttons ("Text clipped", "Contrast failed") come from VoiceOver's invisible buttons lying over the chart, and show on the tab where nothing is faded, too.

## Still to check

- On the real Duo, opened flat: the two columns.
