# TODOS

Work put off on purpose, with why. Each item names where it was decided.

## Milestones journal (deferred in the CEO review, 17 Nov 2026)

- **A one-tap "Moment" button on the Lock Screen, Control Center and the watch** (X3, D10). One tap saves "a moment happened" with the time; the Journal later asks for the words and a photo. Put off to see first how often firsts are added from inside the app, and to keep the Lock Screen and watch uncrowded. Effort M. Reuses the Sleep and nappy widget and the Control Center controls. See `docs/planning/07-milestones-journal.md`.
- **A printable keepsake PDF** (X5, D12). One page per first: the photo, title, date, the baby's age and the note, in the app's look; printed by the parents or any print shop, with no print service in the app. Put off until there are enough firsts to fill a book; the export already keeps every photo and word safe. Effort M.

(Added to the plan in the same review, so not deferred: a notification to the other phone for a new first (X1, D8), the "Firsts" list for the red book (X2, D9), Share (X4, D11), and up to 4 photos and short videos per first (X6, D13).)

## Who does what (deferred in the CEO review, 20 Nov 2026)

- **A weekly look back** (X4, D7). Each Sunday evening a quiet notice opens a short page on the week: feeds, nappies and nights, who did which part, and the longest sleep. Put off because the shared screen already shows a week and the "Last night" card covers each night; add it if the parents find they want a set weekly moment. Effort M. Reuses the shared screen's facts. See `docs/planning/09-who-does-what.md`. (22 Nov 2026: the AI insights' weekly "This week" card on Graphs, D15 of `docs/planning/12-ai-insights-gauntlet.md`, covers the week's feeds, nappies, nights and longest sleep, with no notice and no "who did which part" (D9). Look again after step 2 is built.)

## AI insights (engineering review of step 1, 22 Nov 2026)

- **A "pale or white" poo colour** (R9, D11). Add it to the poo panel's colours on the phone and the watch.
  - **Why:** the NHS asks parents to show pale or chalky poo to a midwife or GP. D3's own example (the NHS's poo page beside a logged pale poo) can't happen without it.
  - **Pros:** a small change; `PooColour` is open, so older builds keep the value and save it back unchanged.
  - **Cons:** one more choice in a panel used at 3am; a new swatch colour in `DESIGN.md`.
  - **Context:** the colour list is `PooColour.known` (`FeedingCore/Sources/FeedingCore/Model/Details.swift`); the poo panel is in `App/Home/CareTiles.swift` and the watch's poo details screen. Start with the colour, its swatch and words, then the tests in `MoreThanFeedsTests`.
  - **Depends on:** nothing. Build it before step 2 (the daily card), so the card can show the NHS poo page beside it. Effort S (human ~3h / CC ~20 min). See `docs/planning/12-ai-insights-gauntlet.md`, R9.
