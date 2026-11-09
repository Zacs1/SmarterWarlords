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

- Part B written and patched: rules.sqf (capture pause and decay, respawn fix, commitment timer, rebuild), gateb.sqf scenario, analyser checks --gate partb, lobby param Rules variant, panel capture text. Spec started in docs/design/rules-variant.md.

## Parts C, D, E, H wiring (23:55)

- Part D (raids.sqf) and Part E (pickets.sqf plus defence and wave hooks) written and wired. Not yet tested live.
- Part C (economy) and Part H (squads) drafted by helpers and now wired per their integration notes in notes/. Not yet tested live. Skipped the suggested filter on vehCheapestTransport: only armour is gated and the cheapest transport is never armour.
- gateb first attempt stalled because Warlords' garrison outweighed the placed men, who hold fire. Scenario now clears the garrison. Rerun as gateb2.
- Helpers working on gated, gatee scenarios and the Commander menu (Part F).

## Part B gate PASS, F and G wired (00:10)

- gateb2 (`tests/server/runs/2026-11-08_23-48-07_gateb2/`): all 8 Part B checks PASS, 0 script errors.
- Part F menu drafted by a helper and wired. Old scroll actions, player* functions and C_REQ removed. Part G in strategy.sqf, wired.

## New requirement: commander activity gate (user request)

Every soak must measure each AI commander's activity and pass or fail on it. See prompt.md addition. Menu round gatef showed 56 script errors, mostly in the scenario; still to triage.

- Activity gate built: `tools/gates_activity.py`, gate name `activity`, plus a per-commander table (`python tools/gates_activity.py <rpt>`). Vanilla baseline scores 10 of 16 commanders passing, so it can tell the difference. Run on every soak.
- Part B review fixed: human side can't be locked out of voting by a ban, expired bans are withdrawn, a rebuilding AI side answers a running vote instead of getting the first sector, a pending switch is tied to its target, banned sectors can't return via AI votes on a mixed side, raid timeout restored with the pause rule off, withdrawal checks every man, the reset flag is cleared for late joiners. Needs a gateb rerun.
- gatef's 56 errors were the scenario starting before the WEST commander existed. Fixed; rerunning as gatef2.

- Reviews fixed (lint clean, not yet retested live): Part G (cut counting, denial value, native services, momentum uses worth, base lone wait longer, defence pull compares both sides, gates G tightened), Part E (need-limited muster response, cap rounds down, pickets only face the enemy, pickets rotate and answer attacks on their own sector, attack comes first, shuffle really moves the leader, hold lasts until responders are back and can't chain, fast travel must help), Part D (raid sector can't be voted for or merges cleanly, raiders and broken probes walk home, travel checks on probes, sector-size aware expiry and vantage).

## 2026-11-09 review fixes, second batch
- Part H review: all 8 findings fixed (LAMBS defend ends by waypoint count, leader short walk, enableAttack restored, turrets vacated, flank avoids restricted sectors, rearm tries other men with backoff, Borrowed gets posture, lambsRelease at borrow).
- Part C and F reviewers are applying their own findings.
- gatef3: 0 script errors, 7/9 Part F checks PASS. Both FAILs were scenario order, fixed in gatef.sqf (death test before the wave leaves, report with a living reporter in range).
- gates_activity: job-change matching and working-job names fixed; on gate6r 14 of 16 pass.
- Reruns queued: gateh2 (running), gateh with LAMBS, gatef4, gateb, gated, gatee, gatec.
- Part C and Part F review fixes applied by their reviewers, lint clean, not yet run live. New settings: defencePayoutCooldown, defencePayoutMinEnemies, menuPickupMaxDistance. gatef runs need -Overrides "menuTestAllowAI=true;menuPickupMaxDistance=1000000".
- 2026-11-09 reruns: gateh3 vanilla PASS (pin and rearm now pass; two earlier rounds had rearm timeouts on the first two trips, cause unknown, timeout now logs distance and command). gateh2l LAMBS: rearm timed out twice then worked, garrison test had no spare group (test fixed, sleep 60 and more states). gatef4: all PASS, 0 errors.
- gateb3 and gated2 failed in the scenario only: `_cmd` was nil because scenarios started before the commander existed. Every scenario now waits for it. Rerunning.

