# Rules variant

SmarterWarlords' changes to Warlords' own rules, written as built. One lobby parameter, "Rules variant", turns all of parts B to E off. Each rule below also has its own switch in `commander/swlc/settings.sqf`, default on.

Terms: **staging** means a sector's muster point or the rally. **Holding point** means the rally point. The rules prompt was written before the muster and rally rework, so its words map onto that model.

## Part B: no more deadlocks

### Capture progress pauses and decays (`ruleCapturePause`)

Warlords runs a capture as a trigger with a countdown that restarts from the top whenever attackers lose the numbers. The rule leaves Warlords' trigger in charge and only changes what the next countdown is set to.

- When a countdown is running on a sector a side is watching (its target, later its raid), the commander records the time left every `capturePollSeconds`.
- When the countdown stops, progress holds for `captureHoldSeconds`, then the time left grows by `captureDecayPerSecond` until it reaches the full length. At that point the record is dropped.
- While it is stopped, the trigger's timeout is set to the time left, so the next countdown starts from there. It is never set below `captureMinRemaining`.
- A watched sector's timeout is fixed at Warlords' middle roll, so the length no longer varies between attempts.
- The commander panel shows "seizing N%" or "holding N%" beside the target, because Warlords' own bar hides while a capture is paused.

### No respawning in a sector being seized (`ruleNoRespawnSeized`)

- Players already respawn at base under stock rules, and fast travel refuses a sector being seized.
- An AI warlord that respawns inside a sector being seized is moved to the nearest owned sector that is not, or to base.
- A capture counts as running for `captureHoldSeconds` after it pauses, so a brief gap doesn't reopen the sector.

### Commitment timer (`ruleCommitTimer`)

Each target gets `commitSeconds`. When the timer runs out the commander decides:

| Situation | Decision |
| --- | --- |
| Capture is at least `commitStayProgress` done, or `commitStayProgressRecent` done and active within `commitRecentSeconds` | Stay for `commitExtendSeconds`, at most `commitMaxExtensions` times |
| Humans on this side | Reopen the vote with a radio call |
| Losing (loss ratio at least `commitLossRatio`, or `commitFailedPushes` failed pushes) with groups below `commitRebuildMenPerGroup` men, or losing with nowhere else to go | Pull back and rebuild for `rebuildSeconds` |
| No other sector to go to, not losing | Stay and check again after `commitExtendSeconds` |
| Otherwise | Switch to the best reachable sector, with `commitProbeWeakBonus` for one that probes found weak |

An abandoned target can't be picked again for `abandonBanSeconds`. Attackers leave its square before the target is cleared, up to `switchWithdrawSeconds`, because Warlords kills AI left inside a sector that is no longer their target.

## Part C: economy and capabilities

All of it lives in `economy.sqf` and `economy_client.sqf`. Each rule has a switch (`ruleIncome`, `ruleCombatIncome`, `ruleCapabilities`, `ruleSupplyLines`, `ruleFortressBase`, `ruleCornered`, `ruleStretchedSupply`, `ruleSectorFort`, `ruleCounterattack`, `ruleScaleAI`). Tunables are in `settings.sqf`, sector types per map in `maps/<world>.sqf`.

- Income: the same flat base value for both sides, plus a per-sector bonus that falls with each extra sector. Kills, squad wipes, captures and successful defences pay on top.
- A sector's type unlocks a capability only while it is connected to the base through owned sectors. A cut-off sector unlocks nothing.
- The base always offers full infantry kit and has static guns. Buying at your own base while it is under attack is cheaper, as is buying near a sector you just lost.
- Rearm and repair work only near the base, a connected industrial sector, or within range of another owned sector.
- A sector held for a while gains sandbags and one gun.
- An all-AI side earns more for each human on the other side.
- Round time limit: lobby parameter, off by default. More sectors wins.

## Part D: raids and probes

`raids.sqf`, switches `ruleRaids` and `ruleProbes`.

