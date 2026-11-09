# Front line run: progress log

Prompt: `prompt.md` here (authoritative). Time limit from the user: built and tested by about 20:30 on 2026-11-09. Priority is code done fast, then testing and refining.

## How to resume after compaction
- Shared brief and interfaces: `notes/build-brief.md`.
- Four helpers build in worktrees and report a branch: part B (`front.sqf`, scenario `frontb`, gate `--gate frontb`), parts A and C (`holdouts.sqf`, `fronta`, `--gate fronta`), part D (`engaged.sqf`, `frontd`, `--gate frontd`), part E (`tools/gates_front.py`, `--gate front`).
- Order after they report: merge B, then D, then A+C, then E into master; lint; smoke; scenarios at most 2 servers at once; fix; Opus review A+B and one for C-E; final soak alone with CBA + LAMBS; sabotage once; rules-off smoke; playable, PLAYABLE.md, rules-variant.md, hand-off, final message.
- Baselines for part E: a commander-off round (`-Overrides "commanderEnabled=false"`) and a round on the current build, both on commit 4d7c8eb or later with `C_KILL` logging. Run these straight after the earlier soak finishes, two servers.
- Check free memory before starting any round.

## Log
- 18:10 Kill logging committed (4d7c8eb, `C_KILL` from `init.sqf`, setting `killLog`). Brief written, four helpers started.
- Prior run's `soakfinal` is still running and is left alone; it is on commit 1fa4e23, without `C_KILL`.
- The user's message: an income multiplier was suggested as the answer to slow rebuilds. It was held back: this soak shows about 16,000 CP unspent at minute 40, so income isn't the limit. Decision was open when this run started.
- 18:15 User addition (end of prompt.md): sustained combat, groups leave as soon as ready, rally only when nobody is attacking. Built on master: `rollingMuster` (each group leaves after `musterGroupSeconds` 15 s, once its men have landed, and boards on its own), `rallyLoneWait` 180 to 60. The rally already sends a group straight in when a push is under way. Decision row for the rules doc: the wait at a rally is 60 s, not removed, because a lone group sent in alone just dies.
- 18:25 Driving fixes on master, not yet run in a round: lift clear when safe (`vehUnstick`, driving leg only, off in fights, near enemies, near players and near attacked sectors), men leave a vehicle that can't drive at once, `vehDepartGap` one vehicle at a time out of a sector, `vehSlowNearby` uses `forceSpeed` near other vehicles and sectors, `vehStuckWindow` 40 to 25. Decision row: a combat vehicle in a fight keeps its crew while its gun works, even when it can't move.
- 18:25 Part E (analyser) and Part B merged. Part E baselines must run with `ruleDefenderFT=false` so Part B doesn't change them.
- 18:30 Earlier `soakfinal` ended (89:51, no winner, 6 captures, 0 script errors, install unchanged, build 1fa4e23). Activity 15/16. No-progress check 16/16. Respawn rung 0 used. Holding limits FAIL: Reserve over 7:00 for WEST 1-1, 1-4 and EAST 1-1, 1-3. `partg` raid rate FAIL (2 raids, 0 probes). Generic "groups moved" FAIL counts non-warlord groups. `final_fight_not_walkover` FAIL: no base fight, round ended by time. Log: `tests/server/runs/2026-11-09_17-00-36_soakfinal`.
- 18:32 WEST Alpha 1-1 at 82% waiting was a real bug: `defReserveTick` kept the first group in the list whenever the reserve shrank after a rebuild, so it held the same group for about 50 minutes. Fixed (ca26717, `reserveRotate`): least-served group stays, six-minute stint with a wave out, then it joins the attack and rests from reserve duty for seven minutes. Decision row: the reserve can stand empty for a few minutes while a wave is out, because sustained combat matters more than a spare group.
- 18:31 Baselines `basevanilla` and `basecurrent` started (30 min, `ruleDefenderFT=false`) on the build before D/A/C.
- 18:33 Parts D, A, C merged (6fd1d2a), lint 0 errors, 51 files. Two Opus reviews started.
- 18:46 Review of A+B applied: reinforcing X now outranks defence, raids, probes, pickets and the reserve unless a sector has real fighting; a human side gets a radio request to vote X instead of having its target cancelled (`holdvote`, new player-visible text); AI sides pull attackers out of the old target first (no ban on it); holdouts keep their HOLD order when they shuffle; restock skips a man no crate can feed and no extra crate is bought with a stocked one beside them; the crate carries the men's own magazines.
- Decision rows: (1) lone seize. The spec says a seize closes fast travel and also that a lone infiltrator can never trigger closure. `frontSeizeMinMen` 3 means one man seizing keeps fast travel open, because defenders need to reach him. The `frontb` scenario fakes the seize with no men present, so run it with `frontSeizeMinMen=0`. (2) `frontExchangeSeconds` 15 to 8 and `frontWindowMinHits` 2, because one 15 s burst could fill two windows. Reviewer's arithmetic, not tuned against a result.
- 18:55 Review of C-E applied: a combat vehicle on its way to the rally now gets the same stuck rescue as a transport; a vehicle that can't drive empties at the next vehicle check instead of after the 25 s window; abandoned vehicles can't be claimed again for 3 minutes; Engaged no longer fires within 300 m of the objective, so rally and go stand; a wave ending leaves a group's road fight alone; a group won't fast travel backwards to defend Y; a group fighting isn't pulled to Y; `reinforce_left` counts only groups actually moving, so the Part A timing gate means something. Left as known issues: an Engaged search-and-destroy across water may trigger a fast travel (routes.sqf); holdout survival counts only wipes.
- 19:02 Part E baselines done, 30 min each, build before D/A/C with `ruleDefenderFT=false`. `basevanilla` (`2026-11-09_18-30-51_basevanilla`): 54 kills after the first clash, 57% contested sector, 31% other sector, 11% edge, 0% between. `basecurrent` (`2026-11-09_18-31-01_basecurrent`): 73 kills, 67% contested, 5% other sector, 26% edge, 1% between. Neither had a sector change hands between the sides, so the "after a sector falls" measure has no baseline data. That limits the Part E gate and must be stated in the result.
- 19:05 User addition: defence as a first-class part, saved verbatim in `prompt-defence.md`, brief in `notes/defence-brief.md`. Where each item is slotted: item 1 (stance) helper "stance", item 2 and 4 (alert, approach, screen, main position, counterattack reserve) helper "alert", item 3 (statics) helper "fortify", item 5 (steamroll measure) helper "steamroll". All four build in worktrees while the front line scenarios run on the earlier build. Their scenarios run in the same batches, the code goes to the existing second review, and the final soak covers everything. The added scope means the run ends after 20:30, because the soak must run on the final code.

