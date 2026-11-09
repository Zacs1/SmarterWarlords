// Resilience gate: every way a commander group can get lost, one case at a time, on separate groups. Run with:
//   powershell -ExecutionPolicy Bypass -File tools\run-round.ps1 -DurationMinutes 22 -Name sabotage -Scenario sabotage -Overrides "testHooks=true"
// Then: python tools/analyse_round.py <rpt> --gate partr
//
// Lines go out as SWL|GS. Each case logs event=sabotage once, then event=track every 10 s while it is watched.
// tools/gates_r.py judges them. A case is run on a group already working, each group is used once, and the sides take turns.
// Men in a case can't be hurt while it is watched: the case measures recovery, not how a firefight went.
// Places are chosen outside sectors the side doesn't own, or Warlords' restricted-area loop would kill the men first.

waitUntil {sleep 1; !isNil "SWLC_ready" && {!isNil "SWLC_cmd_WEST"} && {!isNil "SWLC_cmd_EAST"}};

SWLG_emit = {
	params ["_fields"];
	diag_log text ((["SWL", "GS", format ["t=%1", round time]] + _fields) joinString "|");
};

SWLG_cmds = [missionNamespace getVariable "SWLC_cmd_WEST", missionNamespace getVariable "SWLC_cmd_EAST"];
SWLG_used = [];
SWLG_lastSide = west;
SWLG_watchSeconds = 210;   // the gate allows 180 s, and needs a sample or two past that to report on
SWLG_caseGap = 40;         // seconds between cases; they overlap, but never on the same group
SWLG_pickWait = 20;        // seconds to wait for a group already on the move
SWLG_restrictMargin = 60;
SWLG_movingJobs = ["Travelling", "Advancing", "Assaulting", "Regrouping", "Raiding", "Probing", "Recon", "Hunting", "Mounting"];
SWLG_anyJobs = SWLG_movingJobs + ["Mustering", "Waiting", "Defending", "Picket", "Reserve"];

SWLG_alive = {
	params ["_g"];
	(units _g) select {alive _x}
};

SWLG_kindOk = {
	params ["_g", "_kind"];
	private _men = [_g] call SWLG_alive;
	switch (_kind) do {
		case "foot": {(_men findIf {vehicle _x != _x}) < 0};
		case "vehicle": {
			private _v = vehicle leader _g;
			(_v != leader _g) && {alive _v} && {_v isKindOf "LandVehicle"} && {(driver _v) in _men} && {canMove _v}
		};
		default {true};
	}
};

SWLG_candidates = {
	params ["_jobs", "_kind"];
	private _out = [];
	{
		{
			private _g = _x;
			if (!(_g in SWLG_used) && {([_g] call SWLC_fnc_state) in _jobs} && {[_g, _kind] call SWLG_kindOk}) then {_out pushBack _g};
		} forEach ((_x get "groups") select {!isNull _x && {(units _x findIf {alive _x}) >= 0} && {!([_x] call SWLC_fnc_adGroupHasPlayer)}});
	} forEach SWLG_cmds;
	_out
};

// Prefers a group on the move. The sides take turns, so neither loses its whole wave.
SWLG_pick = {
	params ["_kind"];
	private _deadline = time + SWLG_pickWait;
	private _pool = [];
	waitUntil {
		_pool = [SWLG_movingJobs, _kind] call SWLG_candidates;
		if (_pool isEqualTo [] && {time < _deadline}) then {sleep 2};
		_pool isNotEqualTo [] || {time >= _deadline}
	};
	if (_pool isEqualTo []) then {_pool = [SWLG_anyJobs, _kind] call SWLG_candidates};
	if (_pool isEqualTo []) exitWith {grpNull};
	private _want = [west, east] select (SWLG_lastSide == west);
	private _turn = _pool select {side _x == _want};
	if (_turn isEqualTo []) then {_turn = _pool};
	private _g = selectRandom _turn;
	SWLG_lastSide = side _g;
	_g
};

SWLG_protect = {
	params ["_g", "_on"];
	{_x allowDamage !_on} forEach (units _g);
};

// Groups are small early on, and the cases that need followers need them there.
SWLG_topUp = {
	params ["_g", "_size"];
	private _class = ["B_T_Soldier_F", "O_T_Soldier_F"] select (side _g == east);
	private _pos = getPosATL leader _g;
	private _short = _size - count ([_g] call SWLG_alive);
	for "_i" from 1 to _short do {
		private _u = _g createUnit [_class, _pos, [], 6, "NONE"];
		[_u] joinSilent _g;
		_u allowDamage false;
	};
};