- A raid is paid for, on an enemy front-line sector next to one you own, and marked only on your own side's map.
- Warlords runs the capture: the sector is added to the side's conquered list, which stops Warlords' kill loops and lets its own trigger hand the sector over. Seizing takes `raidSeizeMult` times as long.
- The enemy hears nothing until a soldier spots the raiders or seizing starts, because Warlords only alerts for a side's current target.
- One active per side, then `raidCooldownSeconds`. A raid expires after `raidExpirySeconds`.
- Probes: one spare group goes to the weakest or least-scouted enemy front-line sector and reports to the board. If it is lightly held and the probe wins, the side may buy a raid on it. Otherwise it breaks off.
- The AI buys raids under the same costs and limits.

## Part E: pickets and proportionate response

`pickets.sqf` and hooks in `defence.sqf` and `wave.sqf`, switches `rulePickets` and `ruleProportionate`.

- Each owned front-line sector keeps one small group, at most `picketMaxFraction` of the side's groups and never taking the attack below `picketKeepAttackers` groups.
- A radio call goes out when an enemy starts seizing a sector.
- The response is the reported strength times `responseMargin`: from the reserve first, then the main attack's least-engaged groups, never ones in a fight, at most `responseCapFraction` of the attack.
- A force of `responseCounterattackMen` or more falls through to the full defence rules.
- Responders fast travel to the nearest safe owned sector, never into the one under attack, then walk in.
- If responders find more than reported, the need rises and the next layer goes. When they win they return with a radio call and rejoin the next wave.
- If peeling drops the wave below `peelWorkableGroups`, it holds at the rally for up to `peelHoldMaxSeconds`. A push already in progress carries on.

## Part F: the commander menu

`menu.sqf` and `menu_client.sqf`, switch `ruleCommanderMenu`. One scroll action, "Commander...", replaces the earlier actions. Warlords' own request menu is unchanged. Insert still toggles the AI commanders panel.

- Options: Order raid on sector, Send groups with me, Hold the wave for us, Go now, Report contact, Defend this sector, Request a pickup, Release my groups, What's the plan?, and an entry for the AI commanders panel.
- Every option goes to the server and through the commander's normal rules. A refusal comes back as a radio line. Each option has a short per-player cooldown.
- Only a real player's request is handled. An AI stand-in is accepted only with the test setting `menuTestAllowAI`.
- Borrowed groups follow the player, keep their posture and rearming logic, and go back to the commander when released or when the player dies or leaves.
- A pickup is a vehicle driven to the player and handed over. No AI driver stays with it.

## Part G: what the commander values

`strategy.sqf`, switches `ruleStrategy` and `ruleFortressAware`.

- A sector is worth its Warlords value plus what it unlocks, plus, for an enemy sector, how many of their sectors would lose their road home. This feeds the vote, raid targets, defence value and which front-line sectors get a picket first.
- The enemy base needs `stratBaseGoExtra` more groups at the rally, brings at least `stratBaseAtWanted` launchers, a combat vehicle and smoke, and is a poor target below `stratBaseMinMen` men.
- The final push already stages forward, because groups muster at the owned sector nearest the target.

## Part H: smarter squads

`squads.sqf`, switches `squadPosture`, `squadBounding`, `squadFlank`, `squadRearm`, `squadLambs`. Applies to commander-owned groups, and to borrowed groups for posture and rearming only.

- Formation and speed by situation, with a minimum hold so they don't flip every tick.
- Bounding overwatch from the rally inward, two teams inside the one group.
- Suppress and flank when pinned. Off while LAMBS is loaded.
- Rearming from crates, friendly vehicles and fallen friendlies, respecting stretched supply for crates.
- With LAMBS loaded: garrison and building clearing through LAMBS, and our stance commands wait while LAMBS has the group.

## Part R: resilience

No commander group can get lost or give up. `resilience.sqf`, `routes.sqf`, `upkeep.sqf`, and the existing `watchdog.sqf`, `commander.sqf` and adapter. Master switch `resilience`, plus a switch per behaviour. Unlike parts B to E, this stays on when the rules variant is off.

