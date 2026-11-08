# Progress log: overnight build (2026-11-08)

Prompt is in `prompt.md`.

## Status
- Running. Feasibility run finished (hand-off written and committed). The feasibility final message content must also go in this run's final message, since mid-run text may not reach the user.
- The user replaced the design doc with an updated version during the feasibility run. That is intended. Read the current version first.

## Plan
Phases 0 to 5, then phase 6 (twelve smarter behaviours, added by the user and in `prompt.md`), then the "if time remains" list. Phase 6 notes:
- Each behaviour has its own on/off switch and tunables in the settings file, default on.
- Commit after each behaviour, tag `phase-6-done` at the end, one soak round with everything on.
- Add a "Phase 6: smarter behaviours" section to the design doc, describing each one as built.
- Hand-off and final message need phase 6 results per feature and the full list of radio lines.

## Test plan change (from the user, mid-run, overrides the per-phase test rhythm in `prompt.md`)
"From here, test in batches instead of after every phase." Verbatim points:
- Build phases 3 and 4 together and test them in one set of scenario tests.
- Then phases 5 and 6 together, then the final soak round.
- Keep scenario tests short (the cut-down test variant, not full rounds).
- After each build step, still lint and do a quick smoke round, a few minutes, just enough to catch script errors before stacking more on top.

How I'm applying it: p1b (25 min, already running when the message came) stands as the phase 1 evidence, and the separate phase 1 soak is dropped in favour of the single final soak. The gate 2 scenario is short, so it runs with the phase 3+4 scenario set. The phase 5 LAMBS compatibility round and the phase 6 scenario checks are short rounds in the 5+6 batch.

## Current phase
Building phases 3 and 4 together. Code under `commander/swlc/`, copied into both missions by the build script. Test scenarios under `tests/mission_overlay/swl/scenarios/`.

## Last gate passed
Phase 0: PASS on evidence (`tests/server/runs/2026-11-08_20-47-40_gate0/`), not yet committed or tagged.

## In flight
Read-only prep finished before the feasibility run ended, at the user's request. Findings are in `notes/`: `ai-control-loop.md`, `purchases-fasttravel.md`, `sectors-server-flow.md`. Read these before writing the adapter. No code written yet.

Headline findings to carry into phase 0:
- Steer Warlords' AI, don't fork or stop it. `fn_WLAICore.fsm` has no per-group off switch and only orders moves on entering a state. Commander re-asserts its waypoints each tick and after respawns and vote resets, and casts AI votes through `BIS_WL_selectedSector`.
- Fast travel value 4 blocks players from the contested sector and turns off the FSM's own attack travel, and scripted commander moves aren't checked. Make it the default in the scenario's own Params. Run the phase 0 gate round at 4 and watch targets past the first capture.
- Replace vanilla AI buying, which never buys unarmed transport. CP is per unit (`BIS_WL_funds`), there is no side pool.
- Playable scenario needs `BIS_WLAIVoting` on and `disabledAI = 0`. On a client host, server setup waits for the host to be on WEST or EAST.
- On-foot AI warlords that stand still for about 9 minutes are killed. AI crews holding still for 180 s get ordered out. AI inside sectors neither owned nor targeted can be killed.

## Decisions
Kept in the design doc's "Decision log" section. Headlines: steer not fork; commander buys vehicles, infantry top-ups stay vanilla until phase 3; FT 4 scenario default; next wave can launch by the 4-minute cap even while another wave is in flight.
