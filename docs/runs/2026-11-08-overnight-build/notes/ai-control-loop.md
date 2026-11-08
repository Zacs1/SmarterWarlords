# Warlords AI control loop: how it works and how to take control

Read-only study of `reference/functions_f_warlords/Warlords/fn_WLAICore.fsm` and what it calls. No game was run. All Bohemia code is paraphrased.

**Marking.** A claim with a `file:line` reference was read in the code. **(inferred)** means I reasoned it out and did not read or test it. Engine behaviour is inferred unless stated, because the BI wiki and feedback tracker refused direct fetches (HTTP 403).

**File short names** (all under `reference/functions_f_warlords/Warlords/`, `fn_WL` prefix dropped):
AICore = `fn_WLAICore.fsm`; Purchases = `fn_WLAIPurchases.fsm`; Airdrop = `fn_WLAirdrop.sqf`; PathSeg = `fn_WLAIPathSegmentation.sqf`; Init = `fn_WLInit.sqf`; Vars = `fn_WLVarsInit.sqf`; SelServer = `fn_WLSectorSelectionHandleServer.fsm`; SelClient = `fn_WLSectorSelectionHandle.fsm`; SectorServer = `fn_WLSectorHandleServer.fsm`; Assets = `fn_WLParseAssetList.sqf`.

## The short version

- **The FSM is not a control loop.** It is an event-driven order issuer. It gives movement orders only on entering four states: `fight`, `fast_travel`, `defend` and `defend_1`. Nothing re-issues orders on a timer, which is why vanilla groups idle once their two SAD waypoints are used up or lost.
- **Recommendation: steer, do not fork, and do not rely on stopping it.** There is no per-group or per-unit off switch. Details in Q3.

## Q1. What runs the FSM, and where

- **One FSM per Warlord unit, on the server.** Init's `isServer` block (Init:113) loops over `BIS_WL_allWarlords` (Init:116-136) and starts AICore with the unit as `_this`, storing the handle in `BIS_WL_AIHandle` on the unit (Init:128, not broadcast). It also sets the unit's starting funds if it is not a player (Init:118-127), broadcasts an empty `BIS_WL_groupVehs` (Init:129) and sets `allowFleeing` to 0 (Init:131).
- **Who counts as a Warlord.** `playableUnits` plus `switchableUnits` on WEST or EAST (Vars:61), with playables re-added every 5 s (Vars:96). Adding a unit to that list does not start an FSM; only Init:128 and the Respawn handler do.
- **Per unit, orders per group.** `_this` is a unit, and orders go to `group _this`. On Tanoa the two are the same in practice: `MP_Warlords_03.Tanoa/mission.sqm` has 16 playable slots, 8 per side, each alone in its own group. A mission with several slots in one group would have several FSMs ordering one group **(inferred)**.
- **Respawn.** A `Respawn` event handler added per unit starts a new FSM and overwrites the handle (Init:130). Which machine it fires on after a player respawn is **(inferred)** engine behaviour and was not checked.
- **Each FSM also starts** a separate Purchases FSM, handle in `BIS_WL_AIPurchasesHandle` (AICore:251), and a detached stuck-unit script (AICore:270-288). Neither stops when AICore stops.
- **Players in a slot.** The `player_or_dead` link fires on `isPlayer` or dead (for example AICore:361). The FSM goes to `debug_info`, deletes the group's waypoints except index 0 (AICore:386-390), and returns to `status_` if an AI retakes the slot (AICore:412).
- **Player subordinates and player-bought AI get no FSM.** Bought men are created in the buyer's group (Airdrop:59) and are never Warlords. Nothing in AICore addresses them: while the Warlord is a player the FSM is parked. The commander's ownership filter still has to exclude them itself.
- **`disabledAI`.** Stock Altis descriptions set `disabledAI` to 1; `tests/README.md` records the test mission adds `disabledAI = 0`. An empty slot with AI disabled has no unit and so no FSM **(inferred)**. The playable scenario needs the same setting.

## Q2. States and transitions

Link priority is noted as P3/P2/P1/P0 where it matters; unmarked links are P0. **Shared conditions used throughout:**

