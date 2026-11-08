# Warlords rules: findings for the rules-variant run

Read-only research on the unpacked code in `reference/`. Paraphrase and our own conclusions only. Nothing here was run in Arma, so every "hook" is a design until a scenario test proves it. Facts come from the cited lines; anything resting on engine behaviour I could not read is marked **(inferred)**.

Shorthand: files are in `reference/functions_f_warlords/Warlords/` with the `fn_WL` prefix dropped. SHS = `SectorHandleServer.fsm`, SHC = `SectorHandle.fsm` (client), SelServer = `SectorSelectionHandleServer.fsm`, SelClient = `SectorSelectionHandle.fsm`, MPS = `reference/missions_f_warlords/`. `<S>` means WEST or EAST.

Already covered, not repeated: `docs/runs/2026-11-08-overnight-build/notes/sectors-server-flow.md`, `purchases-fasttravel.md`, `ai-control-loop.md`.

**Correction to the older notes:** `sectors-server-flow.md` section 2 says the capture bonus goes to the losing side. It goes to the capturing side (SHS:264-271). `purchases-fasttravel.md` is right.

## Summary of answers

| Question | Answer | Mission-side? |
|---|---|---|
| Pause and decay the countdown | No command sets a running countdown. Bank progress ourselves and shorten the native trigger's timeout between countdowns | Yes, needs an engine test |
| Capture a non-target sector natively | Add it to `BIS_WL_conqueredSectors_<S>`. Warlords' own trigger then seizes it | Yes, with extra steps (1.5) |
| Block respawn in a seized sector | Players already only respawn at base. Only AI warlords teleport into sectors; correct them just after respawn | Yes, after-the-fact only |
| Force a new target or vote | Set the voting-reset flag and name publicly. Works for AI and human sides, and is free | Yes |
| Change prices at runtime | Static through mission config; runtime by patching each client's `BIS_WL_purchasable` | Yes, client-enforced only |
| Gate assets at runtime | Rewrite `BIS_WL_sectorSpecial` and trigger a recalculation | Yes |
| Raiders being killed | The same conquered-list entry disables all three kill loops | Yes |
| Time-limit round end | Write the loser's base owner, which fires the vanilla ending | Yes, needs `MissionEnd` > 0 |

## 1. Seizing

### 1.1 Who runs it

One SHS instance per sector, on the server. It starts the first time a sector is selected (SelServer:175, :356), or at init for bases (Init:137). Guarded by `BIS_WL_handleServerRunning`.

It makes four triggers (SHS:76-79), a square of half-side Size/2 (:90). Each gets `setTriggerTimeout` with min T/3, mid T/1.5, max T, interruptible (:91-92). T is `BIS_WL_timeoutBase`, read only here at init, so changing that variable later never changes capture timing. T comes from SectorsSetup:83, :114-123.

The trigger objects are not stored for WEST or EAST. Only the scan trigger (:82) and the GUER seize trigger (:83) are. W, E and G triggers carry `BIS_WL_parentSector`, set non-public (:89), so a server script can find them by that variable and the first element of `triggerActivation`.

### 1.2 Attacker and defender counting

There is none in script. It is the engine's `<side> SEIZED` activation. The conditions are crossed by name: the trigger stored as West's uses EAST SEIZED and vice versa (SHS:132-143). Empirical thresholds are in `sectors-server-flow.md` line 236.

Condition for side X: X has engine control AND (the sector is in `BIS_WL_conqueredSectors_X` OR is `BIS_WL_currentSector_X`), or X already owns it (:132-143). These are evaluated live.

Consequence: **a sector ever in a side's conquered list can be retaken by that side without being its target.** This is vanilla and is the lever raids should use.

### 1.3 Countdown and reset

Interruptible trigger: when the condition drops, the engine resets the countdown.

A 3 s mirror loop runs per trigger, forever (SHS:94-122):
- While `triggerTimeoutCurrent` is 0 or more and the side does not own the sector, it publishes the value to `BIS_WL_timeoutCur_<side>` on the sector.
- On the first sample after a reset, it overwrites the public `BIS_WL_timeoutBase` with the rolled value (:109).
- Otherwise it writes -1 publicly (:112-119).

