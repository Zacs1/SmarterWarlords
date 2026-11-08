# LAMBS Danger: how the commander should use it (Part H.5)

Source: LAMBS **stable** Workshop item 1858075458 only. PBOs are version 2.6.2.1 (git 711f433, built with HEMTT 1.19.1). They were unpacked to the gitignored `reference/lambs_stable/lambs_{main,danger,wp,eventhandlers,formations,range}`. CBA was only inspected (Workshop item 450814997, v3.19.0): file lists and strings in its binarized `config.bin`.

File references are relative to `reference/lambs_stable/`. `wp/` is `lambs_wp/functions/` and `danger/` is `lambs_danger/functions/`, unless a longer path is given.

**How far this can be trusted.** This is all from reading code. Arma was not run, so nothing here is confirmed in game. Each PBO has readable `.sqf` plus compiled `.sqfc` duplicates. I read the `.sqf` and did not check that the `.sqfc` matches. `.fsm` and `config.cpp` are readable. CBA's `config.bin` is binarized, so only its strings and file names were used. LAMBS is GPL: this file paraphrases and names only functions and variables.

## Recommendation in brief

1. Detect once at init (section 1). No LAMBS means today's behaviour, unchanged.
2. When LAMBS is present, **stop re-applying `setBehaviour`/`setSpeedMode`/`setFormation`/`setCombatMode` while a group is reacting**. Split `SWLC_fnc_adApplyOrder` into waypoint repair (always) and the four `set*` commands (only when not busy). This is the most important change, because those four commands undo LAMBS' tactics on every guard re-apply.
3. Use LAMBS for sector tasks only: `lambs_wp_fnc_taskCQB` to clear, then `lambs_wp_fnc_taskGarrison` to hold. Call them directly on server-local groups and keep the script handle. CQB never ends by itself, so the commander must detect completion, terminate it and clean up (section 2).
4. Under LAMBS, turn off our suppress-and-flank. Keep bounding for pre-contact movement only. Keep rearming, gated on not busy and protected with `lambs_danger_forceMove` (section 4).
5. Never use `lambs_wp_fnc_taskRush`, `taskHunt`, `taskCreep`, `taskCamp` or `taskAssault` on commander groups, and never `taskGarrison`/`taskDefend` with patrol on.

## 1. Runtime detection and how functions are reached

**CfgPatches classes**
- `lambs_main` (requires `cba_main`, requiredVersion 2.18), `lambs_danger` (requires `lambs_main`), `lambs_wp`, `lambs_eventhandlers` (requires `lambs_danger`), `lambs_formations`. Source: each PBO's `config.cpp`.
- LAMBS tests for its own waypoint module with an `isClass` check on `lambs_wp` under `CfgPatches`, stored in `lambs_main_Loaded_WP` and `lambs_danger_Loaded_WP` (`lambs_main/XEH_preInit.sqf`, `lambs_danger/XEH_preInit.sqf`).
- CBA: `cba_main`, `cba_common`, `cba_events`, `cba_xeh` appear as patch-name strings in the respective binarized `config.bin` files (`cba_main.pbo`, `cba_common.pbo`, `cba_events.pbo`, `cba_xeh.pbo`). `cba_main` is also the name LAMBS requires.

**How functions are compiled**
- LAMBS functions are **not** in CfgFunctions. Each PBO's `XEH_PREP.hpp` uses the PREP macro (`lambs_main/script_macros.hpp`), which goes through `CBA_fnc_compileFunction` at XEH preInit. So `lambs_wp_fnc_*`, `lambs_danger_fnc_*` and `lambs_main_fnc_*` are ordinary `missionNamespace` globals by mission init, and are callable from server mission script.
- The danger FSM needs no call. It is set by config: `fsmDanger` on `SoldierWB`/`SoldierEB`/`SoldierGB` (`lambs_danger.fsm`) and on `Civilian_F` (`lambs_dangerCivilian.fsm`), in `lambs_danger/config.cpp`.
- CBA functions in use: `CBA_fnc_directCall`, `CBA_fnc_waitAndExecute`, `CBA_fnc_waitUntilAndExecute`, `CBA_fnc_addPerFrameHandler` (files in `cba_common.pbo`), `CBA_fnc_targetEvent`, `CBA_fnc_localEvent`, `CBA_fnc_addEventHandler` (files in `cba_events.pbo`), `CBA_fnc_compileFunction` (file in `cba_xeh.pbo`).

