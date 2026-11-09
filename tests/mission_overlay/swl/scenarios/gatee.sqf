// Part E gate: pickets and the proportionate response. Run with:
//   -DurationMinutes 18 -Scenario gatee -Overrides "goMinGroups=99;rallyLoneWait=99999;scanBuying=false;ruleCommitTimer=false;defenceSightAge=25;defenceStandDownSeconds=30;raidGraceSeconds=20"
// Then: python tools/analyse_round.py <rpt> --gate parte
//
// Setup hands sectors to each side by writing BIS_WL_sectorSide, which is the only thing Warlords' seize trigger does on activation.
// Stage 1: EAST raids a picketed WEST sector with 8 men. WEST should send two groups, one from the reserve and one peeled off the
//          wave, and the wave should wait at the rally for them. The raid is called off once WEST has heard the seize alarm,
//          so the sector can't fall while the response is being watched.
// Stage 2: 8 men and then 8 more, 16 in all, which is a counterattack and has to go to the full defence rules.

waitUntil {sleep 1; !isNil "SWLC_ready" && {!isNil "SWLC_cmd_WEST"} && {!isNil "SWLC_cmd_EAST"}};

SWLG_emit = {
	params ["_fields"];
	diag_log text ((["SWL", "GE", format ["t=%1", round time]] + _fields) joinString "|");
};

SWLG_nameOf = {
	params ["_list"];
	(_list apply {[_x] call SWLC_fnc_adName}) joinString ","
};

SWLG_clearGuer = {
	params ["_s"];
	{
		if (vehicle _x != _x) then {deleteVehicle vehicle _x};
		deleteVehicle _x;
	} forEach (allUnits select {side group _x == resistance && {[_s, getPosATL _x, 150] call SWLC_fnc_adInSquare}});
};

SWLG_take = {
	params ["_side", "_s"];
	[_s] call SWLG_clearGuer;
	_s setVariable ["BIS_WL_sectorSide", _side, true];
	[[format ["event=took|side=%1|sector=%2", _side, [_s] call SWLC_fnc_adName]]] call SWLG_emit;
};

// Neutral sectors on the shortest route between the two sides' territory, nearest WEST first.
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

SWLG_free = {
	params ["_cmd", "_n"];
	private _pool = (_cmd get "groups") select {([_x] call SWLC_fnc_state) == "Waiting" && {vehicle leader _x == leader _x}};
	{
		[_cmd, _x] call SWLC_fnc_waveRemoveGroup;
		[_x] call SWLC_fnc_adClearOrder;
		[_x, "Unassigned", [], "test_free"] call SWLC_fnc_setState;
	} forEach (_pool select [0, _n]);
};

SWLG_placeEast = {
	params ["_s", "_n"];
	private _g = createGroup [east, true];
	private _c = [_s] call SWLC_fnc_adPos;
	for "_i" from 1 to _n do {
		private _u = _g createUnit ["O_T_Soldier_F", _c, [], 25, "NONE"];
		_u allowDamage false;
		_u disableAI "PATH";
	};
	_g setCombatMode "BLUE";
	_g
};

SWLG_inState = {
	params ["_cmd", "_states"];
	(_cmd get "groups") select {([_x] call SWLC_fnc_state) in _states}
};

SWLG_threat = {
	params ["_cmd", "_name"];
	(_cmd get "threats") getOrDefault [_name, createHashMap]
};

SWLG_scrub = {
	params ["_cmd", "_s"];
	_cmd set ["board", (_cmd get "board") select {!((_x get "sector") isEqualTo _s)}];
};

SWLG_op = {
	params ["_cmd"];
	_cmd getOrDefault ["op", createHashMap]
};

// Live groups in the current wave, or none when there is no wave.
SWLG_live = {
	params ["_cmd"];
	private _op = [_cmd] call SWLG_op;
	if (count _op == 0) exitWith {[]};
	[_op] call SWLC_fnc_waveLive
};

