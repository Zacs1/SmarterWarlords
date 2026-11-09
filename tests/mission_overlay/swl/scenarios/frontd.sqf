// Part D gate: two waves on a collision course, then one group against a much bigger force. Run with:
//   powershell -ExecutionPolicy Bypass -File tools\run-round.ps1 -DurationMinutes 15 -Name frontd -Scenario frontd
// Then: python tools/analyse_round.py <rpt> --gate frontd
//
// Lines go out as SWL|GD. Groups are taken from the commander once it has an attack running, so they stay members of
// the real wave and the sweep has nothing to object to. They are moved out of any sector neither side can stand in.
// Tanoa unit classes, as in the other scenarios.

waitUntil {sleep 1; !isNil "SWLC_ready" && {!isNil "SWLC_cmd_WEST"} && {!isNil "SWLC_cmd_EAST"}};

SWLD_emit = {
	params ["_fields"];
	diag_log text ((["SWL", "GD", format ["t=%1", round time]] + _fields) joinString "|");
};

SWLD_cmds = [SWLC_cmd_WEST, SWLC_cmd_EAST];
SWLD_opWait = 300;         // the longest to wait for both sides to have an attack running
SWLD_startGap = 330;       // how far apart the two waves start
SWLD_helperOffset = 220;   // a free group each side, this far off the line of march
SWLD_groupSize = 6;
SWLD_margin = 80;
SWLD_fallbackAt = 360;     // seconds after the collision starts
SWLD_bigForce = 16;
SWLD_used = [];

SWLD_foot = {
	params ["_g"];
	(units _g findIf {alive _x && {vehicle _x != _x}}) < 0
};

SWLD_usable = {
	params ["_g"];
	!(_g in SWLD_used) && {(units _g findIf {alive _x}) >= 0} && {!([_g] call SWLC_fnc_adGroupHasPlayer)} && {[_g] call SWLD_foot}
};

// Attack groups first, so they stay in the wave.
SWLD_pickWave = {
	params ["_cmd", "_n"];
	private _op = _cmd get "op";
	private _pool = ([_op] call SWLC_fnc_waveLive) select {([_x] call SWLD_usable) && {([_x] call SWLC_fnc_state) in ["Mustering", "Travelling", "Advancing", "Waiting"]}};
	_pool select [0, _n]
};

SWLD_pickFree = {
	params ["_cmd"];
	private _pool = (_cmd get "groups") select {([_x] call SWLD_usable) && {([_x] call SWLC_fnc_state) == "Reserve"}};
	if (_pool isEqualTo []) then {
		_pool = (_cmd get "groups") select {([_x] call SWLD_usable) && {([_x] call SWLC_fnc_state) == "Unassigned"}};
	};
	if (_pool isEqualTo []) then {
		// Nobody is spare yet: another of the attack's groups can stand in as the free one.
		_pool = (_cmd get "groups") select {([_x] call SWLD_usable) && {([_x] call SWLC_fnc_state) in ["Mustering", "Travelling", "Waiting"]}};
	};
	if (_pool isEqualTo []) exitWith {grpNull};
	_pool # 0
};

SWLD_topUp = {
	params ["_g", "_size"];
	private _class = ["B_T_Soldier_F", "O_T_Soldier_F"] select (side _g == east);
	private _pos = getPosATL leader _g;
	for "_i" from 1 to (_size - ({alive _x} count units _g)) do {
		[_g createUnit [_class, _pos, [], 6, "NONE"]] joinSilent _g;
	};
};

