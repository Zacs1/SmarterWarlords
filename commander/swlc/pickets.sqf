// Rules variant, part E: a small group on every owned front-line sector, to spot, report and delay.
#include "macros.hpp"

SWLC_fnc_picketOn = { CFG("rulesVariant") && {CFG("rulePickets")} };
SWLC_fnc_propOn = { CFG("rulesVariant") && {CFG("ruleProportionate")} };

// A spot near the goal but far enough from the leader that the order can't complete without moving.
// Warlords kills an on-foot AI warlord who doesn't move for about nine minutes.
SWLC_fnc_shuffleSpot = {
	params ["_goal", "_g"];
	private _spot = _goal;
	private _p = getPosATL leader _g;
	for "_i" from 1 to 8 do {
		private _try = [_goal, random 360, 18 + random 22] call SWLC_fnc_offset;
		if (!surfaceIsWater _try && {(_try distance2D _p) >= 20}) exitWith {_spot = _try};
	};
	_spot
};

// Owned sectors that touch an enemy one, most exposed first. Neutral ground needs no watch.
SWLC_fnc_picketFront = {
	params ["_side"];
	private _enemy = [_side] call SWLC_fnc_adEnemySide;
	private _front = ([_side] call SWLC_fnc_adOwned) select {
		private _s = _x;
		(CFG("picketBases") || {!([_s] call SWLC_fnc_adIsBase)}) && {(([_s] call SWLC_fnc_adLinks) findIf {([_x] call SWLC_fnc_adOwner) == _enemy}) >= 0}
	};
	[_front, [], {
		private _s = _x;
		-({([_x] call SWLC_fnc_adOwner) == _enemy} count ([_s] call SWLC_fnc_adLinks)) - (([_side, _s] call SWLC_fnc_stratWorth) / 100)
	}, "ASCEND"] call BIS_fnc_sortBy
};

SWLC_fnc_picketSpot = {
	params ["_cmd", "_s"];
	private _c = [_s] call SWLC_fnc_adPos;
	private _side = _cmd get "side";
	private _out = ([_s] call SWLC_fnc_adLinks) select {([_x] call SWLC_fnc_adOwner) != _side};
	private _bearing = if (_out isEqualTo []) then {random 360} else {
		[_c, [([_out, _c] call SWLC_fnc_adNearest)] call SWLC_fnc_adPos] call SWLC_fnc_bearing
	};
	private _spots = [_cmd, _s, _bearing] call SWLC_fnc_defSpots;
	[selectRandom _spots, _bearing]
};

