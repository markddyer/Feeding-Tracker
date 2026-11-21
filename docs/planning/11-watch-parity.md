# 11 · The watch does what the phone does

Status: decided 21 Nov 2026 (the parents' choices below); reviewed by Codex the same night (below); the alarm fix it led to is built (`c4f74e1`); **step 1 is built** (the three no-scroll pages, Bath, Medicine, poo details, Pumping, the Logged card with Undo, Earlier and Done by, the phone's answers, capabilities, the new taps' own message and queue); steps 2 and 3 are next.
Mockups (outside the repo, in this project's gstack design folder):
`designs/watch-parity-20261121/` (round1 to round5; approved: `round5-square.html`), and
`designs/watch-bar-20261121/built.html` (the new watch bar, built in `8fb7a19`).

## Why

Parent A asked that "on the watch, [we can] answer every question that can be answered on the
phone regarding feeding, bath time, nappies, etc.", and that every main watch screen fit on the
screen with no scrolling and no unused space.

Today the watch sends eight taps (`WatchCommand`): start, switch side, finish, set a bottle's
amount, discard, fell asleep, woke up, and a nappy (wee, poo or both). The phone can do more.

## Decisions (21 Nov 2026)

| # | Question | Choice |
|---|---|---|
| W-D1 | Feeds on the watch | All four: a bottle during a breastfeed, and after Finish any untapped side or bottle; "Just finished" (about 10, 20, 30 or 45 minutes ago); Pumping (side and amounts on the Digital Crown); "Earlier" feed (start time on the Digital Crown) |
| W-D2 | Sleep, nappy, medicine, bath | All four: Bath; Medicine "Given" for each medicine on the list (the list stays on the phone); the poo's colour and consistency after Poo or Both; late sleep taps |
| W-D3 | After a tap | All four: Undo; Change time (5, 10, 20 or 30 minutes earlier); who did it, and who got up for a wake-up; the night rota ("I'll take it", ask the other parent, answer an ask) |
| W-D4 | Phone only | Growth, firsts with photos, editing older entries in History, settings |
| W-D5 | Where things live | Three pages: Feeds; Sleep and nappy; Bath, medicine and tonight |
| W-D6 | "Logged" after a tap | A full screen for 6 seconds: what and when, Undo and Earlier as big buttons, "Done by you ›" (or "Who got up ›" after Woke up), and the circle closes it |
| W-D7 | Fit | Every main screen fits with no scrolling on 42 mm (187 × 223 pt) and 49 mm (211 × 257 pt), with no unused space; buttons about square (a row of three about 1 : 0.88), spare room spread evenly between the rows, never stretching the buttons |
| W-D8 | Page 1 | The big time with a round main button beside it: Start (Finish while this parent's feed runs). Under it the bar's line and the bar; on 45 mm and up, the bar's two times; then Just finished, Earlier and Pumping (Left, Right and Bottle during a feed), with Stop · discard under them. During the other parent's feed: their side now in an outlined box, "Finish for Sam" normal-sized and soft |
| W-D9 | Page 2 | The sleep time with an oblong button beside it, full words: "Fell asleep" (moon) or "Woke up" (sun); a long time shrinks to fit. Then Wee, Poo and Both, then the last nappy. A late sleep tap: tap, then "Earlier" on the Logged screen |

The small label ("LAST FEED", "AWAKE", "TODAY") sits in the top bar beside the clock, which is
empty today. "ago, at 18:36" sits beside or under the big number. The double tap presses the
page's main button (Start, Finish, Fell asleep or Woke up). A bottle-only watch's Start asks
"Formula or expressed?" (and "Breastfeed (Sam)" when named); its double tap starts the milk used
last, as today.

## Screens

Page 1, Feeds (`IdleScreen`, `RunningScreen`, `OthersFeedScreen`): as above (W-D8).
Page 2, Sleep and nappy (`CareScreen`): as above (W-D9).
Page 3, Bath, medicine and tonight (new): one row each, filling the screen: Bath ("Last
yesterday", Bath); each medicine (name, "Last 09:10", Given), up to two, then "+1 more" opening a
list; Tonight ("Sam's on tonight" and "I'll take it"; "Nobody's on" with "I'll take tonight" and
"Ask Sam"; an ask from the other parent: "Sam asks you to take tonight" with "I'll take it" and
"Not tonight"; the asker's own "Asked Sam").
Opened by a tap: Logged (W-D6); Earlier (5, 10, 20, 30 minutes earlier); Who did it (the two
parents, and "Other" members if any); Who got up (after Woke up); After Finish, "Add to this
feed" (the sides not logged, Formula and Expressed not logged, then each bottle's amount, as the
phone's `DetailChoices`); Just finished (2 × 2: 10, 20, 30, 45 min ago); Earlier feed (start on the
Digital Crown in 5-minute steps, back to 12 hours; then "Add to this feed"); Pumping (Left, Right
or Both, then each side's amount on the Digital Crown); Poo colour (Brown, Yellow, Green, Other,
Skip), then consistency (Liquid, Loose, Firm, Skip).

## The protocol

The phone stays the only writer: each watch tap is a `WatchRequest` the phone applies with
`applyWatch`, exactly as the same tap in the app (so alarms, the other phone and the widgets
follow, and the same safety rules hold). New `WatchCommand` cases, each carrying IDs the watch
picks so a request that arrives twice changes nothing the second time:

- `addBottle(feedID, bottleID, milk)`: during a feed, or after it finished (After Finish).
- `addSide(feedID, side)`: after Finish (a side with no duration), as the phone's panel.
- `justFinished(feedID, minutesAgo)`: a finished feed from `at − minutesAgo` to `at`.
- `earlierFeed(feedID, start)`: a finished feed from `start` to `min(start + 20 min, at)` (the
  phone's Earlier default), refused for a start in the future.
- `pump(pumpID, side, leftML, rightML)`: from `at − 20 min` to `at` (the phone's default length).
- `bath(bathID)`, `medicine(medicineID, name)`: as the phone's tiles.
- `pooDetails(nappyID, colour, consistency)`: either may be nil; sets only what is given.
- `changeTime(ids, field, to)`: start or end, moved earlier only (the watch offers 5 to 30 minutes
  earlier), clamped as `CareLog.apply` does (an end never before its start).
- `setDoneBy(id, member)`, `setGotUp(sleepID, member, ending)`: the phone's `setDoneBy` and
  `setGotUp` (the ending the watch showed, so a later ending ignores it).
- `undo(requestID)`: undoes the change that request made (see below).
- `claimNight(night)`, `askNight(night)`, `declineAsk(night)`, `withdrawAsk(night)`: the phone's
  rota calls, with the night the watch showed.

`fellAsleep` and `wokeUp` stay as they are; the late tap is `changeTime` after them.

`WatchState` (version 3) adds, all optional so an older watch or phone still reads it:
`medicines: [WatchMedicine(name, lastGiven)]`, `lastBath: Date?`, `members: [WatchMember(id, name,
colour)]` (for "who did it"), `tonight: WatchTonight` (the night, who is on, the ask's status for
this parent, the other parent), and on `WatchFeed` the sides logged so far (for After Finish).
`DetailChoices` moves to `FeedingCore` so the phone's panel and the watch ask the same questions.

### Undo

The phone keeps, for each watch request it applied in the last 10 minutes, what Undo needs, in
memory in `WatchRelay`: a new entry's ID (undone as the phone's Undo does: gone if not yet sent,
otherwise deleted, and a sleep that a feed's start ended runs again, `discardFeed`); a Woke up's
ended sleeps (reopened); a Finish (the end cleared); and for a change to an entry, the fields it
changed and their values before (`EventSnapshot.changedFields`, as the phone's Undo since the
Codex review of 21 Nov 2026), so a change from the other phone in the meantime stays. An Undo
the phone can no longer match (restarted, or older than 10 minutes) changes nothing, and the
phone's next state shows the entry as it is.

### Alarms

Every new command does what the same tap on the phone does, so the plan's rules hold. Checked
against "when unsure, alert too much rather than too little": Change time only moves earlier, so
an alarm can only come sooner; Undo of a new feed makes the last feed older (sooner); Undo of a
Finish makes the feed run again (as the phone's Undo); Just finished and Earlier feed log a past
feed, as the phone's buttons do; a claim or an ask goes through the rota's acknowledgement, as on
the phone. A request kept while the phone was out of reach keeps today's guards (a start from
before a feed logged since is refused) and gets the same for Just finished and Earlier feed: one
whose end is before a feed logged since is still logged (it is history), but never moves the
window later than the phone's own latest feed already does.

### Mixed versions

The watch app ships inside the phone app, but the watch can lag behind (installs to the watch
are slow). A newer watch's new commands don't decode on an older phone: the phone ignores them,
and the watch keeps them as waiting (its "waiting for the phone" line), dropped after a day as
today. An older watch on a newer phone sends only the old commands. `WatchState` 3 decodes on an
older watch (unknown keys are skipped), and 2 on a newer one (the new fields are nil and page 3
shows "Open Little Log on your iPhone to update").

## Layout without scrolling

Each page is one fixed screen: a `VStack` with `Spacer(minLength:)` between rows so spare height
is spread evenly, buttons sized by width (`aspectRatio`), and the big number with
`minimumScaleFactor`. Two size steps: small (41 and 42 mm) and large (44 mm and up), from the
screen's width. At the largest text sizes a page falls back to scrolling (`ViewThatFits` with a
`ScrollView`), as Apple asks: text may grow, never be cut off. The label beside the clock is a
toolbar item (`topBarLeading`); check how watchOS 27 places it before relying on it.

## Build order

- W1 · FeedingCore: the new commands, `applyWatch` for each, `applying` for each (the watch shows
  the tap at once), `WatchState` 3, `DetailChoices` moved; tests for every command, both arrival
  orders, a request twice, and old/new decoding. `swift test --package-path FeedingCore`.
- W2 · Phone: `WatchRelay` builds the new state fields and keeps the Undo records; app tests.
- W3 · Watch layout: the three pages with no scrolling (page 1 round Start, page 2 oblong sleep
  button, page 3), on 42 and 49 mm; `-sampleWatch` states for each.
- W4 · Watch feeds: Bottle during a feed, After Finish, Just finished, Earlier feed, Pumping.
- W5 · Watch care: Bath, Medicine, poo details.
- W6 · Logged: Undo, Earlier, Done by and Who got up.
- W7 · Tonight on page 3.
- W8 · Checks and docs: watch simulator screenshots of every screen on 42 and 49 mm, day and
  night, large text; the phone-and-watch simulator pair for a tap of each kind; DESIGN.md's watch
  section; CLAUDE.md's flags; then the Ultra 4 and the phone (Feeding Dev), and Little Log build 3.

## Not in this plan

Growth, firsts, History edits and settings on the watch (W-D4). The watch talking to iCloud
itself (the watch still talks only to its own iPhone).

## Outside review (Codex, gpt-6.2-sol, 21 Nov 2026) and what changed

17 findings (1 critical, 11 high, 5 medium; about 148,000 tokens). The parents' answers:

- **Alarms moved into the past (critical, also true of the phone's editor today).** `reconcile`
  keeps only alerts still to come, so moving the latest feed's start earlier (or deleting it, or a
  shorter window) dropped an alert whose new time had passed before it rang. **Fixed first (A):**
  `passedAlerts` lists them, and `catchUpAlerts` (in `planAlertChanges(passed:)`) sets off at once
  the strongest one per baby (backup, else follow-up, else the close) whose alarm or notification
  this phone still had set for later, in the parent's style, never put off by a later run, once,
  and never in another alarm's minute. The window-opens nudge is never caught up.
  `CatchUpTests` in FeedingCore.
- **Build in three steps, safest first (A).** Step 1: the no-scroll pages, Bath, Medicine, poo
  details and Pumping, and the Logged card for these. Step 2: the feed extras. Step 3: Undo of
  Start or Finish, the night rota, who got up.
- **Page 3 scrolls when there are many medicines (B)**, as drawn; the other pages never scroll. Changed later the same night to **A**: three rows that always fit (Bath; one medicine with its Given, or "Medicine ›" opening a list for two or more; Tonight in step 3).

To be built into the steps (from the review):
- Request results: the phone answers each tap (applied, already applied, refused, too old), and
  the watch's Logged card says "Waiting for iPhone" until it is applied; `PhoneLink.send` returns
  the request's ID. The phone checks a request's age itself, and records the request with the
  change it made, in one save.
- Order: a tap that depends on another (an amount on a new bottle, a poo's details on a new
  nappy, an Undo) names it, and the phone holds it until that one is applied (or refuses both).
- Versions: the phone says which commands it understands (`WatchState.capabilities`), and the
  watch shows a button only when its command is understood. New commands travel in their own
  envelope, and the watch's saved queue reads item by item, so one unknown item never loses the
  rest.
- Undo is the inverse of the exact action: a new entry removed (as the phone's Undo); a bottle
  removed by its ID; a time or a "done by" put back only while it is still what the tap wrote;
  otherwise refused. Undo of Finish, of a rota claim (which becomes "Both phones tonight" once it
  can have reached the other phone, as the phone's `undoTake`) and of a wake-up are step 3.
- Feed extras: the phone re-checks the feed's state and `DetailChoices` when it applies; Just
  finished and Earlier feed are refused when a feed is already logged in their span (the watch
  says so), so a late tap can't log a feed twice.
- After Finish on the watch, the state carries a small summary of the feed just finished (sides,
  bottles and amounts by ID), so the panel works after Just finished, Earlier feed, and for the
  parent whose feed was finished for them.
- Read-back: the last nappy's details show on page 2 ("Add details" when a poo has none);
  "Breastfeed (Sam)" counts for Sam on the Logged card; Pumping uses the phone's defaults (30 to 10
  minutes ago) and allows no amount.
- Layout: prototype the densest screens on 42 mm first, with long names, the "waiting" line and
  large text; the label beside the clock is tried first and falls back to a small first line if
  watchOS 27 won't place it there. The Digital Crown takes focus explicitly on each screen that
  uses it; the double tap only presses the visible page's main button.

## Step 1, as built (21 Nov 2026)

- FeedingCore `Watch/WatchActions.swift`: `WatchAction` (bath, medicine, pump, pooDetails, earlier,
  doneBy, undo) in `WatchActionRequest` (with `after`, the tap it depends on), `WatchOutcome`
  (applied, unchanged, refused, waiting), `applyWatchAction`, the capabilities and `WatchState`
  3's new fields; `WatchSaved.actions`, read item by item (`Lossy`). `WatchActionsTests`.
- The phone (`WatchRelay`): a new tap comes in `WatchMessage.action` or under `WatchKey.action`;
  one whose `after` isn't handled yet is answered `waiting`; every tap is noted as handled only
  after its change is saved, and answered in `WatchState.results`; a tap older than 25 hours is
  refused.
- The watch: `WatchPages.swift` (the three pages, `WatchPageFrame`, `WatchMetrics`, the round and
  oblong buttons, tiles), `WatchLogged.swift` (the Logged card, poo details, Pumping, the shared
  amount picker); `PhoneLink.send` returns the tap's ID.
- Left for step 2: Just finished, Earlier feed, a bottle during a feed, sides and bottles after
  Finish. Step 3: Undo of Start or Finish, Woke up's Earlier, Undo and "who got up", the night rota.
