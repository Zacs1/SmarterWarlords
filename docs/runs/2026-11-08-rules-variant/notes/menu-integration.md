# Part F integration: the "Commander..." menu

New files, already in place: `commander/swlc/menu.sqf`, `commander/swlc/menu_client.sqf`, `tests/mission_overlay/swl/scenarios/gatef.sqf`, `tools/gates_f.py`. `analyse_round.py` already imports `gates_f`.

Existing files need the patches below. Line numbers are from when this was drafted, so go by the quoted text.

## init.sqf (module list, line 31)

Add `"menu"` before `"commander"`:

    ..., "economy", "squads", "strategy", "menu", "commander", "debug"]

## commander.sqf (`SWLC_cmdStages`, line 96)

Add `"menuTick"` after `"probeTick"`:

    ..., "raidTick", "probeTick", "menuTick", "cmdAssign", "planPublish", "statusPublish"];

## initPlayerLocal.sqf

Add after the economy_client line:

    execVM "swlc\menu_client.sqf";

## client.sqf

Delete `SWLC_clSend` and `SWLC_clReport` (lines 5 to 32). `menu_client.sqf` now holds the report code. Replace `SWLC_clAddActions` with:

    SWLC_clAddActions = {
    	player addAction ["<t color='#ffcc66'>Commander...</t>", {call SWLC_menuOpen}, nil, 0.2, false, true, "", "alive _target && {_this == _target} && {missionNamespace getVariable ['SWLC_menuOn', true]}"];
    };

The Insert key still toggles the panel. The panel also has an entry in the menu, so this is the only scroll action.

## defence.sqf

Delete `SWLC_fnc_playerMsg`, `SWLC_fnc_playerReport`, `SWLC_fnc_playerAttack` and `SWLC_fnc_playerDefend` (from the comment above line 371 to the end of `playerDefend`). `menu.sqf` defines `SWLC_fnc_playerMsg` and has the rest folded in.

`SWLC_fnc_defSectorValue`, last line becomes:

    _v + ([_cmd get "side", _s] call SWLC_fnc_stratWorth) + ([_cmd, _s] call SWLC_fnc_menuDefendBonus)

## wave.sqf

In `rallyTick`, directly after line 335 (`if (_op getOrDefault ["holdGo", false]) exitWith {};`):

    if (time < (_op getOrDefault ["playerHoldUntil", -1])) exitWith {};

In the first groups filter (line 10), add the two new states:

    ["Reserve", "Defending", "Raiding", "Probing", "Picket", "Borrowed", "Pickup"]

## pickets.sqf (line 71)

    ["Picket", "Reserve", "Defending", "Raiding", "Probing", "Borrowed", "Pickup"]

## status.sqf (`statusRow` switch, next to `case "Raiding"`)

    case "Borrowed": {
    	_job = "With player";
    	private _by = _g getVariable ["SWLC_borrowedBy", objNull];
    	_place = if (isNull _by) then {"-"} else {name _by};
    	_reason = "on loan to a player until released";
    };
    case "Pickup": {
    	_job = "Pickup";
    	_place = [_goal] call SWLC_fnc_statusPlace;
    	_reason = "bringing a vehicle to a player";
    };

## settings.sqf

Remove `requestDefendRange`, which nothing reads any more. Keep `requestGoMinGroups`, `requestDefendSeconds` and `playerReport*`. Add:

    // Part F: the commander menu
    ["ruleCommanderMenu", true],
    ["menuTestAllowAI", false],          // lets the gatef scenario's AI stand-in count as a requester; never on in play
    ["menuCooldownSeconds", 15],         // per player, per option
    ["menuCooldowns", createHashMapFromArray [["plan", 10], ["release", 5], ["report", 10], ["raid", 10]]],
    ["menuKeepGroups", 2],               // attack groups the commander never lends out
    ["menuBorrowGroups", 3],             // most one player can have
    ["menuBorrowMinGroups", 2],          // fewer than this spare and a first request is refused
    ["menuFollowFar", 700],              // further than this and a borrowed group fast travels if that helps
    ["menuFollowFTSeconds", 120],
    ["menuFollowFTGain", 300],           // the hop must bring it this much closer
    ["menuFollowDist", 40],              // reissue the order once the player has moved this far
    ["menuFollowRefresh", 60],           // reissue anyway this often, or Warlords treats a waiting leader as stuck
    ["menuFollowCombatDist", 200],       // in a fight, only reissue beyond this
    ["menuHoldSeconds", 120],
    ["menuHoldSideCooldown", 300],
    ["menuDefendValue", 100],            // added to the sector's worth while a request lasts
    ["menuPickupMaxActive", 1],
    ["menuPickupBoardSeconds", 90],
    ["menuPickupArriveDist", 60],
    ["menuPickupRefreshMetres", 100],
    ["menuPickupTimeoutSeconds", 420],