SWLG_peeled = {
	params ["_cmd"];
	(_cmd get "groups") select {(_x getVariable ["SWLC_peeledOp", -1]) >= 0 && {([_x] call SWLC_fnc_state) == "Defending"}}
};

// Each loop reports the placed men to whoever is watching, the same way a soldier spotting them would.
SWLG_enemy = [];
SWLG_watch = {
	params ["_cmd"];
	while {true} do {
		if (SWLG_enemy isNotEqualTo []) then {
			private _eyes = [_cmd, ["Picket", "Defending"]] call SWLG_inState;
			if (_eyes isEqualTo []) then {_eyes = (_cmd get "groups") select [0, 2]};
			{
				private _leader = leader _x;
				{
					{_leader reveal [_x, 4]} forEach units _x;
				} forEach SWLG_enemy;
			} forEach _eyes;
		};
		sleep 3;
	};
};

// Picket and responders mustn't die: the gates are about where they go, not how the fight turns out.
SWLG_guard = {
	params ["_cmd"];
	while {true} do {
		{{_x allowDamage false} forEach units _x} forEach ([_cmd, ["Picket", "Defending"]] call SWLG_inState);
		sleep 2;
	};
};

// Warlords' seize trigger needs the attackers to outnumber everyone else in the square, as gateb found.
SWLG_shoveOn = false;
SWLG_shove = {
	params ["_s"];
	private _c = [_s] call SWLC_fnc_adPos;
	private _d = (([_s] call SWLC_fnc_adSize) / 2) + 90;
	while {SWLG_shoveOn} do {
		{
			if (!isPlayer _x) then {_x setPosATL [(_c # 0) + _d + random 20, (_c # 1) + random 40, 0]};
		} forEach (allUnits select {side group _x == west && {[_s, getPosATL _x, 25] call SWLC_fnc_adInSquare}});
		sleep 1;
	};
};

private _cmd = missionNamespace getVariable "SWLC_cmd_WEST";
private _cmdE = missionNamespace getVariable "SWLC_cmd_EAST";
{_x set ["raidNextCheck", 1e9]; _x set ["probeNext", 1e9]} forEach [_cmd, _cmdE];
// One reserve group, so a response needing two has to take the second from the wave.
SWLC_settings set ["reserveBySectors", [[999, 1]]];

// ---- Setup: WEST and EAST sectors touching, so WEST has a front line to picket ----
private _deadline = time + 300;
// The picket front is what this test needs. The raid front leaves out the side's own target, which can be the only enemy neighbour.
while {(([west] call SWLC_fnc_picketFront) isEqualTo []) && {time < _deadline}} do {
	private _route = [] call SWLG_path;
	private _lastOne = if (count _route == 1) then {_route # 0} else {objNull};
	if (_route isNotEqualTo []) then {
		if (isNull _lastOne) then {_cmd set ["preferredTarget", _route # 0]};
		_cmdE set ["preferredTarget", _route # ((count _route) - 1)];
	};
	{
		private _side = _x;
		private _t = [_side] call SWLC_fnc_adTarget;
		if (!isNull _t && {!([_t] call SWLC_fnc_adIsBase)} && {!(([_t] call SWLC_fnc_adOwner) in [west, east])} && {_side == east || {!(_t isEqualTo _lastOne)}}) then {
			[_side, _t] call SWLG_take;
		};
	} forEach [west, east];
	sleep 8;
};
if (([west] call SWLC_fnc_picketFront) isEqualTo []) exitWith {[["event=fail_no_front"]] call SWLG_emit};
[[format ["event=front|enemy_front=%1|picket_front=%2|owned=%3", [[west] call SWLC_fnc_raidFront] call SWLG_nameOf, [[west] call SWLC_fnc_picketFront] call SWLG_nameOf, [[west] call SWLC_fnc_adOwned] call SWLG_nameOf]]] call SWLG_emit;

[_cmd] spawn SWLG_guard;
[_cmd] spawn SWLG_watch;

// ---- A picketed front-line sector ----
private _freed = false;
_deadline = time + 120;
private _picketed = [];
waitUntil {
	sleep 2;
	_picketed = ([_cmd, ["Picket"]] call SWLG_inState) select {!isNull (_x getVariable ["SWLC_picketSector", objNull])};
	if (_picketed isEqualTo [] && {!_freed} && {time > _deadline - 90}) then {_freed = true; [_cmd, 2] call SWLG_free};
	_picketed isNotEqualTo [] || {time > _deadline}
};
private _sector = objNull;
private _picket = grpNull;
if (_picketed isEqualTo []) then {
	_sector = ([west] call SWLC_fnc_picketFront) # 0;
	[[format ["event=picket_missing|sector=%1", [_sector] call SWLC_fnc_adName]]] call SWLG_emit;
} else {
	_picket = _picketed # 0;
	_sector = _picket getVariable "SWLC_picketSector";
};
private _name = [_sector] call SWLC_fnc_adName;
[[format ["event=picket|sector=%1|group=%2|men=%3|pickets=%4", _name, if (isNull _picket) then {"-"} else {groupId _picket}, if (isNull _picket) then {0} else {[_picket] call SWLC_fnc_groupMen}, count _picketed]]] call SWLG_emit;

// EAST mustn't happen to vote for the sector under test.
private _eastTargets = ([east] call SWLC_fnc_adAvailable) - [_sector];
// On a chain of sectors the sector under test can be EAST's only choice, so hand a sector behind EAST's line back to neutral to give it another.
if (_eastTargets isEqualTo []) then {
	private _links = [_sector] call SWLC_fnc_adLinks;
	private _spare = ([east] call SWLC_fnc_adOwned) select {!([_x] call SWLC_fnc_adIsBase) && {!(_x in _links)}};
	if (_spare isNotEqualTo []) then {
		(_spare # 0) setVariable ["BIS_WL_sectorSide", resistance, true];
		[[format ["event=east_spare|sector=%1", [_spare # 0] call SWLC_fnc_adName]]] call SWLG_emit;
		sleep 2;
		_eastTargets = ([east] call SWLC_fnc_adAvailable) - [_sector];
	};
};
[[format ["event=east_options|count=%1", count _eastTargets]]] call SWLG_emit;
if (_eastTargets isNotEqualTo []) then {_cmdE set ["preferredTarget", _eastTargets # 0]};
// A vote that is already running can still land on it, and a raid on the side's own target stands itself down.
private _settle = time + 120;
waitUntil {
	if ((([east] call SWLC_fnc_adTarget) isEqualTo _sector) && {_eastTargets isNotEqualTo []}) then {
		_cmdE set ["preferredTarget", _eastTargets # 0];
		[east] call SWLC_fnc_adForceRevote;
		[[format ["event=east_revote|from=%1|to=%2", _name, [_eastTargets # 0] call SWLC_fnc_adName]]] call SWLG_emit;
		sleep 25;
	};
	sleep 2;
	private _after = [east] call SWLC_fnc_adTarget;
	(!isNull _after && {_after isNotEqualTo _sector}) || {time > _settle}
};
[[format ["event=east_settled|target=%1", [[east] call SWLC_fnc_adTarget] call {params ["_t"]; if (isNull _t) then {"-"} else {[_t] call SWLC_fnc_adName}}]]] call SWLG_emit;

// ---- A wave waiting at the rally and a reserve group ----
_deadline = time + 240;
waitUntil {
	sleep 2;
	({([_x] call SWLC_fnc_state) == "Waiting"} count ([_cmd] call SWLG_live)) >= 3 || {time > _deadline}
};
_deadline = time + 45;
waitUntil {
	sleep 1;
	if (([_cmd, ["Reserve"]] call SWLG_inState) isEqualTo [] && {([_cmd, ["Unassigned"]] call SWLG_inState) isEqualTo []}) then {[_cmd, 1] call SWLG_free};
	([_cmd, ["Reserve"]] call SWLG_inState) isNotEqualTo [] || {time > _deadline}
};
private _live = [_cmd] call SWLG_live;
[[format ["event=wave_ready|live=%1|waiting=%2|reserve=%3|target=%4", count _live, {([_x] call SWLC_fnc_state) == "Waiting"} count _live, count ([_cmd, ["Reserve"]] call SWLG_inState),
	[[_cmd] call SWLG_op getOrDefault ["target", objNull]] call {params ["_t"]; if (isNull _t) then {"-"} else {[_t] call SWLC_fnc_adName}}]]] call SWLG_emit;

// ---- Stage 1: a small raid ----
// The picket and the one reserve group answer first, so the reply has to need three for one to come from the wave.
private _menPerGroup = SWLC_settings get "defenceMenPerGroup";
SWLC_settings set ["defenceMenPerGroup", 4];
private _rec1 = [_cmdE, _sector, "test", []] call SWLC_fnc_raidStart;
private _men = [_sector, 8] call SWLG_placeEast;
SWLG_enemy = [_men];
SWLG_shoveOn = true;
[_sector] spawn SWLG_shove;
[[format ["event=stage1_start|sector=%1|men=8|mult=%2", _name, _sector getVariable ["SWLC_capMult_EAST", -1]]]] call SWLG_emit;

private _startedAt = time;
_deadline = time + 45;
waitUntil {sleep 0.5; (([_cmd, _name] call SWLG_threat) getOrDefault ["seizeCalled", false]) || {time > _deadline}};
private _forced = !(([_cmd, _name] call SWLG_threat) getOrDefault ["seizeCalled", false]);
if (_forced) then {
	// The engine never started counting, so the alarm is raised by hand and the gate reports that it was.
	_deadline = time + 25;
	waitUntil {
		_sector setVariable ["BIS_WL_timeoutCur_EAST", 30];
		sleep 0.5;
		(([_cmd, _name] call SWLG_threat) getOrDefault ["seizeCalled", false]) || {time > _deadline}
	};
	_sector setVariable ["BIS_WL_timeoutCur_EAST", 0];
};
SWLG_shoveOn = false;
[[format ["event=seizing|forced=%1|called=%2|after=%3", _forced, ([_cmd, _name] call SWLG_threat) getOrDefault ["seizeCalled", false], round (time - _startedAt)]]] call SWLG_emit;
// The sector stays WEST's for the rest of the test, however long the response takes.
[_cmdE, _rec1, "test_over"] call SWLC_fnc_raidStop;

// Wait for the peel, then force the hold: a wave this size would otherwise carry on without waiting.
private _peeledGroups = [];
_deadline = time + 60;
waitUntil {
	sleep 1;
	_peeledGroups = [_cmd] call SWLG_peeled;
	_peeledGroups isNotEqualTo [] || {time > _deadline}
};
private _th1 = [_cmd, _name] call SWLG_threat;
private _liveAtPeel = [_cmd] call SWLG_live;
[[format ["event=stage1_response|peeled=%1|need=%2|groups=%3|strength=%4|live=%5|reserve_left=%6", count _peeledGroups, _th1 getOrDefault ["need", -1], count (_th1 getOrDefault ["groups", []]),
	_th1 getOrDefault ["strength", -1], count _liveAtPeel, count ([_cmd, ["Reserve"]] call SWLG_inState)]]] call SWLG_emit;
SWLC_settings set ["goMinGroups", 2];
SWLC_settings set ["peelWorkableGroups", 99];

// Let the response play out, including any second peel.
_deadline = time + 45;
private _seenPeels = _peeledGroups select {true};
waitUntil {
	sleep 1;
	{_seenPeels pushBackUnique _x} forEach ([_cmd] call SWLG_peeled);
	time > _deadline
};
_th1 = [_cmd, _name] call SWLG_threat;
private _responders = _th1 getOrDefault ["groups", []];
[[format ["event=stage1_held|peeled=%1|need=%2|groups=%3|phase=%4|live=%5", count _seenPeels, _th1 getOrDefault ["need", -1], count _responders, ([_cmd] call SWLG_op) getOrDefault ["phase", "-"], count ([_cmd] call SWLG_live)]]] call SWLG_emit;

// The raid is over: nobody left to see, so the responders can go back.
SWLG_enemy = [];
{deleteVehicle _x} forEach units _men;
deleteGroup _men;
[_cmd, _sector] call SWLG_scrub;
_deadline = time + 90;
waitUntil {
	sleep 2;
	[_cmd, _sector] call SWLG_scrub;
	(count ([_cmd, _name] call SWLG_threat)) == 0 || {time > _deadline}
};
sleep 12;
{
	[[format ["event=returned|group=%1|state=%2|peeled_flag=%3", groupId _x, [_x] call SWLC_fnc_state, _x getVariable ["SWLC_peeledOp", -1]]]] call SWLG_emit;
} forEach _seenPeels;
[[format ["event=stage1_clear|threat_gone=%1|phase=%2", (count ([_cmd, _name] call SWLG_threat)) == 0, ([_cmd] call SWLG_op) getOrDefault ["phase", "-"]]]] call SWLG_emit;

// The wave should now go, and not before.
_deadline = time + 90;
waitUntil {sleep 1; (([_cmd] call SWLG_op) getOrDefault ["phase", "-"]) == "ASSAULT" || {time > _deadline}};
[[format ["event=stage1_assault|phase=%1", ([_cmd] call SWLG_op) getOrDefault ["phase", "-"]]]] call SWLG_emit;
SWLC_settings set ["goMinGroups", 99];
SWLC_settings set ["peelWorkableGroups", 3];

// ---- Stage 2: a counterattack ----
SWLC_settings set ["defenceMenPerGroup", _menPerGroup];
_deadline = time + 90;
waitUntil {
	sleep 2;
	([_cmd, ["Reserve"]] call SWLG_inState) isNotEqualTo [] || {(count ([_cmd] call SWLG_live)) >= 2} || {time > _deadline}
};
private _first = [_sector, 8] call SWLG_placeEast;
SWLG_enemy = [_first];
[[format ["event=stage2_start|sector=%1|men=8|reserve=%2|live=%3", _name, count ([_cmd, ["Reserve"]] call SWLG_inState), count ([_cmd] call SWLG_live)]]] call SWLG_emit;
_deadline = time + 75;
waitUntil {sleep 1; (count (([_cmd, _name] call SWLG_threat) getOrDefault ["groups", []])) > 0 || {time > _deadline}};
private _th2 = [_cmd, _name] call SWLG_threat;
[[format ["event=stage2_first|need=%1|groups=%2|strength=%3", _th2 getOrDefault ["need", -1], count (_th2 getOrDefault ["groups", []]), _th2 getOrDefault ["strength", -1]]]] call SWLG_emit;

private _second = [_sector, 8] call SWLG_placeEast;
SWLG_enemy = [_first, _second];
_deadline = time + 60;
waitUntil {sleep 1; ((([_cmd, _name] call SWLG_threat) getOrDefault ["strength", 0]) >= (SWLC_settings get "responseCounterattackMen")) || {time > _deadline}};
_th2 = [_cmd, _name] call SWLG_threat;
[[format ["event=strength_big|reached=%1|strength=%2|need=%3|groups=%4", (_th2 getOrDefault ["strength", 0]) >= (SWLC_settings get "responseCounterattackMen"), _th2 getOrDefault ["strength", -1], _th2 getOrDefault ["need", -1], count (_th2 getOrDefault ["groups", []])]]] call SWLG_emit;
sleep 40;
_th2 = [_cmd, _name] call SWLG_threat;
[[format ["event=stage2_over|strength=%1|need=%2|groups=%3|owner=%4", _th2 getOrDefault ["strength", -1], _th2 getOrDefault ["need", -1], count (_th2 getOrDefault ["groups", []]), [_sector] call SWLC_fnc_adOwner]]] call SWLG_emit;

SWLG_enemy = [];
{{deleteVehicle _x} forEach units _x; deleteGroup _x} forEach [_first, _second];
[["event=done"]] call SWLG_emit;
