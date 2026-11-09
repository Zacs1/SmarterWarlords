// Phase 4 gate: a visible enemy group next to a WEST sector must draw a response within one tick of
// being detected, and the defenders must stand down once the threat is gone. Runs twice: once at the
// base, which is a muster sector early on, and once at the first other sector WEST captures.
// Ends by driving the player request code paths with an AI stand-in, since no player is connected.

waitUntil {sleep 1; !isNil "SWLC_ready" && {!isNil "SWLC_cmd_WEST"}};

SWLG_emit = {
	params ["_type", "_fields"];
	diag_log text ((["SWL", _type, format ["t=%1", round time]] + _fields) joinString "|");
};

// Six EAST riflemen at _dist metres from the sector centre, in the open, invulnerable until the kill.
SWLG_attack = {
	params ["_s", "_label", ["_dist", 230]];
	private _c = [_s] call SWLC_fnc_adPos;
	private _spot = [];
	for "_i" from 0 to 23 do {
		private _p = [_c, _i * 15, _dist] call SWLC_fnc_offset;
		if (!surfaceIsWater _p && {count (_p nearRoads 20) == 0}) exitWith {_spot = _p};
	};
	if (_spot isEqualTo []) then {_spot = [_c, 0, _dist] call SWLC_fnc_offset};
	private _g = createGroup [east, true];
	for "_i" from 1 to 6 do {
		private _u = _g createUnit ["O_T_Soldier_F", _spot, [], 8, "NONE"];
		_u allowDamage false;
		_u disableAI "PATH";
	};
	_g setBehaviour "AWARE";
	_g setCombatMode "GREEN";
	["G4", [format ["event=spawn|label=%1|sector=%2|staging=%3|dist=%4", _label, [_s] call SWLC_fnc_adName,
		count (((missionNamespace getVariable "SWLC_cmd_WEST") get "musters") getOrDefault [[_s] call SWLC_fnc_adName, createHashMap]) > 0, round (_spot distance2D _c)]]] call SWLG_emit;
	// The board only holds what soldiers saw, and the attackers can spawn out of anyone's sight. A lone
	// WEST observer, outside the commander's groups, keeps them in view for the length of the test.
	private _og = createGroup [west, true];
	private _obs = _og createUnit ["B_T_Soldier_F", [_spot, _spot getDir _c, 60] call BIS_fnc_relPos, [], 0, "NONE"];
	_obs allowDamage false;
	_obs disableAI "PATH";
	_obs setCaptive true;
	private _end = time + 75;
	while {time < _end} do {
		{_og reveal [_x, 4]} forEach units _g;
		sleep 3;
	};
	deleteVehicle _obs;
	{_x setDamage 1} forEach units _g;
	["G4", [format ["event=killed|label=%1", _label]]] call SWLG_emit;
};

waitUntil {sleep 1; !isNull ([west] call SWLC_fnc_adTarget)};
sleep 90;

[[west] call SWLC_fnc_adBase, "base"] call SWLG_attack;

// Wait for a sector that isn't the base and has no muster running.
private _cmd = missionNamespace getVariable "SWLC_cmd_WEST";
private _sector = objNull;
private _deadline = time + 720;
waitUntil {
	sleep 5;
	private _list = ([west] call SWLC_fnc_adOwned) select {!([_x] call SWLC_fnc_adIsBase) && {count ((_cmd get "musters") getOrDefault [[_x] call SWLC_fnc_adName, createHashMap]) == 0}};
	if (_list isNotEqualTo []) then {_sector = _list # 0};
	!isNull _sector || {time > _deadline}
};
if (isNull _sector) then {
	["G4", ["event=no_second_sector"]] call SWLG_emit;
} else {
	[_sector, "sector"] call SWLG_attack;
};

// Let the stand-down land, then drive the player paths with an AI stand-in.
sleep 150;
private _stand = leader ((_cmd get "groups") # 0);
private _p = getPosATL _stand;
["G4", ["event=player_paths_start"]] call SWLG_emit;
[_cmd, _stand, "report", [["O_T_Soldier_F", [_p # 0 + 50, _p # 1]], ["NotAClass_X", [_p # 0, _p # 1]]]] call SWLC_fnc_menuHandle;
[_cmd, _stand, "go", []] call SWLC_fnc_menuHandle;
[_cmd, _stand, "defend", [[west] call SWLC_fnc_adBase]] call SWLC_fnc_menuHandle;
["report", _stand, []] call SWLC_fnc_playerMsg;
["G4", [format ["event=player_paths_done|plan_len=%1", count (missionNamespace getVariable ["SWLC_plan_WEST", []])]]] call SWLG_emit;
