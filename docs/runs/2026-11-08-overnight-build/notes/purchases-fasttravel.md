# Warlords purchases, fast travel, CP and scans

Code study for the adapter. Read only, nothing was run, so every timing below comes from the code and not from a round.

Conventions:

- File references are relative to `reference/functions_f_warlords/Warlords/` unless they start with `missions_f_warlords/`, which means `reference/missions_f_warlords/`.
- **(inferred)** marks anything concluded rather than read directly. Everything else was read in the code.
- Bohemia's code is paraphrased. Only names, numbers and line references appear here.
- "Warlord" means a unit in `BIS_WL_allWarlords`: playable and switchable WEST and EAST units (`fn_WLVarsInit.sqf:61`, refreshed at `:96`).

## Q1. How AI fast travel and AI purchases are triggered

There is no request or server-validation layer. Player flows are client-local (`fn_WLRequestFastTravel.sqf`, `fn_WLRequestPurchase.sqf`, `fn_WLRequestSectorScan.sqf`, all built on `player`). AI flows run directly on the server. A server-side commander therefore has no API to call: it does what the AI FSMs do, which is to change `BIS_WL_funds` and then act.

### AI fast travel (`fn_WLAICore.fsm`)

Path once the side has a target: `fight` (3 s, `:504`, `:537`), then `FT_availability`, then `next_check`, `next_check_1`, `next_check_2`, `run_timer_1`, `fast_travel`.

| Gate | Condition | Where |
| --- | --- | --- |
| Param, sector flag, vehicles | No group vehicle within 500 m, `BIS_WL_FTEnabled` in 1 or 3, target's `FastTravelEnabled` is not false. Otherwise it goes to `nothing`, or back to FT from `nothing_1` when the condition clears | `:662`, `:1200` |
| Airdrop | `BIS_WL_AI_airdropping` must be false | `:673`, `:706` |
| Funds | `BIS_WL_funds` of the leader at least `BIS_WL_FTCost` | `:1257`, `:1268` |
| Combat | Not both "crewed enemy object within 200 m" and COMBAT behaviour. The enemy query is refreshed every 10 s | `:1291`, `:1302`, `:1313`, `:1442` |
| Delay | 5 + random 10 s | `:940`, `:995` |

The `fast_travel` state (`:718-805`):

- Charges the leader `BIS_WL_FTCost` publicly on entry (`:718`), before the distance check, so a trip that then does not happen is still paid for.
- Chooses a destination from `BIS_WL_sectorsArray<side>`, indexes 0, 1, 2 for owned, available and linked (`:722-725`, built by `fn_WLSectorListing.sqf:37`):
  - Target is the enemy base: nearest owned sector linked to it (`:731-740`).
  - Target is in the available list: a point 200 + Size/2 from the sector, next to the contested zone (`:742-753`). This is the behaviour the commander must not copy.
  - Otherwise: nearest linked sector (`:755-763`).
- Moves only if farther than 300 m (`:767`), and only units on foot. Non-leaders that are not `unitReady` are **deleted** (`:771-774`).
- Lands with `findEmptyPosition` 0-50 m and a `setPos` / `setPosATL` pair (`:776-788`), regroups stragglers (`:792-802`), then calls `BIS_fnc_WLAIPathSegmentation` (`:805`).

Defend fast travel: state `defend` moves units to their own base **for free** when the param is 1, 3 or 4 (`:1130-1144`). It is entered whenever the unit's own base is either side's current target (`:562`, `:640`).

### AI purchases

Started per warlord from `fn_WLAICore.fsm:251`, stored in `BIS_WL_AIPurchasesHandle`. Details are under Q4.

### Using the same paths and costs from a server-side commander

- Fast travel: check the param (Q2), debit `BIS_WL_funds` publicly by `BIS_WL_FTCost`, then move the on-foot units to an owned sector with your own landing code. Do not copy the deletion of non-ready units.
- Purchase: debit the item cost, set `BIS_WL_dropPos` on the buyer to an object, then call `BIS_fnc_WLAirdrop` with buyer, class list and TRUE. It returns the spawned items (`fn_WLAirdrop.sqf:277`).
- Scan: debit `BIS_WL_scanCost` and set the two sector variables (Q7).

