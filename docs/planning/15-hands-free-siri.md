# Hands-free logging with Siri (26 Nov 2026)

Parent A asked (26 Nov 2026): log with the voice, without picking up the phone and without an
unlock: start and finish a feed, and give its details (the milk, the sides, how much the baby
drank) by voice, as the app takes them. (Examples below use "Sam", the made-up name in the sample
data.)

What was there before this plan:

- "Start a feed in Little Log" and "Finish the feed in Little Log" already ran on a locked phone
  (`FeedIntents.swift`: `.alwaysAllowed`, `.background`, the parents' choice of 16 Nov 2026). The
  sides and the amounts were added later in the app (the details panel opens on Home).
- Sleep, nappy and medicine had actions for Control Center and the Lock Screen, but no Siri phrase
  (doc 06, Q3: "Not Siri or the Action Button for these"). Said to Siri, they opened the app,
  which needs an unlock.
- "Ask Little Log" needs Touch ID and opens the app (AI insights step 4, F1 A, D13).
- The watch had no Siri actions.

## Decisions (Parent A, 26 Nov 2026)

| | Question | Choice |
|---|---|---|
| V1 | What Siri can log | **C**: feeds with their details, sleep, nappies (with poo colour and texture) and medicine, on the phone **and on the watch**. This reverses doc 06's Q3 for Siri. |
| V2 | A spoken amount | **A**: Siri reads the amount back ("90 ml of formula. Is that right?") and saves it only after "yes". Numbers like 15 and 50 sound alike, and a wrong amount would spoil "Bottles through the day" (doc 14). |
| V3 | Ask on a locked phone | **B**: Ask works on a locked phone and Siri reads the answer aloud. This changes D13 of `12-ai-insights-gauntlet.md` for Siri. It has its own short engineering review before it is built (step 3). |
| V4 | Unlock for logging | None, as on 16 Nov 2026: every logging action runs on a locked phone. Anyone near the phone can log by voice; a stray Start moves the next alarm later until Stop · discard, as with the Control Center button. |
| V5 | A question asked on a locked phone | **A**: kept, and shown in Ask after the next unlock. Siri reads the answer; a small file the locked phone can add to (but read only once unlocked) holds it, and at the next unlock it joins Ask's list for 24 hours, as a typed question does. |
| V6 | A danger sign said to Siri on a locked phone | **B**: Siri reads the NHS's urgent words at once (call 999, or 111 for advice), the Get help now page opens at the next unlock, **and a "Get help now" notice shows on the Lock Screen** (one tap, after Touch ID, opens the page). This adds the one thing D13 kept off the Lock Screen. |
| V7 | "Ask Little Log" on an unlocked phone | **A**: as today: Little Log opens on Ask, shows the answer and reads it aloud. Only a locked phone answers in Siri. |
| V8 | The test app's name (27 Nov 2026) | **A**: "Little Log Dev" is renamed **"Test Log"** (home screen, watch and Siri; bundle IDs, container and data unchanged). With both apps on a phone, "Finish the feed in Little Log Dev" made Siri ask "Little Log Dev or Little Log?", and after that question Siri ended the conversation: the feed was finished but its amount never asked. Both phones hold both apps, so the real app would meet the same question. |

## The conversations

Siri's words are plain facts: no "due", "overdue", "missed", "enough" or "too much" (hard rules,
no verdicts). The baby's name is used when the phone knows it, else "the baby". An App Shortcut
phrase can hold words from a fixed list (a milk, a nappy, a medicine), never a free number, so an
amount is always Siri's question after the phrase.

**Start a feed** (as before): "Start a feed in Little Log". On a bottle-only phone with no milk
named: "Formula or expressed milk?". "Start a formula feed in Little Log" names it. Siri: "Feed
started at 03:10."

**Finish the feed**: "Finish the feed in Little Log". The feed is finished and saved first, then
Siri asks only what this feed is missing, one question at a time. If the parent goes quiet or
says "Cancel", the feed stays finished and the app's details panel asks for the rest, as today.