The loop has no reachable handle. **Anything we write to `BIS_WL_timeoutCur_<S>` while the native trigger is not counting is overwritten within 3 s.**

The seizing bar (`SeizingBarHandle.sqf:16, :37-38`) reads those two variables. It takes the first non-negative side in W, E, G order and hides if colours match (:51). It is shown by SelClient (:301, player inside, sector not in conquered) and by SHC's reclaiming path (:161-166, player inside, sector in conquered).

### 1.4 What happens on capture

The trigger's on-activation does exactly one thing: publishes `BIS_WL_sectorSide` = X on the sector (:135, :141). Everything else reacts to that variable.

Server (SHS `side_changed` links :180, :305, :442 to `reposition` :253-277):
- Recomputes `BIS_WL_sectorsArrayWEST/EAST` on the server (:261-262). These lists are per-machine; clients rebuild theirs in RecalculateServices:11-13.
- Pays 10 x value x `BIS_WL_CPIncomeMult` to every warlord of the capturing side, capped by maxCP, once per side per sector (`_paidOff`, :264-271).

Client (SHC `changed` links :188, :252, :291, :556 to `SectorUpdate.sqf`):
- Marker colours (:16-20), icon (:22), `BIS_WL_recalculateIncome` (:24), RecalculateServices (:25).
- Popup and sounds (:27-44), task succeed for the new owner (:32).
- Task-succeed on a sector with no task hits a debug-only error branch (`SectorTaskHandle.fsm` around :175). Harmless.

Selection (SelServer `sector_seized` :221, :390 to `update_vars` :233-246):
- Appends to conquered, clears `BIS_WL_responseArr`, publishes, nulls the target, calls UpdateAO, refreshes `_ownedPrev`, runs the AI scan.
- This runs only when the side's own current target is taken. Enemy capture of your target does not clear your target.

Links and available targets are not stored. `SectorListing.sqf` derives them from `BIS_WL_sectorSide` and `BIS_WL_connectedSectors` whenever called.

### 1.5 Hook (a): pause and decay

No engine command sets a running countdown **(inferred; the Bohemia code uses only `setTriggerTimeout` and `triggerTimeoutCurrent`)**. Non-interruptible mode would make any momentary control a certain capture **(inferred)**.

Recommended: **keep the native trigger as the capture authority** and shorten what is left.

1. On the server, find the sector's W and E triggers (`nearestObjects` at the sector for `EmptyDetector`, filtered by `BIS_WL_parentSector` and activation).
2. Poll `triggerTimeoutCurrent` fast (EachFrame or under 1 s), only on contested triggers.
3. Bank progress as nominal minus the last remaining value. On interruption, decay it at the tunable rate.
4. While the trigger is not counting, call `setTriggerTimeout` with remaining / remaining / remaining / interruptible, so the next countdown is only what is left.
5. On the first sample after a resume, write `BIS_WL_timeoutBase` back to the nominal value, since the mirror will have replaced it (:109). Otherwise the bar misreads.
6. On ownership change, restore the timeout on both triggers.

Details:
- Use min = mid = max to remove the random roll. **Nominal should be T/1.5**, the vanilla mid, or first captures become slower than vanilla on average.
- Clamp remaining to a small floor such as 5 s.
- While paused, the native bar hides because the mirror writes -1. "Holding" needs our own UI.
- Part B's "settle first" point: a restarting countdown counts as progress if the commander reads banked progress from this same tracker, not from `BIS_WL_timeoutCur`, which is 3 s stale and goes to -1 on every interruption.

Rejected: neutralising the native triggers with `setTriggerStatements` and running our own countdown. The mirror still fights our values, and it reimplements more. A private sensor trigger (`X SEIZED`, no timeout) is a clean way to read control for commander logic, independent of the native trigger's state.

### 1.6 Hook (b): raid capture on a non-target sector