## Q2. `BIS_WLFTEnabled` values

The lobby param is `BIS_WLFTEnabled` (`missions_f_warlords/cfgMissionParams_subclasses.inc:22-28`, default 1). A `BIS_WL<Key>` param overrides the module attribute `<Key>` in multiplayer when Params exist (`fn_WLInit.sqf:50-66`). It is read once into `BIS_WL_FTEnabled` (`fn_WLVarsInit.sqf:36`). Tanoa's module attribute is 1 (`missions_f_warlords/MPScenarios/MP_Warlords_03.Tanoa/mission.sqm:2865-2878`).

Labels below were read from `stringtable.xml` inside `language_f_warlords.pbo` and matched to values by their order in the `.inc`.

| Value | Label meaning | Players to owned (`FTSeized`, free) | Players to contested (`FTConflict`, `BIS_WL_FTCost`) | AI attack FT | AI defend FT to own base |
| --- | --- | --- | --- | --- | --- |
| 1 | Enabled for everyone | Yes | Yes | Yes | Yes |
| 0 | Disabled for everyone | No | No | No | No |
| 2 | Disabled for AI | Yes | Yes | No | No |
| 3 | Disabled for players | No | No | Yes | Yes |
| 4 | Enabled only to owned sectors | Yes | No | No | Yes |

The complete list of readers:

- `fn_WLParseAssetList.sqf:150`: `FTSeized` offered if the value is 1, 2 or 4, cost 0.
- `fn_WLParseAssetList.sqf:151`: `FTConflict` offered if the value is 1 or 2.
- `fn_WLAICore.fsm:662`, `:1200`: AI attack FT, values 1 and 3.
- `fn_WLAICore.fsm:1130`: AI defend FT, values 1, 3 and 4.
- `fn_WLSectorHandle.fsm:481`, `:485`, `:579`: base-vulnerable hints only.

**Value 4 is the answer.** It removes the player `FTConflict` service and stops vanilla AI attack FT. Nothing in the param's readers touches a scripted move, so the commander's owned-sector fast travel still works.

The run prompt's note that AI fast travels only on 1 or 3 is right for attack FT, but defend FT also runs on 4.

**Which checks apply to a scripted move:** none of the fast travel checks do. All availability logic sits in the player UI (`fn_WLSubroutine_purchaseMenuAssetAvailability.sqf:12-27`) or in the AI FSM transitions, and nothing hooks `setPos`. To stay honest the adapter should enforce them itself:

- Param value in 1, 3 or 4 (the same set as vanilla defend FT).
- Destination owned by the side, and not one with `FastTravelEnabled` false (`fn_WLRequestFastTravel.sqf:60-63`).
- Units on foot only, no enemy-crewed object within 200 m of the units (`fn_WLSubroutine_purchaseMenuAssetAvailability.sqf:12-16`).
- Own base unavailable once it has been under attack. Players get this through the client-side `BIS_WL_baseFTDisabled` (`fn_WLSectorHandle.fsm:487`, cleared `:581`), so the server needs its own check, such as "own base is a current target" (inferred equivalent).

**One position rule does apply.** Each sector runs a server loop every 20 s that kills AI inside the sector's square (half-width Size/2) if that sector is neither owned by the unit's side nor its current target (`fn_WLSectorsSetup.sqf:89-113`, area test `fn_WLInSectorArea.sqf:24-30`). Landing in an owned sector is safe. **A route or dismount point crossing another enemy or neutral sector is not.** The loop has a bug: `_toCheck` is overwritten rather than appended (`:97`), so in practice it only covers the units of the last non-player warlord in `BIS_WL_allWarlords`, and groups not led by a warlord are never checked. Do not rely on the bug. Route around non-target sectors.

**Lobby default:** Tanoa's `description.ext` only includes the stock params, so a default of 4 needs the scenario's own Params class with `BIS_WLFTEnabled` default 4. Keep class order, because the values are read by position from `paramsArray` (`fn_WLInit.sqf:60-62`). Also set the module attribute to 4, for runs without Params.