**Recommended check (cache one boolean at init, after preInit)**
- `isClass` on `lambs_danger` and `lambs_wp`, and `lambs_wp_fnc_taskGarrison` and `lambs_wp_fnc_taskReset` both non-nil.
- CBA: `isClass` on `cba_main`, and `CBA_fnc_directCall` non-nil. LAMBS cannot load without CBA, so CBA is implied, but the check costs nothing.
- `lambs_main_versionLoadedOnServer` is public on the server if the version needs logging (`lambs_main/XEH_preInit.sqf`).

**Events (optional, not needed for the recommended design)**
- `lambs_wp/XEH_preInit.sqf` registers CBA events on every machine (no `isServer` guard): `lambs_wp_taskAssault`, `taskCamp`, `taskCQB`, `taskCreep`, `taskGarrison`, `taskHunt`, `taskPatrol`, `taskReset`, `taskRush`, `taskDefend`, `taskCampReset`. The modules fire them with `CBA_fnc_targetEvent` targeted at `leader _group` (`lambs_wp/functions/Modules/fnc_moduleCQB.sqf`, `fnc_moduleGarrison.sqf`, `fnc_moduleReset.sqf`).
- This route is the only way to reach a group local to another machine, but it returns no script handle. That rules it out for anything that has to be cancelled.
- Observation hooks: `lambs_danger_OnContact` (unit, group, enemy), `OnAssess`, `OnReinforce`, `OnArtilleryCalled` (`lambs_danger/XEH_postInit.sqf`); `lambs_main_OnInformationShared`, `OnCheckBody`, `OnPanic`, `OnFleeing` (`lambs_main/XEH_postInit.sqf`). They are delivered locally by `lambs_main_fnc_eventCallback`. `danger/fnc_contact.sqf` fires a lower-case `onContact` while the registered name is `OnContact`; whether CBA treats these as the same was not verified, so do not depend on it.

## 2. Garrison and building clearing

All tasks accept a unit or a group, and **silently return false if the group is not local** (each `wp/fnc_task*.sqf`). Defaults come from `lambs_wp/script_component.hpp`.

### `lambs_wp_fnc_taskGarrison` (`wp/fnc_taskGarrison.sqf`)
Parameters: group, pos (default group position), radius 50, area, teleport false, sortByHeight false, exitCondition, patrol false.

- Runs once with no loop. If called where suspension is allowed, it wraps itself in `CBA_fnc_directCall`. No script handle to manage.
- Mixes orders and one waypoint. It sets the group SAFE, `enableAttack false`, and `lambs_main_currentTactic`. Each unit gets `doStop`, then `doMove` to a building position. A `CBA_fnc_waitUntilAndExecute` waits on `unitReady` (no timeout), then applies `disableAI "PATH"` and a `setUnitPos` stance if within 1.5 m, otherwise `doFollow`. Statics use `assignAsGunner` and `orderGetIn`.
- It **appends** a HOLD waypoint. It does not clear existing waypoints or make HOLD current, so clear first and set it current.
- Exit handlers are stored in the unit variable `lambs_wp_eventhandlers`.

Traps:
- **exitCondition.** The file header is off by one. In the code: 0 none, 1 Hit, 2 Fired, 3 FiredNear, 4 Suppressed, -1 all, -2 random. The default is the macro `TASK_GARRISON_EXITCONDITIONS - 2`, which evaluates to -4 and matches no case, so **a default call installs no exit handlers**. Pass -1 explicitly. The handler re-enables PATH and sets combat mode RED.
- **Too few positions.** The list is resized and the extra units (leader end) get no orders. Zero positions still returns true with HOLD added. Count first with `lambs_main_fnc_findBuildings` (`lambs_main/functions/fnc_findBuildings.sqf`, marked Public).
- **patrol true** creates a new group (`lambs_wp_baseGroup`). It would show up as a new ownable group, so do not use it.

