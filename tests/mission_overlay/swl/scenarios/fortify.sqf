// Fortify gate: defenders buy, place and crew statics when their sector is threatened. Run with:
//   powershell -ExecutionPolicy Bypass -File tools\run-round.ps1 -DurationMinutes 12 -Name fortify -Scenario fortify -Overrides "goMinGroups=99;rallyLoneWait=99999;scanBuying=false;ruleCommitTimer=false;ftChargeCost=false"
// Then: python tools/analyse_round.py <rpt> --gate fortify
//
// Lines go out as SWL|GFORT. Test hook: this writes the alert record and the stance straight onto the WEST commander record, so it
// tests fortify on its own and not how the alert helper decides a sector is threatened. A real round's C_ALERT and C_FORT lines do that.
// One WEST sector, three defending groups of five (leader, three riflemen, one AT soldier), all kept from dying except the man shot on purpose.
// EAST never gets an alert, and neither side's raids or waves run.

waitUntil {sleep 1; !isNil "SWLC_ready" && {!isNil "SWLC_cmd_WEST"} && {!isNil "SWLC_cmd_EAST"}};

SWLG_emit = {
	params ["_fields"];
	diag_log text ((["SWL", "GFORT", format ["t=%1", round time]] + _fields) joinString "|");
};

private _cmdW = missionNamespace getVariable "SWLC_cmd_WEST";
private _cmdE = missionNamespace getVariable "SWLC_cmd_EAST";
{_x set ["raidNextCheck", 1e9]; _x set ["probeNext", 1e9]} forEach [_cmdW, _cmdE];
SWLG_cmd = _cmdW;

// The stance module, if merged, may recompute this: writing it every second keeps the test's stance in force.
SWLG_stance = "attack";
[] spawn {
	while {true} do {
		SWLG_cmd set ["stance", SWLG_stance];
		sleep 1;
	};
};

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
SWLG_s = _choices # 0;
SWLG_name = [SWLG_s] call SWLC_fnc_adName;
SWLG_c = [SWLG_s] call SWLC_fnc_adPos;
if (([SWLG_s] call SWLC_fnc_adOwner) != west) then {
	{
		if (vehicle _x != _x) then {deleteVehicle vehicle _x};
		deleteVehicle _x;
	} forEach (allUnits select {side group _x == resistance && {[SWLG_s, getPosATL _x, 200] call SWLC_fnc_adInSquare}});
	SWLG_s setVariable ["BIS_WL_sectorSide", west, true];
};
sleep 8;

// The approach: from the sector towards EAST's base, with whatever road lies that way.
private _size = [SWLG_s] call SWLC_fnc_adSize;
SWLG_bearing = SWLG_c getDir ([[east] call SWLC_fnc_adBase] call SWLC_fnc_adPos);
SWLG_aim = SWLG_c getPos [(_size / 2) + 150, SWLG_bearing];
private _roadCentre = SWLG_c getPos [_size * 0.3, SWLG_bearing];
SWLG_roads = ((_roadCentre nearRoads 120) apply {getPosATL _x}) select {!surfaceIsWater _x};
SWLG_roads = SWLG_roads select [0, 4];