**Vanilla interaction to flag for the AI core study:** on value 4, commander-owned warlords can still be pulled to their base by the free defend FT (`fn_WLAICore.fsm:1130-1144`). Commander orders will not block it.

### Player fast travel, for reference (`fn_WLRequestFastTravel.sqf`)

- Conflict destination is 200 + Size/2 from the sector, toward the player, with water avoidance (`:35-45`); the charge is `:25`, refunded on cancel `:136`.
- Owned destinations come from `BIS_WL_sectorsArrayFriendly # 0`, filtered by `FastTravelEnabled` and `BIS_WL_baseFTDisabled` (`:60-63`).
- Moves group members within 200 m on foot (`:166`), hidden through a 5 s transition (`:168-174`).
- Owned landing: random within 100 x a retry coefficient, flat, no objects within 10 m (`:182-200`). Conflict landing uses `findEmptyPosition` 0-50 (`:180`).

## Q3. CP

**Where it lives:** `BIS_WL_funds` on each warlord unit, public (`setVariable` with TRUE). There is **no side pool**.

- AI start value: `fn_WLInit.sqf:119-120`, with `BIS_WL_startCP` (`fn_WLVarsInit.sqf:28`) and a parallel `BIS_WL_funds_backup`.
- Players: `fn_WLClientInit.sqf:85-91`. A join outside `BIS_WL_recentStart` gets 50 or 0.
- Backup and restore across respawn every 2 s: `fn_WLInit.sqf:406-414`.
- Purchased subordinates hold no funds.

**Income:** `fn_WLCalculateIncome.sqf:13-15` sums `BIS_WL_value` x `BIS_WL_CPIncomeMult` over owned sectors, per minute. `BIS_WL_value` comes from the sector's `Funds` attribute (`fn_WLSectorsSetup.sqf:54`, `:127`).

**Payout:** `fn_WLSectorFundsPayoff.fsm:46-54`, started at `fn_WLInit.sqf:139`. It pays the **full side income to every warlord of that side** every `BIS_WL_fundsPayoffTimeout` = 60 s (`fn_WLVarsInit.sqf:27`), capped at `BIS_WL_maxCP` (`fn_WLVarsInit.sqf:48-49`; -1 means effectively none). A side's true income is therefore income x number of warlords.

**Other sources:**

- Capture bonus 10 x value x multiplier to each warlord of the capturing side, once per side per sector (`fn_WLSectorHandleServer.fsm:264-271`; `_oldSide` is re-read after the change at `:253`, so it is the new owner).
- Kill reward of rating/20 when the rating gain exceeds 100: AI `fn_WLInit.sqf:121-126`, players `fn_WLClientInit.sqf:138-140`, purchased units credit the buyer `fn_WLAirdrop.sqf:62-72`.

**Reading a side's spendable CP:** sum `BIS_WL_funds` over alive, non-player warlords of that side. Exclude players: their CP is theirs to spend and the commander must not debit it.

**Debiting (inferred guidance):** vanilla FSMs read and write the same variable. Take from the richest AI warlords first, and wrap each read-modify-write in an unscheduled block so a scheduled commander cannot interleave with an FSM.

## Q4. What the AI buys (`fn_WLAIPurchases.fsm`)

One FSM per warlord. It waits for `BIS_WL_purchasable` (`:97`), then `set_up_vars` takes a **one-time snapshot** into local variables (`:508-557`).

