# Hand-off: rules variant (2026-11-08 to 2026-11-09)

## What it set out to do

Add game-mode rule changes on top of the commander: deadlock breaking, economy and capabilities, raids and probes, pickets and proportionate response, a commander menu, a commander that uses all of it, and smarter squads (parts B to H). The user merged the overnight build into this run, so Part A became the play-test rework. Part R (resilience) was added mid-run with batched testing, and the user also made a per-commander activity check a gate on every soak.

## How it went

Every part was built. Parts A, B, D, E, F, H and R are tagged. C and G have no tag. Part C's scenario gate passed, but C's and G's soak gates were failed or not recorded. The final soak ran on 1fa4e23 with CBA and LAMBS loaded.

Run folders are under `tests/server/runs/`.

| Part | Built | Gate | Evidence | Tag |
| --- | --- | --- | --- | --- |
| A Play-test rework (muster, rally, one direction, panel) | Yes | No PASS or FAIL recorded | `2026-11-08_23-15-48_smokemuster` and `2026-11-08_23-26-18_gate6r` ran | `rules-a-done` (06d8b5f) |
| B Deadlocks | Yes | PASS: all 8 checks. After review fixes, all behaviour checks PASS and 0 script errors; only the rebuild check failed, and that check was wrong. It was corrected, and no rerun is recorded | `2026-11-08_23-48-07_gateb2`, `2026-11-09_02-51-10_gateb5` | `rules-b-done` (06d8b5f) |
| C Economy | Yes | Scenario PASS, 6 of 6, 0 script errors. Soak: `final_fight_not_walkover` FAIL (no base fight). Late-round affordability and "leader still wins" are not recorded | `2026-11-09_15-19-53_gatec2` | None |
| D Raids and probes | Yes | PASS: 16 of 16, 0 script errors, with resilience merged | `2026-11-09_16-09-26_gated11` | `rules-d-done` (3f65535) |
| E Pickets and response | Yes | PASS, 0 script errors | `2026-11-09_14-43-17_gatee10` | `rules-e-done` (aed4b89) |
| F Commander menu | Yes | PASS, 0 script errors, no players connected. Testing with real players is not recorded | `2026-11-09_01-16-09_gatef4` | `rules-f-done` (06d8b5f) |
| G Commander uses the rules | Yes | Soak: `partg` raid rate FAIL (2 raids, 0 probes). "Targets capability sectors more than chance" and "no deadlock outlasts the timer" are not recorded | `2026-11-09_17-00-36_soakfinal` | None |
| H Smarter squads | Yes | Vanilla PASS. LAMBS all PASS after a gate fix (posture changes 1.07 a minute against a limit of 1.5, once keyed by side). The LAMBS round was cut at 10 of 14 minutes by the crash | `2026-11-09_01-01-49_gateh3`, `2026-11-09_15-19-47_gateh4l` | `rules-h-done` (06d8b5f) |
| R Resilience | Yes | PASS: all 11 sabotage cases, recovery in 10 to 70 s. Soak no-progress check 16 of 16 | `2026-11-09_16-37-22_sabotage2`, `2026-11-09_17-00-36_soakfinal` | `rules-r-done` (1fa4e23) |

Final soak `2026-11-09_17-00-36_soakfinal` (results logged in the front-line `progress.md`, since it ended during that run):

- 89:51, no winner, 6 captures, 0 script errors, install unchanged.
- Commander activity gate 15 of 16. Which commander failed is not recorded in the logs. Earlier: 14 of 16 on `gate6r`, against 10 of 16 for vanilla.
- Respawn rung used 0 times. It fired once in `sabotage2`, for the swimmer.
- FAILs: holding limits (Reserve over 7:00 for WEST 1-1 and 1-4, EAST 1-1 and 1-3), `partg` raid rate, `final_fight_not_walkover` (no base fight, ended by time), and the generic "groups moved" check, which counts non-warlord groups.

Rules-off smoke `2026-11-09_16-37-44_smokeoff2` on 085d38f: 10 minutes, 0 script errors, install unchanged, the commander and ladder ran.

Performance: tick average 12.3 ms once measured properly (`2026-11-09_04-09-59_gatee3`), and 12.87 ms in `smokeoff2`, after the 11:15 slicing pass. The target of well under 5 ms was not met.

Playable was rebuilt from 1fa4e23 after resilience passed. A rebuild after the final soak is not recorded here. See `PLAYABLE.md`.

Spec and decision log: `docs/design/rules-variant.md`. Player-visible text: `notes/player-visible-text.md` (at 085d38f). Prompt conflict: its "staging" and "holding point" were mapped to the muster and rally model.

Tanoa sector types, from `commander/swlc/maps/Tanoa.sqf` (please check; Balavu and Leqa are design choices, no tower or depot was confirmed on the map):

| Sector | Position | Type |
| --- | --- | --- |
| Laikoro | 1715, 6128 | Industrial |
| Rautake | 3411, 6704 | Town |
| Tavu | 983, 7656 | Town |
| Balavu | 2665, 7345 | Military |
| Leqa | 2341, 8183 | Radio |

## Next steps

1. Host a round to test what automation couldn't: the commander menu, raids with borrowed groups, squad behaviour up close, and the final base fight.
2. Get a real base fight in a soak so Part C's gate can be judged.
3. Raids and probes were too rare in the soak (2 and 0). Part G needs another look.
4. The Reserve hold was a real bug, fixed in the front-line run (ca26717). Confirm it in the next soak.
5. An Altis smoke test and further balance soaks are not recorded as done.

## Red flags

- `gateb`, `gatef` and vanilla `gateh` ran before the waypoint guard fix. The log planned to rerun them in the final regression, and the only regression that followed was the soak.
- WEST's vote never resolved in `gatee2` (1 of 22 recent rounds). The cause was not found. `SWLC_fnc_cmdVoteStuck` nudges it now.
- Part H rearm timed out on early trips in earlier rounds, and the cause is unknown.
- 1fa4e23 (the swimmer fast travel fix) is linted but was not rerun in the sabotage scenario.
- The PC blue-screened at about 15:30 on 2026-11-09 with bugcheck 0x116 (VIDEO_TDR_FAILURE, status C000009A), identical to one on 2026-10-21. Three servers were up for the first time, so load can't be ruled out, and the run dropped to two at a time. Details are in the overnight hand-off.
- The unchanged-install check did not run for `gatee4` (`2026-11-09_04-47-23_gatee4`, stopped for low memory) or for the three rounds cut by the crash: `smoker`, `gateh4l` and the first `gated11` (`2026-11-09_15-30-00_gated11`).

Written after the fact, during the 2026-11-09 front-line run, from the progress logs. Later work has since superseded some of it; see `docs/runs/2026-11-09-front-line/` for the current state.
