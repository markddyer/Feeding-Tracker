# Who does what: each parent's share of the care

20 Nov 2026. A parent asked for a way to see how much each parent does: feeds, nappies, and the
rest. Reviewed by the CEO review on 20 Nov 2026 (decisions below, under "Accepted scope"); the
design review comes next, then the engineering review.

## The ask

"Put some logging in place so that we can tell how much [Parent B] is doing and how much I'm doing
in terms of feeding, nappy changing, etc."

## Problem

Two parents share the care of a newborn. At 3am, memory is poor and each parent's own work is the
work they remember. The app already holds a record of nearly every feed, nappy, sleep, medicine and
pumping session. The parents want that record to show who did what, so they can talk about the load
from facts.

## What the app knows today

- **Who logged each entry:** `Event.loggedBy`, a top-level field, on every entry of every kind since
  the first day. History already shows it as a small round picture in the parent's colour. The move
  from Feeding Dev keeps it (the maker becomes the parent bringing it in; the other parent becomes
  the other member).
- **Who finished a feed:** the `endedAt` field's stamp. History shows a second, smaller picture when
  the other parent finished it.
- **Who was on each night:** the night rota and nights taken (`Rota`, `NightAsk`).
- **Day and night:** the household's day hours (`DayHours`, 07:00 to 21:00 by default).
- **How long:** feeds (each side's seconds), sleeps (start to end), pumping sessions.
- Quick taps from the Lock Screen, Control Center, Siri and the watch are logged by the phone's own
  parent.

## The gap: "logged by" is not always "done by"

- One parent breastfeeds while the other taps Start feed on their own phone or watch: logged by one,
  done by the other.
- One parent logs a nappy the other changed, because their phone was closer.
- A parent fills in an entry later for the other parent.
- Breastfeeds and pumping can only be done by the parent who breastfeeds, whoever logs them.

How often this happens is not known. The app was built so each parent logs on their own phone (the
night rota depends on it), so most entries are probably logged by the parent who did them.

## A conflict with DESIGN.md

`DESIGN.md`, Do's and Don'ts: **"Don't: show who fed more as a score; the parent colours show who,
never a comparison."** This feature is a comparison. It needs the parents' go-ahead to change that
rule, and a new rule for how a comparison may look (`CLAUDE.md`: ask before departing from
DESIGN.md).

## Premises (to check)

- **P1. A shared picture, not a contest.** No winner, no score, no "you did less", no red or green.
  Both parents see the same numbers.
- **P2. Counts alone mislead.** A 45-minute breastfeed and a 2-minute nappy are not the same work.
  Time matters for feeds and pumping. (Settling time is not logged, so it is not counted; spec
  review, 20 Nov 2026.)
- **P3. Nights weigh most.** Night feeds and night nappies are the hardest work and the most
  remembered.
- **P4. No extra taps on the quick paths.** A nappy stays one tap; Start feed stays one tap.
- **P5. Works on what is already logged,** back to the first day, as far as it can.

## Approaches

### A. Read "logged by" only
A "Who did what" section on the Graphs tab: per parent, for the chosen range (week, 4 weeks, all):
feeds, nappies, medicines, pumping, sleeps logged; time on feeds and pumping; and the same for nights
only. Bars in the two parent colours. No new data and no new field. Works on all history at once.
Wrong whenever one parent logs for the other. Effort S.

### B. "Done by", which can be changed
As A, but each entry has a "Done by" that starts as:
- the parent who breastfeeds, for a breastfeed and for pumping (a household setting, "Who
  breastfeeds?", asked once);
- otherwise the parent who logged it.

A parent can change it in the entry's editor ("Done by: Parent A / Parent B"). Old entries get the
same starting rule, so history still counts. Needs a new field (an addition to the schema or to the
payload; the engineering review picks). Effort M.

### C. B, plus a weekly look back
As B, plus a short weekly summary on Sunday evening, in the app (and perhaps a quiet notice): what
the week held and who did which part. Facts only. Effort M.

## Draft recommendation

**B.** A shows the wrong parent too often for breastfeeds, which are most of the feeds. B fixes the
biggest gap with no extra tap, and lets a parent correct the rest. C waits until the parents have
seen B for a week or two. (The parents chose B on 20 Nov 2026, D2; C's weekly look back was
deferred, D7.)

## Accepted scope (CEO review, 20 Nov 2026)

1. **A shared "who does what" screen** (R1, D1 A). Each parent's part, side by side, as facts:
   counts, time and nights, in the two parent colours. `DESIGN.md:297`'s rule is replaced by a
   guarded one: never a winner, a score word, red or green; both phones see the same. Range: week,
   4 weeks, all, as the Graphs tab, plus a day (D1's option promised one). Where it lives and how it looks: the design review.
2. **"Done by"** (R2, D2 A). Each entry counts for its "done by". It starts as the parent who logged
   it; a breastfeed or a pumping session starts as the parent who breastfeeds, a shared setting asked
   once ("Who breastfeeds?"). Either parent can change it in the entry's editor. Old entries count by
   the same rule. One new stored detail per entry, stored whenever a parent sets it ("Counting rules");
   where it is stored is the engineering review's.
3. **"Done by" on the Undo bar** (X1, D4 A). After a quick log on Home, the 10-second bar shows who
   did it; one tap swaps it to the other parent. On the Woke up bar it swaps "got up" (R3); Bath's bar has
   it too.
4. **Tap a number to see its entries** (X2, D5 A). Each number opens History with just those entries
   (that parent, that kind, those days, night or day; wake-ups by "got up"), where a wrong "done by"
   can be fixed.
5. **"Last night" on Home** (X3, D6 A). Each morning until midday, a card: last night's feeds,
   nappies and wake-ups, each with who did it, and how long the baby slept. A handover, not a score.
   Each wake-up shows who got up (R3, D9 A).
6. **Baths** (X5, D8 A). Bath becomes a new kind of entry: a Bath button on Home, a Bath row in
   History (with its editor and "done by"), and baths on the shared screen. Not on the Lock Screen, Control Center or the watch in this plan. (Spec review: D8's answer
   named Home, History and the shared screen; baths on the "Last night" card were not in it, so they
   are not in scope.)
7. **Logging the other parent's breastfeed on a bottle-only phone** (design review DD15, the
   parents' own ask): see the design review table.

What counts: feeds (count and time), pumping (count and time), sleeps (who settled the baby: the
"Fell asleep" entry's "done by"), nappies, medicines, baths; growth and firsts are not work and
don't count. Nights use the household's night hours.

### Counting rules (stated after the spec review, 20 Nov 2026)

These follow from R1 and R2; none changes what the parents chose.

- **Which entries:** live entries of the baby only. Deleted entries don't count. A feed logged on
  both phones counts once, as History shows it (the hidden copy of a `duplicatePairs` pair is
  skipped, `App/Home/HistoryView.swift:25`). (Changed by the engineering review, D11 C and D12 A:
  a sleep, nappy, medicine or bath logged on both phones is also found and counted once, shown
  as feeds are; see TD2 and TD2b. The earlier rule, "counts twice, and a parent deletes the copy",
  no longer applies.) A feed pair counts once, for the "done by" stored on either copy (the later
  stamp wins when both have one), else by the starting rule on the copy History shows, so a
  correction on the hidden copy is never lost (outside review, finding 5). A running feed or sleep
  counts as one from its start.
- **One wake-up, one "got up":** sleeps ended by one tap (Woke up, or the Start feed that ended
  them) are one wake-up, even when a back-dated tap gave them different end times (each end is kept
  after its own start, `MoreThanFeeds.swift:29`). They share one "got up"; the swap and the editor
  change it for all of them; the screen, the card and the X2 list count it once. How the tap is
  remembered (for example an ID shared by those sleeps): the engineering review (outside review,
  finding 3).
- **When:** (night rule changed by design pass 1A: a night is named by its evening, see the design
  review) an entry belongs to the day and to day or night by its start, read on the household's
  wall clock (`DayHours.period(at:in:)`). Two exceptions, judged by their end: a wake-up ("got up")
  belongs to the day and the day or night of the moment the sleep ended. "Nights" means entries
  started (wake-ups: ended) in the household's night hours (21:00 to 07:00 by default); the rota is
  not used for counting. With no night hours (`dayStart == nightStart`), there are no night lines and
  no "Last night" card.
- **Time, case by case:**
  - a feed whose breast sides all have their seconds: the sum of those seconds;
  - any other finished feed (a bottle, a side logged afterwards with no seconds, or "Feed logged"
    with no details): start to end;
  - pumping: start to end;
  - a running entry: no time until it ends;
  - sleeps and baths: counted, not timed (the baby's sleep is not a parent's work; a bath has no
    length).
- **Range:** a day, week, 4 weeks and all. D1's chosen option promised "a day, a week or more", so a
  day is required; how a day is picked (today, going back a day) is the design review's. A "day"
  is a calendar date on the household's wall clock (midnight to midnight), as the Graphs tab
  (`Graphs.swift:67`) and History group them; the screen's ranges and the X2 list use the same
  days, so a tapped number always matches its list. Night or day is a mark on each entry
  (`DayHours.period`), not a way of dividing days.
- **The "Last night" card (X3):** "last night" is the household's most recent night that has ended
  (`DayHours`, the night as a whole, across midnight). The card shows from the night's end until
  12:00 (D6: "until midday"); when the night ends at or after 12:00, there is no card. It lists that
  night's feeds, nappies and wake-ups (each with its "done by" or "got up") and how long the baby
  slept in it: the sleeps that overlap the night hours, cut to those hours (a sleep still running
  counts up to the night's end), with overlapping sleeps joined so no time counts twice (as the
  rhythm report's `sleepSpans`, `Rhythm.swift:125`; outside review, finding 6). A night with
  nothing logged shows no card.
- **"Done by" starting rule:** a parent's own choice, when one was made, always wins and is always
  stored (even if it matches the starting rule, so it never flips later). With no choice stored: a
  feed with any breast side, or a pumping session, counts for the parent who breastfeeds; anything
  else counts for the parent who logged it. A breastfeed with a top-up bottle given by the other
  parent counts as one feed for the parent who breastfeeds; the top-up can't be split.
- **"Who breastfeeds?":** one shared setting, with three answers: Parent A, Parent B, Nobody. Either
  parent can answer or change it. Unanswered or Nobody: every entry starts with the parent who
  logged it. Changing it recounts the past for every entry with no stored choice, and the setting
  says so. When and where it is first asked: the design review.
- **"Got up" (R3, D9 A):** a sleep keeps who settled the baby ("done by", from Fell asleep) and who
  got up when it ended ("got up"). "Got up" is stored when the sleep is ended, as the parent who
  tapped Woke up or Start feed (Start feed ends a running sleep; a Woke up that ends several sleeps
  sets each). A sleep ended by a feed that reached this phone late (`endSleepsInterruptedByFeeds`,
  `MoreThanFeeds.swift:105`) gets that feed's logger, not the phone that ran the rule. Swapped on the
  Woke up Undo bar, fixed in the sleep's editor, mapped by the move, kept by older builds. A sleep
  that runs again (Undo of Woke up, or "Stop · discard" of the feed that ended it,
  `MoreThanFeeds.swift:87`) loses its "got up", stored or not. **A "got up" belongs to one ending:**
  it is kept together with the end it was given for, and a sleep whose end is no longer that end
  (reopened and ended again, on any phone or build, or a late correction meant for an earlier end)
  ignores it; Change time on this build moves it with the end (outside review, finding 2). Any
  ended sleep with no valid stored "got up" (ended before this build, or by an older build) shows a
  worked-out one, marked as such (as History's "logged by"): if its end time equals a feed's start,
  that feed's logger; otherwise the parent in the end time's stamp. A worked-out value is never
  stored by an unrelated edit, because the stamp names whoever last changed the end time, not
  who got up; it is stored only when a parent picks it (outside review, finding 4). The end time's
  own stamp is never rewritten for this ("Stop · discard" uses it to find the sleep to reopen). Night wake-ups count as "got up at night" for that
  parent; daytime wake-ups are not counted on the screen (D9 named nights only). A running sleep has
  no "got up".
- **Where "done by" can be set:** every editor of a kind that counts (feeds, pumping, sleeps,
  nappies, medicines, baths), the add-later screens (Earlier feed, Pumping), and the Undo bar (X1).
  Growth and firsts have no "done by".
- **Two parents:** the screen, the swap and the editors assume two members, as the household does
  today. The stored detail names a member, so a third person later needs no data change.
- **History:** a list opened from a number (X2) is a temporary filter by parent, kind (feeds,
  pumping, sleeps settled, wake-ups got up, nappies, medicines, baths), days and night or day, and
  leaves History's saved filter alone. In that list each row shows the "done by" (or "got up") it
  was counted for and, for a time number, the time it added, so both the count and the total can
  be checked from the list (outside review, finding 7). Whether History's ordinary rows also switch
  their picture from "logged by" to "done by" was not put to the parents: an open item for the
  design review.
- **Bath on Home:** one tap logs it at once, with the 10-second Undo bar and its "done by" swap.
- **Which Undo bars get the swap (X1), exactly:** Wee, Poo, Both, Fell asleep, Woke up (it swaps
  "got up"), Given, and Bath. Not "Feed logged" or the bars after a feed is started, finished or
  changed (not in D4's answer); a feed's "done by" is fixed in its editor.
- **The move from Feeding Dev:** a stored "done by", a stored "got up" and the "Who breastfeeds?"
  answer are mapped to the new member IDs, as `loggedBy` is (`HouseholdMove.swift:286`), on a first
  move only. A repeat move keeps today's rule (`HouseholdMove.swift:273`): entries already here are
  left as they are and settings come once, so a later "done by" set in Feeding Dev is not carried.
  The household's move is planned before this feature ships, so in practice the parents set "done
  by" and "Who breastfeeds?" in Little Log (outside review, finding 8).
- **Older builds:** an older build keeps a newer entry's "done by" and "got up" and never erases them
  when it saves that entry (`KeptJSON`, step 0 of the journal). How: the engineering review. If it
  chooses a newer details format, an older build can't show those entries' details until it is
  updated (`HistoryView.swift:187`); the engineering review must name that and choose it or avoid it.
- **Tests (in `FeedingCore`):** clock changes both ways, a 30-minute time zone, travel, the clock set
  back, midnight and the 21:00 boundary (as `CLAUDE.md` requires), plus duplicates, deletes,
  running entries, mixed feeds, an unanswered or changed "Who breastfeeds?", and a stored choice
  that matches the starting rule.
- **Baths reach:** Home's Bath button, History (its row, its editor, its filter button), the shared
  screen. Not the "Last night" card (D8's answer did not include it), the rhythm report, Export, the
  Lock Screen, Control Center or the watch. A bath does not end a running sleep.
- **Rollout (a release step, not a check in the app):** both phones are updated to the new build
  before the parents rely on the screen; a phone on an older build shows no screen and no baths
  (TestFlight installs are each parent's). Feeding Dev first.

## NOT in scope

- **A weekly look back** (X4, D7 B): deferred to `TODOS.md`; the screen already shows a week and the
  morning card covers each night.
- Baths from the Lock Screen, Control Center or the watch (not offered; Home only for now).
- Other unlogged jobs (washing bottles, settling without a sleep entry): not logged, so not counted.

## Open questions (draft; answered or moved)

1. Is the aim a fair share, or to notice when one parent is worn out, or both? Both: facts both
   trust (0A).
2. Count, time, or both? Both; which kinds count is in "Accepted scope".
3. Where does it show? The shared screen, History (through tapped numbers) and Home's "Last night"
   card; the screen's place is the design review's.
4. Is a "Done by" field worth it? Yes (D2).
5. How does it look so it never reads as a score? The design review, under the new rule.

## CEO review (20 Nov 2026)

Review depth: implementation-ready. Working plan: this file. The branch's design doc
(`~/.gstack/projects/<owner>-Feeding-Tracker/…-design-20261117-223018.md`) is the journal's, not
this feature's, so this file is the source of truth.

### 0A. The real problem

- **The pain:** two worn-out parents each judge the load from memory. Research on new parents (Ohio
  State's New Parents Project, time diaries against what couples said) found that parents misjudge
  how the extra work is shared. Facts both parents trust are the direct fix; this plan is that fix,
  not a stand-in for it.
- **The target outcome:** both parents can look at one screen and see, for a day, a week or more,
  who did which feeds, nappies, sleeps, medicines and pumping, how long it took, and who got up at
  night. They then plan nights and swaps from that.
- **Cost of doing nothing:** small but real. History already shows who logged each entry, so a
  parent can scroll and count. Nobody will, at 3am.
- **The risk this plan carries:** a side-by-side count can read as a score and start an argument.
  That is why `DESIGN.md` forbids it today.
- **Landscape (web search, 20 Nov 2026):** shared baby trackers (Burp, Mjello, Pebbi, BabySync)
  tag each entry with who logged it. None found shows each parent's share. Layer 1 (tried and
  true): tag each entry. Layer 3 (first principles): the tag is "who tapped", not "who did it", so
  a share built only on it is wrong whenever one parent logs for the other.

### Premise table

| # | Claim | Receipt | Verdict |
|---|---|---|---|
| F1 | Every entry stores who logged it | `FeedingCore/Sources/FeedingCore/Model/Event.swift:16` | verified |
| F2 | History shows the logger's picture | `App/Home/FeedRows.swift:67` | verified |
| F3 | History shows who finished a feed when it was the other parent | `App/Home/FeedRows.swift:109` | verified |
| F4 | The move from Feeding Dev keeps who logged each entry, mapped to the new IDs | `FeedingCore/Sources/FeedingCore/Store/HouseholdMove.swift:286` | verified |
| F5 | A watch tap is logged as the watch's own parent | `App/Model/WatchRelay.swift:84` | verified |
| F6 | Each breast side keeps its seconds | `FeedingCore/Sources/FeedingCore/Model/Details.swift:18` | verified |
| F7 | Day hours default to 07:00 to 21:00 | `FeedingCore/Sources/FeedingCore/Time/DayHours.swift:22` | verified |
| F8 | The rota knows who is on each night | `FeedingCore/Sources/FeedingCore/Rota/Rota.swift:63` | verified |
| F9 | `DESIGN.md` forbids showing who fed more as a score | `DESIGN.md:297` | verified |
| F10 | Each phone's feeding style (breast and bottle, or bottle only) is kept on that phone only, not shared | `App/ContentView.swift:12` | verified |
| F11 | Most entries are logged by the parent who did them | none | unverified |
| F12 | Breastfeeds are most of the feeds | none | unverified |
| F13 | No shared tracker shows each parent's share | web search, 20 Nov 2026 | unverified (outside source) |
| F14 | Parents misjudge their own share of the new work | web search, 20 Nov 2026 | unverified (outside source) |

unverified=4

### 0B. What already exists

| Need | Reuse |
|---|---|
| Per-day facts from entries | `graphDays` (`Insights/Graphs.swift:60`) and `rhythmDays` (`Insights/Rhythm.swift:112`): a new pure function beside them, same inputs |
| Week, 4 weeks, all | `GraphRange` (`Insights/Graphs.swift:7`) |
| Day or night | `DayHours.period(at:in:)` (`Time/DayHours.swift:30`) |
| Who was on at night | `Rota.onDuty(night:)` (`Rota/Rota.swift:63`): not used for counting ("Counting rules"); the design review may show it as context |
| Who finished a feed | the `endedAt` stamp, as History reads it (`App/Home/FeedRows.swift:109`) |
| Parent colours and pictures | `Avatar`, `RowPerson`, the parent colours in `DESIGN.md` |
| A list of one parent's entries | History's filter (`App/Home/HistoryView.swift:19`) |

Nothing is rebuilt.

```
REALITY: premise-table finding unverified=4: F11 and F12 decide how wrong "logged by" is; F13-F14 are outside sources docs/planning/09-who-does-what.md:1
REALITY: already-done pass no commit mentions a done-by or share feature (git log --all --grep) c4fedda
REALITY: surface-check pass the plan names code symbols only, no command or route; each was found FeedingCore/Sources/FeedingCore/Model/Event.swift:16
REALITY: binding-decisions finding DESIGN.md's rule against a who-fed-more score conflicts with the ask; no branch decision covers this feature DESIGN.md:297
REALITY: numbers pass 07:00 to 21:00 is measured from the code; "45-minute breastfeed" and "2-minute nappy" are examples [estimated] FeedingCore/Sources/FeedingCore/Time/DayHours.swift:22
REALITY: deferred-asks pass no linked issue; the ask is quoted in full docs/planning/09-who-does-what.md:9
REALITY: pr-count pass no ship policy; work is committed on the one branch, one wave CLAUDE.md:59
```

### 0C. Where this goes

```
  NOW                              THIS PLAN                          IN 12 MONTHS
  Each entry has who logged it;    One shared screen: who did what,   The app is the household's
  History shows a small picture.   counts, time and nights, in the    shared memory of the work:
  Nobody adds it up.               two parent colours. No score.      it helps plan nights and
                                                                      swaps, gently, as the baby
                                                                      grows (solids, bath, nursery
                                                                      runs).
```

### 0E. Mode

Mode: SELECTIVE EXPANSION; approved decisions: R1 (D1 A), R2 (D2 A). Chosen by the parents (D3,
"A) As planned, show me extras"), 20 Nov 2026. Estimated about 14 changed files [estimated] before the extras; about 28 after X1, X2, X3, X5 and the counting rules [estimated, spec review].

### 0G. Hold checks and extras

**Hold checks.**
- *Size (before the extras):* about 14 files and 1 new part (the share facts, beside `graphDays`). Fewer parts can't do
  it: the facts, the screen, the editor's "Done by", the stored detail, the "who breastfeeds"
  setting and the tests are each needed by R1 and R2. No cut is proposed.
- *Minimum:* the facts function, one screen section, "Done by" in the two editors, one shared
  setting, the stored detail, `DESIGN.md`'s new rule, tests. Nothing in it can wait without
  breaking R2.
- *Rules kept:* `reconcile` and the alerts never read "done by" (feed timing and the rota are not
  touched). No medical words. The repo stays free of names. Old builds must keep working with
  entries that carry the new detail (the engineering review picks how).

**10x.** Not a chart: a record both parents trust. Every number can be checked (tap it, see the
entries) and fixed (change "done by"), and nights get their own line, because nights are what
parents remember and argue about.

**Platform.** "Done by" names a household member, not "one of two". A grandparent or a nanny joining
later fits with no new design; today's screen shows the two parents.

**Extras (each asked on its own, below):**

| # | Extra | What you notice | Effort | Risk |
|---|---|---|---|---|
| X1 | "Done by" on the Undo bar | After a quick log, the bar shows who did it; one tap swaps it to the other parent | S | low |
| X2 | Tap a number to see its entries | Tap "12 nappies" under a parent: History opens, showing just those | S | low |
| X3 | "Last night" on Home in the morning | Until midday, Home shows who did which night feeds and nappies | M | medium |
| X4 | A weekly look back | Sunday evening, a short page on the week: who did which part | M | medium |
| X5 | Log baths too | A Bath button, so baths count as well | M | low |

### 0H. Spec review and approval

Three review rounds (the cap), scores 6, 7 and 7 out of 10: 41 issues found, 30 confirmed fixed by
the next round, the third round's 8 fixed in the text after it (issues verified: 8 of 8, applied
edits, not a verdict; **spec not re-verified**). One finding needed the parents (R3, D9). The CEO
summary is `~/.gstack/projects/<owner>-Feeding-Tracker/ceo-plans/2026-11-20-who-does-what.md`.
The parents approved both documents with the spec not re-verified: D10 answer "A) Approve and
continue (recommended)", 20 Nov 2026.

### 0I. Build order (estimates)

```
  HOUR 1 (foundations):   EventKind "bath"; where "done by" and "got up" live (E1, engineering
                          review); the "breastfeeder" setting; ONE resolver, doneBy(entry) and
                          gotUp(sleep), used by every screen so a number and its list never differ.
  HOUR 2-3 (core logic):  share facts (counts, time cases, calendar days, night mark, duplicates),
                          last-night facts, the X2 entry list; "got up" through end, Undo,
                          Stop · discard and the late-feed rule (MoreThanFeeds).
  HOUR 4-5 (integration): editors and add-later screens, the Undo bar swap, Bath on Home, History's
                          temporary filter, the Graphs section, Home's card, Settings, the move's
                          mapping, sync (and schema.ckdb if E1 picks a record field).
  HOUR 6+ (polish/tests): the time edge-case tests, sample data flags, VoiceOver, the five Duo
                          widths, DESIGN.md's new rule.
```

Effort: human about 2 weeks, Claude about 5 to 7 hours [estimated]. Feasibility blockers: none; E1
must be settled before the first stored detail is written. Pending choices: E1, E2 (engineering
review), DS1 (design review).

### Section 1: Architecture

```
  FeedingCore (pure, Linux-tested)                        App (iOS)
  ───────────────────────────────────                     ───────────────────────────────────
  Event.kind += "bath" (own field list, no schema change) Editors: EventEditor (incl. Earlier feed
  Event: doneBy, wakeID, gotUpBy, gotUpFor  ──────────►    and Pumping modes), CareEditor: "Who did it"
    (4 encrypted fields, E1 D2 + A5 D8; stamps in       Undo card (top, glass): one-tap swap (X1)
     the details, only with a value, E3)                 CareTiles: Bath button; poo panel swap
  Setting "breastfeeder" (Parent A / B / Nobody)  ─────►  SettingsView: "Who breastfeeds?"
  HouseholdData: set "done by" / "got up"; copies of      One entries list (D1): behind a number (X2)
    any kind (D11, D12); "missing value" list (E3 D9)       and the "Last night" sheet (X3)
  MoreThanFeeds: wake-up ID per ending (A5 D8)            Graphs tab: tile → the page (DD3)
  HouseholdMove: maps the new IDs                         HomeView: the morning line (DD4, 3A)
  Insights/Shares.swift (NEW): WhoDidIt, one value per    History: big picture = who did it (DD12)
    store change (A4 D5) ◄── every screen reads it ──►    Sync: RecordMapping + schema.ckdb (4 fields);
    facts(range) / lastNight(now) / entries(for:)           fetch-by-name of missing values (E3 D9)
  reconcile / AlertPlan: UNTOUCHED (never read them)      Spikes: debug lines (E2 D4)
```

- **Coupling:** new screens depend on one resolver in `FeedingCore`, not on each other. `reconcile`
  gains no input. OK.
- **Data flow, the share facts:** happy: live entries → copies skipped → resolver → calendar day and
  night mark → per-parent counts and time. Nil: a payload that can't be read gives no sides, so the
  entry counts for its logger and with start-to-end time (and a "done by" kept in that payload is
  unreadable too: one reason E1 matters). Empty: no entries, or the other parent not joined yet:
  the screen shows its empty state (DS1). Error: a "done by" naming someone no longer in the
  household counts on an "Other" line, never dropped.
- **State, "got up":**
  ```
  running (none) ──Woke up / Start feed──► ended (stored: who tapped)
  ended ──Undo of Woke up / Stop · discard──► running (cleared)
  ended ──swap / editor──► ended (stored: chosen)
  ended, none stored (old) ──first edit──► ended (stored: worked out)
  running with a stored value (reopened on an older build): ignored; replaced at the next end
  ```
- **State, "done by":** none stored (worked out from the rule and the setting) → a parent sets it →
  stored, wins for good. Changing "Who breastfeeds?" recounts only entries with none stored.
- **Scale:** about 30 entries a day, about 11,000 a year: one pass per screen draw is fine.
- **Single points of failure:** the resolver (by design: one source of truth, heavily tested).
- **Security surface:** no new endpoint; writes go through the existing household zone.
- **Rollback:** reinstall the earlier TestFlight build; older builds keep the new details.
- **Cherry-pick fit:** X3 needed R3 to work (who got up); both now share the resolver. X5 (Bath)
  touches the most files but no alarm code.

Findings: 1, the storage choice (E1), owned by the engineering review. No other issues found.

### Section 2: Error and rescue map

```
  CODEPATH                    | WHAT CAN GO WRONG                          | RESCUED? | USER SEES
  ----------------------------|--------------------------------------------|----------|------------------------------
  resolver doneBy/gotUp       | payload unreadable or newer                | Y        | counted for the logger
                              | member not in the household any more       | Y        | an "Other" line
                              | "Who breastfeeds?" unanswered              | Y        | counted for the logger
  HouseholdData.setDoneBy     | entry gone or deleted meanwhile            | Y        | nothing changes (edit → false)
                              | payload newer than this build              | Y        | editor read-only (existing rule)
  setGotUp / sleep end        | late feed ends a sleep on the other phone  | Y        | "got up" = the feed's logger
                              | Undo / Stop · discard reopens it           | Y        | "got up" cleared
  breastfeeder setting save   | iCloud save fails                          | Y        | retried by the sync engine
                              | both parents change it at once             | Y        | later change wins on both
  Undo bar swap               | tapped after Undo removed the entry        | Y        | nothing (bar is gone)
  X2 list                     | an entry deleted while the list is open    | Y        | the row leaves the list
  "Last night" card           | no night hours, or nothing logged          | Y        | no card
  move from Feeding Dev       | a "done by" names an unknown member        | Y        | file refused (unclearParents)
```

No catch-all handlers: Swift's typed results and `Bool` edits. **0 gaps.**

### Section 3: Security and threat model

| Threat | Likelihood | Impact | Mitigated? |
|---|---|---|---|
| One parent changes the other's "done by" | Medium | Low | By design (both may fix); the field stamp records who changed it last |
| A record with a "done by" outside the household | Low | Low | Only household members can write the zone; the resolver shows it as "Other" |
| "Who did what" seen by Apple if stored as a record field | Low | Low | Same exposure as `loggedBy` today; a payload field would be encrypted (E1) |

No new inputs beyond a choice of two members; no secrets, no new packages, no third parties.
No issues found beyond E1's privacy trade, noted there.

### Section 4: Data flow and interaction edge cases

```
  INPUT (tap / sync) → VALIDATE (member is in household) → TRANSFORM (resolver) → PERSIST (field
  stamp, later wins) → OUTPUT (screen, card, X2, History)
  shadows: nil payload → logger │ unknown member → "Other" │ two phones at once → later stamp wins
           │ older build saves → kept (KeptJSON) │ copy on both phones → feeds once, others twice
```

**Async ordering.** Invariant: after both phones sync, they show the same numbers. The facts are a
pure function of the stored entries, so the only race is two phones setting the same field. Both
orders: phone 1 sets A then phone 2 sets B → B wins if its stamp is later, on both phones; the
reverse order gives the same answer, because the merge orders by stamp time then member ID
(`FieldStamp`, `Payload.swift:14`). Proof: a merge test for the new field(s) in both orders.

| Interaction | Edge case | Handled? | How |
|---|---|---|---|
| Undo bar swap | tapped twice fast | Y | toggles; the last state stands |
| Undo bar swap | then Undo | Y | the entry goes; the swap goes with it |
| Swap or editor | both phones at once | Y | later stamp wins |
| Shared screen | before the other phone has synced | Y | numbers match once both have synced (stated on the screen: DS1) |
| Shared screen | other parent not joined | Y | empty state (DS1) |
| X2 list | zero entries | Y | an empty list with a short line |
| X2 list | "All" over months | Y | one pass, fine at this size |
| Card | a feed running at the night's end | Y | counted by its start |
| Card | phone in another time zone | Y | the household's wall clock |
| "Who breastfeeds?" | changed while the screen is open | Y | recount on change |

No unhandled cases.

### Section 5: Code quality

- One resolver for "done by" and "got up", used by the screen, the card, X2 and History, so they
  can't disagree. Under 5 branches each.
- New facts in `Insights/Shares.swift`, beside `graphDays` and `rhythmDays`, same inputs.
- Bath copies the nappy's quick-log path (`CareTiles`, `CareText`, `CareRow`, `CareEditor`), not a
  new pattern.
No issues found.

### Section 6: Tests

```
  NEW                                  TYPE         HAPPY                 FAILURE / EDGE
  resolver doneBy                      unit         stored wins           unreadable payload, unknown member, unanswered setting, setting changed
  resolver gotUp                       unit         Woke up tapper        late feed, Undo, discard, old sleep fallback, reopened on old build
  shareFacts                           unit         counts and time       copies, deletes, running, mixed feed, time cases, calendar days,
                                                                          night mark; clock changes both ways, 30-min zone, travel, clock
                                                                          set back, midnight, 21:00
  lastNight                            unit         a normal night        no night hours, empty night, night ending at/after 12:00, sleep
                                                                          still running
  entries(for:) (X2)                   unit         matches the number    every kind, night or day
  merge of the new field(s)            unit         later stamp wins      both orders
  move mapping                         unit         IDs mapped            unknown member refused
  older build keeps the detail         unit         KeptJSON round trip   save by an older build
  Bath kind                            unit         logged, counted       never touches reconcile
  Undo swap, editor line, X2 list      UI (tap)     one tap swaps         Undo after swap
  screen, card                         audit        VoiceOver labels      Duo widths
```

- Assertions: each number equals its X2 list's length (rejects a screen and list that disagree;
  no_claim: real iCloud sync, mocked by the store). A stored choice that matches the starting rule
  survives a setting change (rejects a flip; no_claim: none beyond protects).
- 2am Friday test: a full made-up week through the resolver with both phones' copies, then the
  setting changed. Hostile QA: swap on both phones at once, offline. Chaos: an older build saving a
  sleep mid-night.
- Flakiness: every time test uses fixed dates and zones, never the clock.
No gaps beyond the list above, which is the plan's required coverage.

### Section 7: Performance

One pass over at most about 11,000 entries a year per draw [estimated]; worked out again only when
the store changes, as the Graphs tab does. No network, no new storage of facts. No issues found.

### Section 8: Observability

No new network path, so no new sync log lines. Debugging a wrong number: the X2 list shows the
entries behind it. Pending (E2, engineering review): show "done by" and "got up" in Feeding Dev's
household debug screen (`App/Spikes/HouseholdDebugView.swift`). 1 gap, owned by E2.

### Section 9: Deployment and rollout

- Order: Feeding Dev build on both phones with made-up data → checks → Little Log build 2 to
  TestFlight → each parent installs. If E1 picks a record field: `schema.ckdb` addition, Dev import,
  then the Production deploy with the parents' go-ahead **before** the build that writes it ships.
- Mixed builds: an older phone keeps the new details, shows no screen and no baths; nothing breaks.
- Rollback: install the earlier TestFlight build; data stays.
- Post-install check: the screen's numbers match on both phones after a sync; the card shows after
  07:00.
1 risk flagged: the Production schema step, only if E1 picks a record field.

### Section 10: Long-term trajectory

- Reversibility: 4 of 5 (stored details stay in the data; a record field would be permanent).
- Debt: History's ordinary picture (DS1); copies of non-feed entries count twice (a later
  duplicate rule).
- Next: the weekly look back (`TODOS.md`); more kinds of work (bottles washed); a third person
  (the stored detail already names a member).
- Retrospective: X3 was load-bearing for R3, and both are in. No rejected extra was needed.

### Section 11: Design and UX

```
  Graphs tab ──► Who does what (day │ week │ 4 weeks │ all)
                   ├─ tap a number ──► History, just those entries ──► entry editor (fix "done by")
                   └─ first visit, unanswered ──► "Who breastfeeds?" (A / B / Nobody)
  Home, 07:00 to 12:00 ──► "Last night" card ──► (tap: DS1)
  Home quick log ──► Undo bar [Undo] [Change time] [who ⇄]
  Home ──► Bath button ──► Undo bar
```

| Feature | Loading | Empty | Error | Success | Partial |
|---|---|---|---|---|---|
| Shared screen | none (local) | no entries / other parent not joined | — | two columns | other phone not synced yet |
| "Last night" card | none | no card | — | the night's list | a feed still running |
| X2 list | none | "nothing here" | entry removed | the entries | — |

- DESIGN.md: the new guarded rule replaces `DESIGN.md:297` (write it in the Do's and Don'ts and
  the Decisions Log).
- Accessibility: never colour alone; each column names its parent; VoiceOver reads "Parent A, 12
  nappies"; large text; 44-point targets for the swap.
- Duo: the screen at the five Safari-equivalent widths in `~/.claude/reference/iphone-duo.md`.
- Recommendation: run /plan-design-review on this plan before building (the parents asked for it).
Findings: DS1 (owned by the design review).

### Decision ledger

| ID and owner | Contract and evidence | Current | Proposed | Status | Exact approval and scope |
|---|---|---|---|---|---|
| R1 (parents) | May the app show each parent's part side by side? F9, `DESIGN.md:297` | **A) Side by side, facts only.** `DESIGN.md:297` is replaced by a guarded rule: each parent's part may show side by side as facts (counts, time, nights) in the parent colours; never a winner, a score word, red or green; both phones see the same. | B and C declined | approved | D1 answer "A) Side by side, facts only (recommended)", 20 Nov 2026. Scope: the rule and that a shared screen exists; where and how it looks is the design review's. |
| R2 (parents) | Which approach: a "done by" that can be changed, or "logged by" only? F11, F12 | **A) "Done by", fixable.** Each entry counts for its "done by": it starts as the parent who logged it; a breastfeed or pumping starts as the parent who breastfeeds (one shared setting, asked once); either parent can change it in the entry's editor; old entries count by the same rule; one new stored detail per entry, stored whenever a parent sets it (spec review: the earlier "only when it differs from the starting rule" would let a choice flip later). Counts, time and nights all shown. | B declined. (The weekly look back moves to the expansion list, 0G.) | approved | D2 answer "A) Count who did it, fixable (recommended)", 20 Nov 2026. Scope: the counting rule, the shared "who breastfeeds" setting and the editor change; where the new detail is stored is the engineering review's. |
| X1 (parents) | "Done by" on the Undo bar? | **Added.** After a quick log on Home (Wee, Poo, Both, Fell asleep, Woke up, Given), the 10-second Undo bar shows a small picture of who did it; one tap swaps it to the other parent. Lock Screen, Control Center and watch taps are still fixed in the editor. | B and C declined | approved | D4 answer "A) Add it now (recommended)", 20 Nov 2026. Scope: the Undo bar only; its look is the design review's. |
| X2 (parents) | Tap a number to see its entries? | **Added.** Each number on the shared screen opens History with just its entries (that parent, that kind, those days), where a wrong "done by" can be fixed. | B and C declined | approved | D5 answer "A) Add it now (recommended)", 20 Nov 2026. Scope: the link from a number to a filtered History; its look is the design review's. |
| X3 (parents) | "Last night" on Home in the morning? | **Added.** Each morning until midday, Home shows a "Last night" card: last night's feeds, nappies and wake-ups, each with a small picture of who did it, and how long the baby slept. A handover, not a score. | B (recommended) and C declined | approved | D6 answer "A) Add it now", 20 Nov 2026. Scope: the card, its night (the household's night hours) and its midday end; its look and place on Home are the design review's. |
| X4 (parents) | A weekly look back? | **Deferred** to `TODOS.md` ("Who does what"): not in this plan's scope; the shared screen already shows a week and the morning card each night. | A and C declined | deferred | D7 answer "B) Later, on the to-do list (recommended)", 20 Nov 2026. |
| X5 (parents) | Log baths too? | **Added.** Bath is a new kind of entry: a Bath button on Home, a Bath row in History with its editor and "done by", and baths on the shared screen. Not on the "Last night" card (not in D8's answer), the Lock Screen, Control Center or the watch. | B (recommended) and C declined | approved | D8 answer "A) Add it now", 20 Nov 2026. Scope: Home, History and the shared screen only (spec review: "and the morning card" removed; D8's answer did not name it). |
| R3 (parents) | Who got up when the baby woke? Spec review: a sleep is one entry (Fell asleep starts it, Woke up ends it, and one Woke up can end several sleeps, `App/Home/CareTiles.swift:12`). Its "done by" is who settled the baby, so X1's swap on the Woke up bar would change the wrong thing, and X3's "wake-ups, each with who did it" has nothing to show. | X1 and X3 approved as worded | **A) Record who got up.** Each sleep keeps a second detail, "got up": who got up when it ended. It starts as whoever ended the sleep (Woke up, or Start feed, which ends a running sleep; one Woke up ending several sleeps sets each); the Woke up Undo bar swaps it (X1); the sleep's editor fixes it; it is stored whenever a parent sets it. The "Last night" card shows each wake-up with who got up, and the shared screen counts "got up at night" per parent. | B and C declined | approved | D9 answer "A) Record who got up (recommended)", 20 Nov 2026. Scope: the "got up" detail, its starting rule, the Woke up swap, the sleep editor line, the card and a night line on the screen. |
| E1 (engineering review) | Where "done by" and "got up" are stored: a payload field (encrypted, no schema change; needs a payload version, so an older build can't show those entries' details) or a top-level record field (readable by older builds, but `schema.ckdb` grows and Production needs the parents' go-ahead; Apple can see it, as `loggedBy`). Sections 1, 3, 9. Outside review, finding 1: with the payload field, a running feed whose "done by" was set can't be finished or discarded on an older phone (`HouseholdData.swift:276` refuses to edit a newer payload, and Quick Finish reports success, `QuickFeed.swift:85`); E1 must prevent that (for example, the record field, or no stored "done by" while a feed runs) and test finishing such a feed on the older build. | not chosen | payload field; record field | pending (owner: engineering review) | none yet |
| E2 (engineering review) | Show "done by" and "got up" in Feeding Dev's household debug screen. Section 8. | not planned | add; leave out | pending (owner: engineering review) | none yet |
| DS1 (design review) | Where the screen lives and how it looks under the new rule; how a day is picked; when "Who breastfeeds?" is first asked; whether History's ordinary rows show "done by"; the "Other" line; empty and not-yet-synced states; what a tap on the card does. Sections 1, 4, 11. | not chosen | the design review's options | resolved by the design review, 20 Nov 2026 (DD2 to DD15 and the pass decisions) | the parents' answers D1 to D15 and 1A to 7B |

Approval readiness: PASS. Checked rows and answers: R1 (D1 A), R2 (D2 A), X1 (D4 A), X2 (D5 A),
X3 (D6 A), X4 (D7 B, deferred), X5 (D8 A), R3 (D9 A); the documents approved with the spec not
re-verified (D10 A). The "Counting rules" state what those answers require (spec review and
outside review findings); none adds a feature. Pending, not approved: E1, E2, DS1.

## Answered: currentDecision (R1)
D1 answered A, 20 Nov 2026 (see the ledger). Its full question and options were as follows.
Commitment comparison:

| Commitment | Source or approval | Current | A | B | C |
|---|---|---|---|---|---|
| DESIGN.md's rule against comparison | `DESIGN.md:297` | in force | replaced by a guarded rule | replaced by a guarded rule | kept |
| Where the parts show | pending (design review) | nowhere | a screen both parents see | the same, after a switch in Settings | History filter only |
| Guardrails: no winner, no score words, no red or green, both phones see the same | P1 | none | yes | yes | not needed |
| Effort | estimate | none | comes with R2 | comes with R2, plus one switch | S |

Question: D1 — R1: May the app show the two parents' parts side by side? Project: Little Log, the "who does what" plan. ELI10: You asked to see how much each of you does: feeds, nappies and the rest. The app's own design rules (15 Nov) say: "Don't show who fed more as a score; the parent colours show who, never a comparison." So we change that rule, or find a softer way. Both phones see the same screen. Research says parents often misjudge their own share, so facts help; but a screen that feels like a scoreboard can start an argument at 3am. Stakes if we pick wrong: a screen that feels like a contest hurts more than it helps; a screen too soft does not answer your question. Recommendation: A, because it answers your exact question, and the new rule keeps it from reading as a score. Note: options differ in kind, not coverage, so no completeness score. Net: a clear answer with a kinder rule (A), the same behind a switch (B), or no comparison at all (C).
Header: Side by side
A) A) Side by side, facts only (recommended)
Each parent's feeds, nappies, time and nights, in your two colours. New rule: no winner, no score words, no red or green, both phones see the same. Effort and risk come with the next question. ✅ Answers your question directly, on one screen, for a day, a week or more. ✅ The new rule is written into DESIGN.md, so later screens keep the same kind tone. ❌ Even plain facts side by side can feel like a contest on a hard day; the design review must get the tone right.
B) B) The same, but off until turned on
As A, but the screen stays hidden until either parent turns it on in Settings. Small extra effort (one switch), low risk. ✅ Nobody meets it by surprise; you choose together when to turn it on. ✅ Once on, the same facts and the same kind rule as A. ❌ One more switch to find, and once it is on, both phones see it anyway.
C) C) Keep the rule: History filter only
No comparison screen. History gets a "by parent" filter, and you count the entries yourself. Effort S (human about half a day, Claude about 20 minutes), low risk. ✅ Smallest change; the design rule stays exactly as it is. ✅ Each of you can still see all of one parent's entries in one list. ❌ Does not really answer your question: no totals, no time, no nights, lots of scrolling.

