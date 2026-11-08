# Warlords internals: sectors, capture, voting, server flow

Read-only study for the phase 0 adapter. Everything is paraphrased from Bohemia's code.

**Reference paths.** Unless a path is given, files are in `reference/functions_f_warlords/Warlords/` and are written without the `fn_WL` prefix, so `SectorsSetup.sqf:57` means `fn_WLSectorsSetup.sqf` line 57. `MPS` means `reference/missions_f_warlords/`.

**Evidence labels.** Claims come from code I read unless marked **(inferred)**. Baseline figures come from `tests/server/runs/2026-11-08_19-26-56_baseline/arma3server_x64_2026-11-08_19-26-57.rpt`. That round was still running when I read it, at t=2376.

## 1. Current target and sector ownership (design open question 1)

| Variable | Lives on | Public | Meaning and when it changes |
| --- | --- | --- | --- |
| `BIS_WL_currentSector_WEST` / `_EAST` | missionNamespace | Yes | The side's target. Starts objNull (`VarsInit.sqf:299-300`). Set when the vote timer ends (`SectorSelectionHandleServer.fsm:168-171`). Reset to objNull when that side captures it (`:239-240`) or on a voting reset (`:419-420`). **Not cleared if the enemy captures it.** |
| `BIS_WL_sectorSide` | each sector logic | Yes | The current owner, and the one to trust. Set at init (`SectorsSetup.sqf:56-58,251,274`). In play, only the seize trigger on-activation changes it (`SectorHandleServer.fsm:135,141`). The GUER trigger has no on-activation (`:126-131`), so a sector never reverts to RESISTANCE. |
| `BIS_WL_conqueredSectors_WEST` / `_EAST` | missionNamespace | Yes | Starts at `VarsInit.sqf:301-302`, filled at `SectorsSetup.sqf:57-58,66,70,253,276`, published at `:284-285`, appended at `SectorSelectionHandleServer.fsm:233-237`. Includes bases. I only found additions, so it means "ever conquered or allowed", not "owned now" **(inferred)**. Don't use it for ownership. |
| `BIS_WL_sectors` | missionNamespace | Yes | Every sector and base (`Init.sqf:114-115`). |
| `BIS_WL_base_WEST` / `_EAST` | missionNamespace | Yes | The base logics (`SectorsSetup.sqf:64,68`). |
| `BIS_WL_sectorsArrayWEST` / `EAST` | missionNamespace | No | `[owned, available, linked]`, from `SectorListing.sqf:37`. Dedicated: set once at `Init.sqf:444-445`, then at each owner change (`SectorHandleServer.fsm:261-262`). Non-dedicated: set by `RecalculateServices.sqf:11-12`, called from client-side code (`SectorsCommonInit.sqf:169`, `SectorUpdate.sqf:25`). |

Supporting variables:
- `BIS_WL_leadingSector_*` and `BIS_WL_selectionTime_*` (`VarsInit.sqf:303-306`, published at `SectorSelectionHandleServer.fsm:131-132`).
- `BIS_WL_lastSectorCnt_*` (`UpdateAO.sqf:10`).
- `BIS_WL_sectorSelectedTimestamp_*` (`SectorSelectionHandleServer.fsm:179`).
- `BIS_WL_newlySelectedSector` (`:177-178`).
- `BIS_WL_sectorActivated` (`:176`, `SectorsSetup.sqf:62,252,275`).

**For the adapter:** read the target from `BIS_WL_currentSector_<side>`, and ownership from `BIS_WL_sectorSide`. A stale target is possible, so treat a target the enemy now owns as still valid but changed in nature. The target is also objNull between votes, for at least 19 s after each capture in the baseline (190 to 209, 278 to 295, 510 to 529).

## 2. Sector graph and properties

**Links.** `BIS_WL_connectedSectors` on each sector, public, built from `synchronizedObjects` filtered to sector and base modules (`SectorsSetup.sqf:157-163`). It is static and symmetric, because editor sync is symmetric **(inferred)**. `BIS_WL_linkedWith` is only for drawing map lines (`CalculateSectorConnections.sqf:17-32`).