### `lambs_wp_fnc_taskCQB` (`wp/fnc_taskCQB.sqf`)
Parameters: group, pos, radius 50, cycle 21, area, useWaypoint false.

- Scheduled loop. It spawns itself only if called unscheduled, so a scheduled caller **blocks**. Always `spawn` it and store the handle.
- Uses `doMove` and no waypoints. Sets speed FULL, FILE, `enableAttack false`, `allowFleeing 0`.
- Each unit gets `lambs_danger_disableAI` true and `disableAI` for AUTOCOMBAT and SUPPRESSION, and IR lasers. So **the danger FSM is off during clearing** (no overlap with section 3 reactions, but also no LAMBS cover or flanking).
- **The loop only ends when all units are dead.** Running out of buildings just continues at 1 Hz doing nothing, so its end-of-task reset is effectively unreachable. The commander must decide completion and terminate.
- Each building gets `lambs_main_CQB_cleared_<side>` (for example `..._WEST`). It is set locally and never cleared, so **a sector recaptured later counts as already cleared** unless we nil the variable on nearby buildings first.
- Nudges stuck units by teleport when no player is within 50 m.

### `lambs_wp_fnc_taskDefend` (`wp/fnc_taskDefend.sqf`)
Parameters: group, pos, radius 75, area, teleport false, useCover 0 (a number despite the header saying BOOL: 0 all, 1 buildings, 2 walls, 3 vegetation, 4 buildings+vegetation, 5 buildings+walls, 6 walls+vegetation), stealth false, patrol false.

- Spawns. Sets `lambs_danger_disableGroupAI` true, clears waypoints, adds HOLD, runs a CBA per-frame handler every 8 s plus a scheduled loop.
- Ends when the group's **waypoint count changes** or all are dead, then removes the handler and runs `doAssaultUnitReset` per unit. This is the cleanest cancel of any task, but our guard rewriting waypoints would end it by accident, and `lambs_danger_disableGroupAI` is left true.
- Returns false after setup if no positions are found. Does not disable PATH.
- A reasonable fallback when a sector has too few building positions.

### Others, and why not
- `taskAssault` (`wp/fnc_taskAssault.sqf`): units do not engage (TARGET, WEAPONAIM, FSM disabled and `lambs_danger_forceMove` set). Unusable in a defended sector.
- `taskRush`, `taskHunt`, `taskCreep` (`wp/`): loops until all dead that chase the nearest enemy, taking the group off the commander's plan.
- `taskCamp` (`wp/fnc_taskCamp.sqf`): idle animations with ANIM and PATH disabled. Not suitable.
- `lambs_wp/CfgWaypoints.hpp` still has waypoint types (Attack, Retreat, Garrison, Patrol) but labels them deprecated in favour of modules. `lambs_wp/scripts/fnc_wpGarrison.sqf` is just a spawn of `taskGarrison`, which adds nothing over calling it directly.

### Stopping: what `lambs_wp_fnc_taskReset` does and misses (`wp/fnc_taskReset.sqf`, marked Public)
Parameters: group, softReset false, resetWaypoints false.

It clears `lambs_danger_disableGroupAI`, `lambs_danger_enableGroupReinforce`, and the taskAssault group variables. For each non-player unit it does a `doMove` to self, enables MOVE, PATH, COVER, SUPPRESSION, FSM, TARGET, AUTOTARGET and ANIM, sets `forceSpeed -1` and `setUnitPos AUTO`, plays a reset animation (a visible snap), clears `lambs_main_currentTask`, `currentTarget`, `lambs_danger_disableAI`, `lambs_danger_forceMove`, removes the `lambs_wp_eventhandlers` handlers, and does `doFollow`.

**The hard reset (the default) makes a new group and joins everyone to it**, so all `SWLC_*` group variables are lost. Always pass softReset true.