SWLG_moveMen = {
	params ["_g", "_pos", ["_water", false]];
	{
		private _x2 = (_pos # 0) + random 6 - 3;
		private _y2 = (_pos # 1) + random 6 - 3;
		if (_water) then {_x setPosASLW [_x2, _y2, 0]} else {_x setPosATL [_x2, _y2, 0]};
	} forEach ([_g] call SWLG_alive);
};

SWLG_open = {
	params ["_g", "_p"];
	!([side _g, _p, SWLG_restrictMargin] call SWLC_fnc_adRestricted)
};

// Places. Each returns a position, or [] if there is nowhere suitable.
SWLG_findSea = {
	params ["_g"];
	private _c = getPosATL leader _g;
	private _found = [];
	for "_r" from 200 to 4000 step 100 do {
		for "_b" from 0 to 345 step 15 do {
			private _p = _c getPos [_r, _b];
			if (surfaceIsWater _p && {(getTerrainHeightASL _p) < -4} && {[_g, _p] call SWLG_open}) exitWith {_found = _p};
		};
		if (_found isNotEqualTo []) exitWith {};
	};
	_found
};

SWLG_findForest = {
	params ["_g"];
	private _spots = selectBestPlaces [getPosATL leader _g, 1500, "forest * (1 - sea) * (1 - houses)", 40, 8];
	private _found = [];
	{
		_x params ["_flat", "_value"];
		private _p = [_flat # 0, _flat # 1, 0];
		if (_value > 0.4 && {!surfaceIsWater _p} && {count (nearestTerrainObjects [_p, ["TREE", "SMALL TREE"], 15]) >= 5} && {[_g, _p] call SWLG_open}) exitWith {_found = _p};
	} forEach _spots;
	if (_found isEqualTo [] && {_spots isNotEqualTo []}) then {
		private _flat = (_spots # 0) # 0;
		private _p = [_flat # 0, _flat # 1, 0];
		if (!surfaceIsWater _p && {[_g, _p] call SWLG_open}) then {_found = _p};
	};
	_found
};

// A rock big enough to be a real obstacle, near the group or else near any sector. Failing that, steep ground.
SWLG_findRock = {
	params ["_g"];
	private _c = getPosATL leader _g;
	private _found = [];
	{
		{
			private _p = getPosATL _x;
			private _box = boundingBoxReal _x;
			if (((_box # 0) distance (_box # 1)) >= 5 && {!surfaceIsWater _p} && {[_g, _p] call SWLG_open}) exitWith {_found = _p};
		} forEach (nearestTerrainObjects [_x, ["ROCK", "ROCKS"], 1200]);
		if (_found isNotEqualTo []) exitWith {};
	} forEach ([_c] + (SWLC_sectors apply {[_x] call SWLC_fnc_adPos}));
	if (_found isNotEqualTo []) exitWith {[_found, "rock"]};
	for "_r" from 100 to 2000 step 100 do {
		for "_b" from 0 to 340 step 20 do {
			private _p = _c getPos [_r, _b];
			if (!surfaceIsWater _p && {((surfaceNormal _p) # 2) < 0.75} && {[_g, _p] call SWLG_open}) exitWith {_found = _p};
		};
		if (_found isNotEqualTo []) exitWith {};
	};
	[_found, "steep"]
};

// Vehicles. A group riding one it drives, or else a group on foot in one spawned for this test.
SWLG_spawnVehicle = {
	params ["_g"];
	private _side = side _g;
	private _options = (([_side] call SWLC_fnc_adCatalog) select {(_x # 3) == "transport"}) apply {[_x # 2, _x # 0]};
	_options sort false;
	private _class = if (_options isEqualTo []) then {["B_MRAP_01_F", "O_MRAP_02_F"] select (_side == east)} else {(_options # 0) # 1};
	private _leader = leader _g;
	private _spot = (getPosATL _leader) findEmptyPosition [5, 80, _class];
	if (_spot isEqualTo []) then {_spot = getPosATL _leader};
	private _v = createVehicle [_class, _spot, [], 0, "NONE"];
	_leader moveInDriver _v;
	{if (_x != _leader) then {_x moveInAny _v}} forEach ([_g] call SWLG_alive);
	[[format ["event=vehicle_spawned|group=%1|side=%2|class=%3", groupId _g, _side, _class]]] call SWLG_emit;
	_v
};

SWLG_pickVehicle = {
	private _pool = [SWLG_anyJobs, "vehicle"] call SWLG_candidates;
	if (_pool isNotEqualTo []) exitWith {
		private _g = selectRandom _pool;
		SWLG_lastSide = side _g;
		[_g, vehicle leader _g, false]
	};
	private _g = ["foot"] call SWLG_pick;
	if (isNull _g) exitWith {[grpNull, objNull, false]};
	[_g, [_g] call SWLG_spawnVehicle, true]
};

// The cases. Each takes [group, vehicle] and returns log fields, or false if it found nowhere to do it.
SWLG_doKill = {
	params ["_g"];
	private _l = leader _g;
	private _text = format ["killed=%1|warlord=%2", name _l, [_l] call SWLC_fnc_adIsWarlord];
	_l allowDamage true;
	_l setDamage 1;
	_text
};

SWLG_clearWaypoints = {
	params ["_g"];
	for "_i" from (count waypoints _g - 1) to 0 step -1 do {deleteWaypoint [_g, _i]};
};

SWLG_doNoWaypoints = {
	params ["_g"];
	private _had = count waypoints _g;
	[_g] call SWLG_clearWaypoints;
	format ["deleted=%1", _had]
};

// The harder one: the remembered order goes too, so the guard has nothing to restore and only the sweep can notice.
SWLG_doNoOrder = {
	params ["_g"];
	private _had = count waypoints _g;
	[_g] call SWLG_clearWaypoints;
	[_g] call SWLC_fnc_adClearOrder;
	format ["deleted=%1", _had]
};

SWLG_doSea = {
	params ["_g"];
	private _p = [_g] call SWLG_findSea;
	if (_p isEqualTo []) exitWith {false};
	[_g, _p, true] call SWLG_moveMen;
	format ["x=%1|y=%2|depth=%3", round (_p # 0), round (_p # 1), round (getTerrainHeightASL _p)]
};

SWLG_doForest = {
	params ["_g"];
	private _p = [_g] call SWLG_findForest;
	if (_p isEqualTo []) exitWith {false};
	[_g, _p] call SWLG_moveMen;
	format ["x=%1|y=%2|trees=%3", round (_p # 0), round (_p # 1), count (nearestTerrainObjects [_p, ["TREE", "SMALL TREE"], 15])]
};

SWLG_doRocks = {
	params ["_g"];
	([_g] call SWLG_findRock) params ["_p", "_how"];
	if (_p isEqualTo []) exitWith {false};
	[_g, _p] call SWLG_moveMen;
	format ["x=%1|y=%2|how=%3", round (_p # 0), round (_p # 1), _how]
};

SWLG_doFlip = {
	params ["_g", "_v"];
	_v allowDamage false;
	private _dir = vectorDir _v;
	_v setPosATL ((getPosATL _v) vectorAdd [0, 0, 1]);
	_v setVectorDirAndUp [vectorNormalized [_dir # 0, _dir # 1, 0], [0, 0, -1]];
	format ["vehicle=%1", typeOf _v]
};

SWLG_doImmobilise = {
	params ["_g", "_v"];
	_v allowDamage false;
	private _wanted = ((getAllHitPointsDamage _v) param [0, []]) select {
		private _l = toLower _x;
		"wheel" in _l || {"track" in _l} || {"engine" in _l}
	};
	{_v setHitPointDamage [_x, 1]} forEach _wanted;
	_v setFuel 0;
	format ["vehicle=%1|hits=%2|can_move=%3", typeOf _v, count _wanted, canMove _v]
};

SWLG_doScatter = {
	params ["_g"];
	private _leader = leader _g;
	private _c = getPosATL _leader;
	private _others = ([_g] call SWLG_alive) - [_leader];
	private _step = 360 / ((count _others) max 1);
	private _placed = 0;
	{
		private _man = _x;
		private _bearing = _step * _forEachIndex;
		for "_try" from 0 to 11 do {
			private _p = _c getPos [500, _bearing + _try * 30];
			if (!surfaceIsWater _p && {[_g, _p] call SWLG_open}) exitWith {
				_man setPosATL [_p # 0, _p # 1, 0];
				_placed = _placed + 1;
			};
		};
	} forEach _others;
	format ["scattered=%1", _placed]
};

// Helper B's per-group handling throws one script error for this group when testHooks is on, then clears the variable.
SWLG_doScriptError = {
	params ["_g"];
	_g setVariable ["SWLC_sabotageError", true];
	format ["hooks=%1", SWLC_settings getOrDefault ["testHooks", false]]
};

// One sample every 10 s until the case stops being watched. A deleted group logs once and ends.
SWLG_track = {
	params ["_case", "_g", "_until", "_side", "_name"];
	while {time < _until} do {
		if (isNull _g) exitWith {
			[[format ["event=track|case=%1|group=%2|side=%3|gone=1|men=0", _case, _name, _side]]] call SWLG_emit;
		};
		[_g, true] call SWLG_protect;
		private _men = [_g] call SWLG_alive;
		private _leader = leader _g;
		if (_men isEqualTo [] || {isNull _leader} || {!alive _leader}) then {
			[[format ["event=track|case=%1|group=%2|side=%3|gone=0|men=%4|state=%5", _case, _name, _side, count _men, [_g] call SWLC_fnc_state]]] call SWLG_emit;
		} else {
			private _pos = getPosWorld _leader;
			private _spread = 0;
			{_spread = _spread max (_x distance2D _leader)} forEach _men;
			[[format ["event=track|case=%1|group=%2|side=%3|gone=0|men=%4|state=%5|x=%6|y=%7|wp=%8/%9|combat=%10|veh=%11|spread=%12",
				_case, _name, _side, count _men, [_g] call SWLC_fnc_state, round (_pos # 0), round (_pos # 1), currentWaypoint _g, count waypoints _g,
				[0, 1] select ((behaviour _leader) == "COMBAT"), ["-", typeOf vehicle _leader] select (vehicle _leader != _leader), round _spread]]] call SWLG_emit;
		};
		sleep 10;
	};
	if (!isNull _g) then {[_g, false] call SWLG_protect};
};

SWLG_runCase = {
	params ["_name", "_kind", "_minMen", "_fn"];
	private _g = grpNull;
	private _v = objNull;
	private _spawned = false;
	if (_kind == "vehicle") then {
		([] call SWLG_pickVehicle) params ["_pg", "_pv", "_ps"];
		_g = _pg;
		_v = _pv;
		_spawned = _ps;
	} else {
		_g = [_kind] call SWLG_pick;
	};
	if (isNull _g) exitWith {[[format ["event=skipped|case=%1|why=no_group", _name]]] call SWLG_emit};
	SWLG_used pushBack _g;
	if (_kind == "vehicle" && {isNull _v}) exitWith {[[format ["event=skipped|case=%1|why=no_vehicle|group=%2", _name, groupId _g]]] call SWLG_emit};
	if (_spawned) then {sleep 8};
	if (_minMen > 1) then {[_g, _minMen] call SWLG_topUp};
	[_g, true] call SWLG_protect;
	private _state = [_g] call SWLC_fnc_state;
	private _before = getPosATL leader _g;
	private _men = count ([_g] call SWLG_alive);
	private _detail = [_g, _v] call _fn;
	if (_detail isEqualTo false) exitWith {
		[_g, false] call SWLG_protect;
		[[format ["event=skipped|case=%1|why=no_place|group=%2", _name, groupId _g]]] call SWLG_emit;
	};
	[[format ["event=sabotage|case=%1|group=%2|side=%3|state=%4|men=%5|x0=%6|y0=%7|spawned=%8|%9",
		_name, groupId _g, side _g, _state, _men, round (_before # 0), round (_before # 1), _spawned, _detail]]] call SWLG_emit;
	[_name, _g, time + SWLG_watchSeconds, side _g, groupId _g] spawn SWLG_track;
};

// ---- Wait for the first wave to be on the move ----
private _deadline = time + 420;
waitUntil {
	sleep 3;
	(time >= 180 && {(count ([SWLG_movingJobs, "any"] call SWLG_candidates)) >= 6}) || {time > _deadline}
};
[[format ["event=begin|moving=%1", count ([SWLG_movingJobs, "any"] call SWLG_candidates)]]] call SWLG_emit;

private _cases = [
	["kill_leader", "foot", 3, SWLG_doKill],
	["kill_leader2", "foot", 3, SWLG_doKill],
	["no_waypoints", "foot", 0, SWLG_doNoWaypoints],
	["no_order", "foot", 0, SWLG_doNoOrder],
	["sea", "foot", 0, SWLG_doSea],
	["forest", "foot", 0, SWLG_doForest],
	["rocks", "foot", 0, SWLG_doRocks],
	["flip", "vehicle", 0, SWLG_doFlip],
	["immobilise", "vehicle", 0, SWLG_doImmobilise],
	["scatter", "foot", 4, SWLG_doScatter],
	["script_error", "foot", 0, SWLG_doScriptError]
];

{
	_x call SWLG_runCase;
	sleep SWLG_caseGap;
} forEach _cases;

// The last case still has its whole window to run.
private _end = time + SWLG_watchSeconds + 5;
waitUntil {sleep 5; time > _end};
[["event=done"]] call SWLG_emit;