## Answered: currentDecision (R2)
D2 answered A, 20 Nov 2026 (see the ledger). Its full question and options were as follows.
Commitment comparison:

| Commitment | Source or approval | Current | A | B |
|---|---|---|---|---|
| A shared side-by-side screen | R1 approved | none | yes | yes |
| Whose part an entry counts in | F1, F11 | (nothing counted) | "done by": starts as the parent who logged it; a breastfeed or pumping starts as the parent who breastfeeds | the parent who logged it, always |
| Asked once: "Who breastfeeds?" | F10 (feeding style is per phone, not shared) | not asked | yes, one shared setting | no |
| Change it later | none | n/a | in the entry's editor | not possible |
| Old entries back to day one | F4 | n/a | counted, by the same starting rule | counted as logged |
| New stored data | `schema.ckdb` only grows | none | one detail per entry, kept only when changed | none |
| Counts, time and nights | plan, approach A | n/a | yes | yes |
| Accuracy (coverage) | F11, F12 unverified | n/a | 9/10 | 6/10 |
| Effort | estimate | none | M (human about 3 days, Claude about 1 to 2 hours) | S (human about 1 day, Claude about 40 minutes) |
| Risk | estimate | none | medium (a new stored detail both phones must agree on) | low (reads only) |

Question: D2 — R2: Whose part does each entry count in? Project: Little Log, the "who does what" screen (you chose: side by side, facts only). ELI10: Today the app knows only who TAPPED each entry, not who DID it. They differ when one of you logs for the other: one of you breastfeeds while the other taps Start feed on their phone or watch, or one of you logs a nappy the other changed because their phone was closer. A breastfeed or pumping can only be done by the parent who breastfeeds, whoever taps. If the screen counts by who tapped, those land in the wrong column, and a screen you don't trust is worse than none. Stakes if we pick wrong: wrong numbers start the very argument this is meant to settle; or we spend extra work where the simple count was good enough. Recommendation: A, because breastfeeds and "logged it for you" are exactly the cases that would put work in the wrong column, and most entries still need no change. Completeness: A=9/10, B=6/10. Net: a count you can trust and correct (A), against a quicker count that is sometimes wrong (B).
Header: Who did it
A) A) Count who did it, fixable (recommended)
Each entry has a "Done by". It starts as whoever logged it; a breastfeed or pumping starts as the parent who breastfeeds (asked once). Change it in the entry's editor when it is wrong. Effort M (human about 3 days, Claude about 1 to 2 hours), medium risk. ✅ Breastfeeds and pumping always land with the parent who breastfeeds, back to day one, with no extra tap. ✅ A wrong one is fixed in a few seconds, and both phones then agree. ❌ One more stored detail per entry, so more to build and test before you see it.
B) B) Count who tapped, as it is
Each entry counts for whoever logged it. Nothing new is stored, and the screen says "logged by". Effort S (human about 1 day, Claude about 40 minutes), low risk. ✅ Ready soonest, and works on everything already logged, with nothing new to keep in step. ✅ Can grow into A later if the numbers look wrong. ❌ A breastfeed logged on the other parent's phone or watch counts for the wrong parent, and can't be fixed.