It does **not**:
- Stop scheduled task loops. CQB, Rush, Hunt and Creep keep issuing orders under a soft reset. Terminate the stored handle.
- Re-enable AUTOCOMBAT, WEAPONAIM or FIREWEAPON. CQB disables AUTOCOMBAT, so a group left like this will not go to combat by itself.
- Clear `lambs_main_groupMemory`, `lambs_danger_isExecutingTactic`, `lambs_danger_contact` or the CQB cleared flags.
- Unassign static gunners or restore `enableAttack`.
- Cancel pending `CBA_fnc_waitUntilAndExecute` callbacks. A garrison callback can re-disable PATH after the reset if the unit is within 1.5 m of its spot.

**Cancel recipe (`SWLC_fnc_adLambsRelease`, proposed)**
1. `terminate` the stored CQB handle.
2. Call `taskReset` with softReset true and resetWaypoints true (or a lighter version of our own that avoids the animation snap).
3. On each unit: enable AUTOCOMBAT, WEAPONAIM, FIREWEAPON, PATH. Unassign and eject statics.
4. On the group: nil `lambs_danger_disableGroupAI` and `lambs_main_groupMemory`, and set `enableAttack` as we want it.
5. Mark the group released, apply our order, and **sweep again about 5 s later** (re-enable PATH, re-apply the order) because of pending callbacks and LAMBS' delayed resets (section 3). The 5 s is a design guess, untested.

Run this before any `joinSilent` merge of a LAMBS-held group (the broken-group merge in `commander/swlc/smart.sqf`).

## 3. Danger handling

**How it takes over** (`lambs_danger/scripts/lambs_danger.fsm`)
- The engine runs the FSM per soldier on danger events. `Start_Danger` exits at once if `danger/fnc_isForcedExit.sqf` is true: `lambs_danger_disableAI` set, behaviour CARELESS, or MOVE disabled.
- Init checks `fnc_isForced` (fleeing, `lambs_danger_forceMove`, current command ATTACK/GET IN/ACTION/HEAL/REARM/JOIN, dead, ACE heal queue, player group option). If forced, the unit does not react.
- Otherwise on foot, `fnc_brain` picks Immediate (`brainReact`, dodge/cover), Hide (`brainHide`), Engage (`brainEngage`: within `lambs_danger_cqbRange`, default 60, with PATH enabled it assaults by `doMove` and `forceSpeed`; far and still and able to fire, it suppresses) or Assess (`brainAssess`).
- `End_Danger` does `forceSpeed -1` and nils `lambs_main_currentTask`, so **any `forceSpeed` of ours is wiped when danger ends**.
- `Check_queue` requeues while `lambs_main_groupMemory` is not empty.

**Group tactics** (`danger/fnc_tactics.sqf`, `fnc_contact.sqf`, `fnc_tacticsAssess.sqf`)
- A leader with suppression under 0.2 and not executing a tactic enters `fnc_tactics`, which exits if `lambs_danger_disableGroupAI` is set.
- `fnc_contact` runs once per `lambs_danger_contact` window: `enableAttack false`, formation, facing, weak MIDDLE stance, leader moves to cover. `fnc_tacticsAssess` sets `lambs_danger_isExecutingTactic` true and picks a plan.
- **Our defaults bias its plan.** With speed mode FULL it skips hiding from tanks and the soft-vehicle branches, and replaces SUPPRESS with ASSAULT. Most commander orders use FULL (default in `SWLC_fnc_adSetOrder`; explicit in `wave.sqf`, `smart.sqf`, `defence.sqf`). A current HOLD waypoint within 220 m gives the hide plan. No PATH or MOVE gives no plan, just hold.
- Each tactic captures old state and **restores it later** by a delayed reset:

| Tactic (`danger/fnc_tactics*.sqf`) | Sets | Reset after |
|---|---|---|
| Flank | FILE, leader FULL, forceMove, stance DOWN | up to 120 s; speed, formation, `doFollow` |
| Suppress | LINE | 45 s |
| Assault | LINE, FULL, `groupMemory` | 85 s; `enableAttack`, speed, formation |
| Attack | leader RED, DIAMOND | 60 s |
| Hide | LINE, WHITE | 240 s |
| Garrison | FILE | 180 s (not in the plan table) |
| Hold | | 45 s |