- A bottle with no amount (a feed started as formula or expressed, or a bottle added during it):
  "How much formula did Sam drink, in ml?" "90." "90 ml of formula. Is that right?" "Yes."
  On "No", Siri asks the amount once more; a second "No" saves no amount ("The amount is not
  saved. Add it in the app."). Amounts from 5 to 300 ml, as on the watch; anything else is asked
  again.
- No bottle and no side yet (a breastfeed): "Which side: left, right, left then right, or right
  then left?" The order matters: the next-side suggestion reads the last side (`suggestedNextSide`).
  "Not sure" saves no side.
- A feed that already has its details: nothing is asked.
- At the end: "Feed finished at 03:35. 25 minutes, 90 ml of formula." (or "left then right").

**Add a bottle**: "Add a bottle in Little Log" (or "Add formula in Little Log", "Add expressed
milk in Little Log"). It goes to the feed running now, or to the last feed when it finished in
the last 2 hours and has no bottle of that milk yet: the app's own rules (`DetailChoices`, the
watch's `addBottle`). "Formula or expressed milk?" when not named, then the amount, read back, as
above. A bottle added to the feed running now has no amount yet: its amount is asked at "Finish
the feed", as the app's Bottle during a feed. With no such feed: "There's no feed to add it to.
Start a feed first." (A past feed by voice is not in this plan.)

**Sleep**: "Baby's asleep in Little Log" (also "Asleep in Little Log"): "Asleep at 19:40." "Baby's
awake in Little Log" (also "Woke up in Little Log"): "Awake at 21:05. Asleep 1 hour 25 minutes."
The same rules as the buttons (`quickFellAsleep`, `quickWokeUp`).

**Nappy**: "Log a nappy in Little Log", or with the kind named: "Log a wee / poo / wet nappy /
dirty nappy in Little Log". "Wee, poo or both?" when not named. For a poo: "What colour? Yellow,
green, brown, pale, other, or skip." then "Runny, loose or firm, or skip?". Saved: "Poo at 03:40,
yellow, loose." The colour and texture lists are the app's (`PooColour.known`,
`PooConsistency.known`), with the app's own words.

**Medicine**: "Log a medicine in Little Log", or by name: "Log Vitamin D in Little Log" (the
household's list from Settings; the phrase list is refreshed when it changes). "Which one?" when
not named, with the list. Saved: "Vitamin D at 08:00." Never a dose, a time to give, or a check
(hard rules).

**On the watch**: the same phrases and questions, said to the watch. The watch has no log of its
own: it sends the same taps it sends today (`WatchCommand`, `WatchAction`: start, finish,
`addSide`, `addBottle`, `amount`, `pooDetails`, `medicine`) and chooses the questions from the
phone's last state (`WatchState`). If the phone answers within a few seconds, Siri says what was
saved; if not: "Saved on the watch. It goes to your iPhone when it's near." (the watch's queue).

## Steps

1. **The phone** (V1 phone part, V2, V4). Siri phrases for every logging action; Finish asks the
   missing details; Add a bottle; nappy with poo details; medicine by name.
   - `FeedingCore`: what Siri asks for a feed and how an answer is saved (`VoiceLog`), pure and
     tested on Linux: the questions for a finished feed, the side orders, the amount bounds, the
     feed a bottle goes to. It uses the existing changes (`editFeedDetails`, `quickNappy`,
     `addMedicine`) so a voice entry is the same as a tap.
   - `Shared/`: the intents, with Siri's words in one place (`SiriText`), tested for the
     no-verdict words.
   - `App/Model/FeedingShortcuts.swift`: at most 10 App Shortcuts (Apple's limit).
2. **The watch** (V1 watch part). The same intents in the watch app, sending the watch's taps.
3. **Ask on a locked phone** (V3). A short engineering review first, then the build. What it must
   settle: the AI running with the app closed (D13, and the gate's "app open" check before every
   call); where a locked question is kept (`QuestionLog` uses complete file protection, which a
   locked phone can't write); App Attest with the phone locked; how long Siri waits (Ask's slowest
   answer in the model tests was 10 s); a danger sign with the phone locked (Siri says "Call 999"
   and Get help now waits for the unlock); what Siri reads (the facts, the AI's sentences, "This is
   AI, not medical advice", the NHS page's name); and an unlocked phone (opens Ask, as now).

Each step: build, the narrow tests, Codex's check, the full suite, then the Duo (and the Ultra 4
for step 2). TestFlight when Parent A asks.

## On the devices (manual)

Siri can't be driven by the tests. On the Duo, locked, by day and at night: each phrase, each
question, "No" to an amount, going quiet half-way, Cancel. On the Ultra 4: the same, with the
phone near and with it away. Also: "Allow Siri When Locked" must be on (Settings › Apple
Intelligence & Siri); with it off, Siri asks for an unlock for everything.

Found on 27 Nov 2026:
- iOS 27 has Settings › Siri (no "Apple Intelligence & Siri"), and no "Always Show Speech". To
  tell a mishearing from a wrong action, type to Siri.
- The first phrase on the watch asks "Turn on … shortcuts with Siri?". A "Turn On" that does
  nothing is fixed by opening the watch app once. Never tap "Don't Allow": developers report the
  watch keeps that answer for good.
- The phone app has Siri's "close words" files (`Metadata.appintents/nlu`); the watch app has none,
  so the watch needs the exact words.
- The watch showed its last reply without saying it (the watch's own Siri voice setting, or a
  wrist lowered during the few seconds it waits for the phone; not yet known which).
- Once, "Start a feed" on the Duo ran Log a nappy ("Wee, poo or both?"; nothing saved). Likely a
  mishearing; if it comes back, make every nappy phrase say "nappy".

## Built (26 Nov 2026): steps 1 and 2

- `FeedingCore/Sources/FeedingCore/Store/VoiceLog.swift`: the questions (`VoiceLog.questions`,
  `voiceQuestions`), the side orders (`VoiceSides`), the amounts (5 to 300 ml), where a spoken
  bottle goes (`bottleTarget`, `voiceFeeds`) and the empty-amount check (`voiceAmountGap`). Tests:
  `VoiceLogTests` (16), and `WatchStateTests.theWatchKnowsTheBabysName`.
- `Shared/SiriChoices.swift` (the lists Siri hears, and the amount question with its read-back,
  `SiriAmount`) and `Shared/SiriText.swift` (Siri's words), built into the phone and the watch.
  Tests: `AppTests/VoiceLogTextTests` (the words, no verdict words, every logging action runs on a
  locked phone, at most 10 App Shortcuts).
- The phone: `FinishFeedIntent` asks (the Lock Screen widget's button passes `asksDetails: false`),
  `App/Model/VoiceIntents.swift` (Add a bottle, Log a nappy, Log a medicine, `VoiceRunner`), Fell
  asleep and Woke up offered to Siri, 8 App Shortcuts (`FeedingShortcuts`). Start's words no longer
  say "Add the sides and bottles in the app".
- The watch: `Watch/App/WatchVoiceIntents.swift` (7 App Shortcuts, `WatchVoice`), the baby's name in
  `WatchState.babyName`, Finish shared with the watch's button (`PhoneLink.sendFinish`).

**Codex's review (26 Nov 2026, `gpt-6.2-sol`, about 175,000 tokens; 9 findings, all fixed):** an
empty medicine list no longer logs Vitamin D by itself, and a named medicine must be on the list;
Siri fills only an empty amount, so one the other parent saved meanwhile is kept and said; the
watch's Finish after an unanswered Undo of Finish goes after it, as the button's does; Add a bottle
never chooses a hidden copy of a feed logged on both phones; an amount given in the Shortcuts app
is read back too; a bottle is saved as soon as its milk is known, so going quiet at the amount
keeps it; the details panel is set before the first question and cleared only once all are
answered; a breastfeed on a bottle-only phone or watch asks its sides; the watch waits for every
tap's answer, and says when the phone turned one down; Siri's medicine names follow the list,
changed on either phone. Accepted: a watch's Add a bottle can still name a feed the phone has since
replaced with a newer one (the phone checks the milk, not which feed is newest).

## Step 3: Ask on a locked phone (26 Nov 2026)

The short review's three questions were Parent A's V5 to V7 (above). The engineering choices:

- **The action** (`AskLittleLogIntent`): `.alwaysAllowed`, `[.background, .foreground(.dynamic)]`.
  Unlocked (`isProtectedDataAvailable`): `continueInForeground` and Ask's own route, as before (V7
  A). Locked: `LockedAsk.answer`, and Siri reads the reply. In the first seconds after a lock the
  phone still counts as unlocked, so Siri asks for Touch ID and opens Ask, as before.
- **The route is Ask's own** (`InsightEngine.ask`): the danger signs first (before set-up or
  anything that could make them wait), the medicine replies, the gate with both yeses and the
  pause, then the AI. Only the "app open" check before each call (`isOpen`, step 4 Y2) is lifted,
  for this path alone. A typed question with the AI makes it wait ("Already asking.").
- **What Siri reads** (`InsightQuestions.spoken(locked: true)`): the log's facts, the AI's
  sentences, "This is AI, not medical advice.", and each NHS page's name "in Ask when you unlock".
  A danger sign: "Get help now. The NHS page "When to get urgent medical help for babies and
  children under 5" is in your notifications, and opens when you next open Little Log. It says when
  to call 999 or NHS 111." Never the list's headings alone ("Immediate action required: Call
  999"): without their conditions they read as an order, and the app never says how urgent
  something is. The AI's help flag for a parent's feelings: the page's name and where it waits.
- **Kept** (V5 A): `QuestionLog` never writes its main file while the phone is locked, nor before
  it has been read, so a phone that Siri starts while locked can't write over the questions it
  couldn't read. A locked question goes in its own file in `questions-locked/` ("complete unless
  open": a locked phone can make it, only an unlocked one open it again), out of backups, and joins
  the list at the next unlock (`takeLocked`, on the "protected data available" notice and at
  launch). Siri's reply is marked read, so Ask doesn't read it again.
- **The Lock Screen notice** (V6 B, `HelpNotice`): Time Sensitive, "Get help now", with nothing
  from the question or the log; a tap (after Touch ID) opens Get help now, or Ask for a parent's
  help.
- **Siri's wait**: 25 seconds (Ask's slowest model-test answer was 10). Past it: "Little Log is
  still asking. The answer will be in Ask when you unlock."; the answer is kept unread, so Ask
  reads it aloud when it shows it.
- **Still to check on the Duo**: App Attest and the AI call with the phone locked, how long Siri
  really waits, Siri's voice reading a long answer, the notice on the Lock Screen and its tap.

The AI parts changed (`App/Insights/`, `FeedingInsights`), so the next TestFlight upload runs both
halves of the model tests (cards against `b963395`, Ask against `661eee1`).

**Codex's review of step 3 (27 Nov 2026, `gpt-6.2-sol`, about 135,000 tokens; 12 findings).**
Fixed: the danger check reads "isn't", "can't", "doesn't" and the rest as "is not" and so on, so
"She isn't breathing" opens Get help now and never reaches the AI (this gap was older than step 3
and also open for typed questions); the danger check comes before anything that could ask for an
unlock, and a refused unlock still gets the help; a locked phone that can't read a questions file
changed in the last 10 minutes answers "Unlock, then ask again" instead of sending the question
without the one before it; the locked help words name the NHS page and say it tells when to call
999 or NHS 111, with no order; Siri's 25 seconds no longer wait for the answer, which carries on in
the background, posts its help notice whenever it comes, and is read aloud in Ask if Siri gave up;
a locked file goes only once the main file holds it; a change just after the unlock reads the main
file first; a question taken out while locked stays out; a locked answer is kept as read from the
start, so Ask never reads it again; Get help now opens by itself the next time Little Log comes to
the front, within an hour. **Not changed, older than step 3, for Parent A:** a second try at the
AI reuses the household's yeses read for the first (a few seconds; the gate is still asked before
each call); and Siri reads a medicine's name as the parent typed it, so a name holding a dose
would be read aloud, and an AI sentence with no banned word (such as "absolutely all right") is
read as the screen shows it (step 3 D2 B's recorded limit).