- gateb5 (after review fixes): all Part B behaviour checks PASS, 0 script errors. Only FAIL was the rebuild check, and the check was wrong: mid-rebuild the groups were 4 Reserve and 4 Defending (answering EAST on own sectors), none attacking. Scenario now logs an `attacking` count and the gate requires it to be 0. The generic "groups moved" line fails by design in this scenario because goMinGroups=99 keeps groups back.

- Found while reading tick costs: the waypoint guard re-issued orders to nearly every group about every 4 s (gateb5 2934 C_GUARD lines in 22 min; gate6r 2033 in 14 min). Cause under test: the engine moves a waypoint when placed with radius 0, so comparing it with the requested position always looked like an overwrite. This also reset each group's current waypoint to stale progress. Fix: the guard compares with where the waypoint really went (`SWLC_wpActual`) and logs why it fired. Every gate after this point runs on the fixed guard; the earlier part gates ran on the old one and get rerun in the final regression.

- gated4: the revote fix worked, then the scenario died on a malformed log call of its own at the `event=front` line (a scenario bug, not commander code). Fixed; gated5 next, after gatee2.

- Guard fix confirmed by gatee2: 117 C_GUARD in 17.7 min against about 3000 before, and the rest are real overwrites (why=count, Warlords appending waypoints). Measurement problem also found: avg_ms was far above the sum of stage costs (about 5 ms against 12-49 ms), because the timing starts in scheduled code before the `isNil`, so the measurement can include a whole frame. Next: measure inside the `isNil`.
- gatee2 could not test Part E: WEST's vote at t=39 never resolved, so it had no target for 1052 s and no wave. That happened in 1 of 22 recent rounds, and gated5 with the same setup got its target. Cause not found from the logs. Added `SWLC_fnc_cmdVoteStuck` (`voteStuckSeconds` 120, repeat 60): logs C_VOTESTUCK with the vote state and nudges Warlords' vote machine via `BIS_WL_lastSectorCnt_<side>`. Rerun gatee.

- gated5: front reached, but a vote already running landed on the raid sector, so the refusal, grace and probe tests had no valid raid to work with. Setup now sends that vote back until WEST's target is another sector. Rerun after gatee3.

- gatee3: setup failed with fail_no_front because it waited for the raid front, which leaves out the side's own target. It now waits for the picket front, which is what the test uses. Rerun after gated6.
- Timing now measured properly (gatee3): tick avg 12.3 ms, max 63, poll 2.3, guard 0.8. Largest stage waveTick 4.2 ms, then vehTick, picketTick and defenceTick about 1.4 each. Target "well under 5 ms" is still not met, but the tick is every 10 s per side, so about 1.2 ms per second per side. No C_VOTESTUCK fired this round.

- gated6: WEST's only choice was the raid sector (no neutral sector in reach), so it still could not raid. Setup now hands that sector over when nothing neutral is reachable, and picks the raid sector itself. Rerun after gatee4.

- gatee4 was stopped 3 minutes in by Claude Code because the system ran critically low on memory (2.7 of 31.5 GB free, several `cl` compiler processes at about 1.3 GB each, none started by this run). No server was left running. The runner's check that the server install is unchanged did not run for this round. Paused: rounds restart only when the user says so. Queue when resumed: gatee4, gated7, gatec2, gateh LAMBS, then regression and soaks.

- 2026-11-09 10:55: the user said the machine is free from 13:30 today and testing can resume then. Timer set for 13:32 in this session. No rounds before that.
- 11:15 Performance pass from the logs, no Arma rounds (waiting for 13:30). Commander tick split into slices across frames, each muster and each new group in its own frame, sides half a tick apart, repeated lookups cached, verbose-only lines skipped in the playable build. Linted only. Compare `avg_ms`, new `max_frame_ms` and C_PROF when rounds resume.
- 12:30 gatee5: 5 Part E checks failed, all from the test raiding BLUFOR Base instead of the picketed front sector. Bohemia's WLSectorListing assigns `_sector` without declaring it, which overwrote the scenario's variable through adAvailable. WLAirdrop leaks names the same way. Both shielded with `private` in the adapter. Rerunning as gatee6.