- Infantry: `purchasable # 0` minus `WLAIRequisitonBlacklist` (`:513-520`).
- Vehicles: `purchasable # 1` limited to simulation car or tank, with any numeric `threat` above 0.5, and a Turrets class (`:524-535`). In effect armed vehicles only. **Vanilla AI never buys unarmed transport** (inferred from the filter; individual config values not checked). No aircraft, naval or gear.
- `_dropCost` in `check_funds` (`:143-156`): 25 if within 200 m of an own sector, which also sets `BIS_WL_dropPos` to that sector, otherwise `BIS_WL_dropCost` x 40 = 1000.
- `_maxToPurchase`: min(4, max subordinates) - units + 1, also limited by `_maxCrew` - units.
- Infantry buy condition (`:178`): not already airdropping, funds at least cheapest infantry + `_dropCost`, and room in the group.
- Vehicle buy condition (`:189`): funds at least cheapest vehicle + `_dropCost` x 40 (cheapest + 1000 near a sector, + 40000 away, so effectively never away), and no group vehicle yet.
- Pace: `run_timer` is 5 + random 10 s and sets `BIS_WL_AI_airdropping` (`:308-310`). After a drop, it rechecks 30 s later (`:473-474`, `:496`).
- Selection is random, keeping an FT-cost margin (`:221-230`). Vehicles pick at random, falling back to the cheapest (`:344-417`).

**Money:** funds are reduced by the item cost only (`:233`, `:382`). `_dropCost` is an affordability threshold; the AI never actually pays the fee. Players pay it: 25 to a sector, 1000 to their own position (`fn_WLDropPurchase.sqf:18`).

**After a vehicle buy:** `BIS_WL_groupVehs` on the group is updated publicly (`:386`); a spawned script sleeps 30 s, waits until landed, sleeps 3 s, adds a GETIN waypoint stored in `BIS_WL_curWP`, and deletes group members over the vehicle's capacity (`:393-411`).

**`WLAIRequisitonBlacklist`** (`missions_f_warlords/defaultDescription.inc:21`, crew and pilot classes): removes classes from the AI's infantry list only (`:516`). No effect on vehicles.

**Can it be steered per side?** Not through any supported hook, since the lists are snapshotted once.

- Engine `setFSMVariable` on `BIS_WL_AIPurchasesHandle` could overwrite `_purchasableUnits`, `_purchasableVehs`, `_cheapest` and `_cheapestInf`. An empty unit list plus `_cheapest` set to `["", -1]` would disable buying (inferred, must test). It must be reapplied after respawn, when a new FSM starts (`fn_WLInit.sqf:130`).
- Do not touch `BIS_WL_AI_airdropping`. The AI core depends on it (`fn_WLAICore.fsm:673`, `:706`) and the vehicle branch ignores it.
- Fallback if `setFSMVariable` fails: sweep funds into a commander-held treasury and keep each AI warlord's balance below cheapest infantry + fee, so the vanilla conditions never pass (inferred).

**Recommendation:** replace it. Vanilla buys at random, cannot buy transport, and would spend through any CP reserve. Neutralise vanilla buying and let the commander make every purchase. If the side shopping list needs a mission-level tool as well, `WLAIRequisitonBlacklist` and scenario presets are static but supported.

## Q5. A vehicle bought through Warlords' path

Call: `BIS_fnc_WLAirdrop` with buyer, class array and `orderedByAI` (`fn_WLAirdrop.sqf:9-13`). It does not debit anything; the caller does.

**Use `orderedByAI` TRUE.** With FALSE the vehicle is locked and FF-protected (`:157-167`), and `fn_WLVehicleHandle.sqf:23-30` does player-style marker work, indexing a colour array with `side group player` (`:26`), which is out of range on a dedicated server (inferred) and would kill the cleanup handler.

**Where it lands:**

- The drop centre is the object in the buyer's `BIS_WL_dropPos`, cleared after reading (`:9-10`). It must be an object: `:270` calls `position` on it. Any object should work (inferred), so a helper object at the staging point can set the drop centre. Set it and call in one step per buyer, since it is a single variable.
- Vehicles land at 50 + random 100 x coefficient metres from that centre, in a random direction, on flat ground with nothing within 10 m. The coefficient grows only after repeated failures (`:30-50`).
- Consequence: the landing point is scattered, 50-150 m out. **"Lining up" must be scripted after landing** (the commander moves or drives it to its slot).

**How long:** the parachute starts at 150 + random 100 m (`:52-53`), the vehicle is attached (`:185`) and released under 2 m, then snapped to the final position (`:196-202`). No duration is coded. The AI's own 30 s sleep before polling for landing (`fn_WLAIPurchases.fsm:393-411`) suggests at least 30 s. Estimate **30-60 s (inferred, measure in Phase 3)**. Against a 90 s mount-up cap, buy on arrival at staging, not at the go signal.