- `doGroupFlank` re-issues `doMove` every 11-19 s and `doGroupSuppress` every 6-8 s, skipping units with `lambs_danger_disableAI` (`lambs_main/functions/GroupAction/`).
- `tacticsReinforce` is the only part that touches waypoints (clears HOLD/GUARD/DISMISS, `_group move`) and behaviour (AWARE). It needs `lambs_danger_enableGroupReinforce`, which is off by default. **Do not set it.**
- Otherwise the danger module leaves waypoints and behaviour alone. So it does not cause our waypoint guard to fire, but our guard's re-apply does hit it.

**Disable switches**

| Variable | Scope | Effect | Source |
|---|---|---|---|
| `lambs_danger_disableAI` | unit | whole FSM off, and left out of flank/suppress | `danger/fnc_isForcedExit.sqf`, GroupAction files |
| `lambs_danger_disableGroupAI` | group | blocks only leader tactics/contact; individual reactions continue | `danger/fnc_tactics.sqf` |
| `lambs_danger_forceMove` | unit | no reactions while true | `danger/fnc_isForced.sqf` |
| `lambs_danger_disableAIAutonomousManoeuvres` | CBA setting, global | default false | `lambs_danger/settings.inc.sqf` |

**Which of our commands fight it**

| Command | Effect under LAMBS |
|---|---|
| `setBehaviour "CARELESS"` | FSM exits. Fine only when intended (for example transport legs). |
| `setBehaviour "STEALTH"` | Changes branches in `brainEngage` and paths. Avoid. |
| `setFormation`, `setSpeedMode`, `setCombatMode` in `adApplyOrder` | Directly undo LINE/FILE/WHITE/RED and tactic speed. **Main conflict.** Also LAMBS' delayed resets can restore older values over ours, so re-sync after a tactic ends. |
| `doMove` | Overrides LAMBS' `doMove`; LAMBS re-issues, so the two alternate. Do not send to a busy group. |
| `forceSpeed` | Wiped at `End_Danger`. Not reliable. |
| `setUnitPos` | Outranks LAMBS' `setUnitPosWeak`, blocking stance reactions. Use `setUnitPosWeak` or AUTO. |
| `disableAI "MOVE"` | FSM exits. `"PATH"` removes the unit from many branches. |
| `doSuppressiveFire` | Compatible. `doSuppress` skips units already suppressing. |
| Guard rewriting waypoints | Ends `taskDefend` and removes the garrison HOLD. |

`lambs_formations` also changes all Man units while loaded (`crouchProbability*` 0, `formationTime` 3, `formationX` 4.2, `brakeDistance` 1.5 in `lambs_formations/config.cpp`), so formation spacing and prone behaviour differ from the vanilla test run. Expect different numbers on bounding gates.

## 4. Concrete hand-off

**Busy predicate (proposed `SWLC_fnc_adLambsReacting`).** True if any of:
- group `lambs_danger_isExecutingTactic` is true (`danger/fnc_tacticsAssess.sqf`);
- group `lambs_main_groupMemory` is non-empty;
- any unit has non-nil `lambs_main_currentTask` or `lambs_danger_forceMove`;
- leader behaviour is COMBAT.

Hold it true for 10-15 s after the last positive (a design guess, untested). Do not rely on `lambs_main_currentTactic`, which is good for logging but is never reliably cleared. `lambs_main_FSMDangerCauseData` on a unit is an extra recent-danger signal if needed. These variables are set without broadcast outside debug, so read them where the group is local, which is the server.

**Changes to `commander/swlc/adapter.sqf`**
- `SWLC_fnc_adApplyOrder`: waypoints always, the four `set*` commands only when not busy, and when busy clears, apply them once.
- `SWLC_fnc_adGuardOrder`: same split. A waypoint-only repair must not touch the `set*` commands.
- Avoid FULL once a group is near contact, as it skews LAMBS' plans (section 3).

