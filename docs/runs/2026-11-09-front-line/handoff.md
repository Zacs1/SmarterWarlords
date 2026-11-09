# Front line run: hand-off

Run prompts: `prompt.md` and `prompt-defence.md` here. Spec and decision log: `docs/design/rules-variant.md`. Run log: `progress.md` here.
Final code: commit `665d096`. Every gate below ran on `92dffac` or earlier; the code changes since are the commitment timer, Cancel objective, the rally go rule and the squad size (see "Other additions"). Tags: `front-a-done`, `front-c-done`, `front-d-done` on `92dffac`, `front-b-done` on `e7d218d`.

All paths below under `tests/server/runs/`, plots in this folder.

## Part by part

### Part A: hold X, reinforce the holdouts. Built.
Round `2026-11-09_19-46-58_fronta3`, plot `fronta3.png`, and `2026-11-09_19-24-01_fronta2`.

| Check | Result | Evidence |
|---|---|---|
| Holdouts form when X falls | PASS | 11 men in 3 groups, 4 s after it fell |
| They stay at X | PASS | 0 of 78 samples beyond 350 m |
| Side's target stays X | PASS | 93% of samples, needs 90% |
| Reinforcements leave within 180 s | PASS | 61 s |
| Reinforcements arrive while holdouts live | **FAIL** | First arrival 50 s after the last holdout died. Two causes: this scenario's holdouts are few and under constant attack, and foot groups were crawling in COMBAT (fixed after this round, see moveCalm; not rerun) |
| Resupply reaches holdouts | PASS | delivered at 10 m, 6 restocks |
| Broken holdouts fall back no further than near X | PASS | 155 m, limit 300 m |
| Counterattack once they are gone | PASS | at the end of the Part C defence |

### Part B: defender fast travel closes during real fighting. Built.
Round `2026-11-09_19-08-14_frontb1`, plot `frontb1.png`. All PASS: closes after 65 s of sustained fire, reopens 126 s after it stops; seizure closes in 4 s, reopens at 119 s; 7 fast travel attempts followed the state.

**Players get this rule too, not only the commander.** It's the same `FastTravelEnabled` flag per sector that Warlords' own list reads.

### Part C: switch between holding X and defending Y. Built.
Same rounds as Part A. Goal switches in 4 s, returns 65 s after Y is clear, holdouts fighting near X aren't pulled away: PASS. Other groups turning to defend Y: PASS in `fronta2` (2 groups), not exercised in `fronta3`, where no group was free or near Y in the 150 s the defence lasted, so that round's FAIL isn't a bug.

### Part D: meeting engagements (stays on with rules off). Built.
Round `2026-11-09_20-06-30_frontd2`, plot `frontd2.png`. Both waves stop and fight, radio and board report it, no watchdog or ladder on the 15 groups that fought, survivors resume: PASS. Cost 0.75 ms per tick. Sabotage on the final code: all 11 cases PASS (`2026-11-09_20-19-15_sabotage3`).
Two FAILs are the scenario: nobody near enough to join, and the fallback setup found no free group.

### Part E: measure. Built.
Results: see "Front-line numbers" below.