**What a side can target next.** `[side] call BIS_fnc_WLSectorListing` (`SectorListing.sqf:11-12`) returns three lists (`:14-35`):
- Owned: every sector whose `BIS_WL_sectorSide` matches the side.
- Linked: a breadth-first walk from the side's own base, passing only through owned sectors.
- Available: non-owned sectors adjacent to a linked sector. This includes enemy-owned sectors and the current target.

An owned sector cut off from the base unlocks nothing. Walk `BIS_WL_connectedSectors` directly, or just call the function, which is cheap and works on the server at any time after `BIS_WL_sectors` exists.

**Properties on the sector logic:**

| Property | Source |
| --- | --- |
| Size (diameter) `Size` | module; half is used for the area |
| Value / income `Funds`, published as `BIS_WL_value` | `SectorsSetup.sqf:54,127` |
| Income per payout | value times `BIS_WL_CPIncomeMult` (`CalculateIncome.sqf:14`), paid to each warlord every 60 s (`SectorFundsPayoff.fsm:46-54`, `VarsInit.sqf:27`) |
| Capture bonus | the **losing** side's warlords get 10 x value x multiplier (`SectorHandleServer.fsm:264-271`) |
| Starting side `Side` | 0 GUER, 1 EAST, 2 WEST (`SectorsSetup.sqf:55-59`) |
| Services `Service_Runway`, `_Helipad`, `_Harbour` | become `BIS_WL_sectorSpecial` A, H, W (`SectorsSetup.sqf:54,77-81`) |
| Seizing time `SeizingTime` (optional) | `SectorsSetup.sqf:114`; see section 3 |
| Restricted-zone border `Border` | default 200 (`InSectorArea.sqf:25`) |
| Base flag | `typeOf` is `ModuleWLBase_F` |
| Other | `BIS_WL_timeoutBase`, `BIS_WL_timeoutCur_WEST/EAST/GUER` (public, `SectorsSetup.sqf:116-126`), `BIS_WL_spawnPosArr`, `BIS_WL_vehicles`, `BIS_WL_responseArr`, `BIS_WL_pointer`, `LocationName`, `FastTravelEnabled` (`RequestFastTravel.sqf:60`) |

**Quirks.**
- *Name.* If the module name is empty and the sector allows a location name (default yes for sectors, no for bases, `SectorsSetup.sqf:28`), it takes the nearest config location within 1000 m (`:29-49`). The result is stored **non-public** (`:53`). With no such location it falls back to a localised default (`:73,75`), which is empty on a dedicated server (`tests/README.md:71`). `SectorsCommonInit.sqf:46,57` repeats this on each client, locally.
- *Mid-round name gain: cause not found.* No server-side code I read renames a sector after setup, and this baseline shows no name change through t=2376 (`Sector_1715_6128` stays unnamed for the whole round). `RequestFastTravel.sqf:56` writes `Name` onto the pointer object, not the sector. Key sectors by object or cached position and never by `Name`.
- *Position.* At capture the logic is moved to `[100,100]` and put back about 0.1 s later (`SectorHandleServer.fsm:254-259`, restored from the position saved at `:169/:398`). The triggers are separate objects and do not move (`:76-79`). Cache positions at init.

## 3. How a sector is captured, and the Balavu deadlock

**The triggers.** Each sector's server FSM creates one seize trigger per side (`SectorHandleServer.fsm:76-79`). The area is a **square** with half-side `Size/2` (`:90`), not a circle. The FSM runs only once a sector has first been selected (`SectorSelectionHandleServer.fsm:175,356`), or for bases from the start (`Init.sqf:137`).

**Condition.** The variable names are confusing: `_sectorServerW` uses EAST SEIZED (`:132`) and `_sectorServerE` uses WEST SEIZED (`:138`). For a side X the trigger condition (`:134,140`) is: (the engine reports X has seized the area, AND the sector is either in X's conquered list or is X's current target), OR X already owns it. On activation it publishes X as owner (`:135,141`).

**The timeout.** `setTriggerTimeout` is `[T/3, T/1.5, T, TRUE]` (`:91-92`). The engine picks a countdown in that range. `TRUE` makes it interruptible, so losing the condition resets the countdown.

