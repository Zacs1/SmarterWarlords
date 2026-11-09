# Hand-off: overnight build (2026-11-08)

## What it set out to do

Build the design doc's phases 0 to 5 and the twelve phase 6 behaviours the user added mid-run, test each against its finish line, and leave a playable Tanoa scenario. The user later switched testing to batches (3+4, then 5+6, then one final soak) and asked for something playable by about 23:00.

## How it went

Phases 0 to 4 were built, gated and tagged. Phases 5 and 6 were built, but no gate result is recorded for them and neither has a tag. A playable build went out that evening and the user played it. The run was then merged into `docs/runs/2026-11-08-rules-variant/`, so this log stops there.

Run folders are under `tests/server/runs/`.

| Phase | Built | Gate | Evidence | Tag |
| --- | --- | --- | --- | --- |
| 0 Adapter | Yes | PASS, with the commander disabled and before the adapter review fixes | `2026-11-08_20-47-40_gate0` | `phase-0-done` (4c3360a) |
| 1 Core loop | Yes | PASS: longest staging wait 3:51, 5 of 5 assaults with 3+ groups, idle 24 group-minutes against 84 in baseline over the same 25 minutes, 0 script errors. The separate soak was dropped under the batched test plan | `2026-11-08_21-01-27_p1b` | `phase-1-done` (4c3360a) |
| 2 Intel and radio | Yes | PASS: armour on the board and radio 5 s after being seen, plan changed, 19 board entries all traceable, unseen tank never on the board | `2026-11-08_21-32-53_gate23` | `phase-2-done` (a6afd55) |
| 3 Kit and vehicles | Yes | PASS: launchers 8 of 7 wanted, mount times 0, 90, 91 s, 13 vehicles bought and 0 unused, 0 solo samples, 0 combat vehicles ahead, 0 purchases below reserve | `2026-11-08_21-32-53_gate23` | `phase-3-done` (a6afd55) |
| 4 Defence and players | Yes | Behaviour passed: response 0 s after detection at both spawns, stand-down at 202 s and 186 s, 1 staging abort, 9 reserve postings. Two checks failed, both from one script error in Bohemia's `fn_WLInit.sqf`, not commander code | `2026-11-08_22-02-39_gate4b` (first try `2026-11-08_21-45-29_gate4` had a scenario fault) | `phase-4-done` (a6afd55) |
| 5 Polish | Difficulty and cost logging yes (ac6689e) | Performance target NOT met: tick cost 42-58 ms in the smoke rounds against a target well under 5 ms. Server FPS comparison and a phase 5 LAMBS round are not recorded in this log | `2026-11-08_22-20-47_smoke56`, `2026-11-08_22-27-26_smoke56b` | None |
| 6 Smarter behaviours | Yes, all twelve committed. Differences are in the design doc's "Phase 6 as built" | 0 script errors in the two smoke rounds. Per-feature PASS or FAIL is not recorded. `2026-11-08_23-26-18_gate6r` ran after the muster rework, but its gate result is not in either log | As left | None |

- Playable: `Documents\Arma 3\mpmissions\SmarterWarlords.Tanoa`, commit 13c6a4a. The play-test feedback is verbatim in `progress.md` and drove the muster and rally rework in the rules-variant run.
- Gates 2 and 3 ran before the reviewer's 10 fixes. Their rerun on the fixed code is not recorded.
- The "if time remains" items (tuning soaks, Altis smoke, HEMTT dry run) are not recorded as done here.
- Radio lines: `docs/runs/2026-11-08-rules-variant/notes/player-visible-text.md`.

## Next steps

1. Update the NVIDIA driver before playing (see the crash below). This is a suggestion, not something the logs tested.
2. Tick cost is still over target. See the rules-variant hand-off for later numbers.
3. Phase 6 behaviours have no per-feature test result. Check them in play or give them scenario checks.
4. Player features need real players: request actions and joining a player's push were only confirmed to raise no errors with nobody connected.

## Red flags

From the vanilla baseline. These came from the test-feasibility run (`2026-11-08_19-26-56_baseline`, see its hand-off), not this log:

- Balavu was a 41-minute stalemate. Warlords has no target timeout, so it only ended by attrition.
- EAST kept Balavu as its target after WEST had taken it. An enemy capture doesn't clear a side's target.
- Three extra EAST groups, not warlord groups, appeared at 50:38 and were gone by 58:39. The cause is not recorded.
- The server logs one startup warning about deleted content for `a3_characters_f`. It is benign: the mission runs normally and the analyser reports it apart from script errors.
- Server build 25600558 and client build 25623484 differ. That only matters if a client connects to a dedicated server.

From the later merged work, logged in the rules-variant `progress.md`:

- The PC blue-screened at about 15:30 on 2026-11-09 with bugcheck 0x116 (VIDEO_TDR_FAILURE, status C000009A). An identical one is in the Windows log for 2026-10-21. Three servers had been up for 11 minutes, the first time that many ran, so load can't be ruled out. Dedicated servers don't render, and no resource exhaustion was logged. The GPU and driver are not in the log; read from this machine while writing this: NVIDIA GeForce RTX 5070 Laptop GPU, driver 32.0.16.1088.
- The unchanged-install check did not run for four rounds: the 04:47 `gatee4` (`2026-11-09_04-47-23_gatee4`, stopped 3 minutes in for low memory) and the three cut by the crash, `smoker`, `gateh4l` and the first `gated11` (`2026-11-09_15-30-00_gated11`). Other rounds' checks only cover their own rounds.

Known limits:

- No artillery on stock Tanoa. Prep fire only uses a piece already on the map, and buying one was not built.
- Smoke is a simulated throw: a smoke shell appears 40 m ahead of the leader, from one group only.
- Merging is limited: warlords stay in their own groups, so a merge moves only bought men.
- The built test mission (`tests/missions/`) is gitignored and regenerated from `reference/`. The playable build is generated too and lives outside the repo.

Written after the fact, during the 2026-11-09 front-line run, from the progress logs. Later work has since superseded some of it; see `docs/runs/2026-11-09-front-line/` for the current state.