**Ownership and crew:** no crew except UAVs (`:154`). `BIS_WL_itemOwner` is the buyer (`:155`). The refund on self-destruction is for players only (`:171`). The vehicle is unlocked with TRUE. On AI, `BIS_WL_pointer` is nil at `:275`, so that line does nothing (inferred; only players get a pointer, `fn_WLPlayersTracking.sqf:19`).

**Site requirements:** ground vehicles have `requirements[] = {}`, so none. Air and naval have "H", "A", "W" (`fn_WLParseAssetList.sqf:28`; sector services at `fn_WLSectorsSetup.sqf:78-82`). Players also need the service at an owned sector and a 20-vehicle limit (`fn_WLSubroutine_purchaseMenuAssetAvailability.sqf:59`, `:61`). The AI path checks neither. The commander should impose its own limit.

**Side effects of TRUE, all relevant to the wave plan:**

| Effect | Line | Impact | Mitigation |
| --- | --- | --- | --- |
| `setUnloadInCombat` false | `:218` | Passengers stay in under fire | Commander orders the dismount explicitly |
| 180 s timer from purchase: if the vehicle cannot move, or at 180 s the buyer group's leader is not in it, the group is dropped from it (`leaveVehicle`), and at timeout the group's current waypoint is reset to `BIS_WL_curWP` or index 0 | `:219-233` | **Resets the buyer group's waypoints at 180 s if the leader is not aboard** | Make the buyer a group whose orders do not matter (payer and buyer are independent, inferred), or set `BIS_WL_curWP` and reissue orders at +180 s |
| Stuck check: first sample at +60 s, then every 180 s: if there is live non-player crew and it moved under 0.5 m, the effective commander's group leaves the vehicle | `:234-248` | **A crewed vehicle holding still for a full 180 s window is abandoned. This hits combat vehicles holding for fire support and any crewed vehicle waiting** | Board only at mount-up; nudge holding vehicles at least 0.5 m within each window (inferred) |
| GetIn handler: 20 s after a driver boards, a `move` to their own position | `:249-258` | Can interrupt a drive order given within those 20 s (inferred) | `removeAllEventHandlers "GetIn"` after purchase (inferred safe, the other GetIn handler is player-only, `fn_WLVehicleHandle.sqf:34-40`), or reissue the order after 21 s |

**Cleanup (`fn_WLVehicleHandle.sqf`):**

- Timeout is time + `BIS_WL_vehicleSpan` (`:33`), tripled for ammo, static and autonomous classes (`:42`), +60 s once killed (`:52`).
- Every 5 s when no live crew: the timeout is refreshed once after a crew has left (`:61-63`), and the vehicle is deleted after expiry (`:65`).
- A vehicle that was **never crewed** is deleted a span after purchase, with no refresh. `VehicleSpan` lobby default is 1800 s (`missions_f_warlords/cfgMissionParams_subclasses.inc:134-140`; Tanoa module attribute 3600, lobby overrides).
- Wrecks are engine-managed (`missions_f_warlords/defaultDescription.inc:15-19`). Below-ground removal: `fn_WLInit.sqf:377-404`.

**Infantry through the same call:** they join the buyer's group (`fn_WLAirdrop.sqf:59`), and the buyer must be a real unit. The FSM's infantry buy omits TRUE (`fn_WLAIPurchases.fsm:235`).

## Q6. Asset lists

**Location:** `CfgWLRequisitionPresets` at `missions_f_warlords/config.cpp:86`, merged with any in the mission config (`fn_WLParseAssetList.sqf:10`, `:14`). Structure is preset, then WEST or EAST, then Infantry, Vehicles, Gear, Defences, Aircraft, Naval (and optionally `Gear_custom`), then one class per asset with `cost`, `requirements[]` and an optional `offset`.

