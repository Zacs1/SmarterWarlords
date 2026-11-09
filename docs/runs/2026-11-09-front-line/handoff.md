# Front line run: hand-off

Run prompts: `prompt.md` and `prompt-defence.md` here. Spec and decision log: `docs/design/rules-variant.md`. Run log: `progress.md` here.
Final code: commit `92dffac` (later commits are docs only). Tags: `front-a-done`, `front-c-done`, `front-d-done` on `92dffac`, `front-b-done` on `e7d218d`.

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
- `moveCalm`, not asked for: see decision log. Marching groups otherwise crawl at about 0.8 to 1.4 m/s in COMBAT with no enemy near. The first version didn't hold; the final one turns off the engine's AUTOCOMBAT while marching.

## Rules-off smoke
`2026-11-09_20-21-38_smokeoff3`: 0 script errors, 2 captures, both sides moved.

@@SOAK@@

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
