# Part H (smarter squads): integration notes

Drafted as new files only. `commander/swlc/squads.sqf` does nothing until the hooks below are in. Nothing has run in a live round yet.

## 1. Settings block for `settings.sqf`

```sqf
	// Part H: smarter squads. One switch per behaviour.
	["squadPosture", true],           // formation, speed and stance by situation
	["squadBounding", true],          // two fire teams leapfrog from the rally inward
	["squadFlank", true],             // pinned squads suppress and flank (always off while LAMBS is loaded)
	["squadRearm", true],             // soldiers low on ammo restock nearby
	["squadLambs", true],             // hand garrison and building clearing to LAMBS when it's loaded
	["squadSlices", 2],               // groups are worked through over this many commander ticks

	["squadPostureStates", ["Travelling", "Advancing", "Assaulting"]],
	["squadPostureHoldSeconds", 30],  // minimum time in a posture before leaving it, except to go careful
	["squadRoadTarget", 800],         // column on roads only further than this from the target
	["squadRoadContact", 600],        // and further than this from any recent sighting
	["squadRoadRadius", 30],          // how close a road has to be to count
	["squadRoadBehaviour", "AWARE"],
	["squadOpenFormation", "WEDGE"],
	["squadCarefulTarget", 350],      // slow down this close to the target
	["squadCarefulContact", 250],     // or this close to a recent sighting
	["squadCarefulExitExtra", 100],   // extra distance before leaving careful, so it doesn't flip
	["squadCarefulSpeed", "NORMAL"],

	["bpMinMen", 3],                  // too small to split below this
	["bpMinMetres", 50],              // length of one bound
	["bpMaxMetres", 100],
	["bpStartExtra", 100],            // starts this far outside the rally's distance to the target
	["bpStartMetres", 400],           // start distance if the op has no rally
	["bpInsideFraction", 0.5],        // ends this far into the sector, as a share of its half-size
	["bpCoverRadius", 25],            // cover this close to a bound's end point is used
	["bpReachMetres", 15],
	["bpPhaseSeconds", 30],           // a bound ends after this even if the team hasn't arrived
	["bpMaxSeconds", 180],
	["bpCooldownSeconds", 60],
	["bpCqbDist", 40],                // normal movement with a sighting this close
	["bpCqbRadius", 40],              // normal movement with this many buildings this close
	["bpCqbBuildings", 4],

	["pinnedSuppression", 0.25],      // average getSuppression that counts as pinned
	["pinnedSeconds", 45],            // and no progress for this long
	["pinnedMoveMetres", 15],         // what counts as progress
	["flankMinMen", 4],
	["flankOffset", 100],
	["flankMaxSeconds", 150],
	["flankGiveUpLoss", 0.5],         // gives up after losing this share of the squad
	["flankSuppressSeconds", 9],
	["flankCooldownSeconds", 120],

	["rearmCheckSeconds", 45],
	["rearmRadius", 60],              // how far a soldier will go for ammo
	["rearmReach", 4],
	["rearmTripSeconds", 45],
	["rearmPrimaryMags", 1],          // rifle magazines left that counts as low
	["rearmTakeRockets", 2],
	["rearmTakeRifle", 3],

	["lambsIntelMinKnows", 1.5],      // replaces intelMinKnows while LAMBS is loaded, see section 4
	["lambsBusyHoldSeconds", 12],     // keep treating a group as busy this long after LAMBS lets go
	["lambsMaxCqb", 2],               // groups clearing buildings at once, per side
	["lambsClearRadius", 150],
	["lambsMinBuildings", 2],
	["lambsCqbCycle", 21],
	["lambsCqbSeconds", 240],
	["lambsCheckSeconds", 12],
	["lambsRetrySeconds", 60],
	["lambsHoldDelay", 45],           // a defending group settles this long before garrisoning
	["lambsHoldReach", 40],           // and has to be this close to its spot
	["lambsHoldRadius", 75],
```

Add one cooldown to `radioCooldowns`: `["flank", 45]`.

## 2. Hook points

### `init.sqf`

- Add `"squads"` to the module list before `"commander"`.
- After the adapter's init, before the commanders start: `[] call SWLC_fnc_lambsDetect;`

### `commander.sqf`

- Stage list: add `"squadTick"` after `"smartTick"` and before `"cmdAssign"`. If stages are called as `[_cmd] call SWLC_fnc_<name>`, nothing else is needed.
- Guard, inside the `isNil` block, directly after the `adGuardOrder` call:

```sqf
if (!isNull _g) then {[_cmd, _g] call SWLC_fnc_squadLight};
```

### `adapter.sqf`: LAMBS-busy skip

Split the four set* commands out of `adApplyOrder`, so waypoints are always written and the commands wait while LAMBS has the group. New function:

```sqf
SWLC_fnc_adApplyStance = {
	params ["_g"];
	private _order = _g getVariable ["SWLC_order", []];
	if (_order isEqualTo []) exitWith {};
	if ([_g] call SWLC_fnc_lambsBusy) exitWith {_g setVariable ["SWLC_stanceDirty", true]};
	_g setVariable ["SWLC_stanceDirty", false];
	_g setBehaviour (_order # 1);
	_g setSpeedMode (_order # 2);
	_g setFormation (_order # 3);
	_g setCombatMode (_order # 4);
};
```