## Answered: currentDecision (X1)
D4 answered A, 20 Nov 2026 (see the ledger). Its full question and options were as follows.
Commitment comparison:

| Commitment | Source or approval | Current | A | B | C |
|---|---|---|---|---|---|
| "Done by" fixable in the editor | R2 approved | yes | yes | yes | yes |
| "Done by" on the 10-second Undo bar | X1 pending | no | yes | later, in TODOS.md | no |
| Lock Screen, Control Center, watch taps | no bar there | fixed in the editor | fixed in the editor | fixed in the editor | fixed in the editor |
| Effort | estimate | none | S | S now (none) | S (none) |

Question: D4 — X1: Show "who did it" on the Undo bar after a quick log? Project: Little Log, the "who does what" screen. ELI10: After you tap Wee, Poo, Both, Fell asleep, Woke up or Given on Home, a bar shows for 10 seconds with Undo and Change time. This extra adds a small round picture there, showing who did it; one tap swaps it to the other parent. So when you log for the other parent, you fix it there and then, not later in the editor. Taps on the Lock Screen, in Control Center and on the watch have no bar, so those are still fixed in the editor. Stakes if we pick wrong: without it, wrong entries stay wrong unless someone opens each one; with it, the bar gets a little busier. Recommendation: A, because it fixes the most common mistake at the moment it happens, for little work. Note: options differ in kind, not coverage, so no completeness score. Net: fix it as you log (A), add it later (B), or fix only in the editor (C).
Header: Undo bar
A) A) Add it now (recommended)
A small picture of who did it on the Undo bar; one tap swaps it. Effort S (human about half a day, Claude about 20 minutes), low risk. ✅ Logging for the other parent is fixed with one tap, while you still remember. ✅ Uses the bar you already know, so there is nothing new to learn. ❌ The bar gets a third control; the design review must keep it calm on a small screen.
B) B) Later, on the to-do list
Written into TODOS.md to add after you have used the screen a while. No work now. ✅ Less to build now, and the editor still fixes any entry. ✅ You first see how often you log for each other. ❌ Until then, each mistake needs a trip into that entry's editor.
C) C) No
Not added, and not on the to-do list. No work. ✅ The Undo bar stays exactly as it is. ✅ Nothing more to build or test. ❌ Each mistake needs a trip into that entry's editor, with no plan to change that.

## Answered: currentDecision (X2)
D5 answered A, 20 Nov 2026 (see the ledger). Its full question and options were as follows.
Commitment comparison:

| Commitment | Source or approval | Current | A | B | C |
|---|---|---|---|---|---|
| Each parent's numbers on the shared screen | R1, R2 approved | yes | yes | yes | yes |
| Tap a number to open just those entries in History | X2 pending | no | yes | later, in TODOS.md | no |
| Fix a wrong "done by" from that list | R2 approved (the editor) | through History | one tap away | through History | through History |
| Effort | estimate | none | S | none now | none |

Question: D5 — X2: Tap a number to see the entries behind it? Project: Little Log, the "who does what" screen. ELI10: The new screen shows each parent's numbers, such as "12 nappies" or "3 night feeds". With this extra, you tap a number and History opens with just those entries: that parent, that kind, those days. You can check a number you doubt, and fix a wrong "done by" right there. Stakes if we pick wrong: without it, a number you doubt can only be checked by scrolling all of History and counting. Recommendation: A, because a number you can check is a number you both trust, and History's filter already exists to build on. Note: options differ in kind, not coverage, so no completeness score. Net: numbers you can check in one tap (A), later (B), or numbers you take on trust (C).
Header: Tap a number
A) A) Add it now (recommended)
Each number on the screen opens History with just its entries. Effort S (human about 1 day, Claude about 30 minutes), low risk. ✅ Any number you doubt is checked in one tap, so both of you can trust the screen. ✅ A wrong "done by" is found and fixed from the same list. ❌ History gets one more way to be opened, so a little more to build and test.
B) B) Later, on the to-do list
Written into TODOS.md to add after you have used the screen a while. No work now. ✅ Less to build now; History still holds every entry. ✅ You first see whether you ever doubt a number. ❌ Until then, checking a number means scrolling and counting by hand.
C) C) No
Not added, and not on the to-do list. No work. ✅ The screen stays simple: numbers only. ✅ Nothing more to build or test. ❌ A number you doubt can't be checked quickly, which is when arguments start.

## Answered: currentDecision (X3)
D6 answered A (not the recommended B), 20 Nov 2026 (see the ledger). Its full question and options were as follows.
Commitment comparison:

| Commitment | Source or approval | Current | A | B | C |
|---|---|---|---|---|---|
| Nights on the shared screen | R2 approved | yes | yes | yes | yes |
| A "Last night" card on Home, each morning until midday | X3 pending | no | yes | later, in TODOS.md | no |
| Home's tiles (Sleep, Nappy, Medicine, Next side, Last feed) | 06-more-than-feeds | as now | one more card each morning | as now | as now |
| Effort | estimate | none | M | none now | none |

Question: D6 — X3: A "Last night" card on Home each morning? Project: Little Log, the "who does what" screen. ELI10: Each morning until midday, Home would show a short card: last night's feeds, nappies and wake-ups, each with a small picture of who did it, and how long the baby slept. The parent who slept sees at a glance what happened. It is the first thing you see each day, so it must feel like a handover, not a score. Home already holds the Sleep, Nappy, Medicine, Next side and Last feed tiles. Stakes if we pick wrong: added too soon, Home gets busier and a daily who-did-what can feel like a score; left out, the night (the hardest part) stays one tab away. Recommendation: B, because the shared screen should be lived with first, and Home is already full; this is easy to add once the screen feels right. Note: options differ in kind, not coverage, so no completeness score. Net: a daily handover on Home now (A), later once the screen is tried (B), or not at all (C).
Header: Last night
A) A) Add it now
A "Last night" card on Home each morning until midday. Effort M (human about 2 days, Claude about 1 hour), medium risk. ✅ The parent who slept sees what happened, with no tab to open. ✅ Nights, the hardest part, get the place they deserve. ❌ Home gets one more card, and a daily who-did-what is the part most likely to feel like a score.
B) B) Later, on the to-do list (recommended)
Written into TODOS.md, to add once you have lived with the shared screen. No work now. ✅ Home stays as it is while you try the new screen. ✅ The card can copy whatever tone works on the screen. ❌ For now, last night is one tab away, on Graphs.
C) C) No
Not added, and not on the to-do list. No work. ✅ Home stays exactly as it is. ✅ Nothing more to build or test. ❌ Last night is always one tab away, with no plan to change that.

## Answered: currentDecision (X4)
D7 answered B, 20 Nov 2026 (see the ledger). Its full question and options were as follows.
Commitment comparison:

| Commitment | Source or approval | Current | A | B | C |
|---|---|---|---|---|---|
| The shared screen (week, 4 weeks, all) | R1, R2 approved | yes | yes | yes | yes |
| The "Last night" card on Home | X3 approved | yes | yes | yes | yes |
| A weekly look back, Sunday evening, with a quiet notice | X4 pending | no | yes | later, in TODOS.md | no |
| Effort | estimate | none | M | none now | none |

Question: D7 — X4: A weekly look back on Sunday evening? Project: Little Log, the "who does what" screen. ELI10: Each Sunday evening, a quiet notice would open a short page about the week: how many feeds, nappies and nights, who did which part, and the longest sleep. You have now chosen the shared screen (which can already show a week) and the "Last night" card each morning. The weekly page would be a third place for the same facts, and the only one that comes to you as a notice. Stakes if we pick wrong: added now, it repeats what the screen shows and adds a notice to your phones; left out, you might miss a calm weekly moment to talk it over. Recommendation: B, because the screen already shows a week and the morning card covers each night; a weekly notice is worth adding only if you find you want it. Note: options differ in kind, not coverage, so no completeness score. Net: a weekly page with a notice now (A), later if you want it (B), or not at all (C).
Header: Weekly
A) A) Add it now
A short weekly page and a quiet Sunday evening notice. Effort M (human about 2 days, Claude about 1 hour), medium risk. ✅ A calm, set moment each week to look at the load together. ✅ Nobody has to remember to open the screen. ❌ A third place for the same facts, and one more notice on both phones.
B) B) Later, on the to-do list (recommended)
Written into TODOS.md, to add if you find you want a weekly moment. No work now. ✅ No new notice while you try the screen and the morning card. ✅ The weekly page can copy whatever works on the screen. ❌ To see the week, you open the screen yourself.
C) C) No
Not added, and not on the to-do list. No work. ✅ No new notices, ever, for this. ✅ Nothing more to build or test. ❌ No weekly moment, with no plan to add one.

## Answered: currentDecision (X5)
D8 answered A (not the recommended B), 20 Nov 2026 (see the ledger). Its full question and options were as follows.
Commitment comparison:

| Commitment | Source or approval | Current | A | B | C |
|---|---|---|---|---|---|
| What counts: feeds, pumping, sleeps, nappies, medicines | R2 approved | yes | yes | yes | yes |
| Baths as a new kind of entry, counted too | X5 pending | no | yes | later, in TODOS.md | no |
| Home, History, the shared screen | approved above | as planned | a Bath button and a Bath row | as planned | as planned |
| Effort | estimate | none | M | none now | none |

Question: D8 — X5: Log baths too, so they count? Project: Little Log, the "who does what" screen. ELI10: Today the app logs feeds, pumping, sleeps, nappies, medicines, growth and firsts. Baths are real work too, but the app can't count what it doesn't log. This extra adds Bath as a new kind of entry: a button, a History row and a line on the shared screen. Other unlogged jobs (washing bottles, settling the baby without a feed) would still not count. Stakes if we pick wrong: added now, it is one more button on a busy Home and a new kind to build in every place; left out, bath time stays unseen on the screen. Recommendation: B, because a new kind of entry touches many places (Home, History, Graphs, the editors) and is its own small piece of work, best planned with any other jobs you want counted. Note: options differ in kind, not coverage, so no completeness score. Net: baths counted now (A), later with other jobs (B), or not at all (C).
Header: Baths
A) A) Add it now
A Bath button, a Bath row in History, and baths on the shared screen. Effort M (human about 2 days, Claude about 1 hour), low risk. ✅ Bath time counts, for whoever gives it. ✅ The diary also keeps a record of baths. ❌ One more button on Home and one more kind to build in every place, before you see the screen.
B) B) Later, on the to-do list (recommended)
Written into TODOS.md, to plan with any other jobs you want counted. No work now. ✅ The screen comes sooner, and you see what else you miss on it. ✅ Baths and other jobs get planned together, once. ❌ Until then, baths don't show on the screen.
C) C) No
Not added, and not on the to-do list. No work. ✅ Home keeps the buttons it has. ✅ Nothing more to build or test. ❌ Baths never count, with no plan to change that.

## Answered: currentDecision (R3)
D9 answered A, 20 Nov 2026 (see the ledger). Its full question and options were as follows.
Commitment comparison:

| Commitment | Source or approval | Current | A | B | C |
|---|---|---|---|---|---|
| A sleep counts for who settled the baby (Fell asleep) | "What counts", R2 | yes | yes | yes | yes |
| Who got up when the baby woke | X3 ("wake-ups, each with who did it") | not recorded | recorded: starts as who tapped Woke up (or Start feed, which ends a sleep), fixable | not recorded | who tapped Woke up, not fixable |
| Swap on the Woke up Undo bar | X1 (D4 A) | approved | swaps who got up | removed (Woke up has no swap) | removed |
| Wake-ups on the "Last night" card | X3 (D6 A) | approved | each with who got up | listed with no picture | each with who tapped, marked "logged by" |
| "Got up at night" per parent on the shared screen | R1 nights | not planned | yes | no | yes, as tapped |
| Coverage | spec review | n/a | 9/10 | 6/10 | 5/10 |
| Effort | estimate | none | S | none | none |

Question: D9 — R3: When the baby wakes, should the app record who got up? Project: Little Log, the "who does what" screen. ELI10: A sleep is one entry: Fell asleep starts it, Woke up ends it. Its "done by" is the parent who settled the baby. But you also chose (D4) a swap on the Woke up bar and (D6) a "Last night" card showing wake-ups with who did it. Today nothing records who got up when the baby woke, so the swap would change who SETTLED the baby, and the card would have no one to show. At night, who got up is often the part that matters most. Stakes if we pick wrong: without it, the card can't say who got up and the Woke up swap does the wrong thing; with it, one more small detail to build. Recommendation: A, because it makes your D4 and D6 choices work as you meant them, and "who got up" is the heart of the night. Completeness: A=9/10, B=6/10, C=5/10. Net: who got up, recorded and fixable (A); settler only, with no swap on Woke up (B); or who tapped, not fixable (C).
Header: Who got up
A) A) Record who got up (recommended)
Each sleep also keeps who got up when it ended: it starts as whoever tapped Woke up (or Start feed, which ends a sleep), the Woke up bar swaps it, and the sleep's editor fixes it. The card and the screen show it. Effort S (human about 1 day, Claude about 30 minutes), low risk. ✅ Your Woke up swap and your "Last night" card work as you meant them. ✅ The screen can show who got up at night, the part parents remember most. ❌ A sleep then has two "done by"s (settled and got up), so its editor has one more line.
B) B) Settler only, no swap on Woke up
A sleep counts only for who settled the baby. Woke up gets no swap on its bar, and the card lists wake-ups with no picture; the night's feeds and nappies still show who did them. No extra work. ✅ Simplest: one "done by" per entry, everywhere. ✅ Nothing new to build. ❌ Nobody can see who got up when the baby woke, and the D4 swap is narrowed.
C) C) Who tapped Woke up, not fixable
The card shows whoever tapped Woke up, marked "logged by"; no swap on the bar and no fix in the editor. No extra work. ✅ Shows something for each wake-up, at no cost. ✅ Often right, as the parent who gets up usually taps. ❌ Wrong whenever one of you taps for the other, with no way to fix it.

## CEO review outputs (20 Nov 2026)

### Outside voice

Codex (`gpt-6.2-sol`, high effort, CLI 0.171.0; about 858,000 input tokens, 757,000 of them cached,
and 4,900 output) answered with 8 findings but left out the required recommendation line, so the
check marked it unavailable; the backup reviewer (a Claude Plan helper) did not finish within five
minutes and was stopped. **No completed outside review.** The parent reviewer checked each of the
8 findings against the code and applied them as its own findings: 1 (an older phone can't finish a
running feed whose "done by" is in a newer details format) to E1; 2 (a "got up" belongs to one
ending), 3 (one tap, one wake-up), 4 (a worked-out "got up" is never stored by an unrelated edit),
5 (a feed pair keeps either copy's stored "done by"), 6 (the card joins overlapping sleeps), 7 (the
X2 list shows the time each row added) and 8 (the move maps the new details on a first move only)
to "Counting rules". All 8 resolved; 0 left open.

### Dream state delta

After this plan the app holds a record of who did what that both parents can check and fix, with
nights on their own line and a morning handover. Still short of the 12-month ideal: the weekly look
back (`TODOS.md`), work the app doesn't log (bottles washed, settling), and copies of non-feed
entries found automatically.

### Failure modes registry

```
  CODEPATH                 | FAILURE MODE                               | RESCUED? | TEST? | USER SEES?            | LOGGED?
  -------------------------|--------------------------------------------|----------|-------|-----------------------|--------
  resolver doneBy          | details unreadable or newer                | Y        | Y     | counted for logger    | N (no network)
  resolver doneBy          | member left the household                  | Y        | Y     | "Other" line          | N
  resolver gotUp           | ending replaced (reopened, ended again)    | Y        | Y     | the new ending's value| N
  resolver gotUp           | old sleep, end time edited by other parent | Y        | Y     | marked as worked out  | N
  shareFacts               | feed logged on both phones                 | Y        | Y     | counted once          | N
  shareFacts               | sleep/nappy logged on both phones          | partial  | Y     | counted twice; X2 shows both to delete | N
  older build              | finishes a feed with a newer "done by"     | E1 must  | E1    | (E1 must prevent)     | N
  move                     | repeat move after "done by" set in Dev     | Y        | Y     | not carried (stated)  | N
```

0 critical gaps (no row is unrescued, untested and silent).

### Scope expansion decisions

- Accepted: X1 (Undo bar swap), X2 (tap a number), X3 ("Last night" card), X5 (baths); and R3
  ("got up"), raised by the spec review.
- Deferred: X4 (weekly look back) to `TODOS.md`.
- Skipped: none.

### Diagrams produced

System architecture (Section 1), data flow with shadow paths (Sections 1 and 4), two state
machines ("got up", "done by"), the error map (Section 2), the user flow (Section 11) and the build
order (0I). Deployment and rollback are short enough to state in Section 9.

### Stale diagram audit

Files this plan touches with ASCII diagrams: this file only. `DESIGN.md` and `CLAUDE.md` hold none.
0 stale.

## Implementation Tasks
Synthesized from this review's findings. Each task derives from a specific
finding above. Run with Claude Code or Codex; checkbox as you ship. Tasks T1 to T10 wait for E1
(the engineering review) and the screens for DS1 (the design review).

- [ ] **T1 (P1, human: ~2d / CC: ~1.5h)** — FeedingCore — Bath kind, "breastfeeder" setting, the one resolver for "done by" and "got up"
  - Surfaced by: R2, R3, X5; Section 1 (one resolver)
  - Files: FeedingCore/Sources/FeedingCore/Model/Identifiers.swift, FeedingCore/Sources/FeedingCore/Model/Payload.swift, FeedingCore/Sources/FeedingCore/Store/HouseholdSettingsRecords.swift, FeedingCore/Sources/FeedingCore/Insights/Shares.swift (new)
  - Verify: `swift test --package-path FeedingCore`, resolver tests in Section 6
- [ ] **T2 (P1, human: ~1.5d / CC: ~1h)** — FeedingCore — "got up" through end, Undo, Stop · discard, the late-feed rule, one tap one wake-up, Change time
  - Surfaced by: R3; spec review round 2; outside findings 2, 3, 4
  - Files: FeedingCore/Sources/FeedingCore/Store/MoreThanFeeds.swift, FeedingCore/Sources/FeedingCore/Store/HouseholdData.swift
  - Verify: `swift test --package-path FeedingCore`, "got up" state machine tests
- [ ] **T3 (P1, human: ~2d / CC: ~1.5h)** — FeedingCore — share facts, last-night facts, the X2 entry list
  - Surfaced by: R1, X2, X3; "Counting rules"; outside findings 5, 6, 7
  - Files: FeedingCore/Sources/FeedingCore/Insights/Shares.swift (new), FeedingCore/Tests/FeedingCoreTests/SharesTests.swift (new)
  - Verify: `swift test --package-path FeedingCore`, including the time edge cases `CLAUDE.md` requires
- [x] **T4 (P1, human: ~2h / CC: ~15min)** — FeedingCore — the move maps "done by", "got up" and "Who breastfeeds?" on a first move
  - Surfaced by: spec review round 1; outside finding 8
  - Files: FeedingCore/Sources/FeedingCore/Store/HouseholdMove.swift, FeedingCore/Tests/FeedingCoreTests/HouseholdMoveTests.swift
  - Verify: `swift test --package-path FeedingCore`
- [ ] **T5 (P1, human: ~1d / CC: ~45min)** — App — "Done by" in the editors and add-later screens; "Got up" in the sleep editor
  - Surfaced by: R2, R3; spec review round 1
  - Files: App/Home/EventEditor.swift, App/Home/CareEditor.swift, the Earlier feed and Pumping screens (to be determined)
  - Verify: app build; a tap test that changes "done by"
- [ ] **T6 (P1, human: ~1d / CC: ~45min)** — App — the Undo bar swap and the Bath button
  - Surfaced by: X1, X5; "Which Undo bars get the swap"
  - Files: App/Home/FeedControls.swift, App/Home/CareTiles.swift, App/Home/CareText.swift, Shared/FeedShapes.swift
  - Verify: tap test: log, swap, Undo
- [ ] **T7 (P1, human: ~2d / CC: ~1.5h)** — App — the shared screen and "Who breastfeeds?"
  - Surfaced by: R1, R2; DS1
  - Files: App/Graphs/ (new view), App/Graphs/GraphText.swift, App/Home/SettingsView.swift
  - Verify: simulator with `-sampleData YES`; accessibility audit; the five Duo widths