Use native seizing, not a parallel system. Sequence:

1. **Server FSM.** If `BIS_WL_handleServerRunning` is false, call `BIS_fnc_WLsectorHandleServer` on the sector, as SelServer:175 does.
2. **Client FSMs.** If not yet activated, do what SelServer:176-182 does: set `BIS_WL_sectorActivated` publicly, publish `BIS_WL_newlySelectedSector` (ClientInit:55-59), and start the local handle on a hosting machine, because a public-variable event handler does not fire for the sender. Without client FSMs, no marker, popup or bar changes happen.
3. **Enable.** Append the sector to `BIS_WL_conqueredSectors_<raider>` and `publicVariable` it. This opens native seizing and lifts all kill zones (section 5).
4. **Slow it.** Find the raider's trigger, set its timeout to 2-3x nominal. Restore when the raid ends.
5. **On capture**, all of 1.4's server and client effects fire natively. The `update_vars` work does not, because the sector is not the target. We must clear `BIS_WL_responseArr` ourselves. UpdateAO is optional, and see the warning below.
6. **On expiry or failure**, remove the sector from the list and publish, but only if we added it. Give raiders a grace period first (section 5).

Direct fallback: the one write `BIS_WL_sectorSide` = X, public, is identical to the native on-activation. Use it only for a sector whose trigger cannot be made to work.

Warnings:
- **`nothing_1` trap.** Preset non-GUER sectors enter `nothing_1` (SHS:203, :396-420), whose only exit is `selected_by_other`. It has no `side_changed` link. Raiding such a sector gets no server reaction: no payout, and no recompute of the server's sector arrays, which AI voting reads (AICore:426). Sectors captured during play have passed `populate` and react normally. Either restrict raids to sectors known to have left that state, or do the payout and recompute ourselves. Detecting it means reading the FSM state, or tracking ownership changes ourselves.
- **UpdateAO resets votes.** It writes `BIS_WL_lastSectorCnt_<S>` (`UpdateAO.sqf:10`). The vote-compromise links compare `_ownedPrev` to it (SelServer:145, :257, :339), so calling it while a vote timer runs resets that vote (:286-311). Call it only when no vote timer is running.
- **Conquered-list side effects:** sector scan allowed (`RequestSectorScan.sqf:32`), seizing bar for raiders inside, `SendResponseTeam.sqf:9`, lock markers look unlocked on the raider's clients, and a retake right that persists if we do not remove it.
- `_paidOff` means re-capture by the same side pays nothing. Consistent with vanilla but it will surprise a raid-reward design.
- Stealth holds natively: "incoming" alerts fire only for the current target (SHC:207-210). `BIS_WL_timeoutCur_<S>` is public, but only the bar reads it.

## 2. Respawn

**There are no sector respawn points in vanilla.** Mission respawn is BASE with delay 20 (`MPS/defaultDescription.inc:8-9`). Markers `respawn_<side>` and `_1` to `_14` exist only at bases (Init:451-470). When a base is targeted, SHS moves them to a random non-water ring at Size/2+300 (:317-350) and returns them afterwards (:488-496).

So players already respawn outside a seized sector, including their own base. Nothing is needed for them. The ClientInit Respawn handlers (:490, PlayersTracking:21) only reattach helpers.

The Balavu mechanism is AI only. On respawn, Init:130 restarts AICore, whose first state (`status_`, AICore:324-328) teleports the AI warlord beside a living subordinate if the group has more than one alive and its base is not targeted.

Hook:
- `status_` cannot be blocked from mission script. Correct it just after.
- Use a server `EntityRespawned` mission handler or the commander loop. For a short window after respawn, if an AI warlord is inside a sector its side owns and which is being seized, move it to the nearest owned sector not under attack, or base.
- "Being seized" should come from section 1.5's tracker or a private sensor, not the 3 s mirror.
- The FSM step runs after the EH **(inferred)**, so check over a couple of seconds rather than once.
- The AI's other ways in also need the same check: free defend fast travel and bought men, per `ai-control-loop.md`. This is one post-move check in one loop rather than separate fixes.
- Commander-owned groups are already ours to direct.

