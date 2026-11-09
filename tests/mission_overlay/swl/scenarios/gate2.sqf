// Phase 2 gate: enemy armour at WEST's target reaches the board and radio within 10 s of being seen,
// the next wave's plan changes, and a tank nobody has seen never appears on the board.

waitUntil {sleep 1; !isNil "SWLC_ready" && {!isNil "SWLC_cmd_WEST"}};

SWLG_emit = {
	params ["_type", "_fields"];
	diag_log text ((["SWL", _type, format ["t=%1", round time]] + _fields) joinString "|");
};

waitUntil {sleep 1; !isNull ([west] call SWLC_fnc_adTarget)};
sleep 30;

private _target = [west] call SWLC_fnc_adTarget;
private _tpos = [_target] call SWLC_fnc_adPos;

// Hidden phase: a tank far from every WEST soldier.
private _westMen = allUnits select {side group _x == west};
private _hide = [];
for "_i" from 1 to 60 do {
	private _p = [random worldSize, random worldSize, 0];
	if (!surfaceIsWater _p && {(_westMen findIf {_x distance2D _p < 1800}) < 0}) exitWith {_hide = _p};
};
["G2", [format ["event=hide_pos|x=%1|y=%2", round (_hide # 0), round (_hide # 1)]]] call SWLG_emit;

private _veh = createVehicle ["O_T_MBT_02_cannon_ghex_F", _hide, [], 0, "NONE"];
createVehicleCrew _veh;
private _crew = group driver _veh;
_crew setBehaviour "SAFE";
_crew setCombatMode "BLUE";
{_x disableAI "MOVE"; _x allowDamage false} forEach units _crew;
_veh allowDamage false;
["G2", [format ["event=tank_hidden|net=%1", netId _veh]]] call SWLG_emit;

sleep 40;
private _cmd = missionNamespace getVariable "SWLC_cmd_WEST";
private _onBoard = ((_cmd get "board") select {_veh in (_x get "units")}) isNotEqualTo [];
["G2", [format ["event=hidden_check|on_board=%1", _onBoard]]] call SWLG_emit;

// Shown phase: move the tank to the target and put observers where they can see it.
private _spot = [_tpos, random 360, 60] call SWLC_fnc_offset;
if (surfaceIsWater _spot) then {_spot = +_tpos};
_veh setPosATL [_spot # 0, _spot # 1, 0];
_veh setVectorUp surfaceNormal _spot;
sleep 2;

private _obsPos = [];
private _aim = (getPosASL _veh) vectorAdd [0, 0, 2];
for "_i" from 0 to 23 do {
	private _p = [_spot, _i * 15, 140] call SWLC_fnc_offset;
	if (!surfaceIsWater _p) then {
		private _eye = (AGLToASL _p) vectorAdd [0, 0, 1.7];
		if (([objNull, "VIEW"] checkVisibility [_eye, _aim]) > 0.6) exitWith {_obsPos = _p};
	};
};
if (_obsPos isEqualTo []) then {_obsPos = [_spot, 90, 100] call SWLC_fnc_offset};

private _obs = createGroup [west, true];
for "_i" from 1 to 2 do {
	private _u = _obs createUnit ["B_T_Soldier_F", _obsPos, [], 3, "NONE"];
	_u allowDamage false;
	_u disableAI "MOVE";
};
_obs setBehaviour "AWARE";
_obs setCombatMode "BLUE";
["G2", [format ["event=observer_placed|x=%1|y=%2|dist=%3|tank=%4", round (_obsPos # 0), round (_obsPos # 1), round (_obsPos distance2D _spot), netId _veh]]] call SWLG_emit;

// When did any WEST group first really know about the tank? Independent of the board.
waitUntil {
	sleep 0.5;
	(allGroups select {side _x == west && {!isNull leader _x}}) findIf {(leader _x knowsAbout _veh) >= 1} >= 0
};
["G2", [format ["event=first_known|net=%1", netId _veh]]] call SWLG_emit;