- [ ] **T8 (P1, human: ~1d / CC: ~45min)** — App — X2's temporary History list with each row's counted time
  - Surfaced by: X2; outside finding 7
  - Files: App/Home/HistoryView.swift, App/Home/FeedRows.swift
  - Verify: tap test: each number equals its list's length and time
- [ ] **T9 (P1, human: ~1d / CC: ~45min)** — App — the "Last night" card on Home
  - Surfaced by: X3, R3
  - Files: App/Home/HomeView.swift
  - Verify: simulator at 07:30 and 12:01 with sample data
- [ ] **T10 (P1, human: ~1d / CC: ~45min)** — Storage and sync per E1, with the older-build tests
  - Surfaced by: E1; outside finding 1
  - Files: App/Sync/RecordMapping.swift (and schema.ckdb only if E1 picks a record field)
  - Verify: app tests (every field in `schema.ckdb`); an older build keeps the details and can finish a corrected running feed
- [ ] **T11 (P2, human: ~1h / CC: ~10min)** — Docs — DESIGN.md's new guarded rule and Decisions Log; CLAUDE.md layout line
  - Surfaced by: R1; Section 11
  - Files: DESIGN.md, CLAUDE.md
  - Verify: read back; the app's colour tests still pass
- [ ] **T12 (P2, human: ~1d / CC: ~1h)** — Tests — sample data flags and tap tests for the swap and X2
  - Surfaced by: Section 6
  - Files: App/Spikes/SampleData.swift, the FeedingDevUITests target
  - Verify: `xcodebuild test ... -scheme FeedingDevAudit` with the new tests

### Completion summary

```
  +====================================================================+
  |            MEGA PLAN REVIEW — COMPLETION SUMMARY                   |
  +====================================================================+
  | Mode selected        | SELECTIVE EXPANSION                         |
  | System Audit         | loggedBy on every entry; DESIGN.md:297      |
  |                      | forbade a comparison; nothing in flight     |
  | Step 0               | R1 A, R2 A; X1 X2 X3 X5 in, X4 deferred;    |
  |                      | R3 A from spec review; D10 approved         |
  | Section 1  (Arch)    | 1 issue found (E1, pending)                 |
  | Section 2  (Errors)  | 13 error paths mapped, 0 GAPS               |
  | Section 3  (Security)| 3 issues found, 0 High severity             |
  | Section 4  (Data/UX) | 10 edge cases mapped, 0 unhandled           |
  | Section 5  (Quality) | 0 issues found                              |
  | Section 6  (Tests)   | Diagram produced, 0 gaps                    |
  | Section 7  (Perf)    | 0 issues found                              |
  | Section 8  (Observ)  | 1 gap found (E2, pending)                   |
  | Section 9  (Deploy)  | 1 risk flagged (schema step if E1 = field)  |
  | Section 10 (Future)  | Reversibility: 4/5, debt items: 2           |
  | Section 11 (Design)  | 1 issue (DS1, pending)                      |
  +--------------------------------------------------------------------+
  | NOT in scope         | written (3 items)                           |
  | What already exists  | written (0B)                                |
  | Dream state delta    | written                                     |
  | Error/rescue registry| 13 rows, 0 CRITICAL GAPS                    |
  | Failure modes        | 8 total, 0 CRITICAL GAPS                    |
  | TODOS.md updates     | 1 item proposed (X4, deferred)              |
  | Scope proposals      | 5 proposed, 4 accepted (+R3)                |
  | CEO plan             | written                                     |
  | Outside voice        | codex unavailable (missing marker; 8        |
  |                      | findings applied by the parent); native     |
  |                      | fallback unavailable (5-minute limit)       |
  | Lake Score           | N/A (no question offered a 10/10 option)    |
  | Diagrams produced    | 7 (architecture, data flow, 2 state, error, |
  |                      | user flow, build order)                     |
  | Stale diagrams found | 0                                           |
  | Unresolved decisions | 3 (E1, E2, DS1; owned by later reviews)     |
  | Reality rows         | 7/7 rows (PLAN_REALITY complete), 4 unverified |
  +====================================================================+
```

```
PLAN_REALITY: phase=ceo rows=7/7 missing=none unverified=4: verdict=complete
```

## Design review (20 Nov 2026)

Rated 3/10 at the start ("it says what is counted, not what you see"). Mockups (made-up parents
"Sam" and "Alex", day and 3am): `~/.gstack/projects/<owner>-Feeding-Tracker/designs/who-does-what-20261120/`
(`round1.html` the screen, `round2.html` Home, `round3.html` the smaller parts; `approved.json`).
All choices are the parents' answers, 20 Nov 2026.

| # | Question | Answer |
|---|---|---|
| DD1 | Which parts to design | **All of them** (D1 A). |
| DD2 | The screen's look | **Nights dots, then shared bars** (D2 D, `round1.html` D). Top tile: "Nights · who got up", one column per night, one dot per wake-up in the colour of the parent who got up (bottom to top in time order), the night's short day name under it. Below: a tile headed "Together": per kind, the household's total on the right (SF Pro Rounded, fixed-width digits), one bar split in the two parent colours (16 pt tall, 2 pt gap between the parts, fully round ends), and under it "Sam 24" left and "Alex 7" right with a dot in each colour. Order: Feeds, Feeding time, Nappies, Settled to sleep, Medicines, Baths, Pumping. A kind with nothing in the range is left out. Each kind keeps its shape. |
| DD3 | Where it lives | **Its own page, opened from a tile at the top of Graphs** (D3 A). The tile: "Who did what · nights" with this week's nights dots and a ›; tap anywhere on it. The page has its own Day / 7 days / 4 weeks / All switch (Graphs keeps its own). |
| DD4 | The "Last night" card | **One slim line at the top of Home** (D4 A), under the greeting (and under an ask card, if one is showing), above the ring: a moon, "Last night", one dot per night entry in the colour of who did it (got up, for wake-ups), and "Slept 6h 40m ›" on the right, on `sleep-tint`. Tap: a sheet with the night's entries (time, shape, what, who), as `round2.html` B's card. |
| DD5 | Who did it on the Undo bar | **A small round picture with swap arrows, on the left** (D5 A). One tap swaps it. VoiceOver: "Done by Alex. Double-tap to change to Sam." |
| DD6 | Bath's look | **A water-blue of its own** (D6 B; A, no colour, was recommended): a tub shape in `bath-mark` on a `bath-tint` tile, half-width beside Medicine, with the last bath's day and one Bath button. New tokens `bath`, `bath-mark`, `bath-tint` and their night copies; the mockup used `#1F7F92` (mark) and `#DDF3F6` (tint), night `#3B7480` and `#0E1C1F`. Before building, the colour test must show it apart from the bottle's blue and the teal parent colour, with the usual contrast (marks 3:1 on their tiles); if it can't be, the parents are shown the nearest pair. |
| DD7 | The Undo bar everywhere (the parents' own ask, D5 and D7) | **A big card near the top of the screen, in Apple's Liquid Glass** (D7 A, "in Apple liquid glass style rather than a box with a lack of contrast"). Every Undo bar in the app (Home, History, Journal) moves from the bottom to just under the status bar, floating over the content: line 1, the swap picture (where it applies), what was logged (SF Pro Rounded 17 pt), and a × (44 pt target) that closes it at once; line 2, two big buttons, Change time (where it applies) and Undo, each at least 44 pt tall; a thin line shows the 10 seconds running out. Material: the system's Liquid Glass (`.glassEffect`), not a flat tile. **This departs from DESIGN.md's "Flat. No shadows, glows, gradients or blur"; the parents asked for it.** At night the glass stays dim (no bright refraction over the dark screen) and its text meets 4.5:1. |
| DD8 | "Who did it" in the editors | **As drawn** (D8 A): a "Who did it" section with both parents side by side (picture and name; the chosen one filled), and a line "Logged by Sam." under it. A sleep: "Settled by" and "Got up"; a running sleep shows only "Settled by". Feeds, pumping, nappies, medicines, baths, and the Earlier feed and Pumping screens. Not growth or firsts. |
| DD9 | The Graphs tile and the page | **As drawn** (D9 A), with a last line on the page: "Up to date with both phones · 07:38", or "Waiting for Alex's phone: last entry from it 2 hours ago." |
| DD10 | The list behind a number | **As drawn** (D10 A): its own list (back returns to the page), headed by the kind, with chips (parent · kind · range), the count or total on top, entries grouped by day with the counted parent's picture, and each row's time for a time number. A row opens its editor. History's saved filter is untouched. |
| DD11 | "Who breastfeeds?" | **Asked on the page, the first time** (D11 A): a sheet, "Who breastfeeds?", with Sam, Alex, Nobody and "Not now"; it comes back on each visit until answered (by either parent). A row in Settings changes it. |
| DD12 | History's pictures | **The big picture is who did it** (D12 A). A small second picture shows the other parent when they logged it or finished it (at most two pictures per row). VoiceOver reads "done by Sam, logged by Alex". |
| DD13 | Nothing to show yet | **As drawn** (D13 A): "Nothing logged in these 7 days yet. Each feed, nappy, sleep and bath you log shows here, with who did it."; before the other parent joins, "Alex hasn't joined yet. Once Alex joins on their own phone, their part shows here too."; the sync line as DD9. The Graphs tile shows empty nights with no dots. |
| DD14 | Outside design voices | **Yes, both** (D14 A). |
| DD15 | Logging the other parent's breastfeed on a bottle-only phone (the parents' own ask during this review) | **A third choice on Start feed** (D15 A). Once "Who breastfeeds?" names the other parent, a bottle-only phone's "Formula or expressed?" question (on the phone and on the watch's Start feed) gets a third choice, "Sam breastfeeding"; it starts a breastfeed with the Left / Right buttons, counted for that parent (the starting rule), and that phone's editors show Left and Right. With no answer, or "Nobody", nothing changes. Effort M. |


### Decisions from the 7 passes and the outside voices (20 Nov 2026)

Codex (`gpt-6.2-sol`) and a separate Claude helper read the plan after DD1 to DD15 (both completed,
8 and 14 findings). Each point below went to the parents one at a time.