**Sector capture with LAMBS present**
1. Clear waypoints. Call `SWLC_fnc_adClearOrder` so the guard leaves the group alone (it only empties `SWLC_order`).
2. Nil `lambs_main_CQB_cleared_<side>` on buildings in the radius.
3. `spawn` `taskCQB`, store the handle on the group.
4. Poll: no uncleared buildings or a timeout. Then terminate and run the release recipe.
5. Check position count, then `taskGarrison` with exitCondition -1, teleport false, patrol false, and make HOLD current.
6. Fallback to `taskDefend` if too few positions.

A LAMBS-held group needs its own guard mode: **HOLD stays current, no `set*`**. Warlords requires this: `BIS_fnc_WLAICore` (`reference/functions_f_warlords/Warlords/fn_WLAICore.fsm`) runs per Warlord unit from `fn_WLInit.sqf`, and restarts on Respawn. Its INIT state deletes every waypoint except index 0. `fn_WLAIPathSegmentation.sqf` appends two SAD waypoints and makes the first current. That pulls a garrisoned group off HOLD, so garrisons need our guard as much as anyone. Which FSM states call segmentation in practice was not traced beyond the call sites (lines 502, 805, 1144, 1234).

**Per-squad behaviours**

| Behaviour | With LAMBS |
|---|---|
| Formation and speed choices | Only when not busy and pre-contact. Never during contact. |
| Bounding overwatch | Pre-contact only; abort and hand over when busy. Do not split teams into new groups. |
| Suppress and flank | **Off.** LAMBS does this. The gate can be checked through `lambs_main_currentTactic` values ("Suppressing", "Flanking") in the log. Calling `lambs_danger_fnc_tacticsSuppress` or `tacticsFlank` directly is possible but both are marked Public: No, so treat as unsupported. |
| Rearming | Only when not busy, one unit at a time. Set `lambs_danger_forceMove` on that unit for the trip and re-set it each tick because LAMBS' resets clear it; clear it on arrival or timeout. `REARM` as a current command is also treated as forced. |

## 5. Gotchas

**Locality and group ownership**
- Tasks exit false on non-local groups with no error, so check `local _group` and log when it fails. No `setGroupOwner` or `groupOwner` appears in the commander or the unpacked Warlords functions, so nothing moves groups deliberately, but a group's locality follows its leader.
- Only start tasks on AI-led groups local to the server, and treat a local (client host) server and a dedicated server the same way, by the `local` test. A player-led group is local to that player, so excluded. Under `SWLC_fnc_adOwnableGroups` (groups of `BIS_WL_allWarlords`) and the upcoming Part F borrowed groups, keep the player-group exclusions.
- `lambs_danger_disableAIPlayerGroup` is a client-scope setting and only applies to player-led groups (`lambs_danger/settings.inc.sqf`).
- A client with a different LAMBS version gets an endless hint/systemChat loop (`lambs_main/XEH_preInit.sqf`).

**Intel honesty**
- `lambs_main_fnc_doShareInformation` calls `reveal` between groups (default share range 200 m, radios 500 m, backpack radio +2000 m; `lambs_main/settings.inc.sqf`). So `knowsAbout` is inflated beyond what our soldiers actually saw, which matters for the design's "only what its soldiers have seen". `lambs_main_fnc_addShareInformationHandler` can observe or block sharing, and `lambs_main_radioDisabled` turns it off. Choose one deliberately.

**Performance (estimates; not measured)**
- Costs: one FSM per soldier in danger, target scans in `tacticsAssess`, raycasts in `isIndoor`, `allGroups` scan on share, per-unit waitUntil handlers in garrison, an 8 s per-frame handler per `taskDefend` group.
- Task loops pause while dynamic simulation has the leader disabled.
- Suggest capping concurrent `taskCQB` per side at a small number until it has been measured in the gates.

**Not verified**
- All in-game behaviour, including whether `_unit setCombatMode` in the garrison exit handler affects the whole group (it should, since that is a group command).
- Whether a hard-reset CQB loop hangs at 1 Hz on a null leader.
- The sections of `taskPatrol`'s header not read.
- Identity of `.sqfc` to `.sqf`.