## Defence helpers started (about 19:10)

Four worktree helpers from e7d218d: stance (item 1), alert (items 2 and 4), fortify (item 3), steamroll analyser (item 5). Rounds running meanwhile: smokefront, fronta1. frontb and frontd follow when a slot frees.

## Round results so far

- smokefront (`2026-11-09_19-01-02_smokefront`, merged build): 0 script errors.
- fronta1 (`2026-11-09_19-01-20_fronta1`): holdouts form, target stays on X (99%), reinforcements leave within 60 s, Part C switches to Y and back. FAILs were the scenario's fault: X was flipped at 34 s when groups were 1 man each, and the "harmless" EAST garrison shot them dead by 76 s. Scenario fixed (full groups, garrison disarmed), rerun as fronta2.

## Deadline moved (user message, about 19:45)

"instead of needing to be done by 8:20 it'll be more like 9:30-9:45 instead, so you've got some more time". New target 21:30-21:45; the extra time goes to testing.

- frontb1 (`2026-11-09_19-08-14_frontb1`, build e7d218d): all Part B checks PASS. Tagged `front-b-done` on that build.

- frontd1 (`2026-11-09_19-19-34_frontd1`): collision, radio and board, survivors resuming all PASS. Three FAILs, none a commander bug: joins (sighted strength never needed more groups, rerun with a raised `responseMargin` to exercise it), the fallback case (the scenario's spot was inside `engagedObjectiveMargin`, added by the review after the scenario was written), and one `post_contact_reset` counted as interference (that action only fires when the group isn't fighting). Scenario and gate fixed, rerun as frontd2.

## Defence code review applied

The C-E reviewer read the merged defence code (c1e733e). Fixed: a holdout goal outside attack stance emptied the reserve with no wave to go to (side idle); pickets and raids could take the counter group; fortify bought guns nobody could reach yet; defence shuffle overwrote screen and counterattack orders (new `alertCounterHitSeconds`); face-the-approach turned the AT men on the road; resting groups idled once a side left attack.

- fronta2 (`2026-11-09_19-24-01_fronta2`, build 62d5a61-ish with defence off): holdouts 16 men, held 9 minutes, target stayed on X, resupply delivered at 7 m and 20 restocks, broken groups fell back to 155 m, Part C switched and returned, groups turned to defend Y. Remaining FAILs: arrival (see below), the gate required the resupply after the scenario's own ammo strip (fixed: real fighting ran them low first), and the scenario hit the 18-minute limit (now 20) because it waits for full groups.
- Finding: reinforcements took so long partly because the scenario flipped X back twice, and partly a general problem. Foot groups in COMBAT behaviour moved at 0.9 m/s here against 3.7 m/s in AWARE; in soakfinal 1.4 against 3.5 m/s across 228 samples (30% of Advancing samples). The engine puts a group in COMBAT when it knows of any enemy however far. New `moveCalm` (default on, not under the rules variant): a group Travelling or Advancing, not fighting, no known enemy within 300 m seen in the last 60 s, goes back to its ordered behaviour. Measured after in the next soak with the same split.