Fragile: the correction is after the fact, so a unit is briefly inside the area and can count for the engine's SEIZED check for a moment.

## 3. Target and voting

`ai-control-loop.md` and `sectors-server-flow.md` cover the normal flow. New points:

### How a reset works

- `BIS_WL_sectorVotingReset_<S>` is read only in `evaluate_sector` and `process_sector` (SelServer:210, :401).
- **If set while the target is null it stays TRUE and instantly resets the next target.** Always guard on a non-null target.
- `reset_1` (:413-422) clears the flag on the server after 1 s (not publicly), nulls and publishes the target, calls UpdateAO. Clients clear their own copy (SelClient:492-494).
- It does not raise `BIS_WL_resetVoting` and does not clear votes.
- It then returns to `at_least_one_vot` and `run_timer` (:433-439). Voting reopens for humans through `no_sector_select` and `initialize_sector` (:142-152).
- Client effects (SelClient `popup_msg` :492-520): "Reset" sound, relock marker, delete task, a 60 s grace on the ZR trigger (:509-514), popup.
- The popup waits for `BIS_WL_sectorVotingResetName_<S>` to be non-empty, then shows it inside `STR_A3_WL_popup_voting_reset_user`, then clears it locally. **A mission must set the Name publicly**, or each client on that side keeps a spawned wait that fires on a later reset. The text it inserts is a player name, so choose something that reads sensibly, such as a commander title.

### Answers

- **AI side:** yes, the same flag works. AICore's `seized` links see it (AICore:629, :827, :962, :1178, :1384). The `fight` state has no such link and lasts 3 s, so an AI warlord can miss the 1 s window. The commander votes anyway, so this matters little.
- **Human side, free or timer-reopened:** the server sets flag + Name publicly when the timer expires. Free, no menu entry required, no client patch.
- **The paid menu entry:** appears only if `BIS_WLVotingResetEnabled` is 1 at parse (ParseAssetList:153; lobby default 0, `cfgMissionParams_subclasses.inc:36-41`). Availability needs a non-null target and 300 s since selection (Availability:40-46).
- **`CfgWLAssetCostOverride >> ResetVoting`** must be above 0 (VarsInit:56), so **config cannot make it free**; 1 CP is the floor. A client could set its own `BIS_WL_votingResetCost` to 0 at runtime (read at RequestVotingReset:9), but the server-set flag is simpler. Recommend leaving the menu entry off.

### No ping-pong

`BIS_WL_sectorsArray<S> # 1` will still include the abandoned sector. The server can veto by clearing a vote for a banned sector on AI warlords. For players, a client loop during voting can set `BIS_WL_available` FALSE on that sector's pointer group, which the click handler checks (SectorSelectionStart:43, :53). It must run after the 1 s delay at Start:29 sets it TRUE.

### Are our helpers correct and complete?

**`SWLC_fnc_adForceRevote`**: correct for its one call site, not complete in general.
- It sets the same flag vanilla does (RequestVotingReset:11). The caller (`commander.sqf:135-141`) only fires on a non-null target and an all-AI side, so today's use is valid.
- Missing for human sides: the public Name variable.
- Should be made self-guarding on a non-null target rather than trusting the caller, given the null-target hazard above.
- No record of the abandoned sector, and no handling of units left inside it (next point).

**`SWLC_fnc_adClearVotes`**: correct for what it does, which is not a vote reset.
- Clears AI warlords' votes after a new target is set (`commander.sqf:128`), and rightly leaves players alone (SectorSelectionEnd:19, :26 clear theirs).
- It is needed because AICore only spawns its own clear from the `vote` state (:439-443), and commander-cast votes may bypass that.
- `BIS_WL_disconnectedVotes_<S>` is cleared by SelServer (:169, :289), so that is not a gap.

