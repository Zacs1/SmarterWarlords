// Alert and defence in depth. Run with:
//   powershell -ExecutionPolicy Bypass -File tools\run-round.ps1 -DurationMinutes 12 -Name alert -Scenario alert -Overrides "goMinGroups=99;rallyLoneWait=99999;scanBuying=false;ruleCommitTimer=false"
// Then: python tools/analyse_round.py <rpt> --gate alert
//
// Setup gives WEST a non-base sector touching EAST ground and makes it EAST's target. Men that can't be hurt then walk in along the
// predicted approach, starting a minute after the alert, the head start the warning is meant to buy. Stage 1 checks the layers are set up
// before they arrive and on the right side. Stage 2 is the break-in: they stop being captive and a seize countdown is faked.
//
// Limits: all stance rows are forced to [2, 1, 1] so one run exercises every layer, and the stance is held at "hold". The attackers are placed
// on the predicted approach, so this checks the defence against the prediction, not the prediction against a real attacker. The break-in is
// the seize countdown only; the "enemy known inside the square" path isn't exercised.

waitUntil {sleep 1; !isNil "SWLC_ready" && {!isNil "SWLC_cmd_WEST"} && {!isNil "SWLC_cmd_EAST"}};

SWLG_emit = {
	params ["_fields"];
	diag_log text ((["SWL", "GAL", format ["t=%1", round time]] + _fields) joinString "|");
};

SWLG_take = {
	params ["_side", "_s"];
	{
		if (vehicle _x != _x) then {deleteVehicle vehicle _x};
		deleteVehicle _x;
	} forEach (allUnits select {side group _x == resistance && {[_s, getPosATL _x, 150] call SWLC_fnc_adInSquare}});
	_s setVariable ["BIS_WL_sectorSide", _side, true];
	[[format ["event=took|side=%1|sector=%2", _side, [_s] call SWLC_fnc_adName]]] call SWLG_emit;
};