**Selection:** the module's `AssetList` string (`fn_WLVarsInit.sqf:42-45`, default `A3DefaultAll`). Both stock Tanoa scenarios use `A3PacificAll` (`MP_Warlords_03.Tanoa/mission.sqm:2821`, `MP_Warlords_03a.Tanoa/mission.sqm:2818`). It inherits `A3DefaultAll`, replaces Infantry and Vehicles, and keeps Aircraft, Naval, Gear and Defences from the parent (`config.cpp:745-875`, `:876-1005`).

**Parsed form:** `BIS_WL_purchasable<SIDE>` (`fn_WLParseAssetList.sqf:159`) and a per-unit `BIS_WL_purchasable` (preset per unit `fn_WLInit.sqf:132`). Indexes: 0 Infantry, 1 Vehicles, 2 Gear, 3 Defences, 4 Aircraft, 5 Naval, 6 Gear_custom, 7 Services. Entry: class, cost, requirements, name, preview, text, type, and optional offset. **The adapter should read classes and costs from this array, not from a hardcoded table**, so that it stays correct on other maps and with overrides.

**`CfgWLAssetCostOverride`:** read from the **mission** config only. For asset classes, a value above 0 replaces the cost (`fn_WLParseAssetList.sqf:31-36`). The keys `Scan`, `Airdrop`, `FastTravel`, `LastLoadout`, `Arsenal`, `FundsTransfer` and `ResetVoting` override services (`fn_WLVarsInit.sqf:30`, `:51-56`). Stock Tanoa does not define it (inferred from no match in the Tanoa mission and config search).

### Stock Tanoa ground vehicles (`A3PacificAll`, `requirements` all empty)

Costs match class for class between the sides, with two exceptions: only WEST has the 4000 AFV and only EAST has the 6000 MBT. Lines: WEST `config.cpp:802-866`, EAST `:932-996`.

| Cost | WEST | EAST | Role (inferred from class) |
| --- | --- | --- | --- |
| 100 | `B_T_Quadbike_01_F` | `O_T_Quadbike_01_ghex_F` | Transport |
| 350 | `B_T_LSV_01_unarmed_F` | `O_T_LSV_02_unarmed_F` | Transport |
| 500 | `B_T_MRAP_01_F` | `O_T_MRAP_02_ghex_F` | Transport |
| 650 | `B_T_Truck_01_transport_F` | `O_T_Truck_03_transport_ghex_F` | Transport |
| 750 | `B_T_Truck_01_fuel_F`, `B_T_Truck_01_medical_F` | `O_T_Truck_03_Fuel_ghex_F`, `O_T_Truck_03_medical_ghex_F` | Support |
| 1000 | `B_T_LSV_01_armed_F` | `O_T_LSV_02_armed_F` | Combat |
| 1250 | `B_T_LSV_01_AT_F` | `O_T_LSV_02_AT_F` | Combat |
| 1400 | `B_T_MRAP_01_hmg_F` | `O_T_MRAP_02_hmg_ghex_F` | Combat |
| 1500 | `B_T_Truck_01_Repair_F` | `O_T_Truck_03_Repair_ghex_F` | Support |
| 1600 | `B_T_MRAP_01_gmg_F` | `O_T_MRAP_02_gmg_ghex_F` | Combat |
| 3000 | `B_T_Truck_01_ammo_F`, `B_T_APC_Wheeled_01_cannon_F` | `O_T_Truck_03_ammo_ghex_F`, `O_T_APC_Wheeled_02_rcws_v2_ghex_F` | Support, Combat |
| 3500 | `B_T_APC_Tracked_01_rcws_F` | `O_T_APC_Tracked_02_cannon_ghex_F` | Combat |
| 4000 | `B_T_APC_Tracked_01_AA_F`, `B_T_AFV_Wheeled_01_cannon_F` | `O_T_APC_Tracked_02_AA_ghex_F` | Combat |
| 5000 | `B_T_MBT_01_cannon_F` | `O_T_MBT_02_cannon_ghex_F` | Combat |
| 6000 | none | `O_T_MBT_04_cannon_F` | Combat |

