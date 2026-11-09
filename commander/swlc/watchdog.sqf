// Watchdog: no group the commander owns stays stuck or idle.
#include "macros.hpp"

SWLC_fnc_watchdogTick = {
	params ["_cmd"];
	{
		[_cmd, _x] call SWLC_fnc_watchdogGroup;
	} forEach (_cmd get "groups");
};

SWLC_fnc_watchdogGroup = {
	params ["_cmd", "_g"];
	private _state = [_g] call SWLC_fnc_state;
	private _leader = leader _g;
	if (isNull _leader) exitWith {};

	// Post-contact: when a firefight ends, waypoints can be gone or stale. Re-issue the order once.
	if ((behaviour _leader) == "COMBAT") then {
		_g setVariable ["SWLC_lastCombat", time];
		_g setVariable ["SWLC_wasCombat", true];
	} else {
		if ((_g getVariable ["SWLC_wasCombat", false]) && {(time - (_g getVariable ["SWLC_lastCombat", 0])) >= CFG("postContactQuietSeconds")}) then {
			_g setVariable ["SWLC_wasCombat", false];
			if (_state in ["Travelling", "Advancing", "Regrouping", "Assaulting", "Recon", "Defending", "Raiding", "Picket"]) then {
				[_g, _g getVariable ["SWLC_wpProgress", 0]] call SWLC_fnc_adApplyOrder;
				["C_WD", [["side", side _g], ["group", groupId _g], ["action", "post_contact_reset"], ["state", _state]]] call SWLC_fnc_log;
			};
		};
	};

	if !(_state in ["Travelling", "Advancing", "Regrouping", "Assaulting", "Recon", "Raiding"]) exitWith {};
	if ((_g getVariable ["SWLC_leg", ""]) in ["DRIVE", "FOLLOW", "LATE"]) exitWith {};

	private _goal = _g getVariable ["SWLC_goal", []];
	if (_goal isEqualTo []) exitWith {};

	// Assaulting groups inside the target square are in position, not stuck.
	if (_state == "Assaulting") then {
		private _op = _cmd get "op";
		if (!isNil "_op" && {[_op get "target", getPosATL _leader] call SWLC_fnc_adInSquare}) then {
			_g setVariable ["SWLC_progress", []];
			_goal = [];
		};
	};
	if (_state == "Raiding") then {
		private _raid = [_cmd] call SWLC_fnc_raidOf;
		if (count _raid > 0 && {[_raid get "sector", getPosATL _leader] call SWLC_fnc_adInSquare}) then {
			_g setVariable ["SWLC_progress", []];
			_goal = [];
		};
	};
	if (_goal isEqualTo []) exitWith {};

	private _inCombat = (behaviour _leader) == "COMBAT";
	if (_inCombat) exitWith {_g setVariable ["SWLC_progress", []]};

	private _hist = _g getVariable ["SWLC_progress", []];
	private _dist = _leader distance2D _goal;
	_hist pushBack [time, _dist];
	_g setVariable ["SWLC_progress", _hist];
	if (((_hist # 0) # 0) > (time - CFG("progressWindow"))) exitWith {};

	private _oldDist = (_hist # 0) # 1;
	// A new sample window starts from here either way.
	_g setVariable ["SWLC_progress", []];
	if ((_oldDist - _dist) >= CFG("progressMinMetres")) exitWith {};

	private _stuck = (_g getVariable ["SWLC_stuck", 0]) + 1;
	_g setVariable ["SWLC_stuck", _stuck];
	["C_WD", [["side", side _g], ["group", groupId _g], ["action", "stuck"], ["state", _state], ["count", _stuck], ["dist", round _dist],
		["x", round ((getPosATL _leader) # 0)], ["y", round ((getPosATL _leader) # 1)]]] call SWLC_fnc_log;

	if (_stuck <= CFG("escalateAfterResets")) exitWith {
		[_g, _g getVariable ["SWLC_wpProgress", 0]] call SWLC_fnc_adApplyOrder;
		{_x doFollow _leader} forEach (units _g);
	};

	[_cmd, _g, _state, _goal] call SWLC_fnc_watchdogEscalate;
};

// Stuck after resets: fast travel to the owned sector nearest the goal, or give the group a new job.
SWLC_fnc_watchdogEscalate = {
	params ["_cmd", "_g", "_state", "_goal"];
	private _side = _cmd get "side";
	_g setVariable ["SWLC_stuck", 0];
	private _owned = ([_side] call SWLC_fnc_adOwned) select {[_side, _x] call SWLC_fnc_adCanFTTo};
	private _bestSector = objNull;
	private _bestD = 1e9;
	{
		private _d = ([_x] call SWLC_fnc_adPos) distance2D _goal;
		if (_d < _bestD) then {_bestD = _d; _bestSector = _x};
	} forEach _owned;

	private _moved = false;
	if (!isNull _bestSector) then {
		private _sp = [_bestSector] call SWLC_fnc_adPos;
		private _land = [_sp, [_sp, _goal] call SWLC_fnc_bearing, 40 + random 30] call SWLC_fnc_offset;
		if (surfaceIsWater _land) then {_land = _sp};
		_moved = [_g, _bestSector, _land] call SWLC_fnc_adFastTravel;
	};
	["C_WD", [["side", _side], ["group", groupId _g], ["action", "escalate"], ["fast_travelled", _moved], ["state", _state]]] call SWLC_fnc_log;
	if (_moved) exitWith {[_g, _g getVariable ["SWLC_wpProgress", 0]] call SWLC_fnc_adApplyOrder};

	// Could not fast travel: pull it out of its wave and let the commander reassign it.
	[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
	[_g] call SWLC_fnc_adClearOrder;
	[_g, "Unassigned", [], "watchdog"] call SWLC_fnc_setState;
};
