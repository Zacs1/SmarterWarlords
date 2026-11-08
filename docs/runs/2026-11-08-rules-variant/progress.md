# Rules variant run: progress log

Merged with the overnight build into one run, at the user's request. The overnight log is `docs/runs/2026-11-08-overnight-build/progress.md`.

Order of work:
1. Finish the play-test rework from the overnight run (muster + rally, one attack direction, commander panel). This is effectively part A, since the "notes from playing" section of the prompt was left as the unfilled placeholder and the play-test feedback is logged in the overnight progress file.
2. Finish the overnight run's outstanding gates and docs (phase 5/6 gates, performance, LAMBS round, tags).
3. Parts B to H in order, then the final regression, the two final soaks, then "if time remains".

Mapping decision: this prompt says "staging", "holding points" and "wave". It was written before the muster + rally rework the user asked for afterwards, so "staging" means a sector's muster point or the rally, and "holding point" means the rally point. Recorded for the decision log.

## Log
- Prompt saved. Helper agents started to read Warlords' seize, respawn, vote-reset and income code, and LAMBS' task and danger code. Notes go in `docs/runs/2026-11-08-rules-variant/notes/`.
- Muster + rally + single direction + commander panel written: staging.sqf and wave.sqf rewritten, status.sqf new, patches across commander, defence, vehicles, logistics, smart, watchdog, settings, radio, debug, client. Analyser and gate4/gate6 updated to the new model. memoryAvoidDegrees cut from 40 to 25 because there's now only one direction and the user asked not to get "too extra".
- Warlords and LAMBS research notes are in notes/. Worth remembering for later parts: clearing a target with attackers still inside exposes them to the server kill loop within 20 s (part B); under LAMBS skip the set* commands while a group reacts (part H); LAMBS' information sharing inflates knowsAbout (part H, needs a deliberate choice).