Infantry on Tanoa (`config.cpp:748-796`, `:878-926`): rifleman, crew and pilots 100; grenadier and medic 125; autorifleman, ammo bearer and marksman 150; repair and light AT 200; AA and sniper 300. The AT launcher role is `soldier_LAT_F`.

**Cheapest vehicle seating N:** the presets contain no seat counts. Vanilla uses `emptyPositions` on a spawned vehicle (`fn_WLAIPurchases.fsm:391`), which is too late for buying. Before buying, compute seats from config once per class at init, for example with `BIS_fnc_crewCount` (inferred from memory, not read). Then take the cheapest ground entry from `BIS_WL_purchasable # 1` with seats at least N. From memory, unverified: quad 2, LSV about 6, MRAP 4, transport truck 16 or more. That would make the MRAP (500) never the cheapest choice and put the LSV at 350 for groups up to 6 and the truck at 650 above that. Exclude the fuel, medical, repair and ammo classes from transport choice, because their seat counts make them look like cheap transports (inferred).

## Q7. Sector scans

**Settings:** `BIS_WL_scanCost` 350 (`fn_WLVarsInit.sqf:30`), `BIS_WL_scanDuration` 30 s (`:31`), `BIS_WL_scanCooldown` default 0 (`:47`; param `missions_f_warlords/cfgMissionParams_subclasses.inc:120-126`), `BIS_WL_scanEnabled` (`:37`, service at `fn_WLParseAssetList.sqf:149`).

**Requesting a scan is only two public sector variables:** `BIS_WL_sectorScanActiveSince_<side>` and `BIS_WL_sectorScanLastRequest_<side>`, both set to `BIS_fnc_WLSyncedTime`.

- Player (`fn_WLRequestSectorScan.sqf`): targets are owned sectors plus the current target (`:26-32`). Refused if a scan is active (`:55`) or the last request is newer than duration + cooldown + 5 s (`:56`). Sets the variables (`:58-59`), debits (`:62`).
- AI (`fn_WLAISectorScan.sqf`): spawned once per side for each newly chosen target (`fn_WLSectorSelectionHandleServer.fsm:188`, `:246`, `:368`). Waits 90 + random 30 s, or 10 + random 10 s if the sector is already the side's own (`:14-15`). Same refusal rules (`:22`). A **random AI warlord with enough CP pays 350** (`:24-36`). Sets the variables (`:38-39`).

**What it reveals, and to whom:**

- Humans (`fn_WLSectorScanHandle.fsm`, client-only, started for `side group player` at `fn_WLClientInit.sqf:59` and `fn_WLSectorsCommonInit.sqf:120`): a 5 s lead-in (`:123`), then until request time + duration + 5 s it reveals everything in the scan trigger at level 4 to `units group player` every second and draws map icons (`:135`, `:141-183`). The area is the sector's Size/2 square (`:110-112`, trigger created on the server at `fn_WLSectorHandleServer.fsm:79-82`). A public request from any source triggers it on same-side clients.
- AI (`fn_WLSectorsSetup.sqf:173-202`): a server loop every 3-5 s per sector. On a **dedicated** server it resets the variable locally (`:185`), enables the trigger (`:186-187`), sleeps 5 s, reveals the trigger's contents at level 4 **once**, only to non-player warlords of that side within Size/2 + 200 m of the sector (`:190-194`), and shrinks the trigger again (`:196-197`).
- No result is stored anywhere readable. Groups farther away learn nothing.

**Hosted servers differ, and hosted is the v1.0 target (inferred from `:184` and `:195`).** The enable and reset steps run only when `isDedicated`. On a client host:

- The trigger area comes only from the host's own scan FSM, which runs only for the **host's** side.
- A scan by the all-AI side therefore sees an empty trigger.
- Its `ActiveSince` is never reset on the host, so the server loop keeps firing and vanilla refuses further scans of that sector for that side (`fn_WLAISectorScan.sqf:22`).

Vanilla scans for the all-AI side should be treated as non-functional in a hosted game.