| # | Question | Answer |
|---|---|---|
| 5A | Parent colours too faint as dots and bars (both reviewers; sunflower about 1.5:1 on `surface`) | **A deeper "mark" shade of each of the six parent colours (day and night) for dots and bars, at 3:1 or better on `surface` and `sleep-tint`, and the parent's initial inside every dot** (dots 16 to 17 pt). Mockup values: sunflower mark `#9C6B00` (3.85:1 on `surface`), teal mark `#1D7A6B` (4.30:1); the other four and the night copies are set in the build and tested, with every pair of choices checked against each other. |
| 1A | The nights dots beyond 7 days | **A view per range.** Day: that one night's entries in time order. 7 days: the dots. 4 weeks and All: a "Got up at night" shared bar instead of dots. **A night is named by its evening** (as Home's Nights row: "Tue" is Tuesday night into Wednesday) and counts in a range if that evening is in it; this replaces the "Counting rules" line that put a wake-up on the calendar day of its end. Daytime entries still go by calendar date. |
| 1B | Night feeds and nappies | **Under the dots, three shared bars: "Got up", "Night feeds" (count and time), "Night nappies"**, each opening its list. |
| 1C | Picking a day | **"Day" opens on today, with ‹ › arrows and the date between them ("Today", "Yesterday", "Thu 19 Nov"), and a left or right swipe also changes the day** (the parents' addition). The page opens on 7 days; each phone remembers the last range. |
| 1D | The sync line (reopens D9's wording) | **Only what this phone knows**: "Checked with iCloud 07:38" at the bottom; a failed check, or one older than 15 minutes, shows at the top before the numbers, in `notice`. Nothing about the other phone being behind. |
| 2A | "Not now" on "Who breastfeeds?" (reopens D11's "every visit") | **The sheet once per phone**; after "Not now", a quiet line at the top: "Breastfeeds count for whoever logged them · Set who breastfeeds ›" until answered. |
| 2B | Showing who changed "who did it" | **Silent** (the parents' choice; "Changed by" was recommended). The entry moves with no note. |
| 2C | Order, zeros, a changed row | **The same parent on the left on both phones (the household's owner); a zero is printed ("Alex 0") and the bar is one colour; a row changed in the list behind a number stays, with its new picture, until the list is left, and the count updates.** |
| 2D | Someone no longer in the household | **A grey third part at the end of the bar (`stone`-grey, `text-muted` label), "Other 2", only when there are any**, tappable like the rest. |
| 3A | The morning line could read as a tally (reopens D4's dots) | **Each night entry's own shape (feed, nappy, wake-up) in the colour of who did it, in time order, at most 8 then "+N"**; the line may wrap at large text; VoiceOver: "Last night: 3 feeds, 2 nappies, 2 wake-ups. Slept 6 hours 40 minutes." |
| 4A | The bars' heading | **"Who did what"** (not "Together"). |
| 4B | Wording of DD15's choice | **"Start a feed", with "Formula", "Expressed milk" and "Breastfeed (Sam)"**; the breastfeed is saved with an explicit "done by" Sam at once, so a later change to "Who breastfeeds?" never moves it; on the watch the double-tap stays on the bottle used most. |
| 5B | Rules for the glass Undo card | **Plain system glass** (the parents' choice; tinted-at-night, a solid fallback, a fading timer at night, a pause while touched and a restart rule were recommended). The 10-second line moves by day and night. iOS's own Reduce Transparency handling applies. **This keeps a moving element at night, against DESIGN.md's "fades only"; the parents accepted it.** |
| 6A | The page on the open Duo | **Two columns when open (594 pt and wider): nights on the left, "Who did what" on the right, the switch across the top**; one column when folded and on an ordinary iPhone. |
| 6B | VoiceOver, large text, tap sizes | **As listed:** each night column read as a sentence ("Tuesday night: Sam got up twice, Alex once"); each bar a sentence ("Feeds, 31: Sam 24, Alex 7"); each parent's number its own button, 44 pt tall or more, opening its list; at the largest text sizes the names and numbers under a bar stack on two lines and the night columns become a list of nights; the "Who breastfeeds?" sheet and the Undo card read their buttons in order. |
| 7A | Marking a worked-out "got up" | **A dashed outline on its picture wherever it shows; the sleep's editor says "Worked out from the log: tap to confirm or change"; VoiceOver adds "probably".** |
| 7B | History's small picture | **At most two pictures: big = who did it; small = the other parent when they logged or finished it (or both); VoiceOver and the editor say which.** |
| 8A | Redraw the mockups | **Yes:** `final.html` in the same folder shows the decided design, day and 3am. |

Changed by the passes: DD4's dots (now 3A's shapes), DD9's sync wording (now 1D), DD11's "every
visit" (now 2A), DD2's heading "Together" (now 4A), and the "Counting rules" night rule (now 1A).

### Pass ratings

| Pass | Before | After | Still short of 10 |
|---|---|---|---|
| 1. Information architecture | 3 | 9 | the Graphs tile's place above the rhythm report is untested on a real phone |
| 2. Interaction states | 2 | 8 | changes to "who did it" are silent (2B, the parents' choice) |
| 3. Journey and feeling | 3 | 8 | a comparison is still a comparison; only use will show the tone |
| 4. Specificity (no generic UI) | 4 | 9 | the Bath water-blue is a mockup value until tested |
| 5. Design system | 3 | 7 | the glass card (blur) and its moving timer at night depart from DESIGN.md, by the parents' choice (D7, 5B) |
| 6. Phone sizes and accessibility | 2 | 9 | checked only in mockups so far |

Overall (the lowest pass): 2 → 7. Pass 7: 2 resolved (7A, 7B), 0 deferred.

### Screens and states

```
  Graphs tab ──► tile "Who did what · last 7 nights" (dots with initials) ──► the page
  The page:  [Day | 7 days | 4 weeks | All]   (Day: ‹ Today › and swipe)
     ├─ problem banner (only if the iCloud check failed or is old)
     ├─ quiet line (only if "Who breastfeeds?" is unanswered)
     ├─ Nights: Day = that night in order │ 7 days = dots + 3 bars │ 4 weeks/All = bars
     ├─ Who did what: one shared bar per kind (+ grey "Other" when needed)
     └─ "Checked with iCloud 07:38"
     tap a number ──► its list (chips, count/total, rows) ──► row ──► editor ("Who did it")
     first visit ──► "Who breastfeeds?" sheet (once per phone)
  Home 07:00-12:00 ──► morning line (shapes in order) ──► tap ──► the night's sheet
  Home quick log ──► glass card at the top [who ⇄] what [×] / [Change time] [Undo]
  Bottle-only Start feed ──► "Start a feed": Formula · Expressed milk · Breastfeed (Sam)
```

| Feature | Loading | Empty | Error | Success | Partial |
|---|---|---|---|---|---|
| The page | none (local data) | "Nothing logged in these 7 days yet. Each feed, nappy, sleep and bath you log shows here, with who did it." | check failed or old: banner at the top in `notice` | nights and bars | other parent not joined: their part missing, with "Alex hasn't joined yet…"; "Who breastfeeds?" unanswered: the quiet line |
| Graphs tile | none | empty nights, no dots | none | the last 7 nights | a night still running shows its dots so far |
| List behind a number | none | the count is 0 only if the number was 0 (no tap then) | an entry removed while open leaves the list | chips, count, rows | a changed row stays until you leave |
| Morning line | none | no line (nothing logged in the night) | none | shapes in order, "Slept 6h 40m ›" | a feed still running at 07:00 shows by its start |
| Glass Undo card | none | none | an Undo that can't happen shows "OK" (as today) | Undo, Change time, swap, × | a new quick log replaces it |
| "Start a feed" (bottle-only) | none | before "Who breastfeeds?" names the other parent: today's two choices | none | three choices | none |

### Journey

| Step | Parent does | Parent feels | Plan specifies |
|---|---|---|---|
| 1 | Wakes, opens Home at 07:30 | groggy; "what happened?" | the morning line: the night as shapes, in order, with who (3A) |
| 2 | Taps it | reassured or curious | the night's sheet, each entry with its time and who |
| 3 | Later, opens Graphs | reflective | the tile with the week's nights (DD3) |
| 4 | Opens the page | "is it fair?" | facts only, one shared bar per kind, no winner (R1, DD2, 4A) |
| 5 | Doubts a number | sceptical | taps it; the list with its count; fixes a row (X2, D10) |
| 6 | Logs a nappy for the other parent | rushed | swaps who did it on the glass card (X1, D5, D7) |
| 7 | Logs the other parent's breastfeed on a bottle-only phone | wants it right | "Breastfeed (Sam)" (D15, 4B) |

5-second: the morning line and the dots read at a glance. 5-minute: every number can be checked
and fixed. 5-year: a calm record of who carried which nights, never a score.

### Outside voices: litmus scorecard

```
  Check                                    Claude  Codex  Consensus
  1. Product unmistakable in first screen?  YES     NO     DISAGREE (empty state lacks cues; now has its words, D13)
  2. One strong visual anchor?              NO      YES    DISAGREE (only at 7 days; fixed by 1A)
  3. Scannable by headlines only?           YES     NO     DISAGREE ("Together"; fixed by 4A)
  4. Each section has one job?              YES     YES    CONFIRMED
  5. Cards actually necessary?              YES     YES    CONFIRMED
  6. Motion improves hierarchy?             NO      NO     CONFIRMED failure (the timer; 5B kept it, the parents' choice)
  7. Premium without decorative shadows?    YES     YES    CONFIRMED
  Hard rejections triggered:                none    none   none
```

### What already exists (design)

`DESIGN.md` tokens, Fredoka and SF Pro Rounded rules, `Tile`, `Chip`, `Avatar`, the parent colours,
the kind shapes in `Shared/FeedShapes.swift`, the Graphs tab's tiles and switch, History's rows
(`FeedRows.swift`, with the existing finisher picture), `UndoBanner` (`FeedControls.swift:24`), the
Nights row's naming of nights by their evening, and the bottle-only "Formula or expressed?" question
(`FeedControls.swift:134`). All reused.

### NOT in scope (design)

- "Changed by" notes (2B: the parents chose silent).
- Tinting, a solid fallback, a fading timer and a pause for the glass card (5B: the parents chose
  plain system glass).
- Baths on the morning line, the Lock Screen, Control Center or the watch (CEO review).

### Approved Mockups

| Screen/Section | Mockup Path | Direction | Notes |
|----------------|-------------|-----------|-------|
| The page (look) | ~/.gstack/projects/<owner>-Feeding-Tracker/designs/who-does-what-20261120/round1.html | D: nights dots, then shared bars | heading "Who did what" (4A); per-range views (1A, 1B) |
| Home (morning line, swap, Bath) | ~/.gstack/projects/<owner>-Feeding-Tracker/designs/who-does-what-20261120/round2.html | A slim line; picture swap; Bath water-blue | the line now shows shapes (3A); the Undo card moved to the top (D7) |
| Smaller parts | ~/.gstack/projects/<owner>-Feeding-Tracker/designs/who-does-what-20261120/round3.html | A for each row | sync line (1D) and "Not now" (2A) changed after |
| As decided | ~/.gstack/projects/<owner>-Feeding-Tracker/designs/who-does-what-20261120/final.html | all decisions | the reference for building |

### Design implementation tasks

These add to the CEO review's T1 to T12 above (T5 to T9 there cover the same screens).

- [ ] **DT1 (P1, human: ~4h / CC: ~20min)** — Design tokens — the six parent "mark" shades (day and night) and the Bath colours, with tests
  - Surfaced by: 5A, D6
  - Files: App/Design/Theme.swift, DESIGN.md, the app's Theme colour tests (AppTests)
  - Verify: the colour tests pass (3:1 marks on `surface` and `sleep-tint`, initials 4.5:1, every parent pair and Bath against bottle and teal told apart)
- [ ] **DT2 (P1, human: ~1d / CC: ~45min)** — Undo card — every Undo bar to the top, bigger, with ×, in system glass, with the swap picture
  - Surfaced by: D5, D7, 5B
  - Files: App/Home/FeedControls.swift, App/Home/HomeView.swift, App/Home/HistoryView.swift, App/Journal/JournalView.swift
  - Verify: tap tests (`HistoryDeleteFlowTests` and the others that use Undo) updated and passing; the audit at large text
- [ ] **DT3 (P1, human: ~2d / CC: ~1.5h)** — The page — per-range nights (1A, 1B), the day picker with swipe (1C), the sync line and banner (1D), the quiet line (2A), fixed order and zeros (2C), "Other" (2D), heading (4A), two columns on the open Duo (6A)
  - Surfaced by: Passes 1, 2, 4, 6
  - Files: App/Graphs/ (new views), App/Graphs/GraphText.swift
  - Verify: simulator with `-sampleData YES -sampleWeek 30` at each range, day and night; the five Duo widths
- [ ] **DT4 (P1, human: ~4h / CC: ~25min)** — Home's morning line as shapes in order, with its sheet
  - Surfaced by: D4, 3A
  - Files: App/Home/HomeView.swift
  - Verify: simulator at 07:30 and 12:01; VoiceOver sentence
- [ ] **DT5 (P1, human: ~1d / CC: ~45min)** — "Start a feed" with "Breastfeed (Sam)" on a bottle-only phone and watch; Left and Right in that phone's editors; explicit "done by"
  - Surfaced by: D15, 4B
  - Files: App/Home/FeedControls.swift, App/Home/EventEditor.swift, Watch/App/WatchHomeView.swift
  - Verify: tap test on a bottle-only phone; watch simulator with `-sampleWatch faceStart`
- [ ] **DT6 (P2, human: ~3h / CC: ~20min)** — History's pictures (7B) and the dashed outline for a worked-out "got up" (7A)
  - Surfaced by: D12, 7A, 7B
  - Files: App/Home/FeedRows.swift, App/Home/CareEditor.swift
  - Verify: VoiceOver reads "done by Sam, logged by Alex"
- [ ] **DT7 (P2, human: ~3h / CC: ~20min)** — "Who breastfeeds?" sheet once per phone, and its Settings row
  - Surfaced by: D11, 2A
  - Files: App/Home/SettingsView.swift, App/Graphs/ (the page)
  - Verify: tap test: Not now, then the quiet line; answer, then it goes
- [ ] **DT8 (P2, human: ~2h / CC: ~15min)** — DESIGN.md — the new guarded rule in place of line 297, the glass exception and its moving timer, the mark and Bath tokens, four tabs, the Graphs tile; Decisions Log rows
  - Surfaced by: R1, D7, 5B, 5A, D6; the out-of-date "three tabs"
  - Files: DESIGN.md
  - Verify: read back; the colour tests read the new tokens
- [ ] **DT9 (P2, human: ~4h / CC: ~30min)** — Accessibility as listed in 6B
  - Surfaced by: 6B
  - Files: the new views above
  - Verify: `xcodebuild test ... -scheme FeedingDevAudit` and read the AUDIT lines

## Design Review Completion Summary

```
  +====================================================================+
  |         DESIGN PLAN REVIEW — COMPLETION SUMMARY                    |
  +====================================================================+
  | System Audit         | DESIGN.md present (says 3 tabs; app has 4); |
  |                      | UI scope: page, Home, editors, History,     |
  |                      | Undo bar, Start feed, watch                 |
  | Step 0               | 3/10; all parts (D1 A)                      |
  | Pass 1  (Info Arch)  | 3/10 → 9/10 after fixes                     |
  | Pass 2  (States)     | 2/10 → 8/10 after fixes                     |
  | Pass 3  (Journey)    | 3/10 → 8/10 after fixes                     |
  | Pass 4  (AI Slop)    | 4/10 → 9/10 after fixes                     |
  | Pass 5  (Design Sys) | 3/10 → 7/10 after fixes                     |
  | Pass 6  (Responsive) | 2/10 → 9/10 after fixes                     |
  | Pass 7  (Decisions)  | 2 resolved, 0 deferred                      |
  +--------------------------------------------------------------------+
  | NOT in scope         | written (3 items)                           |
  | What already exists  | written                                     |
  | TODOS.md updates     | 0 items proposed                            |
  | Approved Mockups     | 4 pages made, 4 approved                    |
  | Decisions made       | 30 added to plan                            |
  | Decisions deferred   | 0                                           |
  | Overall design score | 2/10 → 7/10                                 |
  +====================================================================+
```

Pass 5 stays at 7 because the parents chose the glass card and its moving timer at night over
DESIGN.md's flat, still night look (D7, 5B). No design decision is unresolved.

## Engineering review (20 Nov 2026)

Target: this plan, `docs/planning/09-who-does-what.md` (fixed for the whole review). Report file:
this file. The branch's design doc is the journal's, so this plan is the source of truth. Asked
by the parents after the design review; the build waits for it.

### Scope record

Complexity gate: about 35 changed files and 6 new parts [estimated from T1-T12 and DT1-DT9], so
the gate tripped. No feature cut or deferral was proposed: every part is a parents' answer.

- feature answers: none asked (no cut proposed);
- structure: **A) Smaller arrangement**, D1 answer "A) Smaller arrangement (recommended)", 20 Nov
  2026. One entries list, built from History's existing rows (`FeedRows.swift`), serves both the
  list behind a number (X2, DD10: chips, count or total, day groups, the counted parent's picture,
  each row's time) and the "Last night" sheet (DD4: time, shape, what, who, and how long the baby
  slept). Same look as `final.html`. About 34 files and 5 new parts [estimated];
- accepted scope: every approved CEO and design answer (R1 to R3, X1, X2, X3, X5, DD1 to DD15,
  1A to 8A), unchanged, built in the smaller arrangement;
- pending remedies: E1 (where "done by" and "got up" are stored), E2 (the Feeding Dev debug
  screen).

Scope Challenge result: scope accepted as-is (a smaller arrangement that keeps the scope is not a
reduction).

### Scope Challenge findings

- SC1 [INFORMATIONAL] (confidence: 9/10) `docs/planning/09-who-does-what.md:866` — T5 lists "the
  Earlier feed and Pumping screens (to be determined)". They are modes of `EventEditor`
  (`App/ContentView.swift:320`: `EventEditor(mode: .newPump, me: me, babyID: babyID)`). Factual
  correction, no behaviour change: T5's files are `EventEditor.swift` and `CareEditor.swift`.
- Search check (web search; Aside was signed out): [Layer 1] CloudKit saves only the fields a
  client sets, so a field an older app version doesn't know keeps its value in iCloud (Christian
  Selig, "CKSyncEngine questions and answers", Jan 2026, citing `setObject`); unverified on this
  app's own records until the Dev probe in E1. [Layer 1] Apple's answer for an app update that
  starts reading a new field: "refetch all records" once, as a device that ran the older version
  got no change for it (Apple Developer Forums thread 763641, Frameworks Engineer). Discarding
  CKSyncEngine's saved state makes it fetch everything again; its own waiting list goes with it,
  but this app re-queues its waiting changes from its own file (`HouseholdSync.swift:248`).
- TODOS.md: nothing blocks this plan; the one item (weekly look back) stays deferred.
- Distribution: no new app or target. Little Log build 2 through TestFlight; Feeding Dev first.

Dispositions: SC1 recorded as a correction (no question needed).

### Section 1: Architecture

Findings, most severe first:

- A1 = E1 [CRITICAL] (confidence: 9/10) `FeedingCore/Sources/FeedingCore/Store/HouseholdData.swift:279`
  — `guard before.payload != nil else { return false }`: a phone refuses every edit (finish, end,
  delete, change) of an entry whose details it can't read, and `PayloadCoder.decode` returns nil for
  a details version above its own (`Payload.swift:187`: `probe.v <= T.currentVersion`). Storing
  "done by" or "got up" in the details means raising their version, so an older build is stuck on
  those entries. Blocks the build: nothing can be stored until E1 is chosen.
- A2 [INFORMATIONAL] (confidence: 9/10) `FeedingCore/Sources/FeedingCore/Insights/QuickFeed.swift:87`
  — `_ = finishFeed(running.id, by: member, now: now)` ignores a refused finish, then returns
  `.finished(...)`: the Lock Screen, Control Center, Siri and the watch say a feed finished when it
  didn't. Today no feed's details are above version 1, so it can't happen yet; any later version
  raise on feeds would trigger it.
- A3 = E2 [INFORMATIONAL] (confidence: 8/10) `App/Spikes/HouseholdDebugView.swift:268` — the debug
  list shows each entry's logger ("this phone" or the member) and nothing else about who: with two
  new stored values, a wrong number can only be traced through the X2 list.
- A4 [INFORMATIONAL] (confidence: 8/10) `docs/planning/09-who-does-what.md:409` — design-twice on
  the new `Insights/Shares.swift` (below): the plan's shape is per-entry lookups each screen calls.
- A5 [INFORMATIONAL] (confidence: 8/10) `docs/planning/09-who-does-what.md:139` — "How the tap is
  remembered (for example an ID shared by those sleeps): the engineering review." Still open.
  `MoreThanFeeds.swift:29` (`endSleep(babyID:at:by:now:)`) ends every running sleep with one `now`
  and one member, so each gets the same `endedAt` stamp.

**Design-twice (new module `Insights/Shares.swift`).**

- Shape 1 (the plan): free functions `doneBy(entry)`, `gotUp(sleep)`, `shareFacts(range)`,
  `lastNight()`, `entries(for:)`, each screen calling the per-entry lookups as it draws.
- Shape 2: one value, `WhoDidIt`, worked out once per store change from the events and the
  "Who breastfeeds?" setting. It holds, per live entry, the counted parent and whether that was
  stored or worked out (feed pairs and one-tap wake-ups already joined), and answers
  `facts(range)`, `lastNight(now)` and `entries(for:)` from that one table. History's rows, the
  editors' first choice and the Undo bar's picture read the same table.
- Depth: Shape 2 hides the starting rule, the duplicate-pair rule (later stamp wins), the one-tap
  wake-up joining and the worked-out mark behind one value with three questions; Shape 1 leaves
  each caller to apply the pair and wake-up rules around the lookups.
- Red flags in Shape 1: 2 (information leakage: the starting rule could be copied into History's
  rows and the Undo bar), 6 (two ways: `loggedBy` and "done by" both near at hand in History), 8
  (hand-synced list: the kinds that count appear in the facts, in `EventField.fields(for:)`, in
  the editors and in X1's list of Undo bars). Fix for 8 in either shape: one
  `EventKind.countsAsWork` used by all four.

### Decision ledger (engineering review)

#### E1: where "done by" and "got up" are stored
Finding: A1, CRITICAL, confidence 9/10, `HouseholdData.swift:279` and `QuickFeed.swift:87`,
reviewer: Claude (this review), first raised by the CEO review's outside voice (finding 1).
Plan baseline: not chosen; the plan names "a payload field (encrypted, no schema change; needs a
payload version)" or "a top-level record field (`schema.ckdb` grows, Production needs the parents'
go-ahead)" (ledger row E1, line 610). R2, R3, X1 and 4B (a "Breastfeed (Sam)" feed saved with an
explicit "done by" at once) are approved and fixed.
Runtime evidence: an older build refuses to edit details above its version (`HouseholdData.swift:279`,
`Payload.swift:187`). Its record save sets only the fields it knows (`RecordMapping.swift:29-43`),
and CloudKit keeps fields a save doesn't set (outside source; unverified here). It drops a field
it doesn't know from its own file (`Event` is plain `Codable`, `Event.swift:8`). Field stamps are
string-keyed and kept by older builds (`Payload.swift:109`). The move copies `Event` values
(`HouseholdMove.swift:270`).
Comparison grid:

| Choice | Current | A | B |
|---|---|---|---|
| Where the two values live | not stored (pending) | 3 new encrypted fields on the `Event` record: `doneBy` (STRING), `gotUpBy` (STRING), `gotUpFor` (TIMESTAMP, the end it belongs to) | inside the encrypted details (`EventPayload`), version 5 only when set |
| Their change stamps | n/a | in the details' stamps (`doneBy`, `gotUp`), which older builds keep | the same |
| Older build: show, finish, end, change, delete such an entry | n/a | yes, all | refused for every entry with a stored value: each sleep ended on the new build, each Undo-bar swap, each "Breastfeed (Sam)" feed from its start |
| Older build keeps the values | n/a | in iCloud (Dev probe to prove it); dropped from that phone's own file | kept unread in its file |
| A phone updating from an older build | n/a | re-fetches the household zone once at first launch (discards the sync engine's saved place; the app re-queues its own waiting changes) | reads them at once |
| `schema.ckdb` and Production | unchanged | +3 fields to `Event`; Dev import; Production deploy with the parents' go-ahead (asked again then) before Little Log build 2 ships | unchanged |
| Apple can read them | `loggedBy` only | no (encrypted) | no (encrypted) |
| 4B "Breastfeed (Sam)" saved at once | approved | unchanged | unchanged; an older phone can't finish that feed |
| Proof | none | Dev probe: an older build saves an entry and the 3 fields survive; tests for the stamps, the merge in both orders, the move, and the one re-fetch | tests for version 5, the merge, the move; an older build refusing such entries |
| A2 (honest quick finish) | pending | pending | pending |
| E2, A4, A5 | pending | pending | pending |
| Effort | none | human ~2 days / CC ~1.5 h | human ~1.5 days / CC ~45 min |

Question D2:
D2 — Where should the app save "who did it" and "who got up"?
Project/branch/task: Little Log, the "who does what" plan, engineering review (branch claude/focused-hamilton-47r7qx).
ELI10: Each entry is saved in iCloud in two parts: a few labels on the outside (when it started, who logged it) and a locked box of details inside. We must save two new facts: who did it, and who got up. Option A adds them as three new locked labels on the outside. An older copy of the app (for example Little Log build 1, if one of you hasn't updated yet) ignores labels it doesn't know, so it keeps working. Option B puts them in the locked box. Then the box must be marked "new style", and an older copy of the app can't open it: on that phone those entries can't be finished, ended, changed or deleted, and their details don't show. That would include every sleep ended on the new app and every "Breastfeed (Sam)" feed.
Stakes if we pick wrong: with B, a phone that is one update behind can get stuck, with a feed it can't finish or a sleep it can't end; with A, iCloud's live layout grows by 3 labels, for good.
Recommendation: A because older phones keep working on every entry and nothing is lost; the layout change only adds.
Completeness: A=9/10, B=5/10
Pros / cons:
A) Older phones keep working (recommended)
  ✅ A phone one update behind can still finish, end, change and delete every entry
  ✅ No entry's details are hidden from an older phone, and nothing is lost on any phone
  ❌ iCloud's live layout grows by 3 labels, for good; it needs your go-ahead, and I ask again first
  ❌ The first launch of the new app re-reads the household from iCloud once (a few seconds)
B) Keep iCloud's layout as it is
  ✅ No change to iCloud's live layout, so no go-ahead step before the release
  ✅ A little less to build: about half a day less for a person, 45 minutes less for me
  ❌ An older phone can't finish, end, change or delete the entries that have the new facts
  ❌ Both phones must update at the same time, or entries get stuck on the older phone
Net: older phones keep working, for a permanent 3-label layout change (A); or no layout change, but both phones must update together (B).
Header: Where saved
Options:
A) Older phones keep working (recommended)
Three new locked (encrypted) labels on each entry: who did it, who got up, and which ending that belongs to. Older copies of the app ignore them and keep working. iCloud's layout grows by 3 labels: Feeding Dev first, then the live one with your go-ahead (asked again then) before Little Log build 2. The new app re-reads the household once after its update. A test on Feeding Dev proves an older copy keeps the labels. Effort: human ~2 days / me ~1.5 hours.
B) Keep iCloud's layout as it is
The two facts go inside the locked details box, marked "new style". No change to iCloud's layout. An older copy of the app can't open those boxes, so on it those entries can't be finished, ended, changed or deleted, and both phones must update together. Effort: human ~1.5 days / me ~45 minutes.

State: approved
Actual answer: A) Older phones keep working (recommended), D2 answer, 20 Nov 2026.
Accepted scope: "done by" and "got up" are stored as new encrypted fields on the `Event` record,
`doneBy` (ENCRYPTED STRING), `gotUpBy` (ENCRYPTED STRING) and `gotUpFor` (the ending it belongs
to; amended by A5's D8 A: `gotUpFor` is ENCRYPTED STRING holding the wake-up ID, and a fourth field
`wakeID` (ENCRYPTED STRING) is added, so 4 fields in all); their change stamps go in the details' string-keyed stamps (`doneBy`,
`gotUp`); the details' version is not raised. `Event`, `RecordMapping` (both directions, through
`encryptedValues`), the merge, the move and the household file carry them. `schema.ckdb` gains the
3 fields: imported into the Dev container's Development environment first, then deployed to the
real container's Production **only after the parents' go-ahead is asked again at that step**, and
before Little Log build 2 ships. A phone that ran an older build meanwhile fetches the entries
whose values it dropped and gets them back (how: E3, D9 A, which replaced D7 A's full re-read and
the first-launch marker); the sync engines are never reset. Proof: a Dev probe (an older Feeding
Dev build saves an entry that has the 3 fields; they survive in iCloud), and FeedingCore tests for
the stamps, the merge in both orders, the move mapping, and an older build's file keeping the
stamps. The app test that every field written is in `schema.ckdb` covers the new fields. The
Dev probe uses a Feeding Dev build of commit `c4fedda` (Little Log build 1's commit) and covers a
plain save and a save clash (`serverRecordChanged`, merge, save again), and a bath entry on its
Home and History (outside voice, Claude subagent findings 4 and 8).
History: raised by the CEO review (ledger row E1) and its outside voice (finding 1); owner: this review.

#### A2: a quick finish that couldn't finish says so
Finding: A2, INFORMATIONAL, confidence 9/10, `QuickFeed.swift:87` (`_ = finishFeed(running.id, by:
member, now: now)`, then `return .finished(...)`), reviewer: Claude (this review).
Plan baseline: not in the plan (T10's check "can finish a corrected running feed" covers the app,
not the quick actions).
Runtime evidence: `finishFeed` returns false only when the feed is unknown or its details can't be
read (`HouseholdData.swift:277-279`); a running feed is found first, so only unreadable details
remain. No feed's details are above version 1 today (`Payload.swift:128-131`), and E1's answer
keeps it so, so this can't happen yet.
Comparison grid:

| Choice | Current | A | B |
|---|---|---|---|
| Quick finish (Lock Screen, Control Center, Siri, watch) when the finish is refused | says "finished" | says it couldn't finish, and to open Little Log | says "finished" (as now) |
| Test | none | a FeedingCore test with a feed whose details are newer | none |
| E1 | approved (A) | unchanged | unchanged |
| E2, A4, A5 | pending | pending | pending |
| Effort | none | human ~2 h / CC ~15 min | none |

Question D3:
D3 — If a feed can't be finished from the Lock Screen or the watch, should it say so?
Project/branch/task: Little Log, the "who does what" plan, engineering review (branch claude/focused-hamilton-47r7qx).
ELI10: Finish feed on the Lock Screen, in Control Center, by Siri or on the watch always answers "finished", even when the phone refused to finish it. Today that can't happen, and your last answer keeps it so. But a later update could change how a feed's details are saved, and then an older phone would say "finished" at 3am when the feed is still running. The fix is small: say "Couldn't finish the feed here. Open Little Log." instead.
Stakes if we pick wrong: a parent trusts a "finished" that didn't happen; or we spend a little time on a case that can't happen today.
Recommendation: A because it is small, and a wrong "finished" at night is the kind of quiet mistake this app avoids.
Completeness: A=9/10, B=6/10
Pros / cons:
A) Say it couldn't finish (recommended)
  ✅ The Lock Screen, Siri and the watch never claim a finish that didn't happen
  ✅ One small test guards it, so a later update can't bring the problem back unseen
  ❌ About 2 hours for a person (15 minutes for me) on a case that can't happen today
B) Leave it as it is
  ✅ No work now; it can't happen while feed details stay in today's format
  ✅ Nothing changes in the quick actions you already use every day
  ❌ A later update could make an older phone say "finished" for a feed still running
Net: a small guard now (A), or a known gap left for a later update to trip over (B).
Header: Quick finish
Options:
A) Say it couldn't finish (recommended)
When a quick finish is refused, the Lock Screen, Control Center, Siri and the watch say "Couldn't finish the feed here. Open Little Log." instead of "finished". One FeedingCore test. Effort: human ~2 hours / me ~15 minutes.
B) Leave it as it is
Quick finish keeps saying "finished" in every case. No work now. Fixed only if a later update changes how feed details are saved.

State: approved
Actual answer: A) Say it couldn't finish (recommended), D3 answer, 20 Nov 2026.
Accepted scope: `quickFinishFeed` returns a "couldn't finish" result when `finishFeed` refuses
(instead of `.finished`), and every quick path that shows its result (the Lock Screen and Control
Center actions, Siri, and the watch through `WatchRelay`) says "Couldn't finish the feed here. Open
Little Log." One FeedingCore test: a running feed whose details are newer than this build gives
that result and stays running.
History: found by this review while checking E1.

#### E2: "done by" and "got up" in Feeding Dev's debug screen
Finding: A3 = E2, INFORMATIONAL, confidence 8/10, `App/Spikes/HouseholdDebugView.swift:268`
(`let who = snapshot.event.loggedBy == me ? "this phone"`), reviewer: CEO review (Section 8), this
review.
Plan baseline: not planned (ledger row E2: "add; leave out", pending).
Runtime evidence: each debug row shows the start, the details and a status line naming the logger
(`HouseholdDebugView.swift:243-269`); Feeding Dev only.
Comparison grid:

| Choice | Current | A | B |
|---|---|---|---|
| Each entry line in Feeding Dev's household debug screen | start, details, who logged it | adds "done by <who>", marked "saved" or "worked out", and for an ended sleep "got up <who>", marked "saved" or "worked out", with the end it belongs to | as now |
| Little Log | no debug screen | unchanged | unchanged |
| E1, A2 | approved (A, A) | unchanged | unchanged |
| A4, A5 | pending | pending | pending |
| Effort | none | human ~1 h / CC ~10 min | none |

Question D4:
D4 — Show "who did it" and "who got up" on Feeding Dev's test screen?
Project/branch/task: Little Log, the "who does what" plan, engineering review (branch claude/focused-hamilton-47r7qx).
ELI10: Feeding Dev (the test copy of the app) has a hidden screen that lists every entry with who logged it. It is where I look on a real phone when something seems wrong. Option A adds the two new facts to each line, and says whether a parent saved them or the app worked them out. Little Log itself doesn't change.
Stakes if we pick wrong: without it, a wrong number on a phone takes guesswork to explain; with it, a small extra on a screen only I use.
Recommendation: A because when a count looks wrong, the reason shows in seconds on the real phone.
Completeness: A=9/10, B=7/10
Pros / cons:
A) Add them to the test screen (recommended)
  ✅ A wrong number on a real phone can be explained in seconds, not guessed at
  ✅ It shows "saved" or "worked out", which is exactly where a count can go wrong
  ❌ About an hour for a person (10 minutes for me) on a screen only I use
B) Leave the test screen as it is
  ✅ No work now; the list behind each number already shows who it counted
  ✅ The test screen stays short and simple to read
  ❌ The list behind a number can't say whether a value was saved or worked out
Net: a quick way to explain a wrong number (A), or rely on the list behind each number (B).
Header: Test screen
Options:
A) Add them to the test screen (recommended)
Feeding Dev's household test screen shows, on each entry, who did it and, for a sleep, who got up, each marked "saved" or "worked out", with the end it belongs to. Little Log doesn't change. Effort: human ~1 hour / me ~10 minutes.
B) Leave the test screen as it is
No change. A wrong number is checked through the list behind it on the "who did what" page.

