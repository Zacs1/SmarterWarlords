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

## Front line: parts A to E

Built in the run of 2026-11-09 (`docs/runs/2026-11-09-front-line/`). These letters are the front line run's own parts, separate from the rules parts above. The notes below were written as each part was built. Two independent reviews followed, and these changes came from them:

- Reinforcing holdouts outranks defence, raids, probes, pickets and the reserve, unless a sector has real fighting (`SWLC_fnc_holdPriority`).
- A side with human players is asked to vote for X by radio (`holdvote`) instead of having its target cancelled. An AI side pulls attackers out of its old target first, with no ban on that sector.
- `frontExchangeSeconds` is 8, not 15, and a window needs `frontWindowMinHits` 2 polls with an exchange. One burst can no longer fill two windows.
- A seize closes fast travel only with `frontSeizeMinMen` 3 enemy men in the capture square.
- Holdouts keep a HOLD order when they shuffle, restocking skips a man no crate can feed, and the crate carries the men's own magazines.
- A combat vehicle travelling to the rally gets the same stuck rescue as a transport. Engaged doesn't start within `engagedObjectiveMargin` 300 m of the objective's square. A wave ending leaves a group's road fight alone.

### Part A as built: hold X, reinforce the holdouts

Status: lint clean, gate checked against a hand-written log only. Nothing has run in Arma yet.

Code: `commander/swlc/holdouts.sqf`. Hooks: `settings.sqf` (one block after `ruleCommitTimer`), `init.sqf` (load order), `commander.sqf` (`holdoutTick` in the tick list), `status.sqf` (group reason, panel text), `adapter.sqf` (`adProtectSector`, `adUnprotectSector`).

Switch: `ruleHoldouts`, under `rulesVariant`. Default on.

#### Spec as built

