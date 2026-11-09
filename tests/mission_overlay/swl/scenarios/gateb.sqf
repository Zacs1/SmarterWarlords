// Part B gate. Run with goMinGroups=99;rallyLoneWait=99999 so the commander's own groups stay at the rally
// and only the men placed here enter the square.
// A: capture progress pauses, decays and resumes from what is left, on Warlords' own trigger.
// B: an AI warlord that respawns inside a sector being seized is moved out.
// C: a deliberately deadlocked target gets a decision within the timer plus one commander tick.
// D: a second deadlock with heavy losses makes the side pull back and rebuild.

waitUntil {sleep 1; !isNil "SWLC_ready" && {!isNil "SWLC_cmd_WEST"}};

SWLG_emit = {
	params ["_fields"];
	diag_log text ((["SWL", "GB", format ["t=%1", round time]] + _fields) joinString "|");
};

// _n invulnerable, motionless men of _side at the sector.
SWLG_place = {
	params ["_side", "_s", "_n"];
	private _g = createGroup [_side, true];
	private _cls = ["O_T_Soldier_F", "B_T_Soldier_F"] select (_side == west);
	private _c = [_s] call SWLC_fnc_adPos;
	for "_i" from 1 to _n do {
		private _u = _g createUnit [_cls, _c, [], 25, "NONE"];
		_u allowDamage false;
		_u disableAI "PATH";
	};
	_g setCombatMode "BLUE";
	_g
};

private _cmd = missionNamespace getVariable "SWLC_cmd_WEST";
waitUntil {sleep 1; !isNull ([west] call SWLC_fnc_adTarget)};
sleep 25;
private _s = [west] call SWLC_fnc_adTarget;
private _name = [_s] call SWLC_fnc_adName;
private _base = [_s, west] call SWLC_fnc_capNominalFor;
private _trg = [_s, west] call SWLC_fnc_capTrigger;
[[format ["event=setup|sector=%1|nominal=%2|have_trigger=%3", _name, _base toFixed 1, !isNull _trg]]] call SWLG_emit;

