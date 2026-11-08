// Task states and group bookkeeping.
#include "macros.hpp"

SWLC_fnc_setState = {
	params ["_g", "_state", ["_goal", []], ["_reason", ""]];
	private _old = _g getVariable ["SWLC_state", "-"];
	_g setVariable ["SWLC_state", _state];
	_g setVariable ["SWLC_stateSince", time];
	_g setVariable ["SWLC_goal", _goal];
	_g setVariable ["SWLC_progress", []];
	_g setVariable ["SWLC_stuck", 0];
	if (_old != _state) then {
		["C_STATE", [["side", side _g], ["group", groupId _g], ["from", _old], ["to", _state], ["reason", _reason]]] call SWLC_fnc_log;
	};
};

SWLC_fnc_state = { (_this # 0) getVariable ["SWLC_state", "-"] };

SWLC_fnc_groupMen = {
	params ["_g"];
	{alive _x} count units _g
};

SWLC_fnc_groupsMen = {
	params ["_groups"];
	private _n = 0;
	{_n = _n + ({alive _x} count units _x)} forEach _groups;
	_n
};

// Merges new warlord groups into the side's list and removes dead or player-held ones.
SWLC_fnc_refreshGroups = {
	params ["_cmd"];
	private _side = _cmd get "side";
	private _list = _cmd get "groups";

	{
		if !(_x in _list) then {
			if !([_x] call SWLC_fnc_adGroupHasPlayer) then {
				_list pushBack _x;
				_x setVariable ["SWLC_waveId", -1];
				[_x] call SWLC_fnc_adClearOrder;
				[_x, "Unassigned", [], "joined"] call SWLC_fnc_setState;
			};
		};
	} forEach ([_side] call SWLC_fnc_adOwnableGroups);

	private _drop = _list select {
		({alive _x} count units _x) == 0 || {[_x] call SWLC_fnc_adGroupHasPlayer}
	};
	{
		private _had = ({alive _x} count units _x) > 0;
		[_cmd, _x] call SWLC_fnc_waveRemoveGroup;
		[_x] call SWLC_fnc_adClearOrder;
		_x setVariable ["SWLC_state", "-"];
		["C_STATE", [["side", _side], ["group", groupId _x], ["from", "any"], ["to", "released"], ["reason", ["all_dead", "player"] select _had]]] call SWLC_fnc_log;
	} forEach _drop;
	_cmd set ["groups", _list - _drop];

	{
		if (CFG("replaceVanillaBuying")) then {
			[_x] call SWLC_fnc_adSuppressVanillaAll;
		} else {
			[_x] call SWLC_fnc_adSuppressVanillaVehicles;
		};
	} forEach ([_side] call SWLC_fnc_adAIWarlords);
};