1. **Forming.** When a sector the side owned, or its current target, turns enemy with its groups inside (X's square plus `holdoutMargin`), those groups become holdouts: `SWLC_holdout` true, state "Defending". Part D's "Engaged" is accepted as well. Bases never become X. Raiding, Probing, Borrowed, Pickup and Hunting groups are left alone. One X at a time per side: a second loss during a hold doesn't start a new one.
2. **Staying alive.** Warlords kills AI in a sector that is neither on `BIS_WL_conqueredSectors_<side>` nor `BIS_WL_currentSector_<side>`. The conquered list is only ever added to, so a sector the side once captured is already safe. If X isn't on it, `adProtectSector` adds it, and it's taken off again `holdoutUnprotectGrace` seconds after the hold ends. A protected X doesn't depend on the vote going through.
3. **Target stays X.** Set by `preferredTarget` and a forced revote (`adForceRevote`), not by writing the target variable, which would leave Warlords' vote loop holding a stale sector. If the side's target isn't X for `holdoutVoteGrace` seconds in a row, the hold ends with reason `target_moved`. The revote happens once, when the hold forms, so players voting elsewhere can end a hold this way.
4. **Reinforcing.** While the goal is X, `forceGo` is set on the operation every tick. That opens the existing muster and rally, so free groups go without forming a wave. Once the first group is in, the wave's existing reinforce mode sends the rest. The muster sector is the existing staging choice (nearest owned sector). Part C's defence of Y is the only job ahead of this.
5. **Digging in.** Each holdout gets a spot within `holdoutCoverRadius` of X: buildings with room inside first, then the terrain's best spots from the staging search. After `holdoutSettleSeconds` at the spot it uses LAMBS garrison if LAMBS is loaded (`holdoutGarrison`). Without LAMBS it holds the spot under a HOLD waypoint.
6. **Breaking.** A group at or under `holdoutBreakFraction` of the strength it had when the hold formed (its own threshold, separate from the existing break-and-consolidate rule) moves to the nearest cover on the X side of the way to the nearest owned sector, `holdoutFallbackBeyond` past X's edge, never beyond `holdoutFallbackMax` from X. It stays a holdout and waits there.
7. **Resupply.** When any holdout group is short of ammunition or launchers, and `cpFree` covers `holdoutResupplyCost` (so the reserve is respected), the side pays and a crate appears beside that group after `holdoutResupplyDelay`. `holdoutResupplyCooldown` limits the rate, `holdoutResupplyFirstDelay` holds off the first one. The usual rearm is blocked by combat and LAMBS, so `holdRestock` takes from the crate where the soldier stands, using the squad rearm helpers (`holdoutRestock`, `holdoutRestockSeconds`).
8. **Wiped.** With no holdouts left, the goal becomes "counter" and X remains the target, so arriving groups attack it. The commitment timer still applies: when it moves the side on, the hold ends with reason `commit`.
9. **End reasons.** `recaptured`, `commit`, `target_moved`.

#### Tunables (all in `settings.sqf`)

`holdoutCheckSeconds` 3, `holdoutMargin` 60, `holdoutVoteGrace` 150, `holdoutUnprotectGrace` 60, `holdoutCoverRadius` 120, `holdoutGarrison` true, `holdoutSettleSeconds` 20, `holdoutBreakFraction` 0.34, `holdoutFallbackBeyond` 40, `holdoutFallbackMax` 300, `holdoutCoverSearch` 60, `holdoutArriveMargin` 30, `holdoutResupply` true, `holdoutResupplyCost` 200, `holdoutResupplyCooldown` 240, `holdoutResupplyFirstDelay` 30, `holdoutResupplyDelay` 30, `holdoutRestock` true, `holdoutRestockSeconds` 15.

#### Decision rows

| Decision | Why | Alternative rejected |
|---|---|---|
| Keep X as target by vote plus preferred target, and protect X separately if needed | Writing the target directly leaves Warlords' vote loop out of step | Direct write to `BIS_WL_currentSector` |
| Open reinforcement with `forceGo`, not `pushStart` | An ASSAULT phase with no attackers returns "wiped" and repeats the push-over | `pushStart` |
| Crate is a CP debit plus a direct spawn after 30 s | Warlords' airdrop lands 50 to 150 m away, beyond rearm reach of men in cover | Warlords' airdrop |
| Reinforcements carrying extra ammunition: **not built** | Optional in the brief, and the crate covers the need | |
| One X at a time per side | Keeps the goal and the panel unambiguous | A list of holds |
| If Y falls during a hold, Y gets the same protection on the way out and its groups head for X | The men inside would otherwise die to Warlords' kill rule | |

#### Player-visible text

Radio (`%1` is the sector name), cooldown in seconds:

- `holdformed` (20): "We've lost %1 but we're still in there. Holding on." / "%1 has fallen with our people inside. They're staying." / "Enemy has %1. Our groups inside are holding."
- `holdsupply` (30): "Resupply on the way to %1." / "Ammo drop coming in at %1." / "Crate inbound for the holdouts at %1."

Group reason on the panel: "holding out, waiting for reinforcements". Goal text is in `part-c.md`.

#### Item 8: ground between rally points, per Tanoa link

From `MP_Warlords_03.Tanoa` `mission.sqm`. Rally gap = centre distance minus both half sizes minus 2 x `rallyOutside` (200 m), straight line. This is an estimate: the real rally point is on the route, and square sectors are measured along the line.

| Link | Centre distance (m) | Rally gap (m) | Result |
|---|---|---|---|
| Base (2787,5711) to Industrial (1715,6128) | 1149 | 549 | Fine |
| Base (2787,5711) to Town (3411,6704) | 1173 | 573 | Fine |
| Base (1602,8489) to Town (983,7656) | 1038 | 388 | Fine |
| Base (1602,8489) to Radio (2341,8183) | 801 | 201 | Tightest, still open ground |
| Industrial to Town (3411,6704) | 1791 | 1191 | Fine |
| Town (3411,6704) to Military (2665,7345) | 984 | 334 | Fine |
| Town (983,7656) to Radio | 1457 | 807 | Fine |
| Military to Radio | 897 | 247 | Second tightest, still open ground |

All are positive, so no per-map change was made. The two tight links are the ones to watch in a round.

#### Scenario and gate

Scenario `tests/mission_overlay/swl/scenarios/fronta.sqf`, gate `tools/gates_fa.py` (`--gate fronta`, in `analyse_round.py`).

Round command: `-DurationMinutes 18 -Scenario fronta -Overrides "ruleCommitTimer=false;scanBuying=false;holdClearSeconds=60"`, then `python tools/analyse_round.py <rpt> --gate fronta`.

Gate limits, constants at the top of `gates_fa.py`: reinforcements leave within 180 s (the tunable the brief asked to have reported), vote allowed 90 s, target share 0.9, stay within 350 m, fallback slack 60 m, delivered within 40 m.

The scenario makes WEST lose a sector on a real route: three groups are teleported in, 12 invulnerable EAST men garrison it, X is flipped to EAST. It then makes ammunition low (t0+150), breaks a group (t0+300) and wipes the holdouts (t0+620). `SWLC_capMult_WEST` is 100 on X so a capture can't undo it.

#### Scenario limits

- WEST only. The code is side-neutral but EAST isn't exercised.
- `SWLC_fnc_frontFighting` is replaced by a stub, so Part B's detection isn't tested here.
- The scenario can run about 17 of the 18 minutes, so a late start may cut the end.
- "Arrive while holdouts live in a reasonable share of runs" needs several runs; one round gives one sample.
- The winner mustering at X (item 7) is existing behaviour and unchanged. The scenario's EAST is invulnerable and static, so it doesn't test that push.

### Part B as built: defender fast travel until real fighting reaches a sector

Files: `commander/swlc/front.sqf` (new); small edits in `settings.sqf`, `init.sqf`, `rules.sqf` (install), `adapter.sqf`, `radio.sqf`, `status.sqf`, `client.sqf`, `defence.sqf`, `staging.sqf`, `menu.sqf`. Tests: `tests/mission_overlay/swl/scenarios/frontb.sqf`, `tools/gates_fb.py`.

#### Do players get the rule? Yes.

Warlords' fast travel menu builds its list as `(BIS_WL_sectorsArrayFriendly # 0) select {_x getVariable ["FastTravelEnabled", TRUE]}` (`fn_WLRequestFastTravel.sqf` line 60). A public `setVariable ["FastTravelEnabled", false, true]` on the sector takes it out of every player's list. `adCanFTTo` reads the same variable, so players and the commander are driven by one switch. Nothing needs overriding in Warlords.

#### What Warlords' fast travel setting 4 does (from its code)

- It does **not** block an owned sector the enemy is targeting. Slot 0 of `BIS_fnc_WLSectorListing` is simply every sector the side owns (`fn_WLSectorListing.sqf` line 17), target or not. The menu then filters only on `FastTravelEnabled`, and takes away the player's own base while `BIS_WL_baseFTDisabled` is set.
- Setting 4 offers `FTSeized` only (`fn_WLParseAssetList.sqf` line 150). `FTConflict`, fast travel to the conflict for a fee, needs setting 1 or 2.
- Warlords does **not** refuse fast travel into a sector being seized, despite what the prompt expected. The `FTSeized` item has no such check (`fn_WLSubroutine_purchaseMenuAssetAvailability.sqf` lines 12 to 16), so before this rule players could land in a sector being seized. Now a seize closes it. So the rule both keeps nothing open that Warlords would close, and closes the seize case Warlords doesn't.
- For the commander, `adCanFTTo` had no targeted-sector check either, only base-under-attack and "being seized" (rules variant). But three of its callers (`musterChoose`, `defHop`, `menuFollow`) refused any sector on the commander's threat board. Those now use `SWLC_fnc_frontHot`: with the rule on, only real fighting makes a sector off limits; with it off, the old threat-board test. That is what actually gives the commander its defender's advantage.
- Default Tanoa map setting is FT 1 (`mission.sqm`); the test tools pass 4. Every sector's `FastTravelEnabled` in the Tanoa mission is true.

#### Side effect to know about (settings 1 and 2 only)

`FastTravelEnabled` is also read for the attacking side's paid "fast travel to the conflict" (`FTConflict`, line 22 of the availability file) and for vanilla AI's fast travel to the conflict at settings 1 and 3 (`fn_WLAICore.fsm`). So at settings 1 or 2 a player attacking Y loses that paid option while real fighting is on at Y. At setting 4 this can't happen, since `FTConflict` isn't offered. Accepted: it is still "no fast travel into a real fight", and the alternative is rewriting Warlords' menu.

#### Spec as built

State per sector owned by WEST or EAST, polled every 5 s on its own server loop (`SWLC_fnc_frontLoop` calling `SWLC_fnc_frontTick`). All tunables in `settings.sqf`, one switch `ruleDefenderFT`, under `rulesVariant`.

- **Area**: the capture square plus `frontAreaMargin` (175 m).
- **Both sides**: at least one attacker and one defender in the area fired within `frontExchangeSeconds` (15), or a man of either side died in the area within that time, killed by someone. One side shooting at nothing doesn't count.
- **Numbers**: `frontMinAttackers` (3) men of the opposing Warlords side who, within `frontInvolvedSeconds` (90), fired, came under fire or died in the area. GUER don't count as attackers.
- **Sustained**: `frontWindowsNeeded` (2) of the last `frontWindowsTotal` (3) finished `frontWindowSeconds` (30) windows contained a moment meeting both of the above. Windows start at the first exchange, so one burst sits inside one window; the window still running doesn't count. A continuous fight closes it about 60 to 65 s after the first exchange.
- **Seizing**: `SWLC_fnc_capBeingSeized` true for the owner closes it at once, whatever the numbers. Decision: follows the prompt's list, even though a lone man could seize an empty sector, because Warlords' own seize rules decide that and at that point the sector is really being lost.
- **Lifting**: `frontQuietSeconds` (120) since the last qualifying moment and the last seize. A lone enemy can't keep it closed: a moment only qualifies with 3 or more attackers involved, so once they have gone his shots don't extend it.
- A sector changing hands drops the state, reopens its fast travel, and starts fresh for the new owner (`why=owner_changed`, no radio line).
- `SWLC_ftBase` keeps a sector the map disabled closed; `FastTravelEnabled` is written only when it changes.

Interface for the other parts: `[_sector] call SWLC_fnc_frontFighting`, `[_side, _sector] call SWLC_fnc_frontFTOpen`. Reads `SWLC_firedAt` and `SWLC_underFireAt` (part D's handlers). Without those handlers no exchange is ever seen and only a casualty or a seize can trigger it, so part B needs part D merged for real rounds.

While fighting is on, every commander fast travel goes through `adCanFTTo`, so the sector drops out and the callers' existing lists pick the nearest other owned sector (`routeFastTravel`, `watchdogEscalate`, `defHop` already sort or take nearest first).

Rules variant off, or `ruleDefenderFT` off: `frontInstall` exits, no loop or handler runs, `FastTravelEnabled` is never written, `frontFighting` is false and `frontFTOpen` is plain `adCanFTTo`. The three callers fall back to the old threat-board test.

#### Decisions

| Decision | Why |
|---|---|
| One public `FastTravelEnabled`, no change to Warlords' menu | The menu and `adCanFTTo` already read it, so players and commander can't disagree |
| Windows anchored at the first exchange, only finished windows counted | Fixed clock windows let one burst across a boundary look sustained; finished windows match "most of the last 60 to 90 s" |
| Quiet is measured from the last moment that meets the full definition | Stops one remaining enemy holding fast travel shut, in the spirit of "a lone man must never control it" |
| Casualties need a killer | Warlords' restricted-area kills and accidents use `setDamage` with no instigator, and aren't a fight |
| Attackers are the opposing Warlords side only | GUER only garrison neutral sectors; a neutral garrison near Y isn't the attack on Y |
| Radio cooldown 30 s per side and type, added in `frontInstall` rather than the shared cooldown table | Keeps one settings block for this part; a second sector changing inside 30 s still logs in `C_FRONT` |

#### Player-visible text

Radio (`ftclose`, `ftopen`, in `radio.sqf`), `%1` is the sector name:

- "Real fighting at %1. Fast travel there is closed, use the next sector over."
- "%1 is a fight now, no more fast travel in. Come in from a neighbouring sector."
- "Fast travel to %1 is shut, they're on it."
- "%1 is hot. Fast travel closed."
- "%1 has gone quiet. Fast travel there is open again."
- "Fast travel to %1 is back open."
- "%1 is quiet. You can fast travel in again."
- "Fighting's over at %1, fast travel is open."

Commander panel, one line under the header when a sector is targeted, on the threat board or fighting: "Fast travel: Name open, Name closed".

#### Scenario limits

`frontb.sqf` (about 13 minutes, not yet run; rounds are the owner's job) drives the state machine by writing `SWLC_firedAt` directly and raises the seize alarm by hand (`BIS_WL_timeoutCur_EAST`, as gatee's fallback does). It proves the rule and the switches, not part D's handlers or a real capture. A real round's `C_FRONT` lines cover those. The "players get it" claim comes from reading Warlords' code; the scenario checks the public variable, not a live player's menu. A player who already has the destination map open when it closes can still click that sector, because the list is built when the map opens.

### Part C as built: switching between holding X and defending Y

Status: lint clean, gate checked against a hand-written log only. Nothing has run in Arma yet.

Code: `commander/swlc/holdouts.sqf` (`holdGoalTick`, `holdDefendTick`, `holdDefendGroup`, `holdDefendRelease`, `holdSetGoal`, `holdStatusText`). Part B's `SWLC_fnc_frontFighting` is the only source of "active fighting at Y", called through a nil guard, so the fast travel rule and the AI share one signal.

Switch: `holdoutSwitching`, under `ruleHoldouts`. Default on.

#### Spec as built

`_cmd get "frontGoal"` is `[]`, `["hold", X]`, `["counter", X]` or `["defend", Y]`.

1. **Switch to Y.** While a hold is on, if any owned sector has active fighting, the nearest to X becomes Y and the goal is `defend`.
2. **Groups at or near X.** A group within `holdNearXMetres` of X that is fighting carries on. Holdouts never switch and keep the resupply rules.
3. **Groups at or near Y.** Those within Y's half size plus `holdDefendNearMetres`, in a normal job state, turn to defend Y.
4. **New arrivals.** Unassigned, Mustering or Travelling groups on foot fast travel to the side's nearest other sector that allows it, then push into Y. Groups in vehicles drive.
5. **Back to X.** Y is clear when `frontFighting` is false and no enemy is known there for `holdClearSeconds`. Groups defending Y go back to Unassigned and the normal assignment sends them to X, as `hold` or `counter` depending on whether any holdouts are alive.
6. **Y falls while defended.** The goal returns to X. Y gets the same sector protection as X, so the men inside can walk out.
7. **Commitment timer.** If it moves the side on, the hold ends and `frontGoal` clears.

#### Tunables

`holdoutSwitching` true, `holdClearSeconds` 120, `holdNearXMetres` 350, `holdDefendNearMetres` 150.

#### Decision rows

| Decision | Why |
|---|---|
| While a hold exists, reinforcements stop only when the goal is `defend`; the target stays X throughout | Holdouts at X still need Warlords' protection, and a target flip would risk that |
| Y's clear test is `frontFighting` plus the commander's known threat at Y | Matches the brief's "no active fighting, and no enemy known inside Y's area" |
| Assaulting groups count as near Y only when they're at Y | A group attacking elsewhere shouldn't be pulled off |

#### Player-visible text

Radio (`%1` is the sector name), each with a 20 s cooldown:

- `holdgoal_hold`: "Holding %1. All free units get to them." / "Priority is %1. Reinforce the holdouts." / "Holding %1, reinforcements go there first."
- `holdgoal_counter`: "Counterattacking %1." / "Holdouts are gone. Counterattack %1." / "We're taking %1 back."
- `holdgoal_defend`: "Defending %1. Expel them." / "Enemy at %1, everyone not fighting defends it." / "Defending %1, push them out."

Panel, in front of the capture status line: "Holding %1", "Counterattacking %1" or "Defending %1". No client change was needed.

#### Scenario and gate

Same scenario and round as Part A (`fronta`). It switches the stubbed `frontFighting` on for Y at t0+390 and off at t0+480. The override `holdClearSeconds=60` shortens the wait for the switch back.

Gate limits: switch within 30 s of fighting starting at Y, back to X within 200 s of it stopping, counter within 40 s of the wipe.

#### Scenario limits

- `frontFighting` is a stub, so the real detection is only exercised in Part B's own scenario.
- The merged result (A, B, C and D together) hasn't been tested. Without Part B merged, no sector counts as fighting outside the scenario, so the goal never becomes `defend`. Without Part D, "fighting" falls back to the leader being in COMBAT mode.
- A forced revote also affects a side with human players on it, because Warlords has one vote per side.
- Only one Y at a time. A second sector under attack waits until the first is resolved.

### Part D: fights on the way are real fights

Code: `commander/swlc/engaged.sqf`, small hooks elsewhere. Switch: `behEngaged`, default on, independent of the rules variant. Nothing here has run in Arma yet: lint and the gate tool against a made-up log are the only checks so far.

#### As built

**Fire tracking.** Every unit on the server gets `FiredMan`, `Suppressed` and `Hit` handlers once (`SWLC_fnc_contactAttachAll`, at most every 5 s). They write `SWLC_firedAt` and `SWLC_underFireAt`. `SWLC_fnc_groupFighting` is true if a living man fired or was fired on within `fightingWindow` (90 s). Smoke doesn't count, and neither does fire from a friendly side.

**Entering Engaged.** Each tick, a group in `engagedStates` (Travelling, Advancing) stops if it is fighting and knows of enemy within `engagedRange` (300 m), or knows of enemy within `engagedCloseRange` (120 m) whether fighting or not. Not inside the attack's target square, not a group under a LAMBS task, not a group `SWLC_fnc_resMayTouch` refuses. It saves its job, goal, order, leg and wave, then gets a search-and-destroy order at the contact, or holds where it is if the contact is on water or in a sector it may not enter.

**One fight.** Contacts within `engagedMergeMetres` (250 m) share a record, which holds position, strength (infantry + 3 x light + 6 x armour, as in defence) and members. The first contact gives one radio report.

**Joining.** Need is the defence formula: `ceil(strength x responseMargin / defenceMenPerGroup)`, at least 1, at most `defenceMaxGroups`. `responseMargin` is read directly so it applies with the rules variant off. Candidates are in `engagedJoinStates`, within `engagedJoinRadius` (600 m), on foot, not in combat, not fighting. Groups from the current wave are capped at `floor(wave groups x responseCapFraction)`.

**Ending.** The fight ends when no enemy is known near and nobody has fired for `engagedClearSeconds` (40 s), or when nobody has fired for `fightingWindow` even with a sighting still listed. Each group goes back to its saved job, goal, order and leg if its wave or muster still exists, otherwise to Unassigned. A group whose transport has gone continues on foot.

**Bigger enemy.** If strength is at least `engagedFallbackMinMen` (10) and at least `engagedFallbackRatio` (2.5) times the men on hand (a combat vehicle adds 5), the groups go to the nearest owned sector through `defSend`. That sector gets a threat record with the force's strength and is held open `engagedFallbackHoldSeconds` (150 s), and `defRespond` runs at once.

**Vehicles.** A combat vehicle stays crewed and fights under the group's order, then resumes. A transport on its DRIVE leg drops its passengers where it stands, the driver drives `engagedTransportBack` (200 m) away from the contact, then gets out and walks back to the group.

**Resilience.** `groupFighting` is the only test, in each of: watchdog (post-contact reset and progress), ladder (`ladderStep`), sweep (`resFaultOf`, `resIsIdle`), waypoint guard, vehicle stuck check. `waveVehicleLegs` skips Engaged groups. The observer logs `fighting=` on every GRP line. `gates_activity.py` and `gates_r.py` use it and list Engaged as a working job.

#### Decisions

| Decision | Why |
|---|---|
| In transit means Travelling and Advancing only | Mustering and Waiting are already standing at a sector or the rally and fight there. Regrouping and Assaulting have their own rules. `engagedStates` can widen it |
| `FiredMan`, not `Fired` as the brief listed | `Fired` on a man misses shots from a vehicle turret |
| A holdout has no separate test | The 90 s cap makes "holdout in contact" the same as `groupFighting`, so holdouts are covered without Part A code |
| Script errors still climb the ladder for a fighting group | An error says nothing about the fight |
| Waypoint guard leaves a fighting group's waypoints alone unless it is Engaged | Restoring can re-plan a route or fast travel. Warlords' waypoints can stand for up to 90 s after the last shot |
| Mustering groups can't join | Pulling one out would break its muster. Defence still takes them when their own sector is hit |
| Vehicle-borne groups can't join | A transport joining from far away would dismount far from the fight |
| Aircraft don't count as contact | A passing helicopter shouldn't stop a march |
| Contacts need `intelMinKnows` | Same bar as a sighting on the board, so a group only reacts to what its men have seen |

#### Player-visible text

Radio, in `radio.sqf`: `engaged` (where and how strong), `engagedjoin`, `engagedclear`, `engagedfall`. Status panel: job "Fighting", place "on the way", reason "in contact" or "moving to help".

#### Scenario limits (`frontd.sqf`)

- Needs both sides to have an attack running within 300 s, otherwise it logs `no_op` and the gate fails.
- The groups are real commander groups moved into position, so the march isn't a natural meeting of two waves. If a wave resolves during the test, its groups go to Unassigned, not back on route.
- The join gate needs the leaders to see about 9 of the 12 enemy men, or the need stays at 2 and nobody is called.
- The helper group is held in place with `SWLC_patrolAt` and `SWLC_noAssignUntil`, but the reserve can still shrink and release it.
- The waves are on foot, so the transport gate only judges a transport if one meets the enemy by chance. It passes otherwise, and says so.
- The bigger enemy is 16 Syndikat men, on the assumption that independents are hostile to both sides on this mission.

#### Known limits

- `Hit` and `Suppressed` fire only where the unit is local, so player-local units may under-report being fired on. Commander AI is server-local.
- On falling back, `defSend` releases the group's vehicle, so a combat vehicle is left parked. Same as any defence pull today.
- Tick cost is estimated, not measured. Run with `profileStages=true`, and the gate prints `engagedTick` and `contactAttachAll`.

### Part E: measuring where the fighting happens

Built in `tools/gates_front.py`, `tools/plot_round.py` (`--heat`) and registered in `tools/analyse_round.py` as `--gate front`.

#### Commands

```
python tools/gates_front.py <rpt> [<rpt> ...]
python tools/gates_front.py <rpt> --gate front --baseline-share 0.35
python tools/gates_front.py <rpt> --gate front --baseline <baseline rpt> [...]
python tools/gates_front.py --compare <baseline rpts> --variant <variant rpts> [--gate front]
python tools/analyse_round.py <rpt> --gate front --baseline-share 0.35
python tools/analyse_round.py <rpt> --gate front --baseline <baseline rpt> [...]
python tools/plot_round.py <rpt> --heat [--heat-out kills.png]
```

`--gate front` should be added to the gate list in `tests/README.md` when this is merged.

#### Spec as built

Kill classes, checked in this order, for every `C_KILL` from the first sector clash on:

| Class | Meaning |
| --- | --- |
| `contested` | Inside the capture area of a sector either side is targeting at that moment |
| `other_sector` | Inside any other sector's capture area |
| `edge` | Within 200 m of any sector's capture area |
| `between` | Everywhere else |

The capture area is an axis-aligned square of the sector's `size`, as in `fn_WLSectorsSetup.sqf` (`setTriggerArea [size / 2, size / 2, 0, TRUE]`).

After a sector falls from one side to the other, kills are watched for 600 s, or until X or Y changes hands or the round ends. Each kill goes to the latest fall whose window holds it. Zones, in this order:

| Zone | Meaning |
| --- | --- |
| `at_x` | Inside X's capture area or within 200 m of it |
| `loser_sector` | Inside the capture area of a sector the losing side owns at that moment |
| `other_area` | Inside any other sector's capture area |
| `corridor` | Within 300 m of the straight line from X to Y |
| `elsewhere` | Everywhere else |

The gate share is `(at_x + corridor) / all kills in fall windows`. It passes at baseline + 10 points or better (`--margin`), with at least 20 kills in the fall windows.

#### Decisions

| Decision | Why |
| --- | --- |
| The first clash is the earlier of the first capture and the first kill in or within 200 m of a targeted sector | The brief doesn't define it. Kills before that are road contact, and are counted and printed as left out |
| "The loser still targeting X" needs no code of its own | That loser's `TARGET` line still names X, so it is one of the current targets |
| Just after a capture, X counts as `contested` only if someone still targets it | This is the requested definition. A vanilla round, where the loser wasn't targeting X, shows those kills as `other_sector`. The gate's `at_x` zone counts them whatever the targets are |
| Falls from GUER are left out of the fall analysis | There is no losing commander and no next sector of its own |
| Y is the winner's next target if the losing side owned it, otherwise the losing side's nearest owned sector to X | Matches the prompt's two descriptions of Y |
| The gate counts all kills, and the report also prints the share for kills between the two sides only | The brief says "share of kills"; the second number shows how much GUER garrisons affect it |
| The gate fails when it can't judge: no baseline, or under 20 kills | A gate must not pass on missing data. The numbers are printed anyway |
| `C_HOLD`, `C_FRONT`, `C_ENGAGED` are read with `.get`, and a line without `side` or `sector` matches any fall | Those lines are being written by other helpers. Field names follow the brief |
| Sector links on the heat map are read at run time from the stock `mission.sqm` in the gitignored `reference/` | They aren't logged, and Bohemia's mission data must not be committed. With no reference folder the map draws no links and says so |
| "Stayed there" is reported but not gated | The brief's gate is the share. It ends at the first 120 s bin where kills in the losing side's sectors outnumber kills at X and in the corridor |

#### Limits

- No RPT has `C_KILL` yet. Tested on synthetic logs and on a real old RPT with injected kills, so numbers from real kills are untested.
- `C_HOLD`, `C_FRONT` and `C_ENGAGED` are tested only against lines I wrote from the brief's field list. If the helpers name fields differently, those sections need a small change.
- The stored baseline (`2026-11-08_19-26-56_baseline`) has no `C_KILL` lines and only one side-to-side capture, so it can't supply a baseline share. A vanilla round with kill logging is needed for that.
- Engaged contacts are counted from `event=start`. Every start is treated as in transit, because Engaged is a transit state.

## Defence

Built in the run of 2026-11-09, from the user's addition (`docs/runs/2026-11-09-front-line/prompt-defence.md`). Code: `stance.sqf`, `alert.sqf`, `fortify.sqf`, with hooks in `defence.sqf`, `pickets.sqf`, `raids.sqf`, `rules.sqf`, `front.sqf`, `upkeep.sqf` and `squads.sqf`. Each behaviour has its own switch in `settings.sqf`, default on.

**Rules variant.** None of this depends on it. Stance, alert and fortify stay on with the lobby parameter off, like resilience. What goes away with it is what they lean on: pickets, raids, probes, holdouts, the commitment timer, and the capability and price rules for statics.

**Sides with humans.** The commander works the same way on a side with players, using its own groups only.

- It never orders a player, a group with a player in it, or a group that had one within `playerGroupGrace` 120 s (`resMayTouch`), which also covers a player's own AI. Gun crews and AT men are never players.
- Statics are paid for by AI warlords only, because `adSideCP` and `adDebit` only read their funds. A player's CP is never spent.
- The players' vote stays theirs (`voteOnPlayerSide` false). A human side never gets a commit-timer rebuild, because its vote is reopened instead. The AI doesn't buy raids there (`raidAIOnPlayerSide` false).
- In hold or rebuild, the AI groups don't follow the voted target. Players pushing a sector get no AI waves, and only the panel and radio say why.

Status when this was written: the `stance` and `alert` scenarios passed (`stance1`, `alert1`), with the enemy numbers scripted in `stance1`. `progress.md` records no `fortify` scenario result yet.

### Stance: attack, hold, rebuild

`stance.sqf`, switch `stanceEnabled`. Logged as `C_STANCE`. Works per side from the side's own numbers and its intel board, never true enemy numbers.

Every `stanceTickSeconds` 20:

- **Own strength**: men alive, plus CP as men (`CP / stanceCPPerMan` 150, at most `stanceCPMaxMen` 15), plus `stanceArmourWeight` 6 per own combat vehicle, less those the known enemy AT cancels (`planAtPerArmour` 2 launchers each).
- **Known enemy**: from the board, infantry + `stanceLightWeight` 3 per light vehicle or aircraft + 6 per armoured vehicle, less what own AT cancels. Enemy statics and CP aren't counted.
- **Memory**: the known figure is a peak that halves every `stanceMemoryHalfLife` 240 s, so a side at home doesn't "recover" because its board went stale.
- **Ratio**: own / (known peak x `stanceIntelFactor` 1.1) x outcome factor. The factor is 1, plus `stanceOutcomeStep` 0.15 per capture, minus the same per failed push, within `stanceOutcomeWindow` 420 s, kept between `stanceOutcomeMin` 0.7 and `stanceOutcomeMax` 1.2.

| From | To | When |
| --- | --- | --- |
| Attack | Hold | Ratio below `stanceHoldBelow` 0.9 |
| Hold | Rebuild | Ratio below `stanceRebuildBelow` 0.55 |
| Rebuild | Hold | Ratio at least `stanceHoldAbove` 0.8 |
| Hold or rebuild | Attack | Ratio at least `stanceAttackAbove` 1.25, or known peak under `stanceMinKnown` 12 |
| Hold | Attack | The quiet breaker, below |
| Any | Rebuild | The commitment rule's rebuild is running (`reason=commit`, ignores the minimum time) |

Hysteresis is the gap between those thresholds plus `stanceMinSeconds` 180 between switches. On the balance alone, a side passes through hold on the way to rebuild.

**Quiet breaker** (`stanceQuietSeconds` 420): a side in hold whose groups haven't fought for that long, and hasn't changed stance in that time, goes back to attack. Otherwise it stands idle for good, and two sides in hold stall the round. It applies to hold only, not rebuild.

**Attack** is the normal game.

**Hold**:

- No new wave (`SWLC_fnc_stanceNoWave`, the gate on `cmdNewPlan` and the idle-cap replan). For a wave already out, nothing new goes in, groups not in a fight go back, and the op ends once nobody is in contact. A group in a fight is never touched.
- The whole side stands in the reserve (`stanceHoldReserveFraction` 1). Pickets, defence responses, raids and probes draw on it. Pickets stay out rather than returning to an attack.
- Raids and probes (rules variant only) keep `stanceHoldRaidKeep` 3 groups back. AI raids send `stanceHoldRaidGroups` 1 at a sector with at most `stanceHoldRaidMaxDefenders` 3 known strength. A probe takes one group.
- With no wave out, the reserve is topped up with infantry at the central sector, with `stanceAtPerGroup` 1 AT launcher per group plus `planAtPerArmour` per known armour. No vehicles are bought.

**Rebuild** is the existing rebuild (`SWLC_fnc_rebuilding` is true): everyone in the reserve at `defCentralSector`, infantry bought there, no raids or probes. Pickets go back under the existing short-attack rule. Going back to attack is the counterattack.

Votes, holdouts and the commitment timer:

- Hold and rebuild sides vote normally through `voteChoose`. The target is nominal until the side is back in attack. While no wave can start, the commitment timer and the deadlock revote are reset every tick.
- Holdouts' "hold" goal continues in any stance: with X as the target a wave to X is allowed (`stanceHoldoutJob`). "Counter" waits for attack, and the reserve isn't emptied for it.
- A commit-timer rebuild puts the side in the rebuild stance for its full `rebuildSeconds` 240. The balance then decides, so a weak side stays in rebuild longer. The commitment rule's voting pause covers those 240 s only.

Other tunable: `stanceLogSeconds` 60.

### Defence starts when the enemy picks the target

`alert.sqf`, switch `alertEnabled` (also needs `defenceEnabled`). Logged as `C_ALERT`.

**Trigger.** An alert starts when the enemy's Warlords target is one of the side's sectors. It clears when that target changes (`target_changed`) or the sector changes owner (`owner_changed`). One alert at a time per side.

**Predicted approach.** The `alertApproachCandidates` 3 nearest enemy sectors are compared by road length through the route network, and the shortest route is walked out from the sector. Bearing and point are read where the route is `alertApproachSample` 500 m out. Road points are route nodes within `alertRoadRange` 700, thinned by `alertRoadSpacing` 60, at most `alertRoadMax` 8. With no route it uses the straight line to the nearest enemy sector, and roads within `alertRoadSearch` 40 of the points at `alertRoadLineMetres` 200, 400 and 600.

**Groups sent**, from `alertLayers`:

| Stance | Main | Screen | Counter | Most of the side's groups all three may take |
| --- | --- | --- | --- | --- |
| Attack | 1 | 1 | 0 | 0.34 |
| Hold | 2 | 1 | 1 | 0.6 |
| Rebuild | 3 | 1 | 2 | 0.8 |

A sector worth at least `alertValueHigh` 60 (a base or a muster always is) gets one more main group. The share caps the total: main first, then screen, then counter, and at least one group.

**Main position.** The alert writes a threat record, so `defRespond` sends the groups through its usual order and fast travel rules. `alertNeed` is a floor on its need. A record with only the warning (`alertOnly`) takes up to the peel cap, never pulls attackers in contact, doesn't stop a muster and is dropped when the alert clears. A real sighting, an engaged fallback or a counter hit clears `alertOnly`.

**Spots.** `holdCover` around a point `alertCoverBias` 0.6 of the half-width out on the approach side, within `alertCoverRadius` 120. A spot must be within `alertCoverArc` 100 degrees of the bearing, at least `alertCoverMinFraction` 0.25 of the half-width from the centre, and no more than `alertCoverOutside` 50 m outside the square. No spot means `defSpots`.

**LAMBS.** With LAMBS loaded, `lambsHold` centres its garrison on the group's spot (`SWLC_alertCover`), so it garrisons the approach side and not the middle. It uses LAMBS' defend task when the buildings don't have room for the whole group.

**Facing.** Groups at their spots turn to the bearing every `alertFaceSeconds` 30, except AT men on the road.

### Statics from Warlords' defences

`fortify.sqf`, switch `fortifyEnabled`. Logged as `C_FORT`, with a `C_BUY` line per purchase. Reads the alert record only, so no alert means no spending.

Classes, from Warlords' Defences list (read from its config, not a running game). AT is on offer for both sides in this preset. Without it the mix moves on.

| Kind | WEST | EAST | Cost |
| --- | --- | --- | --- |
| MG | `B_HMG_01_F`, `B_HMG_01_high_F` | `O_HMG_01_F`, `O_HMG_01_high_F` | 250 |
| GL | `B_GMG_01_F`, `B_GMG_01_high_F` | `O_GMG_01_F`, `O_GMG_01_high_F` | 250 |
| AT | `B_static_AT_F` | `O_static_AT_F` | 500 |

`fortifyMix` is MG, AT, GL, MG, walked from the gun's slot, so a kind that isn't on offer, allowed or affordable gives way to the next. `fortifyPreferHigh` true takes the raised tripods for MG and GL. Capability rules and prices go through `econAssetAllowed` and `econPriceMult` on every purchase.

| Tunable | Attack | Hold | Rebuild |
| --- | --- | --- | --- |
| `fortifyStatics<Stance>`, guns per sector | 2 | 4 | 4 |
| `fortifyCpFraction<Stance>`, most one gun may cost as a share of free CP | 0.25 | 0.6 | 0.6 |

`fortifyMaxPerSector` 4 is a hard cap over those, and `fortifyBuyPerTick` 1 limits the rate. Free CP is `cpFree`, so the reserve holds. A destroyed gun counts against the cap for `fortifyReplaceSeconds` 240.

**No purchase** unless a man who could crew it is within `fortifyCrewReach` 300 m of the point the guns go to, and no hostile is within `ftEnemyCheckRadius` 200 m of that point (`fortifyRespectEnemyNear` true). Warlords' own rule refuses a player placing a defence in that case.

**Placement.** On the approach at `fortifyEdgeFraction` 0.4 of the sector's width, trying 20, 40 and 60 degrees either side and 30 m in or out. A spot must be inside the square, at least `fortifyMinCentreDist` 40 from the centre, at least `fortifyRoadClear` 8 from a road, gradient under `fortifyMaxGradient` 0.4, at least `fortifySpacing` 30 from other guns, and clear of men. The first spot with open terrain along `fortifyCoverRange` 200 wins, otherwise the first valid one. `fortifyNoSpotRetry` 60 before a sector with no valid ground is looked at again.

**Crew.** From the alert's main groups, each passing `resMayTouch`: alive, not a player, on foot, not the leader, not an AT soldier, not on a kit errand, able to move. So a LAMBS-garrisoned man isn't taken. Riflemen first, nearest first, at most `fortifyMaxCrewPerGroup` 2 per group. He stays in his group and gets `fortifyCrewWalkSeconds` 30 plus the distance at `fortifyCrewWalkSpeed` 2.5 m/s. If he is within `fortifyCrewSeatDist` 12 m when time runs out he is seated directly, otherwise another is picked. A dead gunner is replaced every tick.

**AT soldiers on roads.** Up to `fortifyATMen` 2 non-leader AT soldiers go to a spot `fortifyATRoadOffset` 12 m off a road point within `fortifyATReachFraction` 0.75 of the width, furthest forward first, on opposite sides of the road in turn. They kneel and watch up the road (`fortifyATLookRange` 150). With no road points, the same on the line of the approach. Pushed more than `fortifyATDrift` 25 off the spot, a man is sent back up to `fortifyATDriftMax` 2 times, then released. A LAMBS task on his group ends the job at once.

**Alert end.** Guns stay. Gunners and AT men go back to their groups.

### Defence in depth

All in `alert.sqf`, fitted to the existing pickets, reserve and proportionate response. Groups for the screen and counter come from `alertPool`, in order: a picket on this sector, the reserve, free groups and a muster at this sector, then the attack only if the stance isn't attack. Never a group in a fight or under a LAMBS task. While reinforcing holdouts outranks everything and this sector has no real fighting, only pickets and the reserve can be used.

- **Screen** (`alertScreen`): one small foot group `alertScreenBeyond` 250 m beyond the sector edge on the approach, at cover within `alertScreenCover` 60 if there is any. State Defending, not on the threat record.
- **Main position**: the defenders and the statics, above.
- **Counterattack reserve** (`alertCounter`): state Reserve, waiting `alertCounterBack` 150 m behind the sector edge. On a break-in (the seize countdown, or `alertBreakInMen` 2 enemy known inside the square plus `alertInsideMargin` 0) each group goes straight to a search and destroy on the sector centre and joins the threat record. It is protected from ordinary defence orders for `alertCounterHitSeconds` 300.

Counter groups count towards the reserve's size but aren't rotated, shrunk or moved, and pickets, raids, hunts and engaged joins skip them.

### Measuring the steamroll

`tools/gates_steamroll.py`, also `--gate steamroll` in `tools/analyse_round.py`. An analyser with no in-game switch, so the rules variant doesn't affect it. There is no pass threshold: it reports numbers.

```
python tools/gates_steamroll.py <rpt> [<rpt> ...]
python tools/gates_steamroll.py --compare <baseline rpts> --variant <variant rpts>
```

It reports the first clash and who won it, whether that side won the round, the time after it, sectors lost by each side after it, and whether a comeback happened. The first clash is the earliest decided clash on a sector both sides had a stake in. A comeback is the loser retaking a sector from the winner, or holding off an attack lasting at least 300 s on a sector of its own. The full definitions print with every report.

Four logs are too few to say anything. On those so far, two had no first clash, and neither of the other two had a comeback.

### Player-visible text

Panel, while a wave waits at the rally: "waiting for the rest of the wave, going in within %1" (replaces "needs %1 more group to go, or alone in %2").

Menu entry: "Cancel objective (press twice)". Radio: `cancelask` "Call off the attack on %1? Select Cancel objective again within %2 seconds to confirm."; `cancelok` "Objective %1 called off. Everyone out, then vote for a new target. %1 is off the table for %2 minutes."; `cancelno_none` "We've got no objective to call off."; `cancelno_pulling` "Already pulling out of there."; `cancelno_used` "We only just called one off. Give it a couple of minutes."; `cancelno_off` "Can't call that off, the commitment rule is turned off."

Radio (`%1` is the sector name, `%2` the compass direction of the approach), cooldown in seconds:

- `stance_attack` (20): "Balance has swung back our way. We're going on the attack." / "We've got the strength now. Back on the offensive." / "All units, we're attacking again."
- `stance_hold` (20): "They're stronger than we thought. Hold what we have, no big attacks." / "We're going on the defensive. Hold the line." / "Enemy has the edge for now. Dig in and hold."
- `stance_rebuild` (20): "We're too weak to stay out there. Pull back and rebuild." / "Falling back to rebuild. Everyone to the central sector." / "We need men before we can fight. Pull back, we're rebuilding."
- `alert` (30): "Enemy has picked %1. Expect them from the %2, get set up." / "Warning order: %1 is next, approach from the %2. Take positions." / "They're coming for %1, likely from the %2. Defenders move."
- `alertcounter` (30): "They're in %1. Reserve, hit them now." / "Break-in at %1, counterattack go." / "%1 is breached. Reserve, clear them out."
- `fortbuilt` (30, the default), once per alert when the first gun goes in: "Guns going in at %1, facing their approach." / "Setting up static weapons at %1." / "Digging guns in at %1, they're coming that way." / "%1 is getting guns on the approach."
- `holdvote` (30), from the front line reviews, to a side with players: "Our people are still holding %1. Vote %1 so we can reinforce them." / "%1 has fallen with our men inside. Put your vote on %1 and we'll go get them." / "Holdouts in %1. They need %1 voted as our target to get help."

The other holdout lines are listed under Parts A and C.

Commander panel: "Stance: ATTACK", "Stance: HOLD" or "Stance: REBUILD" on the header line, in front of the holdout goal text. It isn't shown with `stanceEnabled` off. Group rows show the screen and main groups as Defending and the counter as Reserve, through the existing text.

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
| The two-and-a-half hour limit from the user's message overrides the prompt's "No deadline" | The message came with the prompt and asked for testing to get most of the time. It was recorded in the run's progress log. |
| A lone group waits 60 s at a rally, rather than not waiting at all (`rallyLoneWait`) | A group sent in alone just dies. When anyone is already attacking the point, it goes straight in. |
| A stuck vehicle is lifted to a clear spot only well away from any fight, enemy or player (`vehUnstick`) | The user asked for this. It must never be visible or a way out of trouble, and it mustn't lose a bought tank. |
| A combat vehicle in a fight keeps its crew while its gun works, even if it can't move | A tank that has lost its tracks is still a gun. |
| Reserve duty rotates: the least-served group stays, and six minutes with a wave out is the limit (`reserveRotate`) | The reserve always kept the first group in the list, which left one commander waiting for 82% of a soak. The reserve can stand empty for a few minutes, because sustained combat matters more than a spare group. |
| A lone man seizing a sector doesn't close fast travel (`frontSeizeMinMen` 3) | The spec says a seize closes it and also that a lone infiltrator can never trigger closure. Defenders need to be able to reach that man. |
| A side with human players is asked by radio to vote for X, and its target is left alone | Their vote is theirs. If they don't vote for X, the hold ends after `holdoutVoteGrace` as `target_moved`. |
| `stanceIntelFactor` is 1.1, not the 1.25 it was built with | Set during the run, not by the user. Before CP and recent results, equal known numbers gave a ratio of 0.8 at 1.25 and put the side in hold. At 1.1 they give 0.91, above `stanceHoldBelow` 0.9, so they still attack. |
| Hold goes back to attack after `stanceQuietSeconds` 420 without a fight | Without it, a side in hold stands idle forever if the enemy never comes, and two sides in hold stall the round. Risk: a side still weaker than its known enemy can cycle hold, attack, hold. |
| Hold and rebuild sides vote normally | Warlords needs a target, and `voteChoose` already marks down known defenders. The target is nominal until the side is back in attack. |
| The holdouts' "hold" goal continues in any stance | Reinforcing them is a defensive job, so a wave to X is allowed while X is the target. |
| The holdouts' "counter" goal waits for attack | A counterattack is an attack, which the stance has just ruled out. It comes when the stance returns to attack. |
| A commit-timer rebuild puts the side in the rebuild stance, and the balance decides when it ends | The user asked that the commitment timer and rebuild feed into the stance, not run alongside it. The timer's 240 s still run in full. |
| The whole side stands in the reserve during hold, and pickets and raids draw on it | Anyone left Unassigned with no op shows as idle and fails the activity checks. The reserve is the pool those jobs can already use. |
| Left out: no vehicle re-weighting in hold | No muster shop runs without a wave, so none are bought anyway. |
| Left out: enemy statics aren't counted in the stance | They don't come for you. |
| Left out: the screen doesn't fall back and a lost screen isn't replaced | Feeding groups one at a time into the attackers is worse than the warning they give. |
| Left out: one approach prediction per alert | The threat record's bearing follows real sightings, but cover spots for groups already sent aren't redone. |
| Left out: walls and treelines aren't scored | Spots are buildings near the approach, with `holdCover`'s fallback to the staging search, which weights houses and trees. The user asked for walls and treelines, so this is less than requested. |
| The alert uses the enemy's chosen target, which no soldier has seen | The one allowed exception to "only what soldiers have seen", given by the user in the defence addition. The approach comes from enemy sectors on the map. Fortify's enemy-near check also reads real positions, but that is Warlords' own placement rule, not the commander's intel. |
| A sector with only a warning isn't hot (`frontHot`), not requested | Defenders should land in a sector nobody has reached yet. This branch only runs with the fast travel rule off: with it on, `frontHot` is real fighting only, which a warning never is. |
| Defence review: `alertCounterHitSeconds` 300, and the defence shuffle leaves screen and counterattack orders alone | The shuffle was overwriting them. A counterattack group keeps hunting for that long before ordinary defence orders apply. |
| Fortify: guns stay after the alert and gunners return to their groups | The user wants men back on their group's normal orders, and the guns serve the next alert. Risk: a sector that falls leaves its guns for the enemy. |
| `upkeep.sqf` exempts fort gunners and AT men | Upkeep would otherwise pull them away as stragglers or loose crew. Other paths can still move them. |
| Defence review: a gun needs a crew member within `fortifyCrewReach` 300 m of where it goes | Fortify was buying guns nobody could reach yet. An unmanned gun wastes CP and is a gift to the enemy. |
| Fortify refuses to buy with a hostile within 200 m of the gun point | Warlords refuses a player placing a defence in that case. `fortifyRespectEnemyNear` false turns it off. |
| One gun may cost 0.25 of free CP while attacking, 0.6 in hold or rebuild | The attack needs its CP. A side on the defensive has nothing better to spend it on. |
| The commitment timer is now a last resort: `commitSeconds` 3600 for an all-AI side (from 660), `commitSecondsHuman` 5400 for a side with humans | The user's call during the final soak: "the main thing should be the ability to manually cancel if you want to, the timer should be an ultra fallback". At 11 minutes it was calling off waves on their way in. An all-AI side has no cancel, so it gets the lower end of the range the user gave. Set after the final soak began, so no long round has run on these values. |
| "Cancel objective" on the Commander menu | The manual way off a target. It reuses the commitment timer's pull-out, sector ban (`abandonBanSeconds`) and new vote. Needs a second press within `menuCancelConfirmSeconds` (15 s), because the ban is costly and a number key is easy to hit. Per-side cooldown `menuCancelSideCooldown` (120 s). It took the "AI commanders panel" entry, to keep the menu to ten number keys; the panel is still on Insert. It needs the commitment rule, and refuses on the radio with the rules variant off. |
| The first push of a wave waits for most of its men at the rally: `goMassGate`, `goMassFraction` 0.6, `goMassMaxSeconds` 270 | The user asked for this before playing: "me and 3 other guys assaulting while 40 others hang back". In `soakfront` every first push had 1 to 3 of the wave's 2 to 7 groups, because two groups at the rally were enough. Share is by men, not groups, and scouts don't count. Applies to every go, including after a failed push. 270 s keeps a waiting group under the 5-minute activity limit and is the point at which it goes with whoever is there. Once a push is running, or a player is in the sector, arriving groups still go straight in, as the rolling muster note asked. |
| `shopGroupSize` raised: easy 6, normal 10, hard 10 (was 2, 3, 4) | The user pointed out that stock Warlords allows 9 others per warlord. In `soakfront` squads had a median of 3 men, with 13,000 to 35,000 CP unspent. Soak frame rate was flat from 40 to 104 men; `mass10` held 14.5 fps at 120. About 160 AI at full strength has not been tested. Full squads need 18-seat trucks at 650 CP, and on `mass10` WEST bought those before men. |
| `moveCalm`: a marching foot group with no known enemy within `moveCalmRange` 300 m goes back to its ordered behaviour | The engine puts a group in COMBAT when it knows of any enemy however far, and foot groups then crawl: 0.9 against 3.7 m/s in `fronta2`, 1.4 against 3.5 m/s in `soakfinal`. `setBehaviour` alone only lasted a moment (0.8 m/s still in `fronta3`), so the engine's AUTOCOMBAT is turned off for those men. It comes back on the group's next squad pass, at most about 20 s later, when an enemy is known within range, a shot is fired, the job changes, or a player borrows the group. Not under the rules variant. Added without being asked, for the sustained-combat aim. |
| Defence review: a holdout goal outside attack empties the reserve only while the wave to X can run | It was emptying the reserve with no wave to go to, leaving the side idle. |
| Defence review: pickets and raids can't take the counter group | It has to stay near its sector for the break-in. |
| Defence review: facing the approach leaves AT men on the road alone | It was turning them away from the road. |
| Defence review: resting groups can join the reserve once a side has left attack | Their rest from reserve duty kept them idle with no wave to join. |
| The user moved the run's deadline to 21:30-21:45 on 2026-11-09 | Their message at about 19:45. The extra time goes to testing. |