State: approved
Actual answer: A) Add them to the test screen (recommended), D4 answer, 20 Nov 2026.
Accepted scope: each entry line in Feeding Dev's household debug screen
(`App/Spikes/HouseholdDebugView.swift`) adds "done by <who>", marked "saved" or "worked out", and
for an ended sleep "got up <who>", marked "saved" or "worked out", with the end it belongs to.
Little Log is unchanged.
History: raised by the CEO review (Section 8, ledger row E2); owner: this review.

#### A4: "who did it" worked out once, in one place
Finding: A4, INFORMATIONAL, confidence 8/10, `docs/planning/09-who-does-what.md:409`
(`doneBy(entry) / gotUp(sleep)   ◄── one resolver ──►` and `shareFacts(range) / lastNight() /
entries(for:)`), reviewer: Claude (this review, design-twice).
Plan baseline: one resolver used by every screen "so a number and its list never differ" (CEO
Section 1 and 0I, approved with the documents, D10 A); its shape (per-entry lookups) was not asked.
Runtime evidence: none yet (new code). The rules each caller must apply exist today in separate
places: duplicate pairs (`HistoryView.swift:25`), one tap ending several sleeps
(`MoreThanFeeds.swift:29`).
Common work (both options, required by the approved R2 "What counts" and "Where done by can be
set", D2 A of the CEO review): one `EventKind.countsAsWork` list read by the facts, by
`EventField.fields(for:)`, by the editors' "Who did it" section and by X1's Undo bars.
Comparison grid:

| Choice | Current | A | B |
|---|---|---|---|
| How "who did it" and "who got up" reach the screens | per-entry lookups, as planned | one value, `WhoDidIt`, worked out once per store change: for each live entry, the counted parent and "saved" or "worked out", with feed pairs and one-tap wake-ups already joined; it answers the page's facts, "Last night" and each number's list | per-entry lookups `doneBy(entry)` and `gotUp(sleep)`; each screen joins feed pairs and one-tap wake-ups itself |
| Who reads it | the page, its lists, "Last night", History's pictures, the editors' first choice, the Undo card | the same, all from the one value | the same, each through the lookups |
| Kinds that count | in 4 places | one `EventKind.countsAsWork` (common work) | the same (common work) |
| Tests | Section 6 list | the rules tested once on the value; each screen checks it reads it | the rules tested in the lookups and again per screen that joins pairs or wake-ups |
| E1, A2, E2 | approved (A, A, A) | unchanged | unchanged |
| A5 | pending | pending | pending |
| Effort | plan T1 and T3: human ~3.5 days / CC ~3 h | about the same | about the same |

Question D5:
D5 — Should the app work out "who did it" once, in one place, for every screen?
Project/branch/task: Little Log, the "who does what" plan, engineering review (branch claude/focused-hamilton-47r7qx).
ELI10: Many screens show who did each entry: the page, the list behind each number, the "Last night" line, History's pictures, the editors and the Undo card. A few rules decide it: a breastfeed counts for the parent who breastfeeds, a feed logged on both phones counts once, and one Woke up tap that ended two sleeps counts as one wake-up. Option A works all of that out once into one answer sheet, and every screen reads the sheet. Option B gives each screen a helper to ask entry by entry, and each screen must remember the "both phones" and "one tap" rules itself.
Stakes if we pick wrong: with B, one screen that forgets a rule shows a different number from another; with A, a mistake in the sheet shows on every screen at once (so it is also caught at once).
Recommendation: A because every screen then shows the same answer by design, and the rules are tested in one place.
Completeness: A=9/10, B=7/10
Pros / cons:
A) One answer sheet (recommended)
  ✅ The page, its lists, the Last night line and History can never disagree with each other
  ✅ The rules are written and tested once, so a later change can't miss a screen
  ❌ A mistake in the sheet shows everywhere at once, until it is fixed in that one place
B) Each screen asks for itself
  ✅ As the plan is written now, so nothing in the plan needs re-wording
  ✅ A screen that needs only one entry asks for just that entry
  ❌ Each screen must apply the "both phones" and "one tap" rules, and one could forget
Net: one sheet every screen trusts (A), or a helper each screen must use correctly (B).
Header: One answer
Options:
A) One answer sheet (recommended)
"Who did it" and "who got up" are worked out once each time the data changes, for every entry, with the "both phones" and "one tap" rules already applied. Every screen reads that one sheet. One list says which kinds count. Effort about the same as planned: human ~3.5 days / me ~3 hours.
B) Each screen asks for itself
As the plan says now: a helper answers "who did this entry?", and each screen applies the "both phones" and "one tap" rules itself. One list says which kinds count. Effort about the same: human ~3.5 days / me ~3 hours.

State: approved
Actual answer: A) One answer sheet (recommended), D5 answer, 20 Nov 2026.
Accepted scope: one value, `WhoDidIt` (in `Insights/Shares.swift`), worked out once per store
change from the live entries and the "Who breastfeeds?" setting: for each counting entry, the
counted parent and "saved" or "worked out", with feed pairs (later stamp wins) and one-tap
wake-ups already joined. It answers the page's facts, "Last night" and each number's list, and is
the only source for History's pictures, the editors' first choice, the Undo card's picture and
Feeding Dev's debug lines (E2). Common work: one `EventKind.countsAsWork` read by the facts, the
editors' "Who did it" section, X1's Undo bars and the store's "done by" edit (which refuses other
kinds). The rules are tested once on the value.
History: found by this review's design-twice check on `Insights/Shares.swift`. Correction after
D7 (no behaviour change): `countsAsWork` is not read by `EventField.fields(for:)`, because `add`
stamps every field that list names (`HouseholdData.swift:247-248`) and E3 needs "done by" and "got
up" stamped only when a value is set; the D5 question had named `fields(for:)` among the readers.

#### A5: which sleeps one tap ended
Finding: A5, INFORMATIONAL, confidence 8/10, `docs/planning/09-who-does-what.md:139` ("How the
tap is remembered (for example an ID shared by those sleeps): the engineering review"), reviewer:
CEO review's outside voice (finding 3), this review.
Plan baseline: one tap that ends several sleeps is one wake-up with one "got up"; the swap and
the editor change it for all of them (Counting rules, approved with the documents, D10 A). How
the tap is remembered: open.
Runtime evidence: `endSleep` ends every running sleep with one `now` and one member
(`MoreThanFeeds.swift:33-34`: `edit(sleep.id, by: member, now: now) { ... }`), so each gets the
same `endedAt` stamp; `endSleepForFeed` does the same (`:78`). `reopenSleepEnded` already finds
sleeps by that stamp (`:89-91`: `stamp.by == feed.loggedBy && abs(stamp.at.timeIntervalSince(feed.createdAt)) < 1`).

##### History (D6 payload, kept as asked; reopened after the outside voices, see "Current (D8)" below)

Comparison grid:

| Choice | Current | A | B |
|---|---|---|---|
| How the app knows sleeps were ended by one tap | open | the same end stamp (same time and same parent), as `reopenSleepEnded` finds sleeps today | a new shared tap ID saved on each sleep ended |
| Sleeps ended before this build | n/a | joined the same way (their stamps were written the same way) | not joined (no ID) |
| New encrypted iCloud fields | 3 (E1 A) | 3 | 4 (`wakeID` too, in the same Production step) |
| One of those sleeps' end later changed alone (its editor) | n/a | it becomes its own wake-up (its end differs, as "a got up belongs to one ending") | stays joined, with a different end |
| The Woke up swap and Change time | change all of them (approved) | the swap changes `gotUpBy` only, so the end stamps stay equal; Change time already edits every sleep of the tap with one `now` (`CareTiles.swift:97-110`), and also re-stamps the end of a sleep whose end it didn't move (an end clamped to its start), so the stamps stay equal | unchanged |
| E1, A2, E2, A4 | approved (A, A, A, A) | unchanged | unchanged |
| Effort | none | human ~2 h / CC ~15 min | human ~4 h / CC ~30 min |

Question D6:
D6 — How should the app tell that one "Woke up" tap ended two sleeps?
Project/branch/task: Little Log, the "who does what" plan, engineering review (branch claude/focused-hamilton-47r7qx).
ELI10: If each of you logged "Fell asleep", two sleeps are running, and one "Woke up" ends both. That is one wake-up with one "got up", so the app must know those two sleeps go together. Option A: each tap already leaves the same mark on every sleep it ends (the same time, to the thousandth of a second, and the same parent). The app already uses that mark today to put a sleep back after "Stop · discard". Same mark means same tap: no new data, and it works for every sleep already logged. Option B: save a new shared tap number on each sleep. That is a fourth new iCloud label, and it only works for sleeps ended from now on.
Stakes if we pick wrong: with B, past nights can show one wake-up twice; with A, if one sleep's end is later changed on its own, it counts as its own wake-up (which matches the rule that a "got up" belongs to one ending).
Recommendation: A because it needs no new data, works back to day one, and uses a mark the app already trusts.
Completeness: A=9/10, B=7/10
Pros / cons:
A) Use the tap's own mark (recommended)
  ✅ No new iCloud label: the mark is already saved on every sleep, back to day one
  ✅ The app already relies on the same mark to undo "Stop · discard", so it is proven
  ❌ Changing one of those sleeps' end time on its own splits it into its own wake-up
B) Save a new tap number
  ✅ The link stays even if one sleep's end time is later changed on its own
  ✅ Easy to read in the test screen: one number shared by the sleeps of one tap
  ❌ A fourth new iCloud label, and past sleeps can't be joined, so old nights count twice
Net: reuse a mark that is already there and works on old nights (A), or a new label that only works from now on (B).
Header: One tap
Options:
A) Use the tap's own mark (recommended)
Sleeps whose end carries the same mark (same time, same parent) were ended by one tap: one wake-up, one "got up". No new data; works on every sleep already logged. Change time re-marks every sleep of the tap, even one whose end it couldn't move, so they stay together. Effort: human ~2 hours / me ~15 minutes.
B) Save a new tap number
Each "Woke up" (and each Start feed that ends a sleep) saves one new number on every sleep it ends. A fourth new iCloud label, in the same go-ahead step. Past sleeps are not joined. Effort: human ~4 hours / me ~30 minutes.

State: approved
Actual answer: A) Use the tap's own mark (recommended), D6 answer, 20 Nov 2026.
Accepted scope: ended sleeps whose `endedAt` stamps are equal (same time and same member) are one
wake-up with one "got up", for sleeps from day one; no new field. Change time on the Woke up bar
(`CareTiles.swift:97`) re-stamps the end of every sleep of the tap, also one whose end it didn't
move, so the stamps stay equal. The swap changes `gotUpBy` only. `WhoDidIt` (A4) does the joining.
Tests: two sleeps ended by one Woke up count once; Change time keeps them joined, including an end
clamped to its start; a sleep's end edited alone becomes its own wake-up.
History: left open by the CEO review (outside voice finding 3) for this review.

##### Current (D8)

Reopened for concrete new risks (outside voices, verified in the code): the late-feed rule
(`MoreThanFeeds.swift:105-111`) ends every interrupted sleep in one pass with one `member` and one
`now`, whatever its baby and its feed, so equal end stamps join wake-ups that are not one tap;
`edit` stamps only changed fields and `merge` carries only `changedLocally` fields
(`HouseholdData.swift:282-288`, `EventMerge.swift:151`), so D6's forced re-stamp needs a special
case that a save clash can still drop; a sleep reopened and ended again at the same time keeps its
old "got up" (bound to an end time), and a late correction for an earlier ending can win the merge
over the new ending's "got up"; a back-dated tap whose clamped ends straddle 21:00 has no single
night.
Comparison grid:

| Choice | Current (D6 A) | A | B |
|---|---|---|---|
| How one tap's sleeps are joined | equal end stamps | a wake-up ID written with each ending: a new one per Woke up tap; "feed:<feed ID>" when Start feed or the late-feed rule ends sleeps, so both phones and later passes write the same ID | equal end stamps, only for sleeps of the same baby ended by Woke up or Start feed; the late-feed rule never joins; Change time puts the end in `changedFields` so the merge carries the re-stamp |
| What a "got up" belongs to | its end time (`gotUpFor`, TIMESTAMP) | the ending's wake-up ID (`gotUpFor`, STRING); the end and its wake-up ID merge as one field; in a merge, a "got up" whose ID isn't the winning ending's gives way to the copy that matches | its end time, as D6 |
| A sleep reopened and ended again at the same time | keeps the old "got up" | new ID, so the old "got up" is ignored | keeps the old "got up" |
| The late-feed rule: two babies or two feeds in one pass; one feed in two passes | joined wrongly; counted twice | kept apart; joined (same feed ID) | not joined; counted twice |
| A wake-up's moment (its night, day and list time) | undefined when clamped ends straddle 21:00 | the earliest end in its group | the earliest end in its group |
| Sleeps ended before this update | joined by stamp | each its own wake-up (only differs when two sleeps ran at once) | joined by stamp |
| New encrypted fields on `Event` (E1) | 3: `doneBy`, `gotUpBy`, `gotUpFor` (TIMESTAMP) | 4: `doneBy`, `wakeID` (STRING), `gotUpBy`, `gotUpFor` (STRING), same Production step | 3, as now |
| E1 rest, A2, E2, A4 | approved | unchanged | unchanged |
| E3 | approved (D7 A), being reopened separately | unchanged here | unchanged here |
| Effort | human ~2 h / CC ~15 min | human ~4 h / CC ~30 min | human ~3 h / CC ~25 min |

Question D8:
D8 — Should each wake-up get its own number after all?
Project/branch/task: Little Log, the "who does what" plan, engineering review (branch claude/focused-hamilton-47r7qx).
ELI10: In D6 you chose to spot "one Woke up tap ended two sleeps" by the matching mark the tap leaves. Both outside reviewers found real holes in that, and I checked them in the code. (1) When a feed reaches a phone late, the app ends sleeps for it, and it gives the same mark to sleeps ended by different feeds, so they would be joined by mistake. (2) The fix for Change time can be lost when both phones save at once. (3) A sleep that is reopened and ended again at the same time keeps the old "who got up". Option A: give each ending its own wake-up number, saved with it, and tie "who got up" to that number. That is a fourth new locked iCloud label, in the same go-ahead step as the other three. Option B: keep the matching mark and patch the holes; the late-feed case is never joined, and hole 3 stays.
Stakes if we pick wrong: with B, some nights can count one wake-up twice or keep the wrong "who got up"; with A, past nights with two sleeps running show two wake-ups.
Recommendation: A because it closes all three holes in a way the reviewers and the code agree on; the only cost is past nights where both of you logged "Fell asleep".
Completeness: A=9/10, B=6/10
Pros / cons:
A) A number for each wake-up (recommended)
  ✅ Each wake-up and its "who got up" stay together, even after an Undo or a late feed
  ✅ Both phones write the same number for a feed's wake-up, so it never counts twice
  ❌ A fourth new iCloud label, in the same go-ahead step as the other three
  ❌ Past nights where both of you logged "Fell asleep" show two wake-ups, not one
B) Keep the matching mark, patched
  ✅ No fourth iCloud label, and past nights join as before
  ✅ Close to your D6 answer, with the clear holes patched
  ❌ A reopened sleep ended at the same time keeps the old "who got up"
  ❌ A feed that reaches the phone late can count its wake-up twice
Net: one number per wake-up that keeps everything straight (A), or the matching mark with known holes (B).
Header: Wake-ups
Options:
A) A number for each wake-up (recommended)
Each ending saves a wake-up number: a new one per Woke up tap, and the feed's own number when a feed ends sleeps. "Who got up" is tied to that number, so an Undo or a late change can't mix up wake-ups. A fourth locked iCloud label, in the same go-ahead step. Sleeps ended before this update each count as their own wake-up. Effort: human ~4 hours / me ~30 minutes.
B) Keep the matching mark, patched
As D6: sleeps with the same mark are one wake-up, but only for Woke up and Start feed, and Change time's re-mark is forced through. A late-feed ending is never joined; a reopened sleep ended at the same time keeps the old "who got up". Effort: human ~3 hours / me ~25 minutes.

State: approved
Actual answer: A) A number for each wake-up (recommended), D8 answer, 20 Nov 2026 (replaces D6 A).
Accepted scope: each ending of a sleep saves a wake-up ID with its end: a new UUID per Woke up tap
(every sleep that tap ends gets the same one); "feed:<feed ID>" when Start feed
(`endSleepForFeed`) or the late-feed rule (`endSleepsInterruptedByFeeds`) ends sleeps, so both
phones and later passes write the same ID. The end and its wake-up ID are one merge field
(`EventField.endedAt` copies both). "Got up" is `gotUpBy` plus `gotUpFor` (the wake-up ID it was
given for), merged as one field; after a merge, a "got up" whose `gotUpFor` isn't the merged
ending's wake-up ID gives way to the copy that matches, if any, else it is ignored. Sleeps with the
same wake-up ID (and the same baby) are one wake-up; its moment (night, day, list time) is the
earliest end in the group. Reopening (Undo of Woke up, Stop · discard) leaves the old ID behind and
a new ending writes a new one, so an old "got up" is ignored. Sleeps ended before this update have
no ID: each is its own wake-up, with a worked-out "got up" (marked). Change time and the swap keep
the wake-up ID. E1's fields become 4: `doneBy`, `wakeID` (ENCRYPTED STRING), `gotUpBy`, `gotUpFor`
(now ENCRYPTED STRING), in the same Production step. `WhoDidIt` (A4) does the joining. Tests: one
Woke up ending two sleeps is one wake-up; a feed ending sleeps on both phones, or in two passes, is
one wake-up; the late-feed rule never joins two feeds' or two babies' sleeps; reopened and ended
again at the same time drops the old "got up"; a late correction for an earlier ending loses the
merge to the current ending's "got up"; clamped ends straddling 21:00 take the earliest end's night.
History: D6 A (above) replaced after the outside voices (Claude subagent findings 1 and 5; Codex
findings 2, 3 and 6), verified in `MoreThanFeeds.swift:105-111`, `HouseholdData.swift:282-288` and
`EventMerge.swift:151`.

Section 1 dispositions: A1 = E1 accepted (D2 A); A2 accepted (D3 A); A3 = E2 accepted (D4 A); A4
accepted (D5 A); A5 accepted (D6 A), reopened after the outside voices and replaced by D8 A. One realistic production failure per new path: the Production
schema not deployed before Little Log build 2 ships would make iCloud refuse every save that
carries the new fields, so sync stalls on both phones; handled by the deploy-first order (E1) and
the app test that every written field is in `schema.ckdb`.

### Section 2: Code quality

- CQ1 [INFORMATIONAL] (confidence: 8/10) `docs/planning/09-who-does-what.md:437` — "Rollback:
  reinstall the earlier TestFlight build". A phone sent back to build 1 drops "done by" and "got
  up" from its own file (`Event.swift:8`, plain `Codable`); E1's once-only marker would already be
  set when it updates again, so it never fetches them back. Decision E3 below.
- CQ2 [INFORMATIONAL] (confidence: 9/10) `docs/planning/09-who-does-what.md:307` — "A list of one
  parent's entries | History's filter (`App/Home/HistoryView.swift:19`)". History's filter is by
  kind only (`@AppStorage("history.filter") private var filterName = HistoryFilter.all.rawValue`).
  Factual correction, no behaviour change: the shared entries list (D1 A) serves X2.
- CQ3 [INFORMATIONAL] (confidence: 9/10) `docs/planning/09-who-does-what.md:403-410` — the Section 1
  diagram says "`schema.ckdb` only if E1 picks a record field" and "doneBy(entry) / gotUp(sleep)":
  stale after E1 A and A4 A. Updated in this review's outputs (documentation of approved answers).

#### E3: when a phone fetches the household again
Finding: CQ1, INFORMATIONAL, confidence 8/10, `docs/planning/09-who-does-what.md:437` and
`FeedingCore/Sources/FeedingCore/Model/Event.swift:8`, reviewer: Claude (this review).
Plan baseline: E1 A (D2): "The first launch of the build that knows the fields discards the sync
engines' saved place once (a marker in the household file says it was done) ... a phone that ran
an older build meanwhile gets the values back." Rollback to the earlier TestFlight build is the
plan's own path (Section 1, line 437).
Runtime evidence: an older build keeps a part of the household file it doesn't know (`keptParts`,
`HouseholdData.swift:178`), so the marker survives a trip back to build 1; it drops unknown `Event`
keys (`Event.swift:8`) but keeps the details' raw bytes and their string-keyed stamps
(`Payload.swift:109`). `add` stamps every field of a kind (`HouseholdData.swift:247-248`).

##### History (D7 payload, kept as asked; reopened after the outside voices, see "Current (D9)" below)

Comparison grid:

| Choice | Current | A | B |
|---|---|---|---|
| When a phone fetches the whole household zone again | once, at the first launch of the new build (E1 A) | at launch, whenever its file holds a "done by" or "got up" stamp with no value (an older build dropped it) | once, at the first launch of the new build (as approved) |
| A phone sent back to build 1, then updated again | values set meanwhile stay missing | fetched again | stay missing on that phone; the two phones can show different numbers |
| New entries | `add` stamps every field of the kind | "done by" and "got up" are stamped only when a value is set, so a stamp always means a value | as now |
| Values cleared | never ("got up" for another end is ignored, not cleared) | the same | the same |
| The rest of E1 A (3 fields, stamps, Production step, Dev probe) | approved | unchanged | unchanged |
| Effort | none | human ~3 h / CC ~20 min | none |

Question D7:
D7 — When should a phone re-read the whole household from iCloud?
Project/branch/task: Little Log, the "who does what" plan, engineering review (branch claude/focused-hamilton-47r7qx).
ELI10: Your D2 answer means an older copy of the app keeps "who did it" safe in iCloud, but forgets it on its own phone. So the new app re-reads the household once after it is installed. But the plan also says: if a new build has a problem, go back to the earlier TestFlight build. A phone that goes back and then forward again would not re-read the second time, and could show different numbers from the other phone. Option A: re-read whenever the phone finds a "who did it" mark with its value missing, which is a sure sign an older copy dropped it. Option B: re-read once only, as planned.
Stakes if we pick wrong: with B, after a rollback and update, one phone can quietly count differently from the other; with A, a little more to build.
Recommendation: A because the plan's own rollback path would otherwise leave the two phones disagreeing.
Completeness: A=9/10, B=6/10
Pros / cons:
A) Re-read when a value is missing (recommended)
  ✅ Going back to an earlier build and forward again still ends with both phones agreeing
  ✅ The check is exact: a saved mark with no value only happens when an older copy dropped it
  ❌ About 3 hours for a person (20 minutes for me), plus tests for going back and forward
B) Re-read once only
  ✅ Simplest: one re-read at the first launch, and never again
  ✅ No change to how new entries are saved today
  ❌ After going back to build 1 and forward again, that phone can show different numbers