- *base_vulnerable*: this unit's own base is the current target of either side (e.g. AICore:339).
- *selection*: this side has no current target and `_curSector` is owned by this side or null (e.g. AICore:350).
- *seized*: `_curSector` is owned and on this side's conquered list, or this side's `BIS_WL_sectorVotingReset_<side>` is true (e.g. AICore:629).
- *skirmish*: this side has a target and the unit is not airdropping (e.g. AICore:372).
- *cancelled*: global `BIS_WL_resetVoting` is true (e.g. AICore:477).
- *player_or_dead*: as above (e.g. AICore:361).

| State | Lines | What it does on entry | Leaves to |
| --- | --- | --- | --- |
| `INIT` | 241-317 | Builds the side variable names; clears airdropping; starts Purchases; sets `_base`, `_enemyBase` and `_curSector` (own base); **deletes all group waypoints except index 0** (266-268); starts the stuck-unit script | `status_` if AI (312), `debug_info` if player or dead (301) |
| `status_` | 320-377 | **Teleports the unit** next to the second living group member if the group has more than one alive and the base is not targeted (324-328) | P3 base_vulnerable → `defend_1` (339); P2 selection → `run_timer` (350); skirmish → `fight` (372); player_or_dead (361) |
| `debug_info` | 380-417 | Pause. Deletes waypoints if a player holds the slot (386-390) | Dead (P1) → `terminate` (401); AI → `status_` (412) |
| `run_timer` | 545-611 | Sets `_tVoting` to now + 0.2×timeout + random 0.5×timeout, and `BIS_WL_AIVotingReset` true (549-551) | Base → `defend` (562); timeout → `vote` (606); skirmish → `fight` (584); cancelled → itself, restarting the timer (595); player_or_dead (573) |
| `vote` | 420-493 | See Q6. No timeout | Base → `defend` (455); skirmish → `fight` (466); cancelled → `run_timer` (477); player_or_dead (488) |
| `fight` | 496-542 | `_curSector` = target; **PathSeg to target** (two SADs); `_tFight` = now+3 s (500-504) | P2 selection (515); player_or_dead (526); timeout → `FT_availability` (537). **No base or cancelled link** |
| `FT_availability` | 614-711 | Decision hub, no entry code | P3 seized → `reset_var__run_t` (629); P3 base → `defend` (640); P2 selection (651); P2 no-FT → `nothing` (662); P1 not airdropping → `next_check` (673); cancelled (695); airdropping → itself (706); player_or_dead (684) |
| `next_check` | 1242-1273 | None | Funds ≥ FT cost → `next_check_1` (1257); short → `FT_availability` (1268). A broke unit spins here until it has funds |
| `next_check_1` | 1276-1318 | None | P3 every 10 s → `refresh_target_q` (1291); not in combat near enemies → `next_check_2` (1302); else → `FT_availability` (1313) |
| `refresh_target_q` | 1436-1458 | `_enemiesNear` = any crewed enemy object within 200 m (1442) | Always back to `next_check_1` (1453) |
| `next_check_2` | 1321-1366 | Original distance tests are commented out; the links are hardcoded (1336-1337, 1348-1349, 1360-1361) | Always to `run_timer_1` |
| `run_timer_1` | 936-1056 | `_tFT` = now + 5 + random 10 s (940) | Timeout → `fast_travel` (995); base (951); seized (962); selection (973); cancelled (984); combat (1018) / low funds (1029) / airdropping (1040) back; player_or_dead (1051) |
| `fast_travel` | 714-865 | See Q4, ends with PathSeg (805) | Base (816); seized (827); selection (838); cancelled (849); player_or_dead (860). **Never fast travels twice in one pass** |
| `nothing` | 1163-1227 | None. Vehicle or no-FT path | Seized (1178); base (1189); FT possible again → `nothing_1` (1200); cancelled (1222); player_or_dead (1211). **No selection link** |
| `nothing_1` | 1369-1433 | 10 s timer (1373) | Seized (1384); base (1395); cancelled (1417); timeout → `FT_availability` (1428); player_or_dead (1406) |
| `reset_var__run_t` | 880-933 | `_tDebrief` = now+20 s (884) | Any side vote exists → `run_timer` (895); cancelled → `run_timer` (906); 20 s passed **and no living group member over 400 m away** → `continue` (928); player_or_dead (917) |
| `continue` | 1059-1123 | None | Base (1074); selection (1085); cancelled (1107); skirmish (1118); player_or_dead (1096) |
| `defend` | 1126-1160 | If `BIS_WL_FTEnabled` is 1, 3 or 4, **free teleport** of on-foot group members within 500 m to near the base (1130-1142); PathSeg to base (1144) | **Only player_or_dead (1155).** Permanent until death |
| `defend_1` | 1230-1239 | PathSeg to base (1234) | None. Final state, the FSM ends |
| `terminate` | 868-877 | None | Final |