SWLC_fnc_picketAssign = {
	params ["_cmd", "_g", "_s"];
	[_cmd, _s] call SWLC_fnc_picketSpot params ["_spot", "_bearing"];
	[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
	[_g, "Picket", _spot, "picket"] call SWLC_fnc_setState;
	_g setVariable ["SWLC_picketSector", _s];
	_g setVariable ["SWLC_patrolAt", time];
	_g setVariable ["SWLC_picketSince", time];
	[_g, [[_spot, "MOVE", 15]], "AWARE", "NORMAL", "WEDGE", "YELLOW"] call SWLC_fnc_adSetOrder;
	[_g, _s, _spot, _bearing + 180] call SWLC_fnc_defMoveTo;
	["C_PICKET", [["side", _cmd get "side"], ["event", "assign"], ["sector", [_s] call SWLC_fnc_adName], ["group", groupId _g], ["men", [_g] call SWLC_fnc_groupMen]]] call SWLC_fnc_log;
};

SWLC_fnc_picketRelease = {
	params ["_cmd", "_g", "_why"];
	["C_PICKET", [["side", _cmd get "side"], ["event", "release"], ["group", groupId _g], ["why", _why]]] call SWLC_fnc_log;
	_g setVariable ["SWLC_picketSector", nil];
	[_g] call SWLC_fnc_adClearOrder;
	[_g, "Unassigned", [], "picket_released"] call SWLC_fnc_setState;
};

SWLC_fnc_picketTick = {
	params ["_cmd"];
	if !([] call SWLC_fnc_picketOn) exitWith {};
	private _side = _cmd get "side";
	private _front = [_side] call SWLC_fnc_picketFront;
	private _groups = _cmd get "groups";

	private _pickets = _groups select {([_x] call SWLC_fnc_state) == "Picket"};
	{
		private _g = _x;
		private _s = _g getVariable ["SWLC_picketSector", objNull];
		if (!(_s in _front)) then {
			[_cmd, _g, "not_front_line"] call SWLC_fnc_picketRelease;
			_pickets = _pickets - [_g];
		};
	} forEach +_pickets;

	// How many pickets the side can afford.
	private _attackers = {!(([_x] call SWLC_fnc_state) in ["Picket", "Reserve", "Defending", "Raiding", "Probing", "Borrowed", "Pickup"])} count _groups;

	// The attack comes first: if it has shrunk, the least exposed pickets go back to it.
	private _short = CFG("picketKeepAttackers") - _attackers;
	if (_short > 0 && {_pickets isNotEqualTo []}) then {
		private _order = [_pickets, [], {_front find (_x getVariable ["SWLC_picketSector", objNull])}, "DESCEND"] call BIS_fnc_sortBy;
		{
			[_cmd, _x, "attack_short"] call SWLC_fnc_picketRelease;
			_pickets = _pickets - [_x];
			_attackers = _attackers + 1;
		} forEach (_order select [0, _short]);
	};

	// Nobody stands watch all round. A picket hands over, and rests from picket duty for a while.
	{
		if ((time - (_x getVariable ["SWLC_picketSince", time])) >= CFG("picketRotateSeconds") && {(behaviour leader _x) != "COMBAT"}) then {
			_x setVariable ["SWLC_picketRestUntil", time + CFG("picketRestSeconds")];
			[_cmd, _x, "rotate"] call SWLC_fnc_picketRelease;
			_pickets = _pickets - [_x];
			_attackers = _attackers + 1;
		};
	} forEach +_pickets;

	private _roomFromCap = (floor ((count _groups) * CFG("picketMaxFraction"))) - (count _pickets);
	private _roomFromAttack = _attackers - CFG("picketKeepAttackers");
	private _room = _roomFromCap min _roomFromAttack;

	{
		if (_room <= 0) exitWith {};
		private _s = _x;
		if ((_pickets findIf {(_x getVariable ["SWLC_picketSector", objNull]) isEqualTo _s}) < 0) then {
			private _pool = _groups select {([_x] call SWLC_fnc_state) in ["Unassigned", "Mustering", "Travelling"] && {vehicle leader _x == leader _x} && {(behaviour leader _x) != "COMBAT"} && {time >= (_x getVariable ["SWLC_picketRestUntil", -1])}};
			if (_pool isNotEqualTo []) then {
				private _c = [_s] call SWLC_fnc_adPos;
				private _picked = ([_pool, [], {([_x] call SWLC_fnc_groupMen) * 150 + (leader _x distance2D _c)}, "ASCEND"] call BIS_fnc_sortBy) # 0;
				[_cmd, _picked, _s] call SWLC_fnc_picketAssign;
				_pickets pushBack _picked;
				_room = _room - 1;
			};
		};
	} forEach _front;

	// Pickets shuffle so Warlords doesn't treat a waiting leader as stuck.
	{
		private _g = _x;
		private _since = time - (_g getVariable ["SWLC_patrolAt", -1e6]);
		if (_since >= CFG("reservePatrolSeconds") && {([_g] call SWLC_fnc_adOrderDone) || {_since >= 2 * CFG("reservePatrolSeconds")}}) then {
			_g setVariable ["SWLC_patrolAt", time];
			private _goal = _g getVariable ["SWLC_goal", []];
			if (_goal isNotEqualTo []) then {
				private _spot = [_goal, _g] call SWLC_fnc_shuffleSpot;
				[_g, [[_spot, "MOVE", 8]], "AWARE", "NORMAL", "WEDGE", "YELLOW"] call SWLC_fnc_adSetOrder;
			};
		};
	} forEach _pickets;
};