**Initialisation:** the sector variables are only initialised locally on clients (`fn_WLSectorScanHandle.fsm:63-68`). `fn_WLVarsInit.sqf:297-298` sets same-named mission globals that nothing reads (from the search). On a dedicated server they are nil until the first scan, so **read them with a default of -1** (as `fn_WLSectorsSetup.sqf:182` does).

**How the commander should scan:**

1. Check `BIS_WL_scanEnabled == 1`, the target is owned or the side's current target, `ActiveSince <= 0`, and `LastRequest` older than duration + cooldown + 5.
2. Debit `BIS_WL_scanCost` from an AI warlord, publicly.
3. Set both variables publicly. Same-side humans then see the normal scan.
4. After the 5 s lead-in, run the commander's **own server-side query** of the sector's Size/2 square and post the results to the intel board tagged as scan sourced. Do not read the trigger, because on a host it is unreliable.
5. After duration + 5 s, write `ActiveSince` to -1 publicly. This also cures the hosted lock.

**Stopping the vanilla random 350 CP scan (inferred from `fn_WLAISectorScan.sqf:22`):** writing `LastRequest` forward makes it exit. For it to be covered at the latest wake-up (selection + 120 s) with defaults, `LastRequest` must be later than selection + 85 s. The cost is that same-side humans cannot scan that sector during that window (`fn_WLRequestSectorScan.sqf:56`). Worth it on the all-AI side. On a side with humans, weigh it against the blocked scan, or simply count the vanilla scan as part of the budget. If the commander stamps `LastRequest` forward, its own step 1 check must ignore that stamp, so it needs to remember which stamps are its own.

## Summary for the adapter

**Fast travel.** Default the param to 4. Allow commander FT on values 1, 3 and 4. Destinations are owned sectors only, excluding `FastTravelEnabled` false and an own base under attack. Refuse if enemies are within 200 m or the group's units are in vehicles. Charge `BIS_WL_FTCost` (50) to the leader if a warlord, otherwise to the richest AI warlord, matching vanilla AI, with a settings toggle for 0 to match the free player owned-sector rule. Move units by script with spread-out landing points on the far side from the target. Never delete non-ready units as vanilla does.

**Purchases.** Neutralise `fn_WLAIPurchases.fsm` and have the commander do all buying. Debit the item cost from AI warlords, richest first, never from players. Fee parity with vanilla AI is zero; a settings option can charge `BIS_WL_dropCost`. Set `BIS_WL_dropPos` to a helper object at staging, call `BIS_fnc_WLAirdrop` with TRUE, and keep the returned vehicle. Read classes and costs from `BIS_WL_purchasable`. Buy on arrival at staging, because a drop takes roughly 30-60 s (inferred) and lands 50-150 m out.

**Scans.** Debit and set the two public variables, do the query yourself on the server, post to the board, then clear `ActiveSince` publicly after 35 s.

**Surprising things:**

1. Value 4 does exactly what the deliverable needs, and its label says so.
2. Every warlord gets the full side income, so side income is income x warlords, and there is no side wallet to read.
3. Vanilla AI never buys unarmed transport, so vehicle buying cannot be merely steered.
4. The 180 s and stuck-check scripts attached to AI-ordered vehicles will reset waypoints on the buyer's group and make holding crews abandon their vehicles. Combat vehicles holding for fire support are directly exposed.
5. A bought vehicle that is never crewed is deleted one `VehicleSpan` after purchase, with the 1800 s lobby default. This matters for vehicles parked for the next wave.
6. Vanilla AI fast travel charges before checking whether a trip will happen, and deletes non-ready subordinates.
7. Vanilla scans work for AI only on dedicated servers, and only for warlords within Size/2 + 200 m. Hosted games lock the all-AI side's scan on that sector (inferred).
8. The server kills AI inside non-owned, non-target sectors, currently only for one warlord's group because of a bug. Routes should avoid those squares anyway.
9. Defend FT still runs on value 4 and can pull commander-owned warlords to base.

**Must be tested in-game (all inferred above):** `setFSMVariable` on the purchase FSM; a helper object as drop centre; a non-combat buyer absorbing the 180 s timer; real parachute descent time; removing the GetIn handler; hosted-server scan behaviour.