**Orders and how they are given.**
- *PathSeg* appends two SAD waypoints at random points within 0.75 × half of `Size` around the target, without deleting anything (PathSeg:14-18), stores the first in `BIS_WL_curWP` on the leader (23), and jumps to it with `setCurrentWaypoint` unless the current waypoint is GETIN (25-27).
- *`doMove`* appears once, in the post-fast-travel regroup (AICore:800).
- *Garrisoning*: none in this FSM. Garrison and response groups are separate (`fn_WLSendResponseTeam.sqf`, `fn_WLGarrisonRetreat.fsm`, not studied).
- *Vehicles*: see Q5.

**What causes a re-issue.** Only these:
1. A new target after a seize (`nothing`/`fast_travel` → `reset_var__run_t` → `continue` → `run_timer` → `vote` → `fight`).
2. A voting reset, pulling any state with a cancelled link to `run_timer` and so back to `fight`. That adds two more SADs, forces `setCurrentWaypoint` and can fast travel again.
3. A new FSM after respawn (which also wipes the group's waypoints in `INIT`).
4. A player handing the slot back to AI.
5. The base becoming targeted (`defend` or `defend_1`).
6. A delayed entry to `fight`: skirmish requires "not airdropping" (AICore:372), so a unit that is mid-purchase when the target is set enters `fight` later, at an arbitrary moment during the target's life.

After the SADs complete, or the group loses them in contact, nothing restores them. This is the mechanism behind vanilla idling **(inferred from the absence of any such code)**.

## Q3. Can it be switched off? What to do instead

**No switch exists.** AICore has no enable variable. Its only gates are `isPlayer` and `alive`, there is no `isServer`/`isDedicated` test, and nothing in the Warlords code calls `setFSMVariable` or `getFSMVariable`. `isPlayer` cannot be faked.

**Possible stop, untested.** Setting `_this` to `objNull` through the stored handle (`BIS_WL_AIHandle setFSMVariable`) would make `!alive _this` true and walk `debug_info` → `terminate`. The wiki's `execFSM` and `setFSMVariable` pages say FSM variables can be modified from outside by handle, and do not cover `_this` or private variables, so whether it works is **(inferred, must be tested)**. I found no documented command for terminating an FSM. Problems even if it works:
- Links with higher priority can fire first, and `group objNull` behaviour during that window is unknown.
- It must be re-applied after every respawn.
- It does not stop Purchases or the stuck-unit script, which are separate.
- It removes the FSM's vote and its `BIS_WL_AIVotingReset` signal. SelServer waits on that signal when any AI is alive (SelServer:302-303), so the commander would have to set it, or voting resets could hang **(inferred)**.

**Parking** by rewriting `_currentSectorVarID` to an empty variable would hold a unit in `vote`, but keeps `run_timer` behaviour and is fragile. Not worth it.

**Replacing or forking** AICore means shipping changed Bohemia functions, which conflicts with the overlay goal and with the rule against committing Bohemia code. It is not justified, because the steering surface is small.

### Recommendation: steer

1. **Disable FSM fast travel by parameter.** Use `BIS_WLFTEnabled` = 4 (Q4). Every FSM then ends up in `nothing` after `fight`, issuing no further orders. The commander's own fast travel is its own script and is unaffected.
2. **Own the waypoints.** On each commander tick, reassert the owned group's waypoints if the FSM has added any: detect by comparing the waypoint count and types against what the commander last issued, delete strays, and re-issue. Expect FSM SADs at any time during a target's life (trigger 6 above) and within about a frame of a target being set.
3. **Reissue after these events:** the warlord's respawn (`INIT` wipes the group's waypoints, AICore:266-268); `BIS_WL_resetVoting` cycles; a player handing back the slot.
4. **Keep leaders moving.** The stuck-unit script checks a non-player on-foot Warlord every 90 s. Under 1 m of movement earns a 2 m nudge (AICore:275-279), and the sixth consecutive failure kills the unit (AICore:281-282), about 9 minutes stationary. The nudge does not count as movement, because the position is re-sampled afterwards. Applies to Warlord units only. Holding or defending leaders must move at least 1 m per 90 s, or sit in a vehicle.
5. **Handle `defend`.** When the enemy targets this side's base, every FSM on the side that has a base link goes to `defend` for good. With FT mode 4 the free teleport at AICore:1130-1142 is still on, so it **will move owned groups' on-foot units within 500 m of their Warlord to the base**. The commander must expect the jump and re-issue afterwards. In `fight` and `reset_var__run_t` there is no base link, so those units are spared until they leave. This is the one case where mode 4 still lets the FSM move groups.
6. **Filter ownership.** Never touch a group with a player in it or led by one. Player-bought AI is in the buyer's group (Airdrop:59), so "group contains a player" covers it.

