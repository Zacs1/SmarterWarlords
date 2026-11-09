# Addition to the rules variant run: resilience, batched testing, playable builds

Saved verbatim from the user, 2026-11-09, about 12:55. Authoritative for the rest of the run. Re-read before each stage.

---

Addition for the rest of this run. Keep everything already planned (remaining part gates, LAMBS round, regression, soaks, performance work); this adds one more part and changes how the remaining testing is batched. I'll be playing tonight, so whenever I stop you, the playable scenario must be the latest working state.

## New part: resilience (no group can get lost or give up)
Build this next, using helper agents while the queued gate rounds run. Several pieces already exist (order re-assertion each tick, the watchdog, the vote-stuck nudge, the activity gate); extend them, don't duplicate them. "Staging" below means the muster and rally model as now built.
1. Full sweep every tick: every commander-owned group must have a task, a current waypoint, and a goal that still makes sense (target not captured, muster sector still owned, and so on). Anything failing gets a new task immediately. This catches groups the commander has lost track of, which is different from stuck groups.
2. Escalation ladder with a guaranteed last rung, each step after the previous fails: re-issue orders; try a different route; dismount if mounted; fast travel to the nearest safe owned sector; final resort, delete the group and respawn it at base as fresh reinforcements, refunding its CP and logging it. Log every rung used; how often the respawn rung fires is a key number in the hand-off.
3. Idle cap per side: if more than about 20% (tunable) of a side's groups are idle at once, the commander drops its current plan and re-plans from scratch.
4. Never order a land move across water. Any destination a group can't reach on land goes by fast travel instead.
5. Route network: per map, generate once (offline in a tool or at mission start, whichever proves reliable) a network of safe road and track points connecting every sector. Long moves follow it in short hops instead of one distant waypoint. Stored per map.
6. Validate every destination before ordering it: never inside rocks, buildings or water; snap to the nearest open, reachable ground.
7. Stragglers: soldiers more than about 200 m (tunable) from their leader are sent back, or join the nearest friendly commander group if closer.
8. Remnants: groups down to one or two men merge into the nearest suitable group; a group whose leader dies gets a new leader with its orders kept.
9. No fleeing: disable morale fleeing for commander groups; the commander's own fall-back rules decide retreats.
10. Vehicle leftovers: crews who dismount and never remount, and lone gunners left in turrets, get picked up and given orders.
11. Protect the commander: handle each group in isolation so one group's script error can't crash the tick; a separate supervisor checks the commander's heartbeat and restarts it if it stops, logging the error.
12. Locality changes: when a group changes machine (player joins, headless client, host change), re-issue its orders straight away.
13. Sabotage scenario, kept in the test suite from now on: kill group leaders; teleport groups into the sea, dense forest and rocks; delete all waypoints; flip and immobilise crewed vehicles; scatter a squad 500 m apart; throw an error inside one group's handling. Every affected group must be moving purposefully again within about 3 minutes.
Gates: every sabotage case passes; in the final soak, no commander group goes more than about 4 minutes without progress at any point (hard gate, whole round); respawn-rung usage reported. Same rules as the other parts: settings switches, one Opus review, spec added to docs/design/rules-variant.md, decision log.

## Remaining testing, batched to save rounds
- Finish the already-queued part gates as planned (gatee, gated, gatec, gateh with LAMBS). Only rerun what fails.
- Then one round for resilience: the sabotage scenario, after a short smoke round for script errors.
- Then the final soak: full Tanoa, everything on, CBA + LAMBS stable loaded (the way I'll play). It doubles as the full regression, the balance check, the activity gate and the 4-minute check, compared with the vanilla baseline. Plus a short smoke round, not a full soak, with the rules variant off to prove vanilla rules still run.
- Performance work continues alongside, measured from these same rounds; no extra rounds just for it.

## Playable for tonight
- Regenerate the playable scenario now from the current working tree if it's in a working state, again after resilience passes, and again after the final soak.
- Keep a short PLAYABLE.md at the project root, updated each time: what's in the build, how to host it, the lobby settings for two humans plus AI against all-AI, and known issues to avoid.
- Before I play, stop all rounds and leave no server running.