In `adApplyOrder`, replace the four set* lines with `[_g] call SWLC_fnc_adApplyStance;`.

In `adGuardOrder`, at the start of the `if (_intact) exitWith {` block, add this so the commands land once the group is free:

```sqf
if (_g getVariable ["SWLC_stanceDirty", false]) then {[_g] call SWLC_fnc_adApplyStance};
```

`lambsBusy` returns false at once when LAMBS isn't loaded, so the vanilla path costs one call.

### `smart.sqf`

Before the `joinSilent` in the merge in `smartBreakTick` (about line 60-73), for each group being merged in:

```sqf
[_x, false] call SWLC_fnc_lambsRelease;
```

### `defence.sqf`

In the "Defenders holding a spot shuffle as well" loop (about line 249), add to the condition:

```sqf
&& {(_g getVariable ["SWLC_lambsTask", ""]) == ""}
```

Without this the shuffle replaces a garrison's order every `reservePatrolSeconds`, which releases it.

### `status.sqf` (optional)

If the panel should show it, map `SWLC_squadTask` to "Bounding" and "Flanking", and `SWLC_lambsTask` to "Clearing buildings" and "Garrisoning". Those would be new player-visible strings.

### Borrowed groups

`squads.sqf` expects `SWLC_borrowedBy` to hold the player object. `squadTick` finds these groups itself once per tick with one `allGroups` filter. Nothing clears the variable for it: the borrowing code does that when the player lets go. While the variable points at a dead or disconnected player, the group is left alone completely.

## 3. Which state triggers which behaviour

| Behaviour | When |
|---|---|
| Posture | State in `squadPostureStates`, on foot, no bound, flank or LAMBS task running. |
| Bounding | Assaulting, leg FOOT, at least 3 men, between the rally's distance + 100 m and half way into the sector, not borrowed. |
| Suppress and flank | Advancing or Assaulting, at least 4 men, leader in COMBAT, average suppression over 0.25, no 15 m of progress in 45 s, LAMBS not loaded, not borrowed. A bound in progress ends first. |
| Rearm | Any state, on foot, leader not in COMBAT, no task running, checked every 45 s per group. |
| LAMBS building clearing | Assaulting, leader inside the target's square, at least 2 buildings, at most 2 groups per side. |
| LAMBS garrison | Defending for 45 s, within 40 m of its spot, inside an owned sector, not already fighting. `taskDefend` is the fallback when the buildings can't take everyone. |

Tasks are released when the state stops matching or the commander gives the group a new order.

Decisions worth a second look:

- **Borrowed groups** get posture and rearming only. Bounding and flanking would pull them away from the player they are following.
- **Bounding and flanking don't create new groups.** Teams are lists of soldiers inside the one group, moved with `doMove`, `doFollow` and `doStop`.
- **Part C hook.** Crates are checked with `SWLC_fnc_econResupplyAllowed [side, pos]` if it exists, and are allowed if it doesn't. Vehicle cargo and fallen soldiers are never limited by it.

## 4. LAMBS' `knowsAbout` inflation

LAMBS shares contacts between nearby groups with `reveal`, capped at knowledge 1 by `maxRevealValue` and limited to about 200 m by `combatShareRange`, plus radio ranges when a unit carries one. Our `intelPoll` accepts anything at `knowsAbout >= intelMinKnows`, currently 1.0, so a shared reveal alone would make a board entry for an enemy no soldier in that group has seen.

**Recommendation: leave LAMBS' sharing on and raise our threshold.**

- `lambsDetect` sets `intelMinKnows` to `lambsIntelMinKnows` (1.5) when LAMBS is loaded. A shared reveal at 1 no longer makes an entry. A soldier's own sighting climbs past 1.5 quickly, so real contacts still arrive.
- Don't touch `lambs_main_radioDisabled`. It's a global CBA setting and changing it would alter how the user's LAMBS plays everywhere.
- The information is still real, since it starts with a soldier who saw the enemy, so the honest-intel rule is bent rather than broken. The cost of 1.5 is a slightly slower first report in LAMBS rounds. If live rounds show sightings arriving late, lower it towards 1.2.

## 5. Radio lines added

One new type, `flank`, sent when a squad starts a flank. Until these lines are in `SWLC_radioLines` the call returns false and nothing is shown.

```sqf
["flank", [
	"Taking heavy fire. One team suppressing, the other going round.",
	"We're pinned. Moving to flank, keep their heads down.",
	"Can't push through this. Flanking now."
]]
```

These three lines are the only player-visible text in Part H.

## 6. Logs and tests

- New log type `C_SQUAD`, fields `side`, `behaviour` (`posture`, `bound`, `flank`, `rearm`, `lambs`), `event`, then details.
- Scenario: `tests/mission_overlay/swl/scenarios/gateh.sqf`, logging type `GH`.
  Run with `tools\run-round.ps1 -DurationMinutes 14 -Name parth -Scenario gateh -Overrides "scoutMinGroups=99;scanBuying=false"`.
- Analyser: `tools/gates_h.py`. In `tools/analyse_round.py`, after `check` is defined and before the checks run:

```python
import gates_h
gates_h.register(check)
```

  The gate name is `parth`, so `--gate parth` runs these. Everything in this file is gated on it, so normal rounds aren't affected.