**What keeps working when steering:** respawn (Init:130 untouched), purchases (Purchases FSM untouched), voting (FSM still votes unless the commander pre-empts it). All three would need work if the FSM were stopped or replaced.

## Q4. AI fast travel

**All conditions must hold**, in order:
- Side has a target; unit reaches `FT_availability` via `fight`.
- No `BIS_WL_groupVehs` vehicle within 500 m (AICore:662).
- `BIS_WL_FTEnabled` is 1 or 3 (AICore:662).
- Target's `FastTravelEnabled` is not false (AICore:662).
- Not airdropping (AICore:673).
- Funds at least `BIS_WL_FTCost` (AICore:1257). Default 50 (Vars:52), overridable through `CfgWLAssetCostOverride`.
- Not (crewed enemy within 200 m and leader behaviour COMBAT) (AICore:1302).
- A 5 to 15 s delay passes (AICore:940, 995).

**`BIS_WLFTEnabled` values.** Lobby values are 1, 0, 2, 3, 4, default 1 (`missions_f_warlords/cfgMissionParams_subclasses.inc:22-28`). Label strings are not in `reference/`, so these meanings come from the code:

| Value | AI conflict FT (AICore:662) | AI defend teleport (AICore:1130) | Player FT to owned (Assets:150) | Player FT to conflict (Assets:151) |
| --- | --- | --- | --- | --- |
| 1 | Yes | Yes | Yes | Yes |
| 0 | No | No | No | No (0 is in none of the tested lists; that this is the "off" label is **inferred**) |
| 2 | No | No | Yes | Yes |
| 3 | Yes | Yes | No | No |
| 4 | No | Yes | Yes | No |

**Value 4 answers the prompt's question:** players can fast travel only to owned sectors, and the FSM's conflict fast travel is off. The commander's fast travel is separate script, so it still works.

**Cost.** Deducted per unit on entering `fast_travel`, unconditionally, before any position test (AICore:718). A unit that ends up not moving still pays.

**Landing position** (AICore:731-765):
- Target is the enemy base: the owned sector linked to the enemy base that is nearest it, or the unit stays put if none (731-740).
- Target is in `_available`: a point `200 + Size/2` m from the sector centre, on the bearing towards the unit, rotating in 5° steps while the point is water (742-753). `Size` is the diameter (`tests/README.md`), so this is 200 m outside the sector's edge on whichever side the unit came from.
- Otherwise: the nearest sector linked to the target that is in the side's connected network, or stays put (755-763).

**Move.** Only when over 300 m away (767). On-foot units only (771). **Non-leaders that are not `unitReady` are deleted** (772-774). Each unit's landing point seeds the next (782), so the group strings out; each is set 50 m up with ±10 m scatter, then placed on the ground (786-788). A spawned script pulls anyone over 100 m away to the leader, 5 s per unit, and gives each a `doMove` to the leader's position (792-802). Then PathSeg (805).

**Why groups land short.** That is the design: 200 m beyond the edge, on the near side, with only two SADs to continue. There is no fast travel into a contested sector. The `_nearest != _curSector` guard at 770 is effectively always true **(inferred; baseline rounds do fast travel)**.