- **Sweep** (`resSweep`): every tick, every commander group must have a task, a current waypoint and a goal that still makes sense. A failing group gets a new task at once. Logged as `C_RES`.
- **Ladder** (`resLadder`): re-issue orders, try a different route, dismount, fast travel to the nearest safe owned sector (up to `ladderFTCandidates`), then the last rung. Each rung gets `ladderRungSeconds`, and gaining `ladderProgressMetres` ends the climb. Every rung is logged as `C_LADDER`.
- **Last rung** (`ladderRespawn`): the group's bought men are deleted and their price refunded, the slot warlord is killed through Warlords' own forced respawn, and the men come back through the shop as fresh reinforcements. It waits at least `ladderMinClimbSeconds` after the first rung. At most `ladderRespawnMax` per side per `ladderRespawnWindowSeconds`; past that the group gets a job it can reach.
- **Idle cap** (`resIdleCap`): more than `idleCapShare` of a side's groups idle at once drops the plan and re-plans. Logged as `C_IDLECAP`.
- **Route network** (`routeNetwork`): a per-map network of road and track points connecting every sector, in `commander/swlc/maps/<world>_routes.sqf`. A map without a file builds one at mission start over several frames, and `tools/extract_routes.py` turns that round's log into the file. Moves over `routeMinMetres` follow it in hops of about `routeHopMetres`.
- **Water** (`noWaterMoves`): a destination that can't be reached on land goes by fast travel. A group found swimming in deep water for `waterRescueSeconds` goes straight to the fast travel rung (`resWaterRescue`).
- **Destinations** (`validateDestinations`): every order is snapped to the nearest open, reachable ground.
- **Stragglers** (`upkeepStragglers`): further than `stragglerMetres` from the leader for `stragglerGraceSeconds` gets a recall, or joins another commander group if one is closer.
- **Remnants and leaders** (`upkeepRemnants`, `upkeepLeader`): groups of one or two merge into a suitable nearby group while their warlord is dead. A dead leader is replaced and the orders are given again.
- **No fleeing** (`upkeepNoFlee`): commander groups never flee on morale.
- **Vehicle leftovers** (`upkeepLeftovers`): crew who got out and never remounted, and lone gunners, get picked up and given orders.
- **Isolation and supervisor** (`resGroupGuard`, `resSupervisor`): each group's handling is guarded, so one group's error stays with it (`C_GROUPERR`). A separate loop restarts the commander if its heartbeat goes quiet for `supervisorStaleSeconds`, and logs why (`C_SUP`).
- **Locality** (`resLocality`): a group that changes machine has its orders re-issued at once (`C_LOCALITY`).
- **Sabotage scenario**: `tests/mission_overlay/swl/scenarios/sabotage.sqf`, judged by `tools/gates_r.py`, stays in the test suite.

## Decision log