### Defence addition (stays on with rules off). Built.
- Stance: `2026-11-09_19-34-48_stance1`, plot `stance1.png`. All PASS. Enemy numbers scripted in that test.
- Alert, screen, depth, counterattack: `2026-11-09_19-42-11_alert1`, plot `alert1.png`. All PASS.
- Statics and AT on roads: `2026-11-09_20-07-07_fortify2`, plot `fortify2.png`. All PASS except 3 of 4 guns crewed; the men sent to the fourth kept timing out. (`fortify1` bought nothing because the scenario's scripted alert was cleared by the real alert code; a scenario problem.)
- Steamroll measure: `tools/gates_steamroll.py`, numbers below.

### Other additions during the run
- Rolling muster: groups go as soon as their own men are mounted, and don't wait at a rally if anyone is already attacking.
- Driving fixes, including lifting a stuck vehicle clear when nobody is watching.
- Cancel objective on the Commander menu, asked for during the soak: press twice within 15 s, then the same pull-out, 15-minute sector ban and new vote as the commitment timer. The timer itself went from 11 minutes to a last resort, 90 minutes on a side with humans and 60 on an all-AI side. Commit `58035c7`, after the soak began. Tested in `2026-11-09_21-51-31_cancel` with an AI stand-in pressing the handler: first press asks, second cancels, third is refused while pulling out, target cleared in 17 s, next target a different sector 11 s later, fourth press refused by the 120 s cooldown, 0 script errors. A real player using the menu is untested.
- Rally go rule, asked for after the soak: a wave's first push waits for 60% of its men at the rally, or 270 s after the first group arrives. Squads also grew to the stock limit of 10 men on Normal and Hard (6 on Easy), from 3, because the commander had 13,000 to 35,000 CP unspent. Round `2026-11-09_22-02-06_mass10` (14 minutes, solo, CBA + LAMBS, plot not made): 0 script errors, first pushes of 19 men in 6 groups (EAST, soak 4 in 2) and 13 in 4 (WEST, soak 7 in 3), both released by the 60% rule, EAST squads at 10 men by minute 9 and WEST at a median of 8 by minute 12, 120 men alive at the end with the server at a median of 14.5 fps and a low of 13, against 14 and 12 in `soakfinal`. WEST bought 8 trucks first, at 650 CP each, so its squads sat at a median of 1 man for the first 9 minutes; EAST bought none and filled faster. Full strength, about 160 AI, was not reached. No long round has run on the mass rule or the squad size.
- `moveCalm`, not asked for: see decision log. Marching groups otherwise crawl at about 0.8 to 1.4 m/s in COMBAT with no enemy near. The first version didn't hold; the final one turns off the engine's AUTOCOMBAT while marching.

## Rules-off smoke
`2026-11-09_20-21-38_smokeoff3`: 0 script errors, 2 captures, both sides moved.

## Final soak
Round `2026-11-09_20-41-25_soakfront`, plot `soakfront.png`. 70 minutes, alone on the machine, CBA + LAMBS stable, no players. It ran on `92dffac`, so with the old 11-minute commitment timer and without Cancel objective.

| Check | Result | Evidence |
|---|---|---|
| Script errors | PASS | 0 in our code, 0 in Bohemia's |
| Groups spawned and moved | PASS | WEST 13/20, EAST 10/16 moved 100 m or more |
| Sector captured | PASS | 4 captures, first Leqa at 7:08 |
| No group 240 s without progress | **FAIL** | 15 of 16 |
| Holds inside their limits | PASS | 0 over |
| Respawn rungs | PASS | none used. EAST reissue 6, reroute 1, fast travel 5. WEST reissue 3, reroute 1, fast travel 1 |
| Commander activity | **14 of 16 PASS** | baseline 10/16, `gate6r` 14/16, `soakfinal` 15/16 |
| Part E: fighting stays at and beyond a fallen sector | **cannot be judged** | no sector changed hands between the sides, here or in the baseline, so 0 kills fall in the window |

Commanders that failed activity, from their timelines:
- `O Alpha 1-1`: stood in COMBAT for 10:02. It was left in Reserve at Balavu (2584,7381) at about 50:44 when EAST's objective was called off, with enemies around, and stayed there until it was given a job at about 58:46.
- `O Alpha 1-2`: idle 5:01 from 25:08 as Waiting. It reached the Tavu wave's waiting point in a vehicle and waited for the rest of a wave that went in at 25:56 with one group and 3 men. Inside the Waiting limit, but outside the activity gate's.

### Front-line numbers against the baseline
Kills after the first sector clash, baseline `2026-11-09_18-30-51_basevanilla`:

| | Kills | Contested sector | Other sector | Edge | Between sectors |
|---|---|---|---|---|---|
| Baseline | 54 | 57% | 31% | 11% | 0% |
| This soak | 129 | 58% | 22% | 19% | 2% |

The rule set for "after a sector falls" has no soak evidence at all: no holdouts formed, no fast travel closed, no sector fell from one side to the other. That behaviour was exercised only in the Part A, B and C scenarios. Tag `front-e-done` not set for this reason.

### Steamroll numbers
Measured by `tools/gates_steamroll.py`, no pass mark.

| | First clash | Decided | Winner | After the clash | Sectors lost after it | Comeback |
|---|---|---|---|---|---|---|
| Old vanilla baseline (`2026-11-08_19-26-56_baseline`) | Balavu | 50:14 | WEST, won the round | 20:12 | WEST 0, EAST 2 | no |
| `soakfinal` | Balavu | 63:59 | EAST | 25:52 or more | WEST 1 | no |
| This soak | Balavu | 64:29 | WEST | 5:19 or more, the log ended | 0 and 0 | no |

One round each. The clash came so late here that it says little about a steamroll after it.

### Other soak numbers
- Pace, which the user called out: 4 captures in 70 minutes, all neutral sectors. Of 10 objectives that ended, 6 were called off by the 11-minute timer and 4 were captured. The timer fired on Rautake 42 s before WEST took it anyway. Averaged over each 10 minutes, at most 11 men were assaulting, often 0 to 3, out of 21 to 52 per side, with 4 to 22 still walking up. Assaults opened with 3 to 8 men, 3 to 7.5 minutes after the target was picked. The longer timer removes the first of these. The trickle and the long walks remain, see Next steps.
- Stance: 8 switches, all four rebuild-and-back pairs from the commitment timer (241 s each). No oscillation.
- Alerts 2, gun purchases 6, Engaged started 16 and joined once, fallback 0.
- Vehicles lifted clear 39 times, 2 wrecks. Stuck vehicles keep clustering at Laikoro, 1700,6000-6200.
- Foot speed marching: AWARE 2.95 m/s median, COMBAT 1.86 m/s, with COMBAT 15% of samples against 30% in `soakfinal`.
- Commander cost: median 16.8 ms per tick, server median 14 fps; `soakfinal` 14.6 ms and 14 fps. The difference is small, and the soak had more men.

## Next steps
- See how the pace feels on the long timer. If it still crawls: hold a wave's assault until most of its men are close, and fast travel rebuilt waves. Neither is built.
- Laikoro's vehicle spawn ground is a repeat offender for stuck vehicles.
- `moveCalm` logged 0 calm events in this soak (20 in `fronta3`, 7 in `frontd2`). Those rounds were vanilla, this one had LAMBS. Not investigated: it could be that LAMBS counts as busy nearly all the time, or that the groups in COMBAT really had enemies near.
- Open question to the user, unanswered: shorter post-pull-back wait, fast travel of rebuilt waves, a lobby income option. Income alone wouldn't shorten rebuilds: about 32,500 CP sat unspent late in `soakfinal`.


## Rally and muster placement per link
Table in `docs/design/rules-variant.md`, "Item 8". All Tanoa links leave positive ground between rally points. Tightest: OPFOR Base to Radio (201 m), Military to Radio (247 m). No per-map change was needed.

## Known issues
- A static gun can stand empty if its crew can't reach it (1 of 4 in `fortify2`).
- Guns left in a captured sector can be used by the enemy.
- Engaged's search-and-destroy across water may trigger fast travel.
- Holdout survival counts only wipes. Crates are never cleaned up. CP isn't refunded when a resupply is cancelled.
- A human side not voting X ends the hold after 150 s (`target_moved`), and the holdouts are exposed to Warlords' kill loop in that window.
- A human side in hold or rebuild stops AI waves; only the panel and radio say why.
- A stance can cycle hold, attack, hold through the 7-minute quiet rule. Watch `C_STANCE reason=balance`.
- Screen groups don't fall back or get replaced. One approach prediction per alert. Walls and treelines aren't scored.
- Stances are judged from partial intel.
- Part A's scenario is WEST only. Part D's has no transports and joins need many enemies seen. Part B's scenario writes the fire and seize timers directly.
- AI boarding statics is at the engine's mercy, and LAMBS can pull gunners off.
- An already-open player fast travel list can still accept a just-closed sector.

## Deferred
Mortars in the asset lists, the after-action report tool and further tuning soaks: not done. The extra steamroll soak wasn't run, there wasn't time.

## Player-visible text
Listed by part in `docs/design/rules-variant.md` under each "Player-visible text" heading, the defence set just before the decision log.
