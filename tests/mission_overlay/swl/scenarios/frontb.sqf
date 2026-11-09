// Front line part B gate: defender fast travel until real fighting reaches a sector. Run with:
//   powershell -ExecutionPolicy Bypass -File tools\run-round.ps1 -DurationMinutes 15 -Name frontb -Scenario frontb -Overrides "goMinGroups=99;rallyLoneWait=99999;scanBuying=false;ruleCommitTimer=false;ftChargeCost=false"
// Then: python tools/analyse_round.py <rpt> --gate frontb
//
// Lines go out as SWL|GFB. One WEST-owned sector next to WEST's base is the test sector. Men are placed in it and "fire" by having
// SWLC_firedAt written on them directly, so the state machine is tested on its own and not how well AI shoots on a given day.
// That also means this doesn't test the firing handlers themselves; a real round's C_FRONT lines do that.
// The seize case raises the seize alarm by hand, as gatee's fallback does.

waitUntil {sleep 1; !isNil "SWLC_ready" && {!isNil "SWLC_cmd_WEST"} && {!isNil "SWLC_cmd_EAST"}};

SWLG_emit = {
	params ["_fields"];
	diag_log text ((["SWL", "GFB", format ["t=%1", round time]] + _fields) joinString "|");
};

SWLG_firing = [];
SWLG_done = false;
[] spawn {
	while {!SWLG_done} do {
		{_x setVariable ["SWLC_firedAt", time]} forEach SWLG_firing;
		sleep 3;
	};
};

SWLG_place = {
	params ["_side", "_n"];
	private _class = ["B_T_Soldier_F", "O_T_Soldier_F"] select (_side == east);
	private _g = createGroup [_side, true];
	private _c = [SWLG_y] call SWLC_fnc_adPos;
	for "_i" from 1 to _n do {
		private _u = _g createUnit [_class, _c, [], 30, "NONE"];
		_u allowDamage false;
		{_u disableAI _x} forEach ["PATH", "TARGET", "AUTOTARGET"];
		_u setCaptive true;
	};
	_g setCombatMode "BLUE";
	_g
};

SWLG_clear = {
	params ["_groups"];
	SWLG_firing = [];
	{{deleteVehicle _x} forEach units _x; deleteGroup _x} forEach _groups;
};

SWLG_sample = {
	params ["_case"];
	[[format ["event=sample|case=%1|fighting=%2|ftopen=%3|canft=%4|var=%5", _case, [SWLG_y] call SWLC_fnc_frontFighting, [west, SWLG_y] call SWLC_fnc_frontFTOpen,
		[west, SWLG_y] call SWLC_fnc_adCanFTTo, SWLG_y getVariable ["FastTravelEnabled", true]]]] call SWLG_emit;
};

// Watches the sector for up to _seconds, logging every change of state. Stops early on the state asked for.
SWLG_watchCase = {
	params ["_case", "_seconds", ["_stopOnClosed", false], ["_stopOnOpen", false]];
	private _start = time;
	private _end = _start + _seconds;
	private _nextSample = _start;
	private _on = [SWLG_y] call SWLC_fnc_frontFighting;
	[[format ["event=case_start|case=%1|on=%2", _case, _on]]] call SWLG_emit;
	waitUntil {
		sleep 1;
		private _now = [SWLG_y] call SWLC_fnc_frontFighting;
		if (_now isNotEqualTo _on) then {
			_on = _now;
			[[format ["event=change|case=%1|on=%2|after=%3", _case, _on, round (time - _start)]]] call SWLG_emit;
		};
		if (time >= _nextSample) then {
			_nextSample = time + 5;
			[_case] call SWLG_sample;
		};
		time > _end || {_stopOnClosed && {_on}} || {_stopOnOpen && {!_on}}
	};
	[_case] call SWLG_sample;
};

// A real fast travel attempt, with the commander's own function. The man goes back to base afterwards.
SWLG_ftTry = {
	params ["_case"];
	private _man = leader SWLG_ftGroup;
	SWLG_ftGroup setVariable ["SWLC_lastFT", -1000];
	private _moved = [SWLG_ftGroup, SWLG_y, [SWLG_y] call SWLC_fnc_adPos, true] call SWLC_fnc_adFastTravel;
	private _other = [west, [west] call SWLC_fnc_adBase] call SWLC_fnc_adCanFTTo;
	[[format ["event=ft|case=%1|moved=%2|canft=%3|ftopen=%4|var=%5|other=%6|fighting=%7", _case, _moved, [west, SWLG_y] call SWLC_fnc_adCanFTTo,
		[west, SWLG_y] call SWLC_fnc_frontFTOpen, SWLG_y getVariable ["FastTravelEnabled", true], _other, [SWLG_y] call SWLC_fnc_frontFighting]]] call SWLG_emit;
	_man setPosATL SWLG_homePos;
};