| Decision | Why |
| --- | --- |
| Raids reuse Warlords' capture by adding the sector to the conquered list | The trigger, payout and side change stay Warlords' own, which is the safest way to run a second capture. |
| Pickets take the smallest nearby groups | A picket is there to report and delay, so the strongest groups stay with the attack. |
| The cap on peeling is computed from the groups still in the attack | It rounds down as groups leave, so a run of small raids can't drain the wave. |
| Transports aren't filtered by capability | Only armour is gated, and the cheapest transport is never armour. |
| AI scaling pays CP only | Warlord slots are fixed by the mission, so a side can't get more groups. |
| Sector types use positions, not names | Two Tanoa sectors have no usable name. Balavu as military and Leqa as radio are design choices, because no tower or depot was confirmed on the map. |
| LAMBS sharing is left on and `intelMinKnows` is raised to 1.5 while it is loaded | A shared reveal stays at knowledge 1, so it can't create a board entry by itself, and the user's LAMBS settings stay untouched. |
| The commander can reset the vote for an AI side by reusing Warlords' paid voting reset | The reset works for any side while a target is set. It needs the public `Name` field filled, so it uses "the Commander". AI warlords then vote randomly, so the commander overwrites their votes for a switch. |
| A human side's reopened vote is free | It uses the same reset, triggered by the commander rather than bought. Banned sectors can't be clicked. |
| A restarting countdown counts as progress | The prompt asked to settle this. Progress is computed from the time left, so a countdown resumed from banked time reads as the progress it has. |
| A ban never removes the last sector a human side can vote for | Otherwise a side whose only remaining sector is banned has no vote and stalls. |
| While rebuilding, an AI side answers any vote that has started | Warlords' timer runs once one warlord votes, and an empty vote hands the side the first sector in its list. The rebuild still holds the groups back. |
| The menu gets a tenth entry for the AI commanders panel | The panel is already on Insert, but it's easy to forget, so the menu names it too. |
| Hold delays only the rally's go signal | Musters are short anyway, and holding them would leave groups standing at their sectors. |
| A pickup hands the player a vehicle with no AI driver | An AI chauffeur fights the player's own driving and is one more group to manage. |
| A player's raid sends no AI groups by itself | Borrowed groups are the force, so the player decides what goes. |
| Pause and decay write to Warlords' trigger only between countdowns | A running countdown stays untouched, so capture payouts, alerts and side changes are all still Warlords' own. |
| Pickets rotate | A group left on a front sector for good reads as a commander doing nothing. After `picketRotateSeconds` it goes back to the wave and another takes over, and it can't picket again for `picketRestSeconds`. |
| Front line means a sector linked to an enemy sector | Neutral ground doesn't need a watch, and counting it spread pickets too thin. |
| The cap on peeling rounds down | With three groups in the attack, one can go. Rounding up would take half of a small wave for a small raid. |
| A lone group waits twice as long at the enemy base | One group walking into the base alone is wasted, and the base rule asks for more groups anyway. |
| A raid merges into the main capture if the vote lands on its sector | Running two captures on one sector would fight over its countdown. |
| Holding squads under LAMBS send the leader on a short walk every few minutes | Warlords kills AI warlords that don't move for about nine minutes, and LAMBS' garrison disables the leader's pathing. |
| LAMBS' defend task is ended by changing the waypoint count, not by terminating its script | Terminating it would leave its per-frame handler running and giving orders to a group the commander had taken back. |
| Borrowed groups go back to the commander when the player dies | A player can be dead for some time, and the groups would stand around in the meantime. The player asks for them again after respawning. For the user to review. |
| The commander's update is spread across frames, in the same order as before | Most of its cost was short spikes when buying or giving orders to a whole side, and a spike is what a player feels as a stutter. Each muster and each new group gets its own frame, and the two sides work half a cycle apart. |
| A stuck vote gets nudged after `voteStuckSeconds` | One of 22 recent rounds sat with no target for 1052 seconds and the cause was not found. Re-running the vote is cheap and costs nothing when the vote is healthy. |
| Commander groups are always warlord groups, so remnants merge only while the warlord is dead | Warlords needs each warlord alone in its own group. A merge while the warlord lives would break that. |
| The last rung brings men back through the shop instead of creating them | A respawned group then costs and arrives exactly like any other reinforcement, and a refund covers what was deleted. The refund leaves out dying warlords, whose price was paid before the kill. |
| The last rung waits at least 75 seconds after the first | Fast-failing rungs could otherwise reach it in seconds, for a problem one more re-issue would have solved. |
| The last rung is capped per side | A bad map area can't turn into a side deleting its own army. Past the cap, a group gets a job it can reach and isn't sent back for `ladderJobHoldSeconds`. |
| Swimmers skip the lower rungs | The sabotage round showed men swimming about 70 m in 200 seconds. Their slow drift towards the goal counted as progress, so the ladder never started. |
| Men in a broken or unarmed vehicle are pulled out even in a fight | The sabotage round kept a crew in a dead truck for 3 minutes because the leftover rule waited out combat. Only a crew with a working gun stays. |
| Resilience is outside the rules variant switch | It keeps groups working and changes no rule of the game, so it also protects a round with the rules variant off. |
| Hops are a chain of real waypoints, and the caller's order stays as it was | Everything that reads a group's order still sees the real goal. The expanded list is kept apart in `SWLC_orderLegs`. |
| Water moves wait for the route network to be ready | Before then a land route can't be judged, and a wrong answer costs a group 50 CP or a swim. |
| Raiding, Probing, Recon and Picket groups never receive merged men | Those jobs depend on the group staying small and on task. |
| Receiving groups may hold the squad size plus three | A strict limit left remnants with nowhere to go on small fronts. |
| A counterattack on a low-value sector falls through to the full defence rules at `responseCounterattackMen` | That is the written rule. The code was peeling groups for low-value sectors whatever the size of the force, which the Part E round caught. |
