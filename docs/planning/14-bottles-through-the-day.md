# Bottles through the day

**Asked by the parents on 26 Nov 2026.** At some times of day the baby seems hungrier than at others, and the 2 to 4 hour window doesn't always fit. The parents want to see how much the baby has had from bottles at any time of day, beside the day before and the last week at the same time, so they can watch the amounts themselves.

## What the app does (decided 26 Nov 2026)

Parent A chose from side-by-side mockups (kept outside the repo in the gstack design folder `designs/bottles-by-time-20261126/`, with `approved.json`):

| # | Question | Choice |
|---|---|---|
| BT1 | How it looks | **A) A line that climbs through the day.** Today's bottles add up from midnight to now. The day before and the average of the 7 days before run beside it to midnight. A finger slid along the line reads any time ("By 09:00: Today 310 ml, Yesterday 300 ml, Average 290 ml"). Not B (bars for each 6 hours) or C (numbers only). |
| BT2 | Where it is | **A) Home and Graphs.** A line inside Home's Today fold ("Bottles since midnight: 520 ml today · 480 ml yesterday by now · 500 ml average by now"), and a tile on the Graphs tab under "Feeds each day". A tap on either opens the page. |
| BT3 | How careful | **A) Short plan, build, check:** this plan, the build with tests, a Codex review of the build, the full suite, then Little Log Dev on the Duo. No separate design and engineering reviews. |
| BT4 | The gap at a glance | **B) A plain difference** (asked after BT1 to BT3: the parents want to tell at once whether the baby has had more or less than at the same time yesterday or over the week). Under the day before and the average, "Difference + 40 ml" (the day's own total minus that one; "− 20 ml"; "0 ml"), in small muted words, and in the bubble ("Yesterday 300 ml (+ 10 ml)"). Like the weight's "+ 140 g since 12 Nov": no colours, no arrows, no "more" or "less" words. Not A (the amounts only). |

## The page

- **‹ Today, by 15:20 ›** at the top. ‹ goes back a day, down to the first day a feed or pump was logged; › comes forward to today.
- **Three numbers.** Today: "Today", "Yesterday by 15:20", "7-day average by 15:20". A past day: "Whole day", "Day before", "7-day average" (whole days). Under the last two, the plain difference (BT4): "Difference + 40 ml", the day's own total minus that number (the average as shown, to the nearest 5 ml, so the shown numbers add up).
- **The line**, with its key under it. Today in bottle blue (thick), to now, with a dot at now and a faint line down at now. The day before is a muted line. The average is muted and dotted. Each line is a step at each bottle.
- **What isn't counted**, in small muted words: "Also 2 breastfeeds today, 35m. A breastfeed has no amount." and "1 bottle had no amount logged."
- **NHS · About bottle feeding ›**: the NHS link of AI insights step 4 (`NHSLinkRow`), with the bottle-feeding passages only (`NHSLinkSubject.bottles`), whatever else the baby has. Only ticked passages, as for every NHS link. The passages say "Your baby will know how much milk they need" and "Do not force them to take more milk than they want… can lead to overfeeding". This is how the page answers "too much": with the NHS's words, never with the app's own.
- **The day's bottles**, oldest first, each as History's row with "520 ml from midnight" under it. A tap opens it to change.
- On the open Duo, the top on the left and the bottles on the right, as on the other graph pages.

## Rules

- **Facts only.** No "too much" or "too little", no limit line, no "normal" band, no red or green, no up or down arrows, no "more" or "less" (the hard rule on verdicts, and `02-plan-v1.md`'s graphs). The numbers sit side by side, with a plain signed difference (BT4); what they mean for the baby is for the parents and the health visitor.
- **Bottles only.** Formula and expressed milk together. A breastfeed has no amount; it is counted beside the total and said.
- **A bottle counts at its feed's start**, as on "Bottles each day". A bottle given during a breastfeed counts at that feed's start.
- **The page lists the same bottle feeds as "Bottles each day"**, a bottle saved with no amount included: its row adds nothing to the running total, and it can be opened to add the amount. Such a bottle alone is enough for Home's line and the tile to show (Codex review, 2).
- **Days run midnight to midnight** in the household's time zone, as on the Graphs tab, wherever the phone is. A bottle after 21:00 is still that day.
- **"By now" is by the same clock time.** On a day the clocks change, 15:20 is 15:20; both 01:30s on the day they go back read 01:30. Today's total is every bottle logged by now, whatever its clock reading. In the hour that happens twice, a bottle from the first time round sits on the line at the earliest later reading, so the bottles stay in the order they happened and today's line never runs past now (Codex review, 1).
- **The average** is of the 7 whole days before the day shown, at the same clock time, to the nearest 5 ml. Days before the first feed or pump logged are left out, so a new log averages fewer days and says so ("3-day average"). With fewer than 2 such days there is no average (it would only repeat the day before).
- Deleted entries, other babies, a feed logged on both phones (counted once) and anything after now (a clock set back) are treated as on the Graphs tab.
- Home's line and the Graphs tile show only when a bottle was logged today or in the 7 days before.
- Nothing new is stored: no schema change, no new setting, nothing sent anywhere. Alerts don't read any of it.

## Built (26 Nov 2026)

- `FeedingCore/Sources/FeedingCore/Insights/BottlesThroughDay.swift`: `bottlesThroughDay(_:babyID:timeZone:date:now:)` gives `BottlesThroughDay` (the day, the day before, up to 7 days before, the cut-off clock time, the breastfeeds and bottles with no amount). Tested in `BottlesThroughDayTests` (midnight, 21:00, both clock changes, a 30-minute time zone, travel, a clock set back, deleted entries, other babies, pumps).
- `App/Graphs/BottlesThroughDay.swift`: the page (`BottlesThroughDayPage`), the line (`BottlesThroughDayChart`), the Graphs tile, Home's line (`BottlesTodayLine`, in `TodayFold`) and the words (`BottlesText`, tested in `BottlesTextTests`, with a check for verdict words).
- Codex reviewed the build (`gpt-6.2-sol`, about 175,000 tokens): six findings and two test weaknesses, all fixed: the hour the clocks go back (above), bottles with no amount (above), VoiceOver reads any hour by swiping up or down on the line, "About bottle feeding" keeps the bottle-feeding passages alone (`NHSLinks.bottleFeedingOnly`), the page reads a fresh time on every redraw, and the dotted average is drawn to the nearest 5 ml like its number; the tests no longer depend on the hour they run or the phone's region.
- Tap test `BottlesThroughDayFlowTests`; the audit's `testBottlesThroughDay`. Screens: `-openScreen bottles` (with `-graphPageDay 1` for yesterday).
- Not on the open Duo's Book: its left page never scrolls (CH11), so the line is only on the phone's Home and on the Graphs tab.
