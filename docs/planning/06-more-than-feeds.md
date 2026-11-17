# More than feeds: sleep, nappies, growth and medicine

The parents asked on 17 Nov 2026 for the app to log more than feeds, so they can see the baby's daily rhythms: sleep, wet and dirty nappies, and so on. They want quick ways to log each one (in the app, and from Control Center, the Lock Screen and the watch) and easy-to-read reports. This brings "Phase 3: growing with her" in `02-plan-v1.md` forward, ahead of TestFlight.

## Decided (17 Nov 2026, the users' choices)

- **Q1. What to log:** all four of **sleep**, **nappies**, **growth** and **medicine and vitamins**. (The recommendation was sleep and nappies now, growth and medicine later; the users chose all four.)
- **Q2. A nappy is one tap: wee, poo or both.** Nothing else is asked. A note can be added later, as on a feed.
- **Q3. Quick buttons outside the app:** **Control Center**, the **Lock Screen** and the **watch** (its app and its watch face). Not Siri or the Action Button for these, for now. Each button is set up once, as the bottle buttons are.
- **Q4. Order:** this comes first; TestFlight (`04-apple-setup-checklist.md`) waits until it is built.
- **Q5. Home (round one, option A):** two new tiles, **Sleep** and **Nappy**, side by side above the Next side and Last feed tiles. The Sleep tile shows "Asleep 1h 20m, since 10:05" (or how long awake) and one button, Woke up or Fell asleep. The Nappy tile shows the time since the last nappy and what it was, with three buttons: Wee, Poo, Both. Each tap logs at once, with the 10-second Undo bar. (Not B, a row of four quick buttons above Start feed; not C, one "+ Log" button opening a panel.)
- **Q6. The daily rhythm report (round one, option D): midnight to midnight.** On the Graphs tab, above the feed graphs. Each row is a calendar day, like the other graphs, so a night is split across two rows (the evening at the right end of one, the early hours at the left of the next). Sleep shows as bars, feeds as ticks in their colours, wees and poos as dots under the row. Under it, "Asleep per day" (night 21:00 to 07:00, and day, stacked) and "Nappies per day" (wees and poos side by side). Today's bars are paler, as it is not over. (Not E, rows from 07:00 to 07:00, which was the recommendation.)
- **Q7. Poo colour and consistency (the users' ask, 17 Nov 2026):** a poo can also record its **colour** (brown, yellow, green, other) and its **consistency** (liquid, loose, firm). Both are optional and added after the first tap, so a nappy is still saved by one tap (Q2 stands). A wee-only nappy has neither. They show in History ("Poo · yellow, loose"), not in the graphs. Facts only: no colour is ever called normal or a worry. When the app asks for them is round two's choice 6.

### Round two (17 Nov 2026, the users' choices: "1 F, 2 I, 3 K, 4 N, 5 O, 6 Q")

- **Q8. Lock Screen (F):** one wide **Sleep and nappy** widget beside Last feed. It shows how long the baby has slept (or been awake) and when the last nappy was, with four buttons: **Woke up** (or **Fell asleep**), **Wee**, **Poo**, **Both**. They work on a locked phone with no Touch ID, as Start feed does. (Not G, two round buttons.)
- **Q9. Watch app (I):** the feed screen stays as it is. Swipe up, or turn the Crown past the end, for a second page, **Sleep and nappy**, with big buttons: Woke up (or Fell asleep), Wee, Poo, Both. Page dots show there are two pages. (Not H, all on one screen.)
- **Q10. Medicine and growth in the app (K):** a **Medicine** tile on Home, under the other tiles, with one button per medicine; one tap logs it, with the Undo bar. **Growth** goes on the Graphs tab, with an **Add** button on the weight graph. (Not J, a More button with a panel.)
- **Q11. Weights (N):** you type **kilograms**, as in the red book, and see **pounds and ounces** beside it: "3.85 kg (8 lb 8 oz)". Length and head are in centimetres. (Not L, kilograms only; not M, pounds and ounces only.)
- **Q12. A feed during a sleep (O): Start feed ends the sleep.** The sleep stops when the feed starts, wherever Start feed is tapped (app, Lock Screen, Control Center, watch). After the feed, tap Fell asleep. The feed alarms do not change. (Not P, the two kept apart.)
- **Q13. Poo details (Q): asked straight after.** Tap Poo or Both: the nappy is saved at once, and a small panel asks the colour and the consistency. Tap one of each, or swipe it away to skip. A poo logged from the Lock Screen, Control Center or the watch has no details; the Nappy tile then shows "Add details" for it. (Not R, only on request.)
- **Settled on the same page, accepted with the picks:** Control Center has a Sleep switch (on means asleep) and Wee, Poo, Both and Medicine buttons, each set up once. The watch face gets a Sleep piece (the moon and the time asleep; a tap logs Fell asleep or Woke up) and a Nappy piece (opens Feeding on "Wee, poo or both?"). Every quick tap shows the 10-second bar with **Undo** and **Change time**. History holds every kind in time order, with a filter. The medicine list starts with Vitamin D; more are added in Settings; the app never shows a "next dose" time. The weight graph shows only the baby's own weights (no red-book curves). The colours are periwinkle for sleep, yellow for wee, brown for poo.

## Built (17 Nov 2026; on both phones, the watch still to come)

- **Core:** the four kinds, `startFeed` ending a running sleep (O, also from the Lock Screen, Control Center and the watch), Stop · discard putting that sleep back (`discardFeed`), the medicine list (a Setting record, `medicines`, starting with Vitamin D), the rhythm report's facts and the widget's facts (`CareGlance`). Watch taps for Fell asleep, Woke up and a nappy, each with an ID the watch picks.
- **Home:** Sleep and Nappy tiles above Next side and Last feed; a Medicine tile under them, with Given on each row and "+" for the list; the poo panel after Poo or Both; "Add details" on the Nappy tile for a poo with no details; Undo with Change time on every quick log. Holding Woke up or Fell asleep offers "about 10 / 20 / 30 min ago".
- **History:** every kind in time order, with All, Feeds, Sleep, Nappies, Medicine and Growth at the top. Each kind opens its own editor (`CareEditor`).
- **Graphs:** the daily rhythm report, Asleep per day (night and day stacked) and Nappies per day, above the feed graphs; the weight graph with Add, and the latest length and head under it.
- **Lock Screen and Control Center:** the Sleep and nappy widget (F); a Sleep switch, a Nappy button set up as Wee, Poo or Both, and a Medicine button set up with one medicine.
- **Watch:** page two, Sleep and nappy (I); the Sleep and Nappy face pieces.
- **Settings:** Medicines, the shared list.

Small changes from the mockups, found while building:
- The widget's line gives the last nappy's clock time ("Asleep · nappy 10:45"), not "40m ago": iOS's own ticking words were too long for the line.
- Control Center can show only Apple's symbols, and there is no poo symbol: Wee is a drop, Poo a circled P and Both a circled B (like the circled F and E on the milk buttons). Medicine uses the pills symbol. The Sleep switch says "Awake" when off.
- Two colours were made deeper or brighter so they read (DESIGN.md, Decisions Log, 17 Nov 2026). Day sleep beside night sleep on the graph has its own lighter shade, `sleep-soft`.
- Each medicine row's button says **Given**.

Codex review (17 Nov 2026, `gpt-6.1-sol`): nine findings, all checked in the code and fixed, with tests.
- **An alarm whose time has come is kept until a newer feed is logged** (up to 6 hours). Before, any change after its time (now often a nappy or a sleep) cancelled it, so a ringing alarm could stop. `planAlertChanges` now takes each baby's latest feed start (`stillSounding`).
- **A sleep still running when a later feed began ends at that feed**, on every phone after every change (`endSleepsInterruptedByFeeds`): for a sleep and a feed that reached a phone in a different order, a late watch tap, or an Undo of Woke up after a feed began.
- **Stop · discard finds the sleep its Start feed ended by who ended it and when** (the feed's creation), not by the feed's start, which can be corrected.
- The sleep editor saves the Woke up time shown when Still asleep is turned off; its pickers can't crash after the clock is set back; a growth entry keeps each measurement nobody changed exactly; the rhythm rows place times by the clock on the days the clocks change; Change time's choices say "5 min earlier".

Not built yet: spotting one nappy logged on both phones (as feeds do), and a nappy or sleep in the Duo's second column.

## Rules carried over

- **The alarms count feeds only.** A sleep, nappy, growth or medicine entry never sets, moves or silences a feed alarm. `reconcile()` already reads only live feeds (`isLiveFeed`); add a test that proves a new kind changes nothing. A sleeping baby does not pause the feed alerts: "alert too much rather than too little".
- **Facts only.** No targets, no "normal" ranges, no red or green, no "should", "due" or "missed". A sleep shows how long it lasted, not whether that was enough. The disclaimer stays.
- **One or two taps, one-handed, in the dark, and it can be undone** (product principle 2). Every quick log gets the 10-second Undo bar in the app.
- **Two phones, one record.** Same sync and same field-by-field merge as feeds.

## Storage (no iCloud schema change)

Each new entry is an `Event`, like a feed, with a new `kind`. The details go in the encrypted payload, so `schema.ckdb` does not change. `EventPayload.currentVersion` goes up by one for the new detail fields (the rule in `VersionedPayload`).

| Kind | Start | End | Details (encrypted) |
|---|---|---|---|
| `sleep` | fell asleep | woke up (empty while asleep) | none |
| `nappy` | when changed | none | wee, poo (both may be true); for a poo, colour (brown, yellow, green, other) and consistency (liquid, loose, firm), each optional |
| `growth` | when measured | none | weight (g), length (mm), head (mm): any of the three |
| `medicine` | when given | none | what (from the household's own short list, e.g. "Vitamin D"), amount as text (optional) |

- One sleep runs at a time for a baby. A sleep may overlap a feed (a feed during sleep is common at night).
- Older builds ignore kinds they don't know: Home, History and the graphs filter to `feed` and `pump` today (checked 17 Nov 2026), so a phone not yet updated shows nothing odd.

## Still to decide (round two of mockups, with a Day / 3am switch)

1. *(Decided: Q5.)*
2. *(Decided: Q6.)*
3. **Lock Screen, Control Center and watch:** which buttons, and how they fit the small spaces.
4. **Growth:** units (kg or lb and oz), and whether the chart shows centile lines (the red book's curves). The "facts only" rule says no, unless the parents ask.
5. **Medicine:** the starting list (e.g. "Vitamin D"), and how a new one is added.
6. **Forgetting "woke up":** a running sleep shows on Home, with "Woke up about 10 / 20 / 30 min ago", as "Just finished" does for feeds.
7. **A feed during a sleep:** does Start feed end a running sleep (the baby woke to feed), or does the sleep run on until Woke up (a feed given while asleep)?
8. **Where growth and medicine are logged in the app,** now that Home has the Sleep and Nappy tiles.
9. **When the poo details are asked:** straight after Poo or Both (a panel that can be swiped away), or only on request (Details on the Undo bar, "Add details" on the Nappy tile).

All nine are now decided: items 3 to 9 by round two (Q8 to Q13 above). Item 6 (forgetting Woke up) is covered by Change time on the Undo bar and by Woke up on the Sleep tile, which offers "about 10 / 20 / 30 min ago".
