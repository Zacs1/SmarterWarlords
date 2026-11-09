// Phase 6 checks. Smoke, scouting, prep fire and personality happen on their own. The rest are set up
// here, because a short round can't be relied on to produce them: losses, a stalled group, a vehicle
// lost to nothing visible, and the player stand-in. Run with:
//   -Scenario gate6 -Overrides "scoutMinGroups=2;scanBuying=false;reinforceStallSeconds=60"

waitUntil {sleep 1; !isNil "SWLC_ready" && {!isNil "SWLC_cmd_WEST"}};

SWLG_emit = {
	params ["_type", "_fields"];
	diag_log text ((["SWL", _type, format ["t=%1", round time]] + _fields) joinString "|");
};

waitUntil {sleep 1; !isNull ([west] call SWLC_fnc_adTarget)};
SWLG_west = missionNamespace getVariable "SWLC_cmd_WEST";
SWLG_east = missionNamespace getVariable "SWLC_cmd_EAST";

// A crewed mortar at the WEST base, since stock Tanoa sells none.
private _base = [[west] call SWLC_fnc_adBase] call SWLC_fnc_adPos;
private _spot = _base findEmptyPosition [10, 120, "B_Mortar_01_F"];
if (_spot isEqualTo []) then {_spot = +_base};
private _mortar = createVehicle ["B_Mortar_01_F", _spot, [], 0, "NONE"];
createVehicleCrew _mortar;
_mortar allowDamage false;
{_x allowDamage false} forEach crew _mortar;
["G6", [format ["event=mortar|x=%1|y=%2|crew=%3", round (_spot # 0), round (_spot # 1), count crew _mortar]]] call SWLG_emit;

// Break and consolidate: two EAST groups on foot are cut down to one man who isn't a Warlord.
[] spawn {
	private _done = 0;
	private _deadline = time + 600;
	while {_done < 2 && {time < _deadline}} do {
		sleep 5;
		private _w = SWLG_east get "op";
		if (!isNil "_w") then {
				{
					private _g = _x;
					if (_done < 2 && {([_g] call SWLC_fnc_state) in ["Advancing", "Assaulting"]} && {(_g getVariable ["SWLC_leg", ""]) == "FOOT"} && {(_g getVariable ["SWLC_launchMen", 0]) >= 3} && {!(_g getVariable ["SWLG_hit", false])}) then {
						_g setVariable ["SWLG_hit", true];
						private _units = (units _g) select {alive _x};
						private _bought = _units select {!([_x] call SWLC_fnc_adIsWarlord)};
						private _keep = if (_bought isNotEqualTo []) then {_bought # 0} else {_units # 0};
						{_x setDamage 1} forEach (_units - [_keep]);
						_done = _done + 1;
						["G6", [format ["event=break_forced|group=%1|launched=%2|left=1", groupId _g, _g getVariable "SWLC_launchMen"]]] call SWLG_emit;
					};
				} forEach ([_w] call SWLC_fnc_waveLive);
		};
	};
};

// Reinforce success: one WEST group is put inside the sector, the others can't move.
[] spawn {
	private _deadline = time + 600;
	private _forced = false;
	while {!_forced && {time < _deadline}} do {
		sleep 3;
		private _w = SWLG_west get "op";
		if (!isNil "_w" && {(_w get "phase") == "ASSAULT"}) then {
			private _foot = ([_w] call SWLC_fnc_waveLive) select {(_x getVariable ["SWLC_leg", ""]) == "FOOT" && {([_x] call SWLC_fnc_state) == "Assaulting"}};
			if ((count _foot) >= 2) then {
				_forced = true;
				private _c = _w get "tpos";
				private _in = _foot # 0;
				private _stalled = _foot select [1, count _foot];
				{_x allowDamage false; _x setPosATL [(_c # 0) + random 10, (_c # 1) + random 10, 0]} forEach units _in;
				{{_x disableAI "PATH"} forEach units _x} forEach _stalled;
				["G6", [format ["event=reinforce_forced|wave=%1|inside=%2|stalled=%3", _w get "id", groupId _in, count _stalled]]] call SWLG_emit;
				[_in, _stalled] spawn {
					params ["_in", "_stalled"];
					sleep 120;
					{{_x enableAI "PATH"} forEach units _x} forEach _stalled;
					{_x allowDamage true} forEach units _in;
				};
			};
		};
	};
	if (!_forced) then {["G6", ["event=reinforce_not_forced"]] call SWLG_emit};
};

sleep 120;

// Hunt: a WEST vehicle destroyed with no attacker anyone saw.
private _pos = [[west] call SWLC_fnc_adBase] call SWLC_fnc_adPos;
private _quad = createVehicle ["B_Quadbike_01_F", _pos, [], 40, "NONE"];
_quad setVariable ["SWLC_side", west];
sleep 2;
_quad setDamage 1;
["G6", [format ["event=hunt_forced|x=%1|y=%2", round ((getPosATL _quad) # 0), round ((getPosATL _quad) # 1)]]] call SWLG_emit;

sleep 45;

// Memory: a direction recorded as costly is avoided by the next plan for that sector.
private _target = [west] call SWLC_fnc_adTarget;
if (!isNull _target) then {
	private _tpos = [_target] call SWLC_fnc_adPos;
	private _centre = [SWLG_west, _target] call SWLC_fnc_opBearing;
	private _fw = createHashMapFromArray [["target", _target], ["bearing", _centre], ["launchStrength", 6]];
	[SWLG_west, _fw, []] call SWLC_fnc_smartRemember;
	private _next = [SWLG_west, _target, _centre] call SWLC_fnc_smartAvoid;
	["G6", [format ["event=memory_check|costly=%1|bearings=%2", round _centre, round _next]]] call SWLG_emit;
};

sleep 60;

// Momentum: a fast, cheap capture next to a weak sector, and what that does to the vote score.
private _baseSector = [west] call SWLC_fnc_adBase;
private _free = (SWLG_west get "groups") select {({alive _x} count units _x) > 0};
if (_free isNotEqualTo []) then {
	private _men = [[_free # 0]] call SWLC_fnc_groupsMen;
	private _fw = createHashMapFromArray [["target", _baseSector], ["launched", time - 100], ["launchStrength", _men]];
	[SWLG_west, _fw, [_free # 0]] call SWLC_fnc_smartMomentum;
	private _m = SWLG_west getOrDefault ["momentum", []];
	if (_m isNotEqualTo []) then {
		private _owned = [west] call SWLC_fnc_adOwned;
		private _enemyBase = [east] call SWLC_fnc_adBase;
		private _after = [SWLG_west, _m # 0, _owned, _enemyBase] call SWLC_fnc_voteScore;
		SWLG_west deleteAt "momentum";
		private _before = [SWLG_west, _m # 0, _owned, _enemyBase] call SWLC_fnc_voteScore;
		["G6", [format ["event=momentum_score|sector=%1|before=%2|after=%3", [_m # 0] call SWLC_fnc_adName, round _before, round _after]]] call SWLG_emit;
	} else {
		["G6", ["event=momentum_no_push"]] call SWLG_emit;
	};
};

sleep 60;

// Dig in, using a group that isn't busy, at the WEST base.
private _spare = (SWLG_west get "groups") select {([_x] call SWLC_fnc_state) in ["Unassigned", "Mustering", "Waiting", "Travelling"]};
if (_spare isNotEqualTo []) then {
	private _g = _spare # 0;
	[SWLG_west, _g] call SWLC_fnc_waveRemoveGroup;
	[SWLG_west, createHashMapFromArray [["target", _baseSector]], [_g]] call SWLC_fnc_smartDigIn;
	["G6", [format ["event=digin_forced|group=%1", groupId _g]]] call SWLG_emit;
} else {
	["G6", ["event=digin_no_group"]] call SWLG_emit;
};

sleep 45;

// Join the player's push, with an AI stand-in since no player is connected.
private _groups = (SWLG_west get "groups") select {([_x] call SWLC_fnc_state) in ["Unassigned", "Mustering", "Waiting"]};
if (_groups isNotEqualTo []) then {
	[SWLG_west, leader (_groups # 0)] call SWLC_fnc_smartJoinHuman;
	["G6", [format ["event=join_forced|free_groups=%1", count _groups]]] call SWLG_emit;
} else {
	["G6", ["event=join_no_group"]] call SWLG_emit;
};