// Three groups of five near the sector centre.
SWLG_groups = [];
for "_g" from 1 to 3 do {
	private _grp = createGroup [west, true];
	private _spawn = SWLG_c getPos [20 + (_g * 12), random 360];
	{
		private _u = _grp createUnit [_x, _spawn, [], 8, "NONE"];
		_u allowDamage false;
	} forEach ["B_T_Soldier_TL_F", "B_T_Soldier_F", "B_T_Soldier_F", "B_T_Soldier_F", "B_T_Soldier_LAT_F"];
	_grp selectLeader ((units _grp) # 0);
	SWLG_groups pushBack _grp;
};

SWLG_fund = {
	private _cap = missionNamespace getVariable ["BIS_WL_maxCP", 50000];
	{_x setVariable ["BIS_WL_funds", 20000 min _cap, true]} forEach ([west] call SWLC_fnc_adAIWarlords);
};
[] call SWLG_fund;

SWLG_alertOn = {
	SWLG_cmd set ["alert", createHashMapFromArray [
		["sector", SWLG_s], ["since", time], ["approach", [SWLG_bearing, SWLG_aim, SWLG_roads]],
		["groups", SWLG_groups], ["screen", []], ["counter", []]
	]];
};
SWLG_alertOff = {SWLG_cmd set ["alert", createHashMap]};

SWLG_recs = {
	private _all = (SWLG_cmd getOrDefault ["fort", createHashMap]) getOrDefault [SWLG_name, []];
	_all select {alive (_x get "gun")}
};

// How far each gun's facing and position are from the approach, whether it is crewed and by whom.
SWLG_sample = {
	params ["_stage"];
	private _recs = [] call SWLG_recs;
	private _crewed = {alive gunner (_x get "gun")} count _recs;
	[[format ["event=sample|stage=%1|guns=%2|crewed=%3|stance=%4|cp=%5", _stage, count _recs, _crewed, SWLG_stance, round ([west] call SWLC_fnc_adSideCP)]]] call SWLG_emit;
	{
		private _gun = _x get "gun";
		private _p = getPosATL _gun;
		private _man = gunner _gun;
		private _hasMan = alive _man;
		private _off = [SWLG_c getDir _p, SWLG_bearing] call SWLC_fnc_fortAngle;
		private _face = [getDir _gun, _p getDir SWLG_aim] call SWLC_fnc_fortAngle;
		private _faceB = [getDir _gun, SWLG_bearing] call SWLC_fnc_fortAngle;
		private _nearest = 1e6;
		{
			if (!(_x isEqualTo _gun)) then {_nearest = _nearest min (_gun distance2D _x)};
		} forEach ((([] call SWLG_recs)) apply {_x get "gun"});
		[[format ["event=gun|stage=%1|id=%2_%3|class=%4|kind=%5|dist=%6|off=%7|face=%8|faceb=%9", _stage, round (_p # 0), round (_p # 1), typeOf _gun, _x get "kind", round (_p distance2D SWLG_c), round _off, round _face, round _faceB]
			+ format ["|road=%1|nearest=%2|manned=%3|leader=%4|at=%5|ingroup=%6", isOnRoad _p, round _nearest, _hasMan,
				_hasMan && {(leader group _man) isEqualTo _man},
				_hasMan && {([secondaryWeapon _man] call SWLC_fnc_adLauncherKind) == "AT"},
				_hasMan && {(group _man) in SWLG_groups}]]] call SWLG_emit;
	} forEach _recs;
};

SWLG_atSample = {
	params ["_stage"];
	private _men = [];
	{{if ((_x getVariable ["SWLC_fortAT", []]) isNotEqualTo []) then {_men pushBack _x}} forEach units _x} forEach SWLG_groups;
	{
		private _job = _x getVariable ["SWLC_fortAT", []];
		private _roadGap = 1e6;
		{_roadGap = _roadGap min (_x distance2D (_job # 0))} forEach SWLG_roads;
		[[format ["event=at|stage=%1|holding=%2|to_spot=%3|spot_on_road=%4|spot_road_gap=%5", _stage, _job # 2, round (_x distance2D (_job # 0)), isOnRoad (_job # 0), round _roadGap]]] call SWLG_emit;
	} forEach _men;
	[[format ["event=at_summary|stage=%1|men=%2|roads=%3", _stage, count _men, count SWLG_roads]]] call SWLG_emit;
};

[[format ["event=setup|sector=%1|owner=%2|size=%3|bearing=%4|roads=%5", SWLG_name, [SWLG_s] call SWLC_fnc_adOwner, _size, round SWLG_bearing, count SWLG_roads]]] call SWLG_emit;

// ---- 1. No alert: nothing is bought ----
sleep 30;
["noalert"] call SWLG_sample;
[["event=noalert_end"]] call SWLG_emit;

// ---- 2. Alert while attacking: cap of 2 ----
[] call SWLG_fund;
SWLG_stance = "attack";
sleep 2;
[] call SWLG_alertOn;
[["event=alert_on|n=1"]] call SWLG_emit;
private _end = time + 100;
waitUntil {sleep 5; (count ([] call SWLG_recs)) >= 2 || {time > _end}};
sleep 30;
["attack"] call SWLG_sample;

// ---- 3. Stance changes to hold: cap of 4, everything crewed ----
[] call SWLG_fund;
SWLG_stance = "hold";
[["event=stance_hold"]] call SWLG_emit;
_end = time + 90;
waitUntil {sleep 5; (count ([] call SWLG_recs)) >= 4 || {time > _end}};
_end = time + 120;
waitUntil {
	sleep 5;
	private _recs = [] call SWLG_recs;
	({alive gunner (_x get "gun")} count _recs) == (count _recs) && {(count _recs) > 0} || {time > _end}
};
sleep 5;
["hold"] call SWLG_sample;
["hold"] call SWLG_atSample;

// ---- 4. A gunner is killed: he is replaced from the same groups ----
private _crewed = ([] call SWLG_recs) select {alive gunner (_x get "gun")};
if (_crewed isEqualTo []) then {
	[["event=kill_skipped|why=no_crew"]] call SWLG_emit;
} else {
	private _rec = _crewed # 0;
	private _gun = _rec get "gun";
	private _man = gunner _gun;
	_man allowDamage true;
	_man setDamage 1;
	private _killedAt = getPosATL _gun;
	[[format ["event=killed|id=%1_%2", round (_killedAt # 0), round (_killedAt # 1)]]] call SWLG_emit;
	private _start = time;
	private _deadline = _start + 75;
	waitUntil {
		sleep 2;
		(alive gunner _gun && {!((gunner _gun) isEqualTo _man)}) || {time > _deadline}
	};
	private _now = gunner _gun;
	[[format ["event=replaced|ok=%1|after=%2|ingroup=%3", alive _now && {!(_now isEqualTo _man)}, round (time - _start), alive _now && {(group _now) in SWLG_groups}]]] call SWLG_emit;
};

// ---- 5. Alert ends: guns stay, crews go back, AT men released ----
[] call SWLG_alertOff;
[["event=alert_off|n=1"]] call SWLG_emit;
_end = time + 45;
waitUntil {
	sleep 3;
	private _recs = [] call SWLG_recs;
	({alive gunner (_x get "gun")} count _recs) == 0 || {time > _end}
};
["standdown"] call SWLG_sample;
["standdown"] call SWLG_atSample;
private _held = 0;
{{if (!isNull (_x getVariable ["SWLC_fortGun", objNull])) then {_held = _held + 1}} forEach units _x} forEach SWLG_groups;
[[format ["event=released|fortgun_vars=%1", _held]]] call SWLG_emit;

// ---- 6. A second alert at the same sector: nothing more is bought past the cap, the guns are crewed again ----
[] call SWLG_fund;
sleep 5;
[] call SWLG_alertOn;
[["event=alert_on|n=2"]] call SWLG_emit;
sleep 40;
["alert2"] call SWLG_sample;
[] call SWLG_alertOff;

[["event=done"]] call SWLG_emit;