T is `BIS_WL_timeoutBase` (`SectorsSetup.sqf:83,114-123`):
- `idx = (Size/2)^2 / 25000`.
- With a custom `SeizingTime`: that value times 1.5.
- Bases: `60*idx*3`, capped at 300.
- Sectors: `60*idx*1.5`, capped at 200.

| Size | T | Countdown range |
| --- | --- | --- |
| 300 (Balavu) | 81 s | 27 to 81 s |
| 200 | 36 s | 12 to 36 s |

A 3 s loop mirrors `triggerTimeoutCurrent` into `BIS_WL_timeoutCur_<side>`, on the first count overwrites `BIS_WL_timeoutBase` with the rolled value, and writes -1 on reset (`SectorHandleServer.fsm:94-122`). These variables are the way to watch a capture in progress.

**What SEIZED means.** It is an engine rule, not script. Public documentation only says the side is deemed to be in control. The ratio, unit weighting and vehicle counting are not documented, and the code gives no threshold.

**Balavu evidence** (square half-side 150 around 2665,7345; 30 s samples; **group leader positions only**, with each group's size counted at its leader). EAST targeted it at t=209, WEST at t=529. By t=2376 there were still no captures after Rautake at t=510, and neither target had changed.

| t | WEST grp/men inside | EAST grp/men inside | GUER map-wide |
| --- | --- | --- | --- |
| 723 | 4/13 | 8/20 | 2 |
| 1144 | 5/9 | 3/5 | 2 |
| 1324 | 8/23 | **0/0** | 2 |
| 1445 | 8/21 | 2/4 | 2 |
| 1565 | 8/19 | 6/11 | 2 |
| 1835 | 7/17 | 3/7 | **0** |
| 2016 | 7/23 | 1/1 | 0 |
| 2196 | 5/17 | 3/8 | 0 |
| 2376 | 6/23 | 5/13 | 0 |

- **Garrison survivors are not the block.** GUER is zero map-wide from t=1835 and there is still no capture 540 s later. Conversely, Leqa (size 200) fell at t=190 with 9 GUER alive map-wide and EAST 8 groups/26 men inside, and Rautake (size 200) fell at t=510 as GUER dropped from 26 to 18, with no EAST inside. Remaining garrison evidently does not need to be cleared to the last man **(inferred)**.
- **The other warlord side is the block (inferred, likely but unproven).** Of about 62 samples since t=529, only t=1324 had no EAST leader inside, and an EAST leader stood 154 m away on the square metric with followers' positions unknown. EAST men respawn or are bought and return (totals swing 13 to 28), and WEST never holds the area alone for the 27 to 81 s it needs. Either the engine's control test fails while any meaningful enemy is present, or control flips and the interruptible countdown restarts. The t=2016 sample (23 men against 1) is the strongest hint that even tiny enemy presence is enough, but 30 s sampling and leader-only positions can't prove it.
- **Nothing breaks the stalemate.** `evaluate_sector` exits only on own seizure or a voting reset (`SectorSelectionHandleServer.fsm:192-224`). There is no target timeout.

**How a commander should win:**
1. Stand inside the square (`|dx|` and `|dy|` both at most `Size/2`), not at the edge or at holding points. Corners count.
2. Search-and-destroy every enemy inside, stragglers included, and especially warlord-side men. A wave that "arrives" and then stands still has not captured anything.
3. Hold continuously for up to T (at most 200 s for a sector and 300 s for a base). Don't launch elsewhere until `BIS_WL_sectorSide` flips.
4. Block the routes enemy reinforcements use to re-enter, since a single returner may reset the clock **(inferred)**.
5. After N minutes of deadlock, reset the vote and retarget (section 4).
6. Log `BIS_WL_timeoutCur_*` and per-side counts inside the square every tick in phase 0. **That will show the real threshold**, which nothing else here can. Only the GUER seize trigger is stored (`BIS_WL_sectorSeizeTrgGuer`, `:83`), so the two warlord triggers can't be queried directly.

**Hazard: restricted zones.** `SectorsSetup.sqf:89-113` kills AI, every 20 s, that are inside a sector not in their side's conquered list and not their current target (no border applied; `InSectorArea.sqf:24-25`). A bug overwrites `_toCheck` each iteration (`:96-98`), so each pass checks only the last non-player warlord's group. The client equivalent gives the player's group 20 s, using Size/2 + Border (`SectorsCommonInit.sqf:64-72,122-151`). Routes must avoid sectors not yet allowed, and between votes the target is null, so any group standing inside a not-yet-conquered sector during that gap is at risk.

## 4. Target selection and voting

**Server flow** (one FSM per side, started at `Init.sqf:138`, in `SectorSelectionHandleServer.fsm`):
1. `INIT` (`:83-89`), then wait for the first vote (`:111-117`). **The timer starts at the first vote. With no votes it waits forever, and there is no default target.** A saved-progress path is at `:100,351-352`.
2. `run_timer` (`:129-134`) sets the deadline to now + `BIS_WL_selectionTimeout` (module `VotingTimeout`, default 15 s, `Init.sqf:35`, `VarsInit.sqf:26`, lobby param `BIS_WLVotingTimeout` values 5 to 30 at `MPS/cfgMissionParams_subclasses.inc:127-132`).
3. If `BIS_WL_lastSectorCnt_` changes during the timer, the vote is compromised and resets (`:145`).
4. On timeout, `evaluate_sector` (`:168-188`) takes the result, publishes the target and starts the sector's server FSM if needed.
5. It stays there until `sector_null` (`:199`), `voting_reset` (`:210`) or `sector_seized` (`:221`), then `update_vars` (`:233-246`).

**Counting.** `MostVotedSector.sqf` counts `BIS_WL_selectedSector` on warlords by `side group` (`:16-22`), adds `BIS_WL_disconnectedVotes_<side>` (`:24-29`), and returns the first highest, with ties going to the lowest index in `BIS_WL_sectors` (`:31`). It doesn't validate the choice against the available list **(inferred)**.

**AI votes** (`AICore.fsm:424-444`). An AI votes only if `BIS_WL_AICanVote == 1` or the side has no players, and only if its own selection is null. It picks the enemy base if available, otherwise a random available sector. It delays by T x 0.2 plus random T x 0.5 (3 to 10.5 s at default, `:549`), and clears its selection once a target appears. `BIS_WL_AICanVote` is the module's `AIVoting` (`VarsInit.sqf:33`), lobby param `BIS_WLAIVoting`, **default 0** (`MPS/cfgMissionParams_subclasses.inc:50-55`). AI votes read `BIS_WL_sectorsArray<side>`, which can be nil on a host early on (section 5).

**When a new target can be chosen:** after own capture or a voting reset. **An enemy capturing your target does not by itself free you to pick another.**

**Voting reset.**
- `BIS_WL_sectorVotingReset_<side>`, set by players via `RequestVotingReset.sqf:9-12`, costing 2000 CP (`VarsInit.sqf:56`) with a 300 s cooldown (`:57`), and enabled by `VotingResetEnabled` (`Init.sqf:25`, `VarsInit.sqf:38`; lobby default 0, `MPS/cfgMissionParams_subclasses.inc:36-41`).
- The FSM link is `:210` and `:401`, and it auto-clears about 1 s later (`:413-416`).
- The reset state (`:286-311`) sets `BIS_WL_resetVoting`, clears votes for the side, waits for `BIS_WL_AIVotingReset` if there's live AI, and clears the flag only if dedicated (`:308-310`); on a host the client FSM clears it (`SectorSelectionHandle.fsm:142`).
- AI notices via `AICore.fsm:629`. The 1 s window could be missed **(inferred, a race; check against the AI-loop notes)**.

**Can a server script choose the target? Yes, through the votes.**
- *Choose.* In the window before evaluation (or before the first vote), set `BIS_WL_selectedSector` on the side's live AI warlords to the desired sector from the available list. AI that already have a selection won't vote over it. Never overwrite a player unit's vote. Human votes count equally, so a host's side may legitimately overrule it.
- *Force a re-vote.* Set `BIS_WL_sectorVotingReset_<side>` to TRUE on the server. This does not charge CP (the charge is in the request function), and it works even when the lobby option is off, since the FSM link doesn't check it **(inferred)**.
- *Directly writing `BIS_WL_currentSector_*`* is **not safe** in normal flow: it skips the FSM's handle start and `BIS_WL_sectorActivated` work, and the FSM would overwrite it **(inferred)**.

## 5. Dedicated, client-hosted, client (design open question 4)

A grep of the whole Warlords folder finds **zero** uses of `hasInterface` and `didJIP`. Locality is decided by `isDedicated`, `isServer` and `player`.

| Location | What it does | Consequence |
| --- | --- | --- |
| `Init.sqf:52,68,105-107` | Non-dedicated machines block until `player` exists, is a real player and is on WEST or EAST | **On a client host the server-side setup waits for the host's slot. If the host slots on another side or sits unassigned, it hangs.** |
| `Init.sqf:113,297,436-447` | Dedicated takes the else-branch and sets the arrays; non-dedicated spawns client init | Different paths to `BIS_WL_sectorsArray*` |
| `Init.sqf:451,475-514` | Round end; dedicated `endMission` at `:480`, otherwise by `side group player` at `:490,502` | Host ends via the client path |
| `VarsInit.sqf:68,97,178-296` | Includes `player` at `:227,284` | Client setup, harmless |
| `SectorsSetup.sqf:184,195` | Scan trigger reconfigured by the server **only on dedicated** | On a host it relies on the host's client scan FSM (`SectorScanHandle.fsm:110-112,322-324`), which runs for that client's own side. A scan by the other side may reveal nothing on a host **(inferred; test it)** |
| `SectorSelectionHandleServer.fsm:181-186,308-310,361-366` | Uses `side group player` at `:184,364`, and clears a flag only on dedicated | Handled by the client FSM on a host |
| `SectorPopulate.sqf:117` | Passes `player` | objNull is harmless **(inferred)** |
| `ClientInit.sqf:338,453`; `SyncTime.sqf:10`; `SyncedTime.sqf:9` | `isServer` guards and server time | No issue |
| `MPS/commonInitScript.sqf:14-18,29` | Param lookup by config position; a spawned loop waits on `player getVariable` | Never completes on dedicated when the jets filter is off, harmless **(inferred)**. Adding params is safe because it looks them up by name |

**Risks for the commander:**
1. Run wherever `isServer` is true and never touch `player`. No-player dedicated is proven by the baseline.
2. On a host, `BIS_WL_sectorsArray<side>` comes from the spawned client init (`ClientInit.sqf:9` to `SectorsCommonInit.sqf:169`), so it can be nil early, and AI voting reads it (`AICore.fsm:426`) **(inferred)**. The commander should call `BIS_fnc_WLSectorListing` itself.
3. On a host with two humans and AI voting at the default 0, the AI on the human side won't vote (`AICore.fsm:424`), so **that side's target stays null until a human votes**. The commander needs a sensible null-target state, or the playable scenario should default `BIS_WLAIVoting` to 1.
4. `VarsInit.sqf:63-71` has an EntityRespawned handler using an undefined `_x` at `:65` (a bug). The RPT has no script errors from it, and the 5 s loop at `:96` re-adds warlords anyway.

Not testable here: everything host-specific above needs real players.

## 6. Who is a warlord; respawn and group size

**Membership.** `BIS_WL_allWarlords` is playable plus switchable units whose `side group` is WEST or EAST (`VarsInit.sqf:61`). A 5 s loop adds with pushBackUnique (`:96`) and the handler at `:63-71` removes corpses. Server setup for each is at `Init.sqf:116-136`: vote null, CP for AI, a HandleRating handler, the AI core FSM (`:128`), `BIS_WL_groupVehs` (`:129`), a Respawn handler that restarts the AI core (`:130`), allowFleeing 0, and spawn protection (`:135`).

AI only fill those slots with `disabledAI = 0`, which is **not** in `MPS/defaultDescription.inc`. `tests/README.md:24` confirms the test mission adds it. The playable scenario needs it too.

**Respawn.** Mission `respawn = "BASE"` with `respawnDelay = 20` (`MPS/defaultDescription.inc:8-9`). The `respawn_west` and `respawn_east` markers sit at the base (`Init.sqf:451-470`). While a base is targeted they move to a ring at Size/2 + 300 around it (`SectorHandleServer.fsm:317-350`), and return when safe (`:488-496`). Spawn protection is 180 s (`VarsInit.sqf:157-176`). On restart the AI core clears waypoints (`AICore.fsm:266-268`) and teleports the warlord next to a living subordinate (`:326-327`), so **a respawned leader rejoins his men at once, wherever they are**.

**Group identity.** It survives respawn. In the baseline all 16 groups keep one `netId` each through t=2346, and all 16 are still present at the end. The leader's respawn doesn't create a new group (engine behaviour confirmed by the log). Track groups by group object, not leader. The 8 to 7 dips recover within 30 to 60 s, consistent with a sole survivor dead and waiting to respawn (GRP lists only groups with living units) **(inferred)**.

**Shrink and grow.** Subordinates are not replenished for free: `createUnit` and `joinSilent` don't appear in AICore, AIPurchases or RequestPurchase. AI **buy** them (`AIPurchases.fsm:156,219,417`), up to `4 min BIS_WL_maxSubordinates` plus the leader, so 5 men. `BIS_WL_maxSubordinates` defaults to 9 (`VarsInit.sqf:46`; Tanoa `MPS/MPScenarios/MP_Warlords_03.Tanoa/mission.sqm:3106`). Purchase cost includes a drop fee of `BIS_WL_dropCost` = 25 (`VarsInit.sqf:51`) **only within 200 m of an own sector; anywhere else it is 40x, or 1000 CP** (`AIPurchases.fsm:144-153,202-211`). That probably explains groups staying at 1 to 4 men at the front **(inferred)**, and gives the commander a strong reason to fast travel to owned sectors before topping up. Others cover purchase detail.

**Stuck logic.** An on-foot AI warlord moving under 1 m per 90 s gets a 2 m nudge five times and then `setDamage 1` (`AICore.fsm:270-288`). **A warlord that stands still for about 9 minutes is killed.** Waiting forces need this handled or the core suspended.

## 7. Garrisons and defence

**Neutral sectors.** Populated once at first selection (`SectorHandleServer.fsm:166`, `SectorInit.sqf:9`, `SectorPopulate.sqf`).
- `idx = (rx*ry)/25e4` (`:15`). The 8-man garrison is effectively disabled by `_garrisonTotal = 0` (`:16,75`).
- Sentries total `60*idx` (`:17`): size 300 gives 5.4, so **6 groups of 3 (18 men)**. Size 200 gives 2.4, so 3 groups (9 men).
- Sentries walk random MOVE SAFE LIMITED + CYCLE waypoints (`:107-156`). One that does not move for 60 s is deleted (`:133-142`).
- Editor-placed vehicles at `:23-58`.
- Patrols: `SectorInit.sqf:11-61`, 50% per eligible neighbour.

**Response team.** GUER only. On the first COMBAT inside the GUER trigger (`SectorPopulate.sqf:61-69`), `SendResponseTeam.sqf` picks the nearest neighbouring sector with responses left that isn't targeted (`:11-25`), consumes one, spawns INDEPENDENT (`:46`) with SAD waypoints (`:123-128`), and may paradrop (`:130-169`). It exits if the sector is already conquered (`:9`). Response arrays are cleared on capture (`SectorSelectionHandleServer.fsm:235`, `SectorsSetup.sqf:254,277`).

**Owned sectors.** No garrison until an enemy first targets one, then once ever a sentry set of the owner's side appears (`SectorHandleServer.fsm:288-294,410-416,428-431`; flag `BIS_WL_guardSpawned`, `:72,429`). Bases get no populate path **(inferred)**.

**Retreat and cleanup.** After capture, garrison units retreat to the nearest same-side synced sector, else any (`GarrisonRetreat.fsm:83-99,133-137`), which means **GUER flee into neighbouring sectors**. Survivors are deleted 300 s after the owner changes, then only once no player is within 500 m (always true with no players, `RemovalHandle.sqf:17-32`).

**Interaction with the commander's reserve.**
- Spawned guards are BLUFOR/OPFOR non-warlord groups. The commander must exclude them, using `BIS_WL_parentSector` on units (`RemovalHandle.sqf:14`) or by requiring a warlord in the group. They shouldn't be counted as reserve.
- `DefenceSetup.sqf` is player-only static placement and isn't relevant to AI.
- Warlords' AI defends only its own base when targeted (`AICore.fsm:339`), so **the commander's reserve is the only real sector defence**.

## 8. Attaching a mod or overlay; round end

**No readiness flag exists.** `BIS_WL_sectors` is assigned only after setup finishes (`Init.sqf:114`), and Warlords itself waits on it plus `BIS_WL_scenarioServices` (`:430`). The AI cores and FSMs start at `:128,137-138`.

Safe attach, on the server:
1. Wait for `BIS_WL_sectors` and `BIS_WL_scenarioServices`.
2. Wait for `BIS_WL_base_WEST` and `BIS_WL_base_EAST`, and for `BIS_WL_allWarlords` to be non-empty.
3. Cache sector positions and links.

`wl_ready` in the observer already checks `BIS_WL_sectors` (`tests/mission_overlay/swl/observer.sqf:99`).

**Hooks.**
- Overlay: stock `init.sqf` execVMs `\A3\Missions_F_Warlords\commonInitScript.sqf` and must stay. `initServer.sqf` is free and works on dedicated (`tests/mission_overlay/initServer.sqf`). It also runs on a client host **(engine behaviour, inferred here)**.
- Addon: CfgFunctions postInit gated by `isServer` and Warlords being present, tested by `entities "ModuleWLInit_F"` (`MPS/MPScenarios/MP_Warlords_03.Tanoa/mission.sqm:2708`). `WLInit` has no pre or postInit flag in `reference/functions_f_warlords/config.cpp:39`, so a module starts Warlords **(inferred)**, and the same wait applies.

**Round end.** Only if the Init module's `MissionEnd` is above 0 (`Init.sqf:475`). The code default is 0 (`:43`), but Tanoa sets it to 1 (`mission.sqm:2916`). It waits for either base's `BIS_WL_sectorSide` to change (`:478`), then `endMission "End1"` on dedicated (`:480`), otherwise the player-side ending. A commander should watch the same condition, and stop cleanly on a mission `Ended` handler too.

## Summary for the adapter

**Read:**
- `BIS_WL_sectors`; on each sector `BIS_WL_sectorSide`, `Size`, `BIS_WL_value`, `BIS_WL_connectedSectors`, `BIS_WL_timeoutCur_<side>`.
- `BIS_WL_currentSector_<side>`, `BIS_WL_base_<side>`, `BIS_WL_allWarlords`.
- `[side] call BIS_fnc_WLSectorListing` for available targets.
- Position and links cached at init; the group object as identity.

**Hook or write:**
- Start from `initServer.sqf` (later postInit) after the readiness wait.
- Steer the target by setting AI `BIS_WL_selectedSector` from the available list; force a re-vote with `BIS_WL_sectorVotingReset_<side>`.
- Exclude groups led by players and non-warlord guard groups.
- Log `BIS_WL_timeoutCur_*` and per-side counts inside the square.

**Surprises:**
1. The seize area is a square, and the enemy side's presence, not the garrison, appears to block capture **(inferred)**. There is no target timeout, so deadlocks last indefinitely.
2. An enemy capture does not clear your target.
3. With no vote there is no target, ever, and on a host with AI voting at the default 0 the human side depends on a human voting.
4. AI inside a non-allowed sector are killed, and an idle on-foot warlord is killed after about 9 minutes.
5. AI reinforcement away from an owned sector costs 40x the drop fee.
6. `BIS_WL_conqueredSectors_*` doesn't mean owned.
7. On a host the server-side setup waits for the host to be on WEST or EAST.
8. The exact SEIZED threshold and the mid-round name change remain unexplained by the code.