**Related problem in `SWLC_fnc_adCastVotes`:** it only writes when the vote is null. AICore votes randomly at `run_timer` plus delay (AICore:548-551; 0.2 to 0.7 of `BIS_WL_selectionTimeout`, so 3 to 10.5 s at the lobby default of 15). If the FSM gets there first the commander's choice is dropped, which could pick a banned sector. Overwrite for target switches.

**Attackers die on a target switch.** Clearing a target with attackers still inside exposes AI to the server kill loop within 20 s, because the sector is then neither target nor conquered (section 5). Vanilla's 60 s grace is client-side only, covering players' AI. Withdraw first, or temporarily add the sector to the conquered list while also lengthening the trigger timeout so they cannot finish the capture.

## 4. Income and purchasing

### Income

- `CalculateIncome.sqf:13-15` sums value x mult over all owned sectors, not only linked ones.
- `SectorFundsPayoff.fsm:46-54` pays that full amount to **each** warlord on the side every 60 s (VarsInit:27), capped by maxCP. So a side's total scales with warlord count; a "same for both sides" flat income is per warlord.
- Capture: 10 x value x mult, capturing side (1.4).
- Kills: `HandleRating` handlers pay rating/20 when rating is above 100. AI warlords Init:121-126, players ClientInit:138-140, purchased units pay their leader Airdrop:62-72.

Hook for the new income curve. **Recommended: write per-sector `BIS_WL_value` publicly so the vanilla sum equals our curve.** A sector's value only matters to its current owner, so one write per sector per ownership change suffices. Put the flat base on the base sector. Vanilla payout then keeps running and the client's income display stays right after `BIS_WL_recalculateIncome` is set TRUE on clients. Costs: sector labels are built once at init and go stale (SectorsCommonInit:58), and the capture bonus scales with the same value, so write before capture or pay it ourselves.

Alternative: set server-side `BIS_WL_CPIncomeMult` to 0 and pay everything ourselves. Kills both payout and capture bonus, but client UI shows the wrong income (FundsInfo:92-94).

Combat bounties: add on top of vanilla's rating payout through a server `EntityKilled` handler. Removing the existing handlers is awkward, because the player ones are local to each client.

### Requisition lists and gating

- `ParseAssetList.sqf` runs at Init:432 (per-unit presets :132-134, :438-439). It merges config and mission presets (:10, :14). Requirements must be in `BIS_WL_scenarioServices` (:28; built at SectorsSetup:205). Result: `BIS_WL_purchasable<S>` (:159) or the unit's own variable (:161). Indexes 0 infantry to 7 services; entries hold class, cost, requirements and more.
- Gate: `Availability:59` checks requirements against the client's `BIS_WL_servicesAvailable`, rebuilt from all owned sectors (RecalculateServices:14-18), so **not** supply-linked. Recalculated only at SectorUpdate:25, SelClient:199, and init.

### Runtime changes

- **Static price, no addon: yes.** `CfgWLAssetCostOverride` by class (ParseAssetList:31-36) or a mission `CfgWLRequisitionPresets`. West and East use different classes, so this is per-side already.
- **Runtime price or gating per side:** patch `player getVariable "BIS_WL_purchasable"` on each client. There is Bohemia precedent: `MPS/commonInitScript.sqf` strips Jets assets exactly this way. The menu takes cost from the entry when the list is built (SetItemsList:14), so an open menu is stale until the category is reselected.
- **Capability gating and supply lines:** on the server, rewrite `BIS_WL_sectorSpecial` publicly when a chain is cut or restored, then remoteExec `BIS_fnc_WLrecalculateServices` on that side's clients. Only the owner reads a sector's value, so one write suffices. `AircraftArrival:17-22` reads it for arrival position and falls back to base, so it does not break.
- **New letters** beyond A, H, W must be present in `BIS_WL_scenarioServices` at parse, and the map labels only draw A, H, W (SectorsCommonInit:93-95).
- **Cheaper when cornered:** the client patch has no idea where the buyer stands unless the same client loop checks that. Do the position test there.

**Purchases are entirely client-side.** `RequestPurchase:21` deducts locally and there is no server validation. The AI path ignores requirements. Our gates are honest-client gates and are not enforced. The commander prices its own buys, so it must apply these rules itself.