**Hazard.** If this path ever fires for an owned group, subordinates under commander `doMove` orders are not `unitReady`, so they would be deleted **(inferred from `unitReady` semantics)**. Mode 4 prevents it.

## Q5. Vehicles

**Purchasing** (Purchases, an independent FSM):
- Candidates are car or tank simulation with `Turrets` and a threat value over 0.5 (Purchases:534): **armed only, no transports**. The `WLAIRequisitonBlacklist` applies to infantry only (516).
- Drop cost is `dropCost × 40` unless within 200 m of an own sector, then plain `dropCost` (143-156). `dropCost` defaults to 25 (Vars:51).
- A vehicle needs the group to have no vehicle and funds of at least its price plus 40 × the local drop cost (189). The local drop cost is already multiplied when away from an own sector, so the margin is 1000 CP near an owned sector and 40000 CP away from one, which in practice means AI buys vehicles only near its own sectors **(inferred from the arithmetic)**. Infantry need the cheapest infantry price plus the local drop cost, and spare slots (178).
- The infantry purchase budgets from funds minus the drop cost and `FTCost` (215) and adds both back when it writes the final funds (233), so they act as a spending margin. Whether `_costFinal` itself includes a drop charge was not checked.
- After a 5 to 15 s wait, airdropping is set true (308-310). This blocks skirmish and fast travel for that unit.

**After purchase** (Purchases:384-412): the vehicle is appended to `BIS_WL_groupVehs` and broadcast (386). A spawn waits 30 s and for the landing, stores the current waypoint, adds a GETIN waypoint on the vehicle whose statement restores the stored waypoint (402-407), and **deletes group members over the vehicle's capacity** (408-411).

**Airdrop watchdogs for AI-ordered assets:**
- Men over 400 m from the leader on two checks 180 s apart are killed (Airdrop:79-95); not boarded after 120 s, unassigned (96-110).
- Vehicle `setUnloadInCombat` false (218). After 180 s, if it cannot move or the leader is not aboard, it is removed from `groupVehs` and left (219-233). A crewed vehicle moving under 0.5 m per 180 s is abandoned (239-247). A commander buying through this path with the ordered-by-AI flag would see parked crewed transports abandoned **(inferred)**.
- Empty vehicles are deleted after `BIS_WL_vehicleSpan` (`fn_WLVehicleHandle.sqf:33, 60-65`).

**How the loop treats crews.** The vehicle affects the loop in one place: a `groupVehs` entry within 500 m skips fast travel and sends the unit to `nothing` (AICore:662), and losing it re-enables fast travel via `nothing_1` (AICore:1200). Fast travel and `defend` move only on-foot men (771, 1133). There is no dismount, parking or road logic; the vehicle gets the same SADs.

## Q6. Voting

**How AI votes.** In `vote` entry (AICore:424-444): the AI votes if `BIS_WL_AICanVote` is 1 or its side has no player Warlord. If its `BIS_WL_selectedSector` is null, it picks the enemy base when available, otherwise a random available sector, and broadcasts the choice (425-435). A spawned script clears the vote once a target exists (439-443). The vote runs once per state entry. Lobby default for AI voting is off (`cfgMissionParams_subclasses.inc:50-56`).

**Server tally.** Per side, on the server (Init:138). The first vote starts the `BIS_WL_selectionTimeout` countdown (SelServer:114-117, 129-134), then `fn_WLMostVotedSector.sqf:16-31` counts `BIS_WL_selectedSector` across the side's Warlords and takes the highest, with disconnected votes kept (Init:81-88).

**The commander can vote itself. Yes:**
- Write `BIS_WL_selectedSector` (broadcast) on the side's AI Warlords. The tally checks only the value and side, so a commander's vote counts even where `BIS_WL_AICanVote` is 0 **(inferred from most-voted not testing it)**.
- Write before the FSM's own vote at 0.2 to 0.7 × timeout. The FSM skips voting if the variable is set (425).
- Voting early also shortens the wait, since the timer starts on the first vote.
- Clear the votes once a target is set. An FSM not in `vote` will not clear them, and a stale vote would restart the countdown straight after the next seize (SelServer:261-277) **(inferred)**.
- On the human side, 6 AI votes outweigh 2 humans, so whether to cast them there is a design decision. I would have the commander vote only for all-AI sides by default.
- **Forced re-target:** `BIS_WL_sectorVotingReset_<side>` (`fn_WLRequestVotingReset.sqf:11`) sends the server to `reset_1`, nulling the target (SelServer:204-210, 413-422). It also sends the FSMs through the seized link (AICore:629). That is a usable abort lever.