Net: both phones agree even after a rollback (A), or a simpler once-only re-read that misses that case (B).
Header: Re-read
Options:
A) Re-read when a value is missing (recommended)
At launch, a phone that finds a "who did it" or "who got up" mark without its value re-reads the whole household from iCloud. New entries get that mark only when a value is set, so the check is exact. Effort: human ~3 hours / me ~20 minutes.
B) Re-read once only
The new app re-reads the household once, at its first launch, as planned. A phone that goes back to an older build and forward again doesn't re-read. No extra work.

State: approved
Actual answer: A) Re-read when a value is missing (recommended), D7 answer, 20 Nov 2026.
Accepted scope: at launch (at most once per launch), a phone whose file holds a "done by" or "got
up" stamp with no value discards its sync engines' saved place, so the household zone is fetched
again in full; its own waiting changes are queued again from its file. `add` and every edit stamp
"done by" and "got up" only when a value is set, and neither is ever cleared, so a stamp always
means a value. This replaces E1's once-only marker. Tests: a file with a stamp and no value asks
for the re-read and one with both doesn't; a new entry with no choice carries no "done by" stamp;
going back (an older build's file: values dropped, stamps kept) and forward again asks for it.
History: found by this review in Code quality, checking E1's re-fetch against the rollback path.

##### Current (D9)

Reopened for concrete new risks (Claude subagent findings 2 and 3, Codex finding 1, verified):
discarding the engines' saved place also discards waiting changes that live only in the engine
(the zone save at setup, `HouseholdSync.swift:153`: `privateEngine.state.add(pendingDatabaseChanges:
[.saveZone(...)])`); and a stamp whose value iCloud never received (a correction made offline on a
phone sent back to build 1 before it synced) has no end state, so D7 A would fetch the whole zone at
every launch.
Comparison grid:

| Choice | Current (D7 A) | A | B |
|---|---|---|---|
| What is fetched when a value is missing | the whole household zone, by discarding both sync engines' saved place | only the entries with a stamp and no value, fetched by record name from the household zone and passed through the normal receive path (merge kept); the engines are never reset | as D7 A |
| End state | none: a value still missing means a full fetch at every launch | an entry still missing its value after its fetch is noted as checked in the household file and not fetched again; one sync log line names it | none |
| Waiting changes that live only in the engine (the zone save at setup) | lost if the reset runs then | untouched | at risk |
| When it runs | at launch, at most once per launch | at launch, at most once per launch | at launch, at most once per launch |
| Stamps only with a value, never cleared | approved (D7 A) | unchanged | unchanged |
| A correction made offline, then the phone sent back to build 1 before it synced | lost; full fetch at every launch | lost (iCloud never had it); checked once, then quiet; the rollback steps say to let the phone sync first | lost; full fetch at every launch |
| E1, A2, E2, A4, A5 | approved | unchanged | unchanged |
| Effort | human ~3 h / CC ~20 min | human ~4 h / CC ~30 min | none extra |

Question D9:
D9 — What should a phone re-read when a "who did it" value is missing?
Project/branch/task: Little Log, the "who does what" plan, engineering review (branch claude/focused-hamilton-47r7qx).
ELI10: In D7 you chose: when a phone finds a "who did it" mark with its value missing, it re-reads the whole household from iCloud, by wiping its record of where the last sync stopped. The second reviewer found two problems, and I checked them. (1) Wiping that record can also lose one change still waiting to go (setting up the shared space, right at the start). (2) If iCloud has no value either (for example, a correction made offline on a phone that was then sent back to build 1 before it synced), the phone would re-read everything at every launch, for ever. Option A: re-read only the entries that are missing a value, by name, and wipe nothing; if iCloud has no value either, note it and stop asking. Option B: keep D7 as it is.
Stakes if we pick wrong: with B, a phone can lose a waiting change, or re-read the whole household at every launch; with A, a little more to build.
Recommendation: A because it fetches only what is missing, wipes nothing, and always stops.
Completeness: A=9/10, B=6/10
Pros / cons:
A) Re-read only what is missing (recommended)
  ✅ Nothing waiting to go to iCloud can be lost, because nothing is wiped
  ✅ It always stops: an entry iCloud has no value for is checked once, then left alone
  ❌ About 4 hours for a person (30 minutes for me) instead of 3 hours (20 minutes)
B) Keep D7 as it is
  ✅ Uses the sync's own full re-read, so a little less new code
  ✅ Every entry is refreshed, not only the ones missing a value
  ❌ A value iCloud never got makes the phone re-read everything at every launch
  ❌ Wiping the sync's place can lose the shared-space setup if it is still waiting
Net: a small, safe, targeted re-read that always stops (A), or a full re-read that can loop and lose a waiting change (B).
Header: Re-read
Options:
A) Re-read only what is missing (recommended)
At launch, a phone re-reads from iCloud just the entries with a "who did it" or "who got up" mark and no value, by name, through the normal sync path, and wipes nothing. An entry iCloud has no value for either is noted as checked and not asked about again. Effort: human ~4 hours / me ~30 minutes.
B) Keep D7 as it is
At launch, a phone that finds a mark with no value wipes its sync place and re-reads the whole household, at most once per launch, with no end state.

State: approved
Actual answer: A) Re-read only what is missing (recommended), D9 answer, 20 Nov 2026 (replaces D7 A).
Accepted scope: at launch, at most once per launch, a phone lists the entries whose file copy holds
a "done by" or "got up" stamp with no value and that are not yet noted as checked; it fetches just
those records by name from the household zone (a `CKDatabase` fetch, not the sync engine) and passes
each through the normal receive path, so a waiting local change still merges. The sync engines'
saved state is never discarded. An entry still missing its value after its fetch is noted as
checked in the household file (a new part an older build keeps) and not fetched again; one sync log
line names it. `add` and every edit stamp "done by" and "got up" only when a value is set, and
neither is ever cleared (kept from D7 A). Tests: the list of entries to fetch (stamp and no value,
not yet checked); a fetched copy with the value fills it; a fetched copy without it marks the entry
checked and it is not listed again; a new entry with no choice carries no stamp; an older build's
file (values dropped, stamps kept) lists those entries after the update. The rollback steps say:
let a phone sync before going back to an earlier build.
History: D7 A (above) replaced after the outside voices (Claude subagent findings 2 and 3, Codex
finding 1), verified at `HouseholdSync.swift:153`.

Section 2 dispositions: CQ1 = E3 accepted (D7 A), reopened after the outside voices and replaced
by D9 A; CQ2 recorded as a correction; CQ3 applied in this review's outputs.

### Section 3: Tests

Framework (from `CLAUDE.md`): Swift Testing in `FeedingCore` (`swift test --package-path
FeedingCore`, also on Linux in CI); app tests (`AppTests`) and tap tests (`FeedingDevUITests`) in
the iPhone 18 Pro simulator, not in CI. Every path below is new, so nearly every row is a gap with
its proposed test; existing tests that guard behaviour this plan touches are marked TESTED.

```
CODE PATHS (FeedingCore unless marked App)                 USER FLOWS
[+] Event + RecordMapping (E1: 3 encrypted fields)          [+] Undo card at the top (DT2, X1)
  ├── [★★★ TESTED] every written field is in schema.ckdb      ├── [GAP] [→E2E] Wee → card; swap; Undo; × closes at once
  │     AppTests/RecordMappingTests.swift:109                  └── [★★ TESTED] HistoryDeleteFlowTests' Undo, to update
  ├── [GAP] round trip of doneBy, gotUpBy, gotUpFor (App)     [+] Number → list → editor (X2, D1 A, 2C)
  ├── [GAP] an old file without them still reads              │   └── [GAP] [→E2E] list length and total = the number;
  └── [GAP] UPDATE thePayloadIsEncryptedAndNothingElseIs:     │         a changed row stays, count updates
        payload + the 3 fields encrypted, nothing else (App)  [+] "Who breastfeeds?" once per phone (DT7, 2A)
[+] Store: set "done by" / "got up" (E1, E3, A4)              │   └── [GAP] [→E2E] Not now → quiet line; answer → gone
  ├── [GAP] stamped only when a value is set; never cleared   [+] Morning line (DT4, X3)
  ├── [GAP] refused for kinds that don't count                │   └── [GAP] 07:30 shows, 12:01 not; tap → the shared list
  ├── [GAP] entry deleted meanwhile → false                   [+] Bottle-only "Breastfeed (Sam)" (DT5, 4B)
  └── [GAP] a swap inside the Undo window goes with the add   │   └── [GAP] [→E2E] three choices; Left/Right; done by saved
[+] Merge (EventMerge)                                        [+] Two phones (hostile QA)
  ├── [★★★ TESTED] unreadable server copy kept whole          │   └── [GAP] swap on both offline → later stamp wins
  │     PayloadTests (10 merge tests)                         │         (unit both orders + on-device)
  ├── [GAP] doneBy / gotUp: later stamp wins, both orders     [+] Older build (E1 Dev probe) [→E2E on device]
  └── [GAP] an unknown stamp name survives decode + encode    │   └── [GAP] older Feeding Dev saves an entry: the 3 fields
[+] Re-read of missing values (E3, D9 A)                      │         survive; updated phone fetches them and agrees
  ├── [GAP] list: stamp + no value + not checked; else none   [+] Error and empty states
  ├── [GAP] older build's file (values dropped) → listed      │   ├── [GAP] iCloud check failed or > 15 min → banner (1D)
  ├── [GAP] fetched copy with value fills it; without → checked, never listed again
  └── [GAP] App: fetch by name goes through the normal receive path; engines untouched (on-device, E1 probe)
                                                              │   └── [GAP] other parent not joined → DD13 words
[+] WhoDidIt (A4)
  ├── [GAP] stored wins; breast side or pump → breastfeeder; else logger; Nobody or unanswered → logger
  ├── [GAP] a stored choice equal to the rule survives a "Who breastfeeds?" change
  ├── [GAP] feed pair once; either copy's later stamp wins; else the rule on the shown copy
  ├── [GAP] got up valid only when gotUpFor == the sleep's wakeID; else worked out (feed at the end →
  │         its logger; else the end stamp's member), marked worked out
  ├── [GAP] one wake-up = one wakeID (A5, D8 A); a feed's wakeID from both phones or two passes joins;
  │         two feeds or two babies never join; old sleeps (no ID) each alone; moment = earliest end
  ├── [GAP] running feed/sleep counted from start, no time, no got up; unreadable details → logger,
  │         start-to-end time; member gone → Other; deleted out
  ├── [GAP] non-feed copies (TD2b): same kind, 5 min, other parent, same nappy/medicine → hidden,
  │         once; "They were two" → both, twice; non-matches stay
  ├── [GAP] History's "finished by" (TD1): only when the end equals its stamp's time; a correction → none
  └── [GAP] bath counted, not timed; growth and firsts not counted
[+] facts(range), lastNight(now), entries(for:)
  ├── [GAP] time cases (sides' seconds; else start to end; pumping; running none)
  ├── [GAP] calendar days and night named by its evening (1A); day, 7 days, 4 weeks, all
  ├── [GAP] clock changes both ways, 30-min zone, travel, clock set back, midnight, 21:00 (CLAUDE.md)
  ├── [GAP] card: until 12:00; no night hours; empty night; night ending at/after 12:00;
  │         overlapping sleeps joined and cut to the night; a running sleep to the night's end
  └── [GAP] each number = its list's length and total
[+] MoreThanFeeds "got up" (R3, A5)
  ├── [★★★ TESTED] Woke up ends a sleep started on each phone — MoreThanFeedsTests.swift:289
  ├── [GAP] Woke up stores tapper + one new wakeID; Start feed and late-feed rule → "feed:<id>", the feed's logger
  ├── [GAP] Undo of Woke up / Stop · discard, ended again at the same time → old got up ignored (new wakeID)
  └── [GAP] merge: a late correction for an earlier ending loses to the current ending's got up
[+] Move (T4)
  ├── [★★★ TESTED] IDs mapped, maker → this parent — HouseholdMoveTests.swift:86
  └── [GAP] doneBy, gotUpBy, "Who breastfeeds?" mapped on a first move only
[+] QuickFeed (A2)
  ├── [★★★ TESTED] finish whoever started it — QuickFeedTests.swift:57
  └── [GAP] refused finish → "couldn't finish", feed still running
[+] Alerts untouched ("Rules kept", 0G)
  └── [GAP] reconcile's plan identical with doneBy/gotUp set and with baths logged (ReconcileTests extend)
[+] Bath kind, 4B start
  ├── [GAP] fields(for: .bath); add; never ends a sleep; History row and filter
  └── [GAP] bottle-only start "Breastfeed (Sam)" saves doneBy at once; watch request carries it

COVERAGE: 6/50 paths tested (12%) | Code paths: 5/40 | User flows: 1/10
QUALITY: ★★★:5 ★★:1 ★:0 | GAPS: 44 (5 E2E, 0 eval)   [measured: counted from the rows above, after D8 to D12]
```

Regression rule: the existing behaviour this plan puts at risk is covered by approved contracts,
carried here with their proof: the merge (E1 A: both orders; the 10 existing merge tests stay
green); sleep endings (A5, D8 A: the existing Woke up, Start feed, Stop · discard and late-feed
tests in `MoreThanFeedsTests` stay green with the wake-up ID added; Change time only carries the ID);
quick finish (A2 A; `QuickFeedTests.swift:57` stays green); the Undo bar's move to the top (DT2:
the tap tests that use Undo, updated); alerts never reading the new fields ("Rules kept", CEO 0G:
the ReconcileTests row above); sync's waiting changes (E3, D9 A: the engines are never reset, and
`SendListTests` and `FetchScopeTests` stay green). Intentional changes: History's big picture becomes "done by"
(DD12); `thePayloadIsEncryptedAndNothingElseIs` is rewritten to "the details and the 3 new fields
are encrypted, nothing else" (E1 A). No regression contract is left unapproved.

Tests made obsolete: none. Test to rewrite: `AppTests/RecordMappingTests.swift:34`. No test needs a
production seam. LLM/eval scope: none (no prompt or model code).

Test plan artifact: `~/.gstack/projects/<owner>-Feeding-Tracker/<owner>-claude-focused-hamilton-47r7qx-eng-review-test-plan-20261120-213119.md`.

Section 3 dispositions: 44 gaps, each with a proposed test that is the required proof of an
approved answer (R1 to R3, X1 to X5, DD and pass answers, E1, E3, A2, A4, A5); no new test policy
or optional depth was proposed, so no question.

### Section 4: Performance

No issues found. `WhoDidIt` is one pass over the live entries per store change (about 11,000 a
year [estimated]), worked out again only when the store changes, as the Graphs tab's facts are; the
feed-pair pass already runs on every History draw (`HistoryView.swift:25`). The re-read (E3, D9 A)
fetches only the entries missing a value, by name, at most once per launch, and each entry at most
until it is noted as checked; the photos zone is never touched. One suppressed finding is in the
appendix.

### Outside voice

Codex (`gpt-6.2-sol`, high effort, CLI 0.171.0; about 870,000 input tokens, 771,000 cached, 6,600
output) ran on a 30 KB condensed plan (accepted scope, counting rules, design answers, this
review's answers D1 to D7) and returned 10 findings, but labelled them "High ·" instead of
"Severity: High", so the gstack check marked it **unverified** (missing coverage, not a pass). The
native fallback (a Claude Plan helper, same prompt, 5-minute limit) **completed** in about 3.5
minutes with 8 findings. Every point from both was checked against the code by this review.

Codex, in short: 1 (High) build 1 drops an unsent correction on a downgrade; 2 (High) the late-feed
rule joins wake-ups of different feeds, and one feed in two passes counts twice; 3 (High) a reopened
sleep can keep its old "got up", and a late correction can win over the new ending; 4 (High) the
watch's queued "Breastfeed (Sam)" start carries no parent; 5 (Medium) the Lock Screen toggle and the
watch don't pass on a refused finish; 6 (Medium) clamped wake-up ends straddling 21:00 have no
single night; 7 (Medium) running views pick Left/Right from the phone's setting, not the feed; 8
(Medium) the poo details panel covers the Undo card's swap; 9 (Medium) the sync line's time can move
before a fetch completes; 10 (Low) History's "finished by" is the last parent to set the end time.

Claude subagent, in short: 1 (High) A5's re-stamp is dropped by `edit` and `merge`; 2 (High) E3 has
no end state; 3 (High) resetting the engines drops engine-only waiting changes; 4 (Medium) the
older-build promise rests on CloudKit, and build 1 may lack KeptJSON; 5 (Medium) equal stamps join
unrelated wake-ups; 6 (Medium) Feeding Dev's iCloud environment is unchecked; 7 (Medium) ship the
Undo card and 4B separately; 8 (Low) bath needs its own field list and a build-1 check.

Cross-model tension and dispositions (agreement is evidence, not approval):

| Finding | Verified? | Disposition |
|---|---|---|
| Subagent 1, 5; Codex 2, 3, 6 (A5) | yes: `MoreThanFeeds.swift:105-111`, `HouseholdData.swift:282-288`, `EventMerge.swift:151` | A5 reopened: D8 A (a wake-up ID per ending) |
| Subagent 2, 3; Codex 1 (E3) | yes: `HouseholdSync.swift:153`; partly: media deletes don't use the engine | E3 reopened: D9 A (fetch only what is missing, with an end state); rollback steps say to sync first |
| Subagent 4 | partly: build 1 is `c4fedda`, which contains KeptJSON (`38c3f63`); the save-clash path was untested | required proof added to E1 (Dev probe on `c4fedda`, with a clash) |
| Subagent 6 | no: Feeding Dev is development-signed (`project.yml:100`, `aps-environment: development`), so it uses the Development environment where the fields are imported | rejected on evidence |
| Subagent 7 | premise contradicted: X1's swap lives on the Undo card (D4 A of the CEO review, DD5, DD7), and 4B needs "done by"; splitting builds the swap twice | not adopted; parents' answers D5, D7 and D15 stand |
| Subagent 8 | yes: `Payload.swift:66` (`default: return Set(allCases)`) | required by X5: `.bath` gets its own field list; the bath check joins the Dev probe |
| Codex 4 | yes, in part: the watch's request must carry the chosen parent | required by DD15 and 4B: the start request carries the member; the watch offers "Breastfeed (Sam)" only when the phone's watch state names the parent who breastfeeds |
| Codex 5 | yes: `FeedIntents.swift:148` drops the result | required by A2 (D3 A, "every quick path"): each surface shows the refusal; the watch asks for bottle details only after the phone accepts |
| Codex 7 | yes | required by DD15 ("starts a breastfeed with the Left / Right buttons"): the running feed shows Left and Right when it has a breast side or counts for the parent who breastfeeds with no bottle, whatever the phone's setting |
| Codex 8 | yes: Poo and Both open the details panel at once | required by X1 (Poo and Both are on the list): the details panel shows the same "who did it" picture and swap until the Undo window ends |
| Codex 9 | plausible (not traced to the line) | required by 1D: "Checked with iCloud" comes from a completed fetch of the household zone; a failed fetch is kept apart; verify at build |
| Codex 10 | yes: `FeedRows.swift:109` reads the end time's stamp | existing behaviour, outside this plan's answers: TODO question below |

### TODOS.md updates

#### TD1: History's "finished by" from a time correction
Finding: Codex 10, INFORMATIONAL, confidence 8/10, `App/Home/FeedRows.swift:109` (the finisher is
read from the `endedAt` stamp), reviewer: Codex (outside voice), verified by this review.
Plan baseline: DD12 and 7B keep a small second picture for the other parent "when they logged it or
finished it", read aloud as "finished by"; how "finished" is known was not asked.
Runtime evidence: History treats the parent in the end time's stamp as the finisher; a later
correction of the end time by the other parent re-stamps it (`HouseholdData.swift:284`).
What: show "finished by" only when the end was set at the moment it was tapped (the end time equals
its stamp's time, within a second); a later correction or a feed logged afterwards claims no
finisher. No new data.
Why: with DD12 the small picture and VoiceOver say who finished; a time correction would credit the
wrong parent on the very screen this plan redesigns.
Context: today's rule is in `FeedRows.swift:109` (finisher picture, F3 of the CEO review). The same
"stamp time equals the value" test is how `reopenSleepEnded` finds a feed's sleep
(`MoreThanFeeds.swift:89-91`).
Depends on: none.
Comparison grid:

| Choice | Current | A | B | C |
|---|---|---|---|---|
| History's "finished by" | whoever last set the end time | as now, written in TODOS.md | as now, not written down | only when the end was set as it was tapped; else no claim |
| Data | none new | none | none | none |
| Tests | none | none | none | a FeedRows or FeedingCore test: a Finish tap names the finisher, a later correction doesn't |
| Effort | none | none now | none | human ~2 h / CC ~15 min |

Question D10:
D10 — Should History stop saying "finished by" a parent who only corrected the time?
Project/branch/task: Little Log, the "who does what" plan, engineering review (branch claude/focused-hamilton-47r7qx).
ELI10: In History, a feed shows a small second picture when the other parent finished it, and VoiceOver says "finished by". Today the app decides that from whoever last set the end time. So if Alex later corrects the end time of a feed Sam finished, History says Alex finished it. The fix needs no new data: say "finished by" only when the end time was set at the moment Finish was tapped; a later correction claims nothing. Option A puts it on the to-do list, B drops it, C fixes it now.
Stakes if we pick wrong: left as is, History can credit the wrong parent on the screen this plan redesigns; fixed now, a little more work in this build.
Recommendation: C because it is small, needs no new data, and stops a wrong "who did it" on a "who did it" screen.
Completeness: A=6/10, B=5/10, C=9/10
Pros / cons:
A) Add to the to-do list
  ✅ No work now; the fix is written down with where to start
  ✅ This build stays the size it is
  ❌ Until then, a time correction makes History say the wrong parent finished the feed
B) Skip it
  ✅ No work now and nothing to track later
  ✅ The small picture still shows the right parent whenever nobody corrects the time
  ❌ The wrong "finished by" stays, with no plan to fix it
C) Fix it now (recommended)
  ✅ History only says "finished by" when the app really knows who tapped Finish
  ✅ No new iCloud label: it uses the time mark the app already saves
  ❌ About 2 hours for a person (15 minutes for me) more in this build
Net: fix a wrong credit now for little work (C), note it for later (A), or leave it (B).
Header: Finished by
Options:
A) Add to the to-do list
Written into TODOS.md under "Who does what", with what, why and where to start. No work now.
B) Skip it
Not written down and not fixed. History keeps today's rule.
C) Fix it now (recommended)
In this build, History's small "finished" picture and VoiceOver's "finished by" show only when the end time was set as Finish was tapped; a later correction or a feed logged afterwards claims no finisher. One test. Effort: human ~2 hours / me ~15 minutes.