### Squad caps, rearm, repair

- `BIS_WL_maxSubordinates` default 9 (VarsInit:46). Client `BIS_WL_matesAvailable` starts at half (VarsInit:197). `Reputation.sqf` loses 1 per man lost, gains 1 per 120 s, capped by the max, which is read live (:16-21). So a town bonus can write the max on the client. The check is Availability:60. AI uses min(4, max) per the AI notes.
- No rearm or repair service exists. They are bought assets: crates (`MPS/config.cpp` around :286-314) and support trucks (around :176-204).
- Last Loadout and Arsenal already require standing in an owned sector (Availability:31-35, :48-52). Defences similar (:71-75).
- Stretched supply has no vanilla hook. Do it by removing those entries through the client patch based on the player's position, plus our own control of `setRepairCargo` and similar on the objects.

## 5. Restricted areas

Three kill paths, all checking "in conquered list OR is current target":

1. Server loop per sector, every 20 s, kills AI and vehicles inside the Size/2 square (SectorsSetup:89-113). A bug keeps only the last non-player warlord's units in its exemption list (:96-98), so its behaviour with several AI warlords is rough.
2. Client loop per sector, for sectors not the player's side at init, kills the player inside Size/2+Border after 20 s (SectorsCommonInit:122-151; InSectorArea:24-25; Border default 200).
3. Client ZR trigger kills AI members of the player's group after 20 s (SectorsCommonInit:63-72).

**A public append to `BIS_WL_conqueredSectors_<S>` turns all three off.** It is the same write as raid step 3, so there is nothing further to change.

Removing the entry re-arms all three immediately, so a raid expiry must give raiders time to leave. Emulate vanilla's 60 s grace (SelClient:509-514) by keeping the entry for a minute after expiry, with the trigger timeout set very long so they cannot finish the capture during it.

Being outside the Size/2 square is not enough for players; they need to be beyond Size/2+Border.

## 6. Round end

Init:475-514: only if `MissionEnd` is above 0 (default 0, Init:43; Tanoa sets it). Every machine waits for either base's `BIS_WL_sectorSide` to stop being its own side (:478). A dedicated server calls `endMission "End1"` (:480); otherwise each client runs victory or defeat by side. SelClient `game_over` links react too (:108 etc.).

Hook: a server loop for the time limit. At expiry, count `BIS_WL_sectorSide` over `BIS_WL_sectors`, then publicly write the loser's base `BIS_WL_sectorSide` to the winner. That fires the vanilla ending everywhere with the right music and debrief.

Ties need a rule. Suggest higher total `BIS_WL_value`, then a short sudden-death extension, since vanilla has no draw path.

## Riskiest assumptions

1. **`setTriggerTimeout` takes effect between countdowns on an interruptible trigger, with no side effects from the roll.** The whole pause-and-decay design rests on it. Test first.
2. **`triggerTimeoutCurrent` polling catches the last remaining value before reset**, and very brief interruptions behave sanely with a short remaining time.
3. **`nothing_1` sectors** really are unreactive, and we can tell which sectors are in that state. Preset sectors raided early are the case to test.
4. **Starting SHS and SHC late**, outside the selection flow, leaves those FSMs in a good state and does not surprise players with visible side effects, particularly `BIS_WL_newlySelectedSector` on a hosted machine.
5. **Conquered-list side effects**: scans, the retake right, lock markers and SendResponseTeam, particularly if a raid is removed while a unit is inside.
6. **Post-respawn correction arrives before the moved unit decides a seizure**, given it is briefly inside the area.
7. **`BIS_WL_value` rewrites** do not disturb anything else that reads them; I found the income, capture and label uses only.
8. **Compile-final:** I assumed `BIS_fnc_WL*` cannot be replaced from a mission (`functions_f_warlords/config.cpp` registers them through CfgFunctions), so everything above avoids it **(inferred)**.
9. **Client-enforced gates** are good enough. Nothing server-side stops a modified client from buying anything, in vanilla as well.
