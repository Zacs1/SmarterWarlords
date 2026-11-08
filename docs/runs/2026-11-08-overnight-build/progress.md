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

## 21:40 update

- Phase 0 tagged. Gate 0 passed with the commander disabled, before the adapter review fixes.
- Phase 1 tagged. The 25-minute round p1b passed all phase 1 checks: longest staging wait 3:51, 5/5 assaults with 3+ groups, idle 24 group-minutes against 84 in baseline over the same 25 minutes, 0 script errors. Tick cost averaged 12 ms, which phase 5 must bring under 5 ms.
- Phases 3 and 4 written, lint clean, first smoke round found two problems: a one-off startup script error in Warlords' purchase FSM from emptying its list (now an unaffordable sentinel entry), and first waves leaving as lone men because the go fired before top-ups (now men are bought first, and the go waits up to 40 s after first arrival while men are still affordable).
- Decision: vehicles are only bought when staging is at least 300 m beyond the far dismount distance (1100 m from the target). Shorter hops lose more to the 90 s mount-up than they save.
- Seize threshold from gate 0 census: no countdown at w=6 vs g=9; countdown at w=8 vs g=3 and e=20 vs g=1. Attackers appear to need to outnumber those inside.

## 21:50 update

- gate23 (12 min, built before the reviewer fixes): gate 2 PASS (armour on board and radio 5 s after being seen, plan at_wanted 0 to 2 plus combat vehicle, 19 board entries all traceable, unseen tank never on board). Phase 3 PASS: launchers 8 of 7 wanted, mount times [0, 90, 91], 13 bought 0 unused, 612 vehicle samples 0 solo, 16 combat samples 0 ahead, 40 purchases 0 below reserve. RPT tests/server/runs/2026-11-08_21-32-53_gate23.
- Opus reviewer on phases 3 and 4: 10 findings, all checked against the code and fixed (vehicles released on a new plan; fleet cap limits buying only, reuse radius 500 m; re-seat when Warlords' timer unassigns the crew; pulled groups no longer count as casualties; staging abort restarts the gather clock; stale leg flags cleared; reserve shrink select form; pulled riders fast travel once on foot; player reports count each enemy; smoke and ammo trips once per wave).
- Phase 6 decision: hidden-AT hunting estimates the firing area from the wreck towards the objective. It does not read the killer's real position, to keep the "only what soldiers have seen" rule.
- gate4 running on the fixed tree.

## 22:05 gate4 first run
Counterattacks at the scenario's spawns were never detected: nobody on WEST could see them (the check is honest, board = what soldiers saw). A real EAST detection at Leqa (t=478) did show the chain working: response in the same tick, 7 groups staging-aborted, stand-down at +161 s. Scenario fixed with a lone WEST observer outside the commander's groups. 0 script errors with all reviewer fixes.