`menuFollowRefresh` at 60 s is well inside the 150 s `reservePatrolSeconds` that already keeps waiting leaders from counting as stuck.

Add to `radioCooldowns`:

    ["raidno_off", 3], ["raidno_active", 3], ["raidno_cooldown", 3], ["raidno_not_front", 3], ["raidno_funds", 3], ["menubad", 3],
    ["borrowok", 3], ["borrowno", 3], ["borrowmax", 3], ["holdok", 3], ["holdno_noop", 3], ["holdno_assault", 3], ["holdno_used", 3],
    ["gook", 3], ["gono", 3], ["gono_going", 3], ["reportno", 3], ["defendok", 3], ["defendthin", 3], ["defendbad", 3],
    ["pickupok", 3], ["pickupno", 3], ["pickupbusy", 3], ["pickupbad", 3], ["pickuphere", 3], ["pickupfail", 3],
    ["releaseok", 3], ["releasenone", 3], ["plan", 5], ["planidle", 5]

## radio.sqf (`SWLC_radioLines`)

`reqok` and `reqno` are only used by the old request code, so they can go. Add:

    ["raidno_off", ["Raids aren't authorised right now."]],
    ["raidno_active", ["We've already got a raid running."]],
    ["raidno_cooldown", ["Too soon after the last raid. Give it time."]],
    ["raidno_not_front", ["Can't raid %1, it isn't next to anything we hold."]],
    ["raidno_funds", ["A raid costs %2 CP and you haven't got it."]],
    ["menubad", ["Didn't catch which sector. Say again."]],
    ["borrowok", ["Groups on their way to you: %1."]],
    ["borrowno", ["Can't spare any groups for that right now."]],
    ["borrowmax", ["You've got as many groups as I can give you."]],
    ["holdok", ["Holding the go signal for up to %1 minutes. Get there."]],
    ["holdno_noop", ["There's no attack forming right now."]],
    ["holdno_assault", ["Too late, they're already going in."]],
    ["holdno_used", ["We held the wave recently. Can't hold it again yet."]],
    ["gook", ["Go now. All staged groups, move."]],
    ["gono", ["Not enough groups at staging to go yet."]],
    ["gono_going", ["The attack's already under way."]],
    ["reportno", ["Couldn't place that contact. Nothing added."]],
    ["defendok", ["Roger, %1 comes first. Groups moving there."]],
    ["defendthin", ["No one free right now, but %1 comes first if it's hit."]],
    ["defendbad", ["%1 isn't ours to defend."]],
    ["pickupok", ["%1 is bringing a vehicle to you. Stay put."]],
    ["pickupno", ["Can't send a pickup right now, nothing to spare."]],
    ["pickupbusy", ["A pickup's already running. Wait for it to finish."]],
    ["pickupbad", ["Can't get a vehicle to you there."]],
    ["pickuphere", ["Your vehicle's here. It's yours."]],
    ["pickupfail", ["Pickup's off. We lost it or couldn't reach you."]],
    ["releaseok", ["Copy, those groups are back with the commander."]],
    ["releasenone", ["You've got no groups on loan."]],
    ["plan", ["Target %1, staging at grid %2. %3 %4"]],
    ["planidle", ["No attack planned right now. %1"]],

## gate4.sqf and analyse_round.py (the old request functions are gone)

`tests/mission_overlay/swl/scenarios/gate4.sqf`, replace lines 76 to 79:

    [_cmd, _stand, "report", [["O_T_Soldier_F", [_p # 0 + 50, _p # 1]], ["NotAClass_X", [_p # 0, _p # 1]]]] call SWLC_fnc_menuHandle;
    [_cmd, _stand, "go", []] call SWLC_fnc_menuHandle;
    [_cmd, _stand, "defend", [[west] call SWLC_fnc_adBase]] call SWLC_fnc_menuHandle;
    ["report", _stand, []] call SWLC_fnc_playerMsg;

`tools/analyse_round.py`, `check_player_paths`: read `data.of("C_MENU")` instead of `data.of("C_REQ")`.

## Interactions to know about

- Squads: `SWLC_borrowedBy` holds the player object and is set to nil on release, so the draft's `getVariable ["SWLC_borrowedBy", objNull]` is right.
- Funds: the raid debit is a server `setVariable` on `BIS_WL_funds`, so it has the same race with a client's own spending as part C's server-side changes.
- Raids: a player's raid sends no AI groups by itself. Borrowed groups following the player are the raid force, and the player can walk into the sector because `raidStart` adds it to the conquered list.