private _cmdW = missionNamespace getVariable "SWLC_cmd_WEST";
private _cmdE = missionNamespace getVariable "SWLC_cmd_EAST";
{_x set ["raidNextCheck", 1e9]; _x set ["probeNext", 1e9]} forEach [_cmdW, _cmdE];

// ---- Setup: one WEST sector that isn't the base ----
private _base = [west] call SWLC_fnc_adBase;
private _target = [west] call SWLC_fnc_adTarget;
private _links = [_base] call SWLC_fnc_adLinks;
private _choices = ([west] call SWLC_fnc_adOwned) select {!([_x] call SWLC_fnc_adIsBase) && {!(_x isEqualTo _target)}};
if (_choices isEqualTo []) then {
	_choices = _links select {!(([_x] call SWLC_fnc_adOwner) in [west, east]) && {!(_x isEqualTo _target)}};
};
if (_choices isEqualTo []) then {_choices = _links select {([_x] call SWLC_fnc_adOwner) != east}};
if (_choices isEqualTo []) exitWith {[["event=fail_no_sector"]] call SWLG_emit};
SWLG_y = _choices # 0;
private _yName = [SWLG_y] call SWLC_fnc_adName;
if (([SWLG_y] call SWLC_fnc_adOwner) != west) then {
	{
		if (vehicle _x != _x) then {deleteVehicle vehicle _x};
		deleteVehicle _x;
	} forEach (allUnits select {side group _x == resistance && {[SWLG_y, getPosATL _x, 200] call SWLC_fnc_adInSquare}});
	SWLG_y setVariable ["BIS_WL_sectorSide", west, true];
};
sleep 8;
[[format ["event=setup|sector=%1|owner=%2|size=%3|east_target=%4", _yName, [SWLG_y] call SWLC_fnc_adOwner, [SWLG_y] call SWLC_fnc_adSize, ([east] call SWLC_fnc_adTarget) isEqualTo SWLG_y]]] call SWLG_emit;

// The man who tries the fast travels.
private _basePos = [_base] call SWLC_fnc_adPos;
SWLG_homePos = _basePos getPos [40, random 360];
SWLG_ftGroup = createGroup [west, true];
private _ftMan = SWLG_ftGroup createUnit ["B_T_Soldier_F", SWLG_homePos, [], 5, "NONE"];
_ftMan allowDamage false;
_ftMan disableAI "PATH";

// Defenders stay for the whole test.
private _west = [west, 4] call SWLG_place;
private _defenders = units _west;

// ---- Case 1: a lone enemy hidden in the sector ----
private _lone = [east, 1] call SWLG_place;
["hidden", 100] call SWLG_watchCase;
["hidden"] call SWLG_ftTry;
[[_lone]] call SWLG_clear;
sleep 6;

// ---- Case 2: a lone enemy shooting from inside, defenders shooting back, one defender killed ----
_lone = [east, 1] call SWLG_place;
SWLG_firing = (units _lone) + _defenders;
["shooting", 60] call SWLG_watchCase;
(_defenders select ((count _defenders) - 1)) setDamage [1, true, leader _lone, leader _lone];
[[format ["event=killed_defender|left=%1", {alive _x} count _defenders]]] call SWLG_emit;
["shooting", 60] call SWLG_watchCase;
["shooting"] call SWLG_ftTry;
[[_lone]] call SWLG_clear;
sleep 20;

// ---- Case 3: four attackers in a sustained exchange ----
private _attackers = [east, 4] call SWLG_place;
SWLG_firing = (units _attackers) + (_defenders select {alive _x});
["exchange", 100, true] call SWLG_watchCase;
["exchange"] call SWLG_ftTry;
// Still fighting: it must stay closed.
["exchange_more", 20] call SWLG_watchCase;
["exchange_more"] call SWLG_ftTry;
SWLG_firing = [];
[["event=fire_stopped|case=exchange"]] call SWLG_emit;
// Attackers stay, hiding. Two quiet minutes must still reopen it.
["exchange_quiet", 170, false, true] call SWLG_watchCase;
["exchange_quiet"] call SWLG_ftTry;
[[_attackers]] call SWLG_clear;
sleep 6;

// ---- Case 4: the enemy seizing it ----
private _seizeEnd = time + 20;
SWLG_y setVariable ["BIS_WL_timeoutCur_EAST", 30];
["seizing", 20, true] call SWLG_watchCase;
["seizing"] call SWLG_ftTry;
waitUntil {sleep 1; SWLG_y setVariable ["BIS_WL_timeoutCur_EAST", 30]; time > _seizeEnd};
SWLG_y setVariable ["BIS_WL_timeoutCur_EAST", 0];
[["event=fire_stopped|case=seizing"]] call SWLG_emit;
["seizing_quiet", 170, false, true] call SWLG_watchCase;
["seizing_quiet"] call SWLG_ftTry;

SWLG_done = true;
[["event=done"]] call SWLG_emit;