// Neutral sectors on the shortest route from WEST ground to EAST ground, nearest WEST first.
SWLG_path = {
	private _seen = +([west] call SWLC_fnc_adOwned);
	private _parent = _seen apply {-1};
	private _hit = -1;
	private _i = 0;
	while {_hit < 0 && {_i < count _seen}} do {
		private _from = _i;
		{
			private _n = _x;
			if (_hit < 0 && {!(_n in _seen)}) then {
				private _owner = [_n] call SWLC_fnc_adOwner;
				if (_owner == east) then {_hit = _from};
				if (_owner != east && {_owner != west}) then {
					_seen pushBack _n;
					_parent pushBack _from;
				};
			};
		} forEach ([_seen # _from] call SWLC_fnc_adLinks);
		_i = _i + 1;
	};
	private _route = [];
	while {_hit >= 0} do {
		if (([_seen # _hit] call SWLC_fnc_adOwner) != west) then {_route pushBack (_seen # _hit)};
		_hit = _parent # _hit;
	};
	reverse _route;
	_route
};

SWLG_touching = {
	([west] call SWLC_fnc_adOwned) select {
		!([_x] call SWLC_fnc_adIsBase)
		&& {(([_x] call SWLC_fnc_adLinks) findIf {([_x] call SWLC_fnc_adOwner) == east}) >= 0}
	}
};

private _cmd = missionNamespace getVariable "SWLC_cmd_WEST";
private _cmdE = missionNamespace getVariable "SWLC_cmd_EAST";
{_x set ["raidNextCheck", 1e9]; _x set ["probeNext", 1e9]} forEach [_cmd, _cmdE];
SWLC_settings set ["alertLayers", createHashMapFromArray [["attack", [2, 1, 1, 0.8]], ["hold", [2, 1, 1, 0.8]], ["rebuild", [2, 1, 1, 0.8]]]];
SWLC_settings set ["reserveBySectors", [[999, 2]]];
_cmd set ["stance", "hold"];

// ---- A WEST sector on the front line ----
private _deadline = time + 90;
while {(([] call SWLG_touching) isEqualTo []) && {time < _deadline}} do {
	{[west, _x] call SWLG_take} forEach ([] call SWLG_path);
	sleep 4;
};
private _touching = [] call SWLG_touching;
if (_touching isEqualTo []) exitWith {[["event=fail_no_front"]] call SWLG_emit};
private _sector = _touching # 0;
private _name = [_sector] call SWLC_fnc_adName;
private _c = [_sector] call SWLC_fnc_adPos;
private _half = ([_sector] call SWLC_fnc_adSize) / 2;
[[format ["event=setup|sector=%1|size=%2", _name, round (_half * 2)]]] call SWLG_emit;

// ---- It becomes EAST's target ----
_cmdE set ["preferredTarget", _sector];
_deadline = time + 150;
private _nextVote = time;
waitUntil {
	sleep 2;
	if (time >= _nextVote && {([east] call SWLC_fnc_adTarget) isNotEqualTo _sector}) then {
		_nextVote = time + 40;
		[east] call SWLC_fnc_adForceRevote;
	};
	([east] call SWLC_fnc_adTarget) isEqualTo _sector || {time > _deadline}
};
if (([east] call SWLC_fnc_adTarget) isNotEqualTo _sector) then {
	missionNamespace setVariable ["BIS_WL_currentSector_EAST", _sector, true];
	[["event=target_forced"]] call SWLG_emit;
};

_deadline = time + 40;
waitUntil {sleep 1; (count (_cmd getOrDefault ["alert", createHashMap]) > 0) || {time > _deadline}};
private _rec = _cmd getOrDefault ["alert", createHashMap];
if (count _rec == 0) exitWith {[["event=fail_no_alert"]] call SWLG_emit};
if ((_rec get "sector") isNotEqualTo _sector) exitWith {[[format ["event=fail_wrong_sector|got=%1", [_rec get "sector"] call SWLC_fnc_adName]]] call SWLG_emit};
(_rec get "approach") params ["_bearing", "_point", "_roads"];
private _alertAt = time;
[[format ["event=alert|sector=%1|bearing=%2|roads=%3", _name, round _bearing, count _roads]]] call SWLG_emit;

// The groups under test mustn't die: the gates are about where they go.
SWLG_on = true;
[_cmd] spawn {
	params ["_cmd"];
	while {SWLG_on} do {
		{{_x allowDamage false} forEach units _x} forEach ((_cmd get "groups") select {([_x] call SWLC_fnc_state) in ["Defending", "Reserve"]});
		sleep 2;
	};
};

// ---- The attackers: start on the approach, as far out as isn't forbidden ground ----
private _startDist = 1000;
private _start = [_c, _bearing, _half + _startDist] call SWLC_fnc_offset;
while {_startDist > 300 && {surfaceIsWater _start || {[east, _start, 50] call SWLC_fnc_adRestricted}}} do {
	_startDist = _startDist - 100;
	_start = [_c, _bearing, _half + _startDist] call SWLC_fnc_offset;
};
private _att = createGroup [east, true];
for "_i" from 1 to 6 do {
	private _u = _att createUnit ["O_T_Soldier_F", _start, [], 15, "NONE"];
	_u allowDamage false;
	_u setCaptive true;
};
_att setCombatMode "BLUE";
_att setBehaviour "CARELESS";
_att setSpeedMode "FULL";
[[format ["event=attackers|men=%1|dist=%2", count units _att, _startDist]]] call SWLG_emit;

SWLG_angle = {
	params ["_a", "_b"];
	abs ((((_a - _b) mod 360) + 540) mod 360 - 180)
};

// Each group's place against the predicted approach. "goal" is where it was sent, "off" and "out" are where its leader actually is.
SWLG_spots = {
	params ["_role", "_groups"];
	{
		private _g = _x;
		private _goal = _g getVariable ["SWLC_goal", []];
		private _p = getPosATL leader _g;
		private _gapGoal = if (_goal isEqualTo []) then {-1} else {round (_p distance2D _goal)};
		private _goalOff = if (_goal isEqualTo []) then {-1} else {round ([[_c, _goal] call SWLC_fnc_bearing, _bearing] call SWLG_angle)};
		[[format ["event=spot|role=%1|group=%2|state=%3|off=%4|out=%5|goalOff=%6|fromGoal=%7|half=%8",
			_role, groupId _g, [_g] call SWLC_fnc_state, round ([[_c, _p] call SWLC_fnc_bearing, _bearing] call SWLG_angle), round (_p distance2D _c), _goalOff, _gapGoal, round _half]]] call SWLG_emit;
	} forEach _groups;
};

private _inSquare = {
	params ["_groups"];
	{[_sector, getPosATL leader _x] call SWLC_fnc_adInSquare} count _groups
};
private _sample = {
	params ["_held"];
	private _r = _cmd getOrDefault ["alert", createHashMap];
	private _main = _r getOrDefault ["groups", []];
	private _screen = _r getOrDefault ["screen", []];
	private _counter = _r getOrDefault ["counter", []];
	[[format ["event=sample|alert=%1|main=%2|mainIn=%3|screen=%4|counter=%5|counterReserve=%6|attIn=%7|heldIn=%8|heldReserve=%9",
		count _r, count _main, [_main] call _inSquare, count _screen, count _counter,
		{([_x] call SWLC_fnc_state) == "Reserve"} count _counter,
		{alive _x && {[_sector, getPosATL _x] call SWLC_fnc_adInSquare}} count units _att,
		[_held] call _inSquare, {([_x] call SWLC_fnc_state) == "Reserve"} count _held]]] call SWLG_emit;
};

// ---- Stage 1: the head start, then the walk in ----
private _moveAt = _alertAt + 60;
private _moved = false;
private _breakAt = _alertAt + 330;
private _entered = false;
waitUntil {
	_cmd set ["stance", "hold"];
	_cmdE set ["preferredTarget", _sector];
	if (!_moved && {time >= _moveAt}) then {
		_moved = true;
		_att move _c;
		[[format ["event=attackers_move|after=%1", round (time - _alertAt)]]] call SWLG_emit;
	};
	[[]] call _sample;
	if (!_entered && {({alive _x && {[_sector, getPosATL _x] call SWLC_fnc_adInSquare}} count units _att) >= 3}) then {
		_entered = true;
		// Long enough in the square to see who got there first, then the break-in.
		_breakAt = _breakAt min (time + 20);
	};
	sleep 5;
	time >= _breakAt
};

// ---- Stage 2: the break-in ----
_rec = _cmd getOrDefault ["alert", createHashMap];
if (count _rec == 0) exitWith {[["event=fail_alert_gone"]] call SWLG_emit; SWLG_on = false};
["main", _rec get "groups"] call SWLG_spots;
["screen", _rec get "screen"] call SWLG_spots;
["counter", _rec get "counter"] call SWLG_spots;
private _held = +(_rec get "counter");
if (!_entered) then {
	{_x setPosATL [(_c # 0) + (random 30) - 15, (_c # 1) + (random 30) - 15, 0]} forEach units _att;
	[["event=attackers_teleported"]] call SWLG_emit;
};
{_x setCaptive false} forEach units _att;
[[format ["event=breakin|held=%1", count _held]]] call SWLG_emit;

private _seizeEnd = time + 40;
[_sector, _seizeEnd] spawn {
	params ["_sector", "_seizeEnd"];
	while {time < _seizeEnd} do {
		_sector setVariable ["BIS_WL_timeoutCur_EAST", 30];
		sleep 0.5;
	};
	_sector setVariable ["BIS_WL_timeoutCur_EAST", 0];
};

private _end = time + 200;
waitUntil {
	_cmd set ["stance", "hold"];
	_cmdE set ["preferredTarget", _sector];
	[_held] call _sample;
	sleep 5;
	time >= _end
};

SWLG_on = false;
[["event=done"]] call SWLG_emit;