// ---- A: pause, decay, resume ----
private _men = [west, _s, 30] call SWLG_place;
// The placed men hold fire, so Warlords' sector garrison, which outweighs them on the engine's seize count, is removed for them.
SWLG_clearing = true;
[_s] spawn {
	params ["_s"];
	private _c = [_s] call SWLC_fnc_adPos;
	private _r = ((_s getVariable ["SWLC_size", 300]) * 1.5) max 150;
	while {SWLG_clearing} do {
		{
			if (alive _x && {side group _x != west}) then {
				private _v = vehicle _x;
				if (_v isNotEqualTo _x) then {
					{_v deleteVehicleCrew _x} forEach (crew _v);
					deleteVehicle _v;
				} else {deleteVehicle _x};
			};
		} forEach (_c nearEntities [["Man", "LandVehicle", "Air", "Ship"], _r] apply {effectiveCommander _x} select {!isNull _x});
		sleep 1;
	};
};
private _deadline = time + 240;
waitUntil {sleep 0.5; ([_s, west] call SWLC_fnc_capProgress) >= 0.4 || {time > _deadline}};
private _keyA = [_s, west] call SWLC_fnc_capKey;
private _recA = SWLC_capRecs getOrDefault [_keyA, createHashMap];
if (count _recA == 0) exitWith {[["event=fail_no_countdown"]] call SWLG_emit};
private _left0 = _recA get "rem";
{_x setPosATL [(getPosATL _x # 0) + 1500, (getPosATL _x # 1) + 1500, 0]} forEach units _men;
[[format ["event=pushed_off|left=%1|nominal=%2", _left0 toFixed 1, (_recA get "nominal") toFixed 1]]] call SWLG_emit;

sleep 15;
[[format ["event=held|after=15|left=%1|counting=%2", (_recA get "rem") toFixed 1, _recA get "counting"]]] call SWLG_emit;
sleep 30;
private _left1 = _recA get "rem";
[[format ["event=decayed|after=45|left=%1|counting=%2", _left1 toFixed 1, _recA get "counting"]]] call SWLG_emit;

private _pos = [_s] call SWLC_fnc_adPos;
{_x setPosATL [(_pos # 0) + (random 40) - 20, (_pos # 1) + (random 40) - 20, 0]} forEach units _men;
private _back = time;
[[format ["event=back_on|left=%1", _left1 toFixed 1]]] call SWLG_emit;
_deadline = time + 240;
waitUntil {sleep 0.5; ([_s] call SWLC_fnc_adOwner) == west || {time > _deadline}};
[[format ["event=capture_after_back|seconds=%1|owner=%2|expected=%3", (time - _back) toFixed 1, [_s] call SWLC_fnc_adOwner, _left1 toFixed 1]]] call SWLG_emit;
{deleteVehicle _x} forEach units _men;
SWLG_clearing = false;

// ---- B: respawn inside a sector being seized ----
sleep 5;
private _candidates = (_cmd get "groups") select {alive leader _x && {!isPlayer leader _x} && {[leader _x] call SWLC_fnc_adIsWarlord}};
if (_candidates isEqualTo []) exitWith {[["event=fail_no_group"]] call SWLG_emit};
private _g = _candidates # 0;
private _p = [_s] call SWLC_fnc_adPos;
// Warlords puts a respawned AI warlord beside a living subordinate, so every man in the group goes into the square.
private _sub = _g createUnit ["B_T_Soldier_F", _p, [], 10, "NONE"];
_sub allowDamage false;
{
	if (_x isNotEqualTo leader _g) then {
		_x allowDamage false;
		_x disableAI "PATH";
		_x setPosATL [(_p # 0) + (random 30) - 15, (_p # 1) + (random 30) - 15, 0];
	};
} forEach units _g;
private _trgE = [_s, east] call SWLC_fnc_capTrigger;
private _fakeKey = [_s, east] call SWLC_fnc_capKey;
SWLC_capRecs set [_fakeKey, createHashMapFromArray [["sector", _s], ["side", east], ["trg", _trgE], ["nominal", 1e6], ["rem", 1e5], ["applied", 1e5],
	["counting", true], ["started", time], ["last", time], ["countedAt", time], ["pausedAt", time]]];
// Keep the record "counting" against the capture loop, which would otherwise see the trigger idle and pause it.
SWLG_keepFake = true;
[_fakeKey] spawn {
	params ["_key"];
	while {SWLG_keepFake} do {
		private _r = SWLC_capRecs getOrDefault [_key, createHashMap];
		if (count _r > 0) then {_r set ["counting", true]; _r set ["pausedAt", time]};
		sleep 0.1;
	};
	SWLC_capRecs deleteAt _key;
};
(leader _g) setPosATL _p;
private _warlord = leader _g;
private _before = units _g;
[[format ["event=respawn_test|group=%1|seized=%2", groupId _g, [west, _s] call SWLC_fnc_capBeingSeized]]] call SWLG_emit;
sleep 2;
_warlord setDamage 1;
private _end = time + 60;
waitUntil {
	sleep 0.5;
	time > _end || {((units _g) select {alive _x && {!(_x in _before)}}) isNotEqualTo []}
};
sleep 12;
private _fresh = (units _g) select {alive _x && {!(_x in _before)}};
if (_fresh isEqualTo []) then {
	[["event=respawn_after|respawned=false"]] call SWLG_emit;
} else {
	private _u = _fresh # 0;
	[[format ["event=respawn_after|respawned=true|in_square=%1|dist=%2", [_s, getPosATL _u, 50] call SWLC_fnc_adInSquare, round (_u distance2D _p)]]] call SWLG_emit;
};
SWLG_keepFake = false;
{if (_x isNotEqualTo leader _g && {_x in _before}) then {_x allowDamage true; _x enableAI "PATH"}} forEach units _g;
deleteVehicle _sub;

// ---- C: deadlocked target ----
// A switch needs somewhere to switch to. With only one way forward, that sector is handed over and the next target is used.
private _tries = time + 240;
private _t2 = objNull;
waitUntil {
	sleep 1;
	private _now = [west] call SWLC_fnc_adTarget;
	if (!isNull _now && {_now isNotEqualTo _s} && {([_now] call SWLC_fnc_adOwner) != west}) then {
		if (([_cmd, _now] call SWLC_fnc_commitCandidates) isNotEqualTo []) then {
			_t2 = _now;
		} else {
			{
				if (vehicle _x != _x) then {deleteVehicle vehicle _x};
				deleteVehicle _x;
			} forEach (allUnits select {side group _x == resistance && {[_now, getPosATL _x, 150] call SWLC_fnc_adInSquare}});
			_now setVariable ["BIS_WL_sectorSide", west, true];
			[[format ["event=handed_over|sector=%1", [_now] call SWLC_fnc_adName]]] call SWLG_emit;
			sleep 5;
		};
	};
	!isNull _t2 || {time > _tries}
};
if (isNull _t2) exitWith {[["event=fail_no_second_target"]] call SWLG_emit};
private _name2 = [_t2] call SWLC_fnc_adName;
private _defenders = [east, _t2, 30] call SWLG_place;
sleep 20;
_cmd set ["commitUntil", time + 90];
private _setAt = time;
[[format ["event=deadlock_start|sector=%1|due=%2", _name2, round (_setAt + 90)]]] call SWLG_emit;
waitUntil {sleep 1; ([west] call SWLC_fnc_adTarget) isNotEqualTo _t2 || {time > (_setAt + 240)}};
sleep 30;
private _t3 = [west] call SWLC_fnc_adTarget;
[[format ["event=deadlock_after|new_target=%1|banned=%2|banned_is_old=%3|groups_in_old=%4", if (isNull _t3) then {"-"} else {[_t3] call SWLC_fnc_adName},
	[_cmd, _t2] call SWLC_fnc_commitBanned, _t3 isEqualTo _t2, {[_t2, getPosATL leader _x, 0] call SWLC_fnc_adInSquare} count (_cmd get "groups")]]] call SWLG_emit;
{deleteVehicle _x} forEach units _defenders;

// ---- D: pull back and rebuild ----
if (isNull _t3) exitWith {[["event=done_no_third_target"]] call SWLG_emit};
SWLC_settings set ["commitRebuildMenPerGroup", 99];
SWLC_settings set ["rebuildSeconds", 90];
_cmd set ["commitLosses", -100];
_cmd set ["commitUntil", time + 15];
[["event=rebuild_start"]] call SWLG_emit;
private _waitD = time + 60;
waitUntil {sleep 1; [_cmd] call SWLC_fnc_rebuilding || {time > _waitD}};
sleep 20;
[[format ["event=rebuild_mid|rebuilding=%1|target=%2|reserve=%3|total=%4|attacking=%5", [_cmd] call SWLC_fnc_rebuilding, if (isNull ([west] call SWLC_fnc_adTarget)) then {"-"} else {[[west] call SWLC_fnc_adTarget] call SWLC_fnc_adName},
	{([_x] call SWLC_fnc_state) == "Reserve"} count (_cmd get "groups"), count (_cmd get "groups"),
	{([_x] call SWLC_fnc_state) in ["Mustering", "Waiting", "Travelling", "Mounting", "Advancing", "Assaulting", "Regrouping"]} count (_cmd get "groups")]]] call SWLG_emit;
private _waitEnd = time + 150;
waitUntil {sleep 2; !([_cmd] call SWLC_fnc_rebuilding) && {!isNull ([west] call SWLC_fnc_adTarget)} || {time > _waitEnd}};
[[format ["event=rebuild_over|target=%1", if (isNull ([west] call SWLC_fnc_adTarget)) then {"-"} else {[[west] call SWLC_fnc_adTarget] call SWLC_fnc_adName}]]] call SWLG_emit;
[["event=done"]] call SWLG_emit;