SWLD_place = {
	params ["_g", "_pos"];
	{_x setPosATL [(_pos # 0) + random 10 - 5, (_pos # 1) + random 10 - 5, 0]} forEach (units _g select {alive _x});
};

SWLD_ok = {
	params ["_p"];
	!(surfaceIsWater _p) && {!([west, _p, SWLD_margin] call SWLC_fnc_adRestricted)} && {!([east, _p, SWLD_margin] call SWLC_fnc_adRestricted)}
};

// Open ground between the two sides, with room for both start points and the helpers.
SWLD_findGround = {
	params ["_from", "_to"];
	private _axis = [_from, _to] call SWLC_fnc_bearing;
	private _found = [];
	for "_d" from 0 to 1800 step 150 do {
		{
			private _mid = [_from, _axis + _x, ((_from distance2D _to) / 2) + _d] call SWLC_fnc_offset;
			private _a = [_mid, _axis + 180, SWLD_startGap] call SWLC_fnc_offset;
			private _b = [_mid, _axis, SWLD_startGap] call SWLC_fnc_offset;
			private _ha = [_a, _axis + 90, SWLD_helperOffset] call SWLC_fnc_offset;
			private _hb = [_b, _axis + 90, SWLD_helperOffset] call SWLC_fnc_offset;
			if ([_mid] call SWLD_ok && {[_a] call SWLD_ok} && {[_b] call SWLD_ok} && {[_ha] call SWLD_ok} && {[_hb] call SWLD_ok}) exitWith {_found = [_mid, _a, _b, _ha, _hb, _axis]};
		} forEach [0, 20, -20, 40, -40];
		if (_found isNotEqualTo []) exitWith {};
	};
	_found
};

// March a group at a far point as a part of its wave.
SWLD_march = {
	params ["_cmd", "_g", "_start", "_end"];
	SWLD_used pushBack _g;
	[_g, SWLD_groupSize] call SWLD_topUp;
	[_g] call SWLC_fnc_adClearOrder;
	[_g, _start] call SWLD_place;
	_g setVariable ["SWLC_leg", "FOOT"];
	[_g, "Advancing", _end, "frontd"] call SWLC_fnc_setState;
	[_g, [[_end, "MOVE", 30]], "AWARE", "NORMAL", "WEDGE", "YELLOW"] call SWLC_fnc_adSetOrder;
	[[format ["event=placed"], format ["side=%1", side _g], format ["group=%1", groupId _g], "role=wave"]] call SWLD_emit;
};

SWLD_helper = {
	params ["_cmd", "_pos"];
	private _g = [_cmd] call SWLD_pickFree;
	if (isNull _g) exitWith {[[format ["event=no_helper"], format ["side=%1", _cmd get "side"]]] call SWLD_emit};
	SWLD_used pushBack _g;
	[_g, SWLD_groupSize] call SWLD_topUp;
	[_g] call SWLC_fnc_adClearOrder;
	[_g, _pos] call SWLD_place;
	// Stays put: the reserve's patrol would walk it back to its post, and a spare group would be given a job.
	_g setVariable ["SWLC_patrolAt", time + 600];
	_g setVariable ["SWLC_noAssignUntil", time + 600];
	_g setVariable ["SWLC_waveId", -1];
	_g setVariable ["SWLC_leg", ""];
	[_g, "Reserve", _pos, "frontd_helper"] call SWLC_fnc_setState;
	[[format ["event=placed"], format ["side=%1", side _g], format ["group=%1", groupId _g], "role=helper"]] call SWLD_emit;
};

// ---- The collision ----

private _deadline = time + SWLD_opWait;
waitUntil {
	sleep 5;
	time >= _deadline || {(SWLD_cmds findIf {isNil {_x get "op"}}) < 0 && {(SWLD_cmds findIf {count ([_x, 2] call SWLD_pickWave) < 2}) < 0}}
};
if ((SWLD_cmds findIf {isNil {_x get "op"}}) >= 0) exitWith {[["event=no_op", format ["waited=%1", round time]]] call SWLD_emit};

private _west = SWLC_cmd_WEST;
private _east = SWLC_cmd_EAST;
private _from = [([west] call SWLC_fnc_adOwned) # 0] call SWLC_fnc_adPos;
private _to = [([east] call SWLC_fnc_adOwned) # 0] call SWLC_fnc_adPos;
private _nearestEast = [[east] call SWLC_fnc_adOwned, _from] call SWLC_fnc_adNearest;
_to = [_nearestEast] call SWLC_fnc_adPos;
private _nearestWest = [[west] call SWLC_fnc_adOwned, _to] call SWLC_fnc_adNearest;
_from = [_nearestWest] call SWLC_fnc_adPos;

private _ground = [_from, _to] call SWLD_findGround;
if (_ground isEqualTo []) exitWith {[["event=no_ground"]] call SWLD_emit};
_ground params ["_mid", "_startW", "_startE", "_helpW", "_helpE", "_axis"];

{[_west, _x, _startW, _startE] call SWLD_march} forEach ([_west, 2] call SWLD_pickWave);
{[_east, _x, _startE, _startW] call SWLD_march} forEach ([_east, 2] call SWLD_pickWave);
[_west, _helpW] call SWLD_helper;
[_east, _helpE] call SWLD_helper;
private _began = time;
[["event=collision", format ["x=%1", round (_mid # 0)], format ["y=%1", round (_mid # 1)], format ["axis=%1", round _axis]]] call SWLD_emit;

// ---- A much bigger force ----
// Independents, so no commander picks them up and marches them away.

waitUntil {sleep 5; time >= _began + SWLD_fallbackAt};

private _pool = ((_west get "groups") select {([_x] call SWLD_usable) && {([_x] call SWLC_fnc_state) in ["Travelling", "Advancing", "Waiting", "Mustering", "Reserve", "Unassigned"]}});
private _op = _west get "op";
if (_pool isEqualTo [] || {isNil "_op"}) exitWith {[["event=fallback_skipped", format ["groups=%1", count _pool], format ["op=%1", !isNil "_op"]]] call SWLD_emit};

private _spot = [];
{
	private _ring = _x;
	for "_b" from 0 to 345 step 15 do {
		private _p = _mid getPos [_ring, _b];
		private _e = _p getPos [240, _b];
		if ([_p] call SWLD_ok && {[_e] call SWLD_ok}) exitWith {_spot = [_p, _e]};
	};
	if (_spot isNotEqualTo []) exitWith {};
} forEach [900, 1200, 1600, 2000];
if (_spot isEqualTo []) exitWith {[["event=fallback_skipped", "why=no_ground"]] call SWLD_emit};
_spot params ["_here", "_there"];

private _g = _pool # 0;
private _sqdSize = 4;
SWLD_used pushBack _g;
[_g, _sqdSize] call SWLD_topUp;
[_g] call SWLC_fnc_adClearOrder;
[_g, _here] call SWLD_place;
_g setVariable ["SWLC_leg", "FOOT"];
_g setVariable ["SWLC_waveId", _op get "id"];
[_g, "Advancing", _there, "frontd_fallback"] call SWLC_fnc_setState;
[_g, [[_there, "MOVE", 30]], "AWARE", "NORMAL", "WEDGE", "YELLOW"] call SWLC_fnc_adSetOrder;

private _big = createGroup [resistance, true];
for "_i" from 1 to SWLD_bigForce do {
	_big createUnit ["I_C_Soldier_Para_1_F", _there, [], 25, "NONE"];
};
_big setBehaviour "COMBAT";
_big setCombatMode "RED";
private _wp = _big addWaypoint [_here, 0];
_wp setWaypointType "SAD";
[["event=fallback", format ["group=%1", groupId _g], format ["side=%1", side _g], format ["x=%1", round (_here # 0)], format ["y=%1", round (_here # 1)],
	format ["enemy=%1", SWLD_bigForce], format ["men=%1", {alive _x} count units _g]]] call SWLD_emit;
