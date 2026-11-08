# Progress log: overnight build (2026-11-08)

Prompt is in `prompt.md`.

## Status
- Queued. Starts only after the test-feasibility run is finished: baseline round analysed and plotted, hand-off written, final message sent.
- The user replaced the design doc with an updated version during the feasibility run. That is intended. Read the current version first.

## Plan
Phases 0 to 5, then phase 6 (twelve smarter behaviours, added by the user and in `prompt.md`), then the "if time remains" list. Phase 6 notes:
- Each behaviour has its own on/off switch and tunables in the settings file, default on.
- Commit after each behaviour, tag `phase-6-done` at the end, one soak round with everything on.
- Add a "Phase 6: smarter behaviours" section to the design doc, describing each one as built.
- Hand-off and final message need phase 6 results per feature and the full list of radio lines.

## Current phase
Not started.

## Last gate passed
None.

## In flight
Read-only prep finished before the feasibility run ended, at the user's request. Findings are in `notes/`: `ai-control-loop.md`, `purchases-fasttravel.md`, `sectors-server-flow.md`. Read these before writing the adapter. No code written yet.

Headline findings to carry into phase 0:
- Steer Warlords' AI, don't fork or stop it. `fn_WLAICore.fsm` has no per-group off switch and only orders moves on entering a state. Commander re-asserts its waypoints each tick and after respawns and vote resets, and casts AI votes through `BIS_WL_selectedSector`.
- Fast travel value 4 blocks players from the contested sector and turns off the FSM's own attack travel, and scripted commander moves aren't checked. Make it the default in the scenario's own Params. Run the phase 0 gate round at 4 and watch targets past the first capture.
- Replace vanilla AI buying, which never buys unarmed transport. CP is per unit (`BIS_WL_funds`), there is no side pool.
- Playable scenario needs `BIS_WLAIVoting` on and `disabledAI = 0`. On a client host, server setup waits for the host to be on WEST or EAST.
- On-foot AI warlords that stand still for about 9 minutes are killed. AI crews holding still for 180 s get ordered out. AI inside sectors neither owned nor targeted can be killed.

## Decisions
None yet.