State: approved
Actual answer: C) Fix it now (recommended), D10 answer, 20 Nov 2026.
Accepted scope: in this build, History's small "finished" picture and VoiceOver's "finished by"
show only when the feed's end time equals its stamp's time within a second (set as Finish was
tapped); a later correction, or a feed logged afterwards, claims no finisher. No new data. One test:
a Finish tap names the finisher; a later correction by the other parent doesn't.
History: raised by the outside voice (Codex 10).

#### TD2: entries other than feeds logged on both phones
Finding: CEO review Section 10 debt ("copies of non-feed entries count twice (a later duplicate
rule)"), INFORMATIONAL, confidence 9/10, `App/Home/HistoryView.swift:25`
(`let pairs = data.duplicatePairs(babyID: model.baby?.name ?? "")`, feeds only), reviewer: CEO
review, this review.
Plan baseline: Counting rules (approved with the documents, D10 A of the CEO review): "a sleep,
nappy, medicine or bath logged on both phones counts twice, and a parent deletes the copy (the X2
list shows both)".
Runtime evidence: `duplicatePairs` finds feeds logged on both phones only; two "Fell asleep" taps,
one per phone, make two sleeps (`MoreThanFeedsTests.swift:289`).
What: find a sleep, nappy, medicine or bath logged on both phones (same kind, close in time, one
per parent) and count it once, as feeds already are.
Why: a double tap on both phones adds one to each parent's count and to "Settled to sleep", until
someone deletes the copy.
Context: the feed rule and its tests are `duplicatePairs` and `DuplicatesTests`; how often it
happens for other kinds is not known; a wrong rule would hide a real second nappy.
Depends on: the shared screen in use for a few weeks, to see how often it happens.
Comparison grid:

| Choice | Current | A | B | C |
|---|---|---|---|---|
| A non-feed entry logged on both phones | counts twice; the list behind the number shows both to delete one | as now, written in TODOS.md | as now, not written down | counted once by a new rule (kind, time window, one per parent) |
| Risk | none new | none | none | a real second entry close in time could be hidden |
| Effort | none | none now | none | human ~1 day / CC ~1 h, plus a design question on how a copy shows |

Question D11:
D11 — Should "logged on both phones" for nappies, sleeps, medicines and baths go on the to-do list?
Project/branch/task: Little Log, the "who does what" plan, engineering review (branch claude/focused-hamilton-47r7qx).
ELI10: When both of you log the same feed on your own phones, the app already spots it and counts it once. For nappies, sleeps, medicines and baths it doesn't: if you both tap "Wee" for the same nappy, it counts twice, until one of you deletes the copy (the list behind each number shows both). A rule to spot these is possible, but a wrong rule would hide a real second nappy a few minutes later. Option A writes it on the to-do list, B drops it, C builds it now.
Stakes if we pick wrong: built too soon, real entries could be hidden; dropped, double taps keep adding to the counts until someone deletes them.
Recommendation: A because we should first see how often it really happens on the new screen before picking a rule.
Completeness: A=7/10, B=5/10, C=8/10
Pros / cons:
A) Add to the to-do list (recommended)
  ✅ Written down with what, why and where to start, to pick up after a few weeks of use
  ✅ No risk of hiding a real second nappy with a rule picked too early
  ❌ Until then, a double tap counts twice until one of you deletes the copy
B) Skip it
  ✅ No work now and nothing to track later
  ✅ The list behind each number already lets you spot and delete a copy
  ❌ Double taps keep adding to the counts, with no plan to change that
C) Build it now
  ✅ Double taps count once from the first day of the new screen
  ✅ Uses the same idea as the feed rule the app already has
  ❌ About a day for a person (an hour for me) and a design question, with a risk of hiding real entries
Net: wait and see how often it happens (A), never fix it (B), or a rule now that may hide real entries (C).
Header: Both phones
Options:
A) Add to the to-do list (recommended)
Written into TODOS.md under "Who does what", with what, why and where to start. No work now.
B) Skip it
Not written down and not built. A copy is deleted by hand from the list behind a number.
C) Build it now
A new rule in this build counts a nappy, sleep, medicine or bath logged on both phones once. Needs a design choice on how the copy shows. Effort: human ~1 day / me ~1 hour.

State: approved
Actual answer: C) Build it now, D11 answer, 20 Nov 2026 (not the recommended A).
Accepted scope: in this build, a sleep, nappy, medicine or bath logged on both phones counts once
on every screen that counts (the page, its lists, "Last night", the Graphs tile). This replaces the
Counting rules' "counts twice, and a parent deletes the copy". How the rule matches and how a copy
shows: TD2b (D12), pending.
History: debt named by the CEO review (Section 10).

#### TD2b: how a non-feed copy is found and shown
Finding: follows from D11 C ("Needs a design choice on how the copy shows").
Plan baseline: D11 C approved; the rule and the look are open.
Runtime evidence: feeds use `duplicatePairs` (`HouseholdData.swift:664`): starting within 5
minutes (`duplicateWindow`, `Insights.swift:80`), logged by different parents, not marked as two
(a shared "distinct-<id>-<id>" setting, `markDistinct`); the screens hide the copy logged second
(`hiddenDuplicates`) and the kept one says so (`HistoryView.swift:24-27`); `reconcile` reads every
feed, so alerts never depend on it.
Comparison grid:

| Choice | Current | A | B |
|---|---|---|---|
| What counts as a copy | feeds only | same kind, starting within 5 minutes, logged by different parents, not marked as two; a nappy only with the same Wee/Poo/Both, a medicine only with the same name | the same match as A |
| How it shows | n/a | as feeds today: the copy logged second is hidden on every screen; the kept one says "Logged on both phones", with "They were two" to show both again (on both phones) | both stay in History; the second is marked "Logged on both phones · counted once", with "They were two" |
| Counted | twice | once | once |
| "They were two" record | feeds only (`DistinctFeeds`) | the same shared setting, for any kind | the same |
| Alerts | never use it | unchanged | unchanged |
| Effort | none | human ~1 day / CC ~1 h | human ~1 day / CC ~1 h |

Question D12:
D12 — How should a nappy, sleep, medicine or bath logged on both phones look?
Project/branch/task: Little Log, the "who does what" plan, engineering review (branch claude/focused-hamilton-47r7qx).
ELI10: You chose to count these once (D11). The app needs a rule and a look. The rule, for both options: the same kind of entry, started within 5 minutes, logged by different parents (a nappy only if both said the same Wee, Poo or Both; a medicine only with the same name). That is how feeds work today. Option A also shows them like feeds: the second one is hidden everywhere, and the one kept says "Logged on both phones", with "They were two" to show both again. Option B keeps both in History, the second one marked "counted once".
Stakes if we pick wrong: with A, a real second entry within 5 minutes is hidden until someone taps "They were two"; with B, History shows the same nappy twice.
Recommendation: A because it works exactly like feeds, which you already know, and History stays clean.
Note: options differ in kind, not coverage — no completeness score.
Pros / cons:
A) Same as feeds (recommended)
  ✅ One rule and one look for every kind, the way feeds already work
  ✅ History shows each nappy or sleep once, so it stays easy to read at night
  ❌ A real second entry within 5 minutes stays hidden until someone taps "They were two"
B) Keep both in History
  ✅ Nothing is ever hidden: you see both taps and the note that it counted once
  ✅ A real second entry is easy to spot and mark as two
  ❌ History shows the same nappy twice, unlike feeds, so two looks to learn
Net: hide the copy as feeds do (A), or show both with a "counted once" note (B).
Header: Copy look
Options:
A) Same as feeds (recommended)
Same kind, within 5 minutes, different parents (same Wee/Poo/Both, same medicine): the second one is hidden on every screen and counted once; the kept one says "Logged on both phones", with "They were two". Effort: human ~1 day / me ~1 hour.
B) Keep both in History
The same match, counted once, but both stay in History; the second is marked "Logged on both phones · counted once", with "They were two". Effort: human ~1 day / me ~1 hour.

State: approved
Actual answer: A) Same as feeds (recommended), D12 answer, 20 Nov 2026.
Accepted scope: a sleep, nappy, medicine or bath is a copy of another of the same kind and baby
when it started within 5 minutes of it (`duplicateWindow`), was logged by the other parent, is not
marked as two, and (a nappy) has the same Wee, Poo or Both, or (a medicine) the same name. As with
feeds, the copy logged second is hidden on every screen and counted once; the kept one says
"Logged on both phones", with "They were two" (the same shared "distinct-" setting, for any kind)
to show both again on both phones. `WhoDidIt` (A4) applies it; for a pair, the later stored "done
by" on either copy wins, else the starting rule on the kept copy (as feed pairs). Alerts never use
it. Tests: each kind's match and non-match (other parent required, 5-minute edge, different
nappy contents, different medicine), hidden and counted once, "They were two" shows both and
counts two.
History: opened by D11 C.

Approval readiness: PASS. Checked IDs and answers: scope D1 A; E1 D2 A (amended by D8 A); A2 D3 A;
E2 D4 A; A4 D5 A; A5 D8 A (D6 A in History); E3 D9 A (D7 A in History); TD1 D10 C; TD2 D11 C;
TD2b D12 A. Required proof added without a new question: the Dev probe's save-clash and bath cases
(E1), the ReconcileTests row ("Rules kept", CEO 0G), the rewritten RecordMappingTests encryption
test (E1). Outside-voice requirements carried under existing answers: Codex 4 and 7 (DD15, 4B),
Codex 5 (A2), Codex 8 (X1), Codex 9 (1D), subagent 8 (X5). No remedy without an answer.

### NOT in scope (engineering)

- Shipping the Undo card and "Breastfeed (Sam)" in separate builds (Claude subagent 7): not
  adopted; X1's swap lives on the card and 4B needs "done by".
- A stored "finished by" field: D10 C fixes History's claim with the existing stamp instead.
- A full household re-fetch or a sync-engine reset: replaced by D9 A's fetch by name.
- Joining old sleeps (before this update) into one wake-up: D8 A counts each alone.
- The weekly look back: still in `TODOS.md` (CEO X4).

### What already exists (engineering)

Reused, not rebuilt: `duplicatePairs` and the "distinct-" setting (`HouseholdData.swift:633-670`),
widened from feeds to every counting kind (D11, D12); the stamp-time test `reopenSleepEnded` uses
(`MoreThanFeeds.swift:89-91`), reused for "finished by" (D10); string-keyed details stamps and
`keptParts` for older builds (step 0); `RecordMapping`'s `encryptedValues` and its schema test; the
sync receive path, used by the fetch by name (D9); History's rows (`FeedRows.swift`) for the one
entries list (D1); `HouseholdDebugView` (E2). New: `WhoDidIt` (A4), the wake-up ID (D8), 4 `Event`
fields (E1).

### Failure modes (engineering)

| New path | Realistic failure | Test | Handling | User sees |
|---|---|---|---|---|
| Saving the 4 fields | Production schema not deployed before build 2 | schema test (every written field) | deploy first, with the go-ahead | the sync problem line; nothing silent |
| Older build saving an entry | it clears the fields | Dev probe on `c4fedda`, plain and clash | CloudKit keeps fields not set | nothing (values kept) |
| Fetch by name (E3) | offline at launch | unit: list unchanged, retried next launch | retried; checked once found empty | nothing; counts catch up |
| Wake-up ID merge | a late correction for an earlier ending | unit, both orders | the matching ending's "got up" wins | the right "got up" |
| Non-feed copies | a real second nappy within 5 minutes | unit: match and non-match | "They were two" on the kept entry | "Logged on both phones" |
| Quick finish | refused (newer details) | unit | "Couldn't finish the feed here" | the message, feed still running |

0 critical gaps (no row is untested, unhandled and silent).

### Worktree parallelization strategy

| Step | Modules touched | Depends on |
|---|---|---|
| ET1 fields, stamps, merge, kinds | FeedingCore/Model, FeedingCore/Store | — |
| ET2 schema and record mapping | schema.ckdb, App/Sync, AppTests | ET1 |
| ET3 wake-up IDs | FeedingCore/Store | ET1 |
| ET4 WhoDidIt, copies, facts | FeedingCore/Insights | ET1, ET3 |
| ET5 fetch of missing values | FeedingCore/Store, App/Sync | ET1, ET2 |
| DT1 tokens, DT2 Undo card | App/Design, App/Home | — |
| Screens (CEO T5 to T9, DT3 to DT9) | App/Home, App/Graphs, Watch | ET4, DT1 |

Lane A: ET1 → ET3 → ET4 (FeedingCore, sequential). Lane B: DT1 → DT2 (App/Design, App/Home),
from the start. Lane C: ET2 → ET5 (App/Sync), after ET1. Launch A and B; start C after ET1; merge
all; then the screens. Conflict flag: DT2 and the screens both touch `App/Home` (sequence them).

### Unresolved decisions

None in this review.

### Completion summary (engineering review)

- Step 0: Scope Challenge — scope accepted as-is (smaller arrangement, D1 A)
- Reality rows: 7/7 rows (`PLAN_REALITY: phase=eng rows=7/7 missing=none unverified=3`), 3 unverified premises
- Architecture Review: 5 issues found (A1 = E1, A2, A3 = E2, A4, A5)
- Code Quality Review: 3 issues found (CQ1 = E3, CQ2, CQ3)
- Test Review: diagram produced, 44 gaps identified
- Performance Review: 0 issues found
- NOT in scope: written
- What already exists: written
- TODOS.md updates: 2 items proposed to user (D10 C, D11 C: both built now, none added)
- Failure modes: 0 critical gaps flagged
- Unresolved decisions: 0 in this review
- Outside voice: Codex `gpt-6.2-sol` ran but unverified (severity labels unreadable); native
  fallback (Claude Plan helper) completed, 8 findings; both sets checked against the code
- Parallelization: 3 lanes, 2 parallel / 1 after ET1
- Lake Score: 0/10 (10 answers scored; no option was scored 10/10; each answer but D11 took the
  highest-scored option)

### Implementation Tasks (engineering review)

Synthesized from this review's findings. They add to the CEO review's T1 to T12 and the design
review's DT1 to DT9; CEO T10 ("storage per E1") is now ET1, ET2 and ET5; CEO T5's files are
`EventEditor.swift` and `CareEditor.swift` (SC1).

- [x] **ET1 (P1, human: ~2d / CC: ~1.5h)** — FeedingCore — the 4 encrypted `Event` fields, stamps only with a value, merge (end and wake-up ID as one; "got up" pair with the wake-up guard), `EventKind.countsAsWork`, `.bath`'s own field list
  - Surfaced by: E1 (D2 A, D8 A), E3 (D9 A), A4 (D5 A), subagent 8
  - Files: FeedingCore/Sources/FeedingCore/Model/Event.swift, Model/Payload.swift, Model/EventMerge.swift, Model/Identifiers.swift, Store/HouseholdData.swift
  - Verify: `swift test --package-path FeedingCore` (merge both orders; old file reads; no stamp without a value)
- [ ] **ET2 (P1, human: ~4h / CC: ~30min)** — Sync — `schema.ckdb` +4 encrypted fields, `RecordMapping` both ways, rewrite `thePayloadIsEncryptedAndNothingElseIs`; Dev import; Production deploy only after the parents' go-ahead (asked again), before Little Log build 2 (built 21 Nov 2026: schema.ckdb, RecordMapping and the Dev import done; the Production deploy waits for the go-ahead)
  - Surfaced by: E1 (D2 A, D8 A)
  - Files: schema.ckdb, App/Sync/RecordMapping.swift, AppTests/RecordMappingTests.swift
  - Verify: app tests in the simulator (every written field in the schema); `xcrun cktool` export matches the file
- [x] **ET3 (P1, human: ~4h / CC: ~30min)** — FeedingCore — wake-up IDs: a UUID per Woke up tap, "feed:<id>" for Start feed and the late-feed rule; "got up" stored with them
  - Surfaced by: A5 (D8 A); Codex 2, 3, 6; subagent 1, 5
  - Files: FeedingCore/Sources/FeedingCore/Store/MoreThanFeeds.swift, App/Home/CareTiles.swift
  - Verify: `swift test --package-path FeedingCore` (MoreThanFeedsTests stay green; new wake-up tests)
- [x] **ET4 (P1, human: ~2.5d / CC: ~2h)** — FeedingCore — `WhoDidIt` in `Insights/Shares.swift`: counted parent and "saved"/"worked out", feed and non-feed copies, wake-ups, facts, last night, entries
  - Surfaced by: A4 (D5 A), D11 C, D12 A; CEO T1, T3
  - Files: FeedingCore/Sources/FeedingCore/Insights/Shares.swift (new), Store/HouseholdData.swift (copies of any kind), FeedingCore/Tests/FeedingCoreTests/SharesTests.swift (new)
  - Verify: `swift test --package-path FeedingCore`, including the CLAUDE.md time cases
- [x] **ET5 (P1, human: ~4h / CC: ~30min)** — FeedingCore and Sync — the list of entries missing a value, the "checked" part of the file, fetch by name through the receive path
  - Surfaced by: E3 (D9 A); subagent 2, 3; Codex 1
  - Files: FeedingCore/Sources/FeedingCore/Store/HouseholdData.swift, App/Sync/HouseholdSync.swift
  - Verify: `swift test --package-path FeedingCore`; on-device in ET8
- [x] **ET6 (P2, human: ~2h / CC: ~15min)** — Quick finish refused says so on the Lock Screen, Control Center, Siri and the watch; the watch asks for bottle details only after success
  - Surfaced by: A2 (D3 A); Codex 5
  - Files: FeedingCore/Sources/FeedingCore/Insights/QuickFeed.swift, Shared/FeedIntents.swift, App/Model/WatchRelay.swift, Watch/App/WatchHomeView.swift
  - Verify: `swift test --package-path FeedingCore` (QuickFeedTests)
- [x] **ET7 (P2, human: ~1h / CC: ~10min)** — Feeding Dev debug lines for "done by" and "got up"
  - Surfaced by: E2 (D4 A)
  - Files: App/Spikes/HouseholdDebugView.swift
  - Verify: simulator with `-sampleData YES`, Settings' debug screen
- [ ] **ET8 (P1, human: ~3h / CC: ~30min)** — Device check — Feeding Dev build of `c4fedda` on one phone saves entries with the new fields (plain and clash) and sees a bath; then update it; both phones agree
  - Surfaced by: E1 proof; subagent 4, 8
  - Files: none (checks on the two phones)
  - Verify: the numbers match on both phones; the sync log shows the fetch by name
- [ ] **ET9 (P2, human: ~2h / CC: ~15min)** — History's "finished by" only when the end was set as Finish was tapped
  - Surfaced by: TD1 (D10 C); Codex 10
  - Files: App/Home/FeedRows.swift (through WhoDidIt)
  - Verify: unit test; VoiceOver in the audit
- [ ] **ET10 (P1, human: ~1d / CC: ~1h)** — History: "Logged on both phones" and "They were two" for every counting kind
  - Surfaced by: TD2 (D11 C), TD2b (D12 A)
  - Files: App/Home/HistoryView.swift, App/Home/FeedRows.swift
  - Verify: simulator with `-sampleDuplicate YES` widened to a nappy; unit tests in ET4
- [ ] **ET11 (P1, human: ~4h / CC: ~30min)** — Outside-voice requirements inside the design tasks: the watch's start request carries the parent and is offered only when the phone names who breastfeeds (DT5); Left/Right from the feed, not the phone's setting (DT5); the poo panel carries the swap (DT2); "Checked with iCloud" from a completed household fetch (DT3)
  - Surfaced by: Codex 4, 7, 8, 9
  - Files: Watch/App/WatchHomeView.swift, FeedingCore/Sources/FeedingCore/Watch/WatchState.swift, App/Home/FeedControls.swift, App/Home/CareTiles.swift, App/Sync/HouseholdSync.swift
  - Verify: watch simulator `-sampleWatch faceStart`; tap test for the poo panel swap
- [ ] **ET12 (P2, human: ~30min / CC: ~5min)** — Docs — rollback step "let a phone sync before going back to an earlier build"; CLAUDE.md layout lines for `WhoDidIt` and the 4 fields
  - Surfaced by: E3 (D9 A); Codex 1
  - Files: docs/planning/08-going-live.md, CLAUDE.md
  - Verify: read back

Carried from the journal's engineering list (still open there): T10, T12, T14, T15, T18, T19, T20
(T20 joins DT2's Undo card), T21. Shipped and closed: T1 to T9, T11, T13, T16, T17.

### Suppressed findings (appendix)

- P1 [INFORMATIONAL] (confidence: 3/10) — a stamp with no value in iCloud could make E3 fetch at every
  launch. No path writes one (the store sets value and stamp in one edit, the move maps both).
  Resolved anyway by D9 A's end state.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 2 | ISSUES OPEN | 5 proposals, 4 accepted, 1 deferred |
| Outside Review | Codex `gpt-6.2-sol` (CLI), auto after the CEO and engineering reviews; Codex and a Claude helper in the design review | Independent 2nd opinion | 3 | plan review: unavailable twice (engineering round: Codex unverified, native fallback completed); design: completed | engineering round: Codex 10 findings (labels unreadable), Claude Plan helper 8 findings; all checked against the code; A5 and E3 reopened and settled (D8, D9) |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 3 | ISSUES OPEN (all mapped into ET1 to ET12; 0 unresolved) | 52 issues (5 architecture, 3 code quality, 44 test gaps, 0 performance), 0 critical gaps |
| Design Review | `/plan-design-review` | UI/UX gaps | 2 | ISSUES OPEN | score: 2/10 → 7/10, 30 decisions |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | — | — |

- **OUTSIDE COVERAGE:** after the CEO review: Codex unavailable (missing recommendation marker),
  native fallback unavailable (five-minute limit). Design phase: Codex completed (8 findings), the
  Claude helper completed (14). Engineering round (this review): Codex `gpt-6.2-sol` ran (about
  870,000 input tokens, 771,000 cached, 6,600 output) but is **unverified** (severity labels
  unreadable), so it gives no outside coverage; the native fallback (Claude Plan helper, in-host)
  completed with 8 findings. No completed external review of this plan's engineering choices.
- **CROSS-MODEL:** engineering round: Codex (unverified) and the Claude helper both found the A5
  holes (the late-feed rule joining unrelated wake-ups; a reopened sleep's "got up") and the E3
  re-read's risks; only the Claude helper raised the engine reset and the build split; only Codex
  raised the watch request, Left/Right, the poo panel swap, the sync line and "finished by".
- **VERDICT:** no review CLEAR on this plan; the engineering review is complete with every finding
  answered or mapped into tasks (ISSUES OPEN means mapped work); eng review required by the
  dashboard rule until a clean run.

**UNRESOLVED DECISIONS:**
- + 3 unresolved from prior reviews (the CEO review's log row still counts E1, E2 and DS1; E1 and E2 are settled by this review, D2 A and D4 A, and DS1 by the design review)