## Q7. Dedicated versus client host, and T156979

**AICore has no dedicated-specific branch.** The differences are elsewhere:
- A non-dedicated machine waits for `player` before Vars init (Init:105-107).
- `BIS_WL_sectorsArray*` are set by client init on a host and directly once on dedicated (Init:436-447). SectorServer recomputes them on every ownership change (261-262), after the side has changed (180, 305), so they are not stale. I checked this and ruled it out as a stall cause.
- Client sector bits run only when not dedicated (SelServer:181-186, 361-366).
- **`BIS_WL_resetVoting` is cleared differently.** On dedicated the server clears it, locally, once the AI signal arrives (SelServer:307-310). On a host only the local client FSM clears it, on reaching `initialize_sector` (SelClient:142). So on dedicated the flag can be very short-lived: `BIS_WL_AIVotingReset` is set by any FSM in `run_timer` and stays true until a reset consumes it, so the spawned wait can pass at once **(inferred)**. An FSM that misses the flag in `vote` then has its vote cleared and does not vote again, since vote is entry-only. If all the side's AI miss it, the server waits forever at `at_least_one_vot` (SelServer:315-331) **(inferred, a real stall candidate)**.
- `BIS_WL_resetVoting` is not per-side: one side's reset pulls both sides' FSMs to `run_timer`, and a state with a cancelled link can re-issue SADs on the other side (AICore:477 etc.; SelServer:286-287).

**T156979.** I could not open the ticket (403). A search summary of it says: with fast travel disabled for all including AI on a dedicated server, AI appears to stop after seizing the first sector; the same game hosted locally works; enabling fast travel restores it. Status unknown. Taken as a claim to check:

- **Not confirmed by the code.** The FT-off path reads as continuing: `fight` → `FT_availability` → `nothing` → seized → `reset_var__run_t` → `continue` → `run_timer` → `vote` → `fight`, with new SADs. There is no FT-off-specific dedicated branch.
- **The reset race does not explain "the first sector".** A first seize of a neutral sector does not pass through `reset`: `update_vars` re-reads the count after `UpdateAO` (SelServer:242-244), so `sector_compromis` does not fire. It would only fire on a capture that changes a side's count during voting.
- **Plausible contributors, all (inferred):**
  1. The straggler gate at AICore:928. Without fast travel's regrouping, a member over 400 m away holds that unit out of the next vote until another side vote exists. Airdrop's kill timer clears AI-ordered stragglers within minutes.
  2. Long walks with no restored waypoints, made worse by water on maps such as Tanoa: on foot, the second target can be unreachable or take a very long time, and looks like a stall.
  3. `nothing` has no selection link, so with FT off an FSM there depends on the seized or cancelled links only. If the target is nulled by a reset and the flag is missed, it stays there.
  4. A side with a player and AI voting off waits for a human vote.

**Our baseline ran with FT=1, so this is untested here. Mode 4 sends every FSM down this same path.** The phase 0 gate round should run at FT 4 and watch `TARGET` lines past the first capture. Commander-cast votes make the voting candidates moot.

## Surprises worth carrying into the design

- Fast travel **deletes** busy subordinates (AICore:772-774).
- A stationary on-foot AI Warlord is **killed after about 9 minutes** (AICore:275-282).
- `defend` is a permanent sink until death, and mode 4 still teleports (AICore:1130, 1155).
- `BIS_WL_resetVoting` is global across sides (SelServer:286-287).
- FT cost is charged even when no move follows (AICore:718).
- AI buys only armed vehicles and trims the group to the crew (Purchases:534, 408-411).
- `INIT` wipes the group's waypoints on every respawn (AICore:266-268).
- Vars:65 uses an undefined `_x` in the EntityRespawned handler, so a new unit is probably not added there **(inferred)**.
