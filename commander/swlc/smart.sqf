// Phase 6 behaviours. Each has an on/off switch and its tunables in settings.sqf.
#include "macros.hpp"

SWLC_fnc_smartLog = {
	params ["_cmd", "_behaviour", "_event", ["_fields", []]];
	["C_SMART", [["side", _cmd get "side"], ["behaviour", _behaviour], ["event", _event]] + _fields] call SWLC_fnc_log;
};

// A personality factor, or the default when no personality is set.
SWLC_fnc_persona = {
	params ["_cmd", "_key", ["_default", 1]];
	(_cmd getOrDefault ["persona", createHashMap]) getOrDefault [_key, _default]
};

SWLC_fnc_smartTick = {
	params ["_cmd"];
	// SMART_INIT
	[_cmd] call SWLC_fnc_smartBreakTick;
	// SMART_CALLS
};

SWLC_fnc_smartOnSeized = {
	params ["_cmd", "_w", "_live"];
	// SMART_SEIZED
};

// 1. Break and consolidate: a group down to about a third pulls back to staging and merges.
SWLC_fnc_smartBreakTick = {
	params ["_cmd"];
	if !(CFG("smartBreak")) exitWith {};
	{
		private _w = _x;
		if ((_w get "phase") in ["TO_HOLD", "ASSAULT"]) then {
			{
				private _g = _x;
				private _launch = _g getVariable ["SWLC_launchMen", 0];
				private _men = [_g] call SWLC_fnc_groupMen;
				if (_launch >= CFG("breakMinLaunchMen") && {(_g getVariable ["SWLC_leg", ""]) == "FOOT"} && {_men <= ((floor (_launch * CFG("breakFraction"))) max 1)}) then {
					[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
					_g setVariable ["SWLC_broke", true];
					if (!isNil {_cmd get "gather"}) then {
						[_cmd, _g, "Regrouping"] call SWLC_fnc_sendToStaging;
					} else {
						[_g] call SWLC_fnc_adClearOrder;
						[_g, "Unassigned", [], "broke"] call SWLC_fnc_setState;
					};
					[_cmd, "break", "retreat", [["group", groupId _g], ["men", _men], ["launched", _launch], ["wave", _w get "id"]]] call SWLC_fnc_smartLog;
					[_cmd get "side", "breaking", [], _g] call SWLC_fnc_radio;
				};
			} forEach ([_w] call SWLC_fnc_waveLive);
		};
	} forEach (_cmd get "flying");

	// Merge at staging. Warlords stay in their own groups, so only their bought men change group.
	private _groups = _cmd get "groups";
	{
		private _g = _x;
		private _partners = _groups select {
			_x isNotEqualTo _g && {([_x] call SWLC_fnc_state) == "Staging"}
			&& {([_x] call SWLC_fnc_groupMen) <= CFG("mergeMaxMen")} && {(leader _x distance2D leader _g) <= CFG("mergeRadius")}
		};
		if (_partners isNotEqualTo []) then {
			private _other = _partners # 0;
			private _big = [_other, _g] select (([_g] call SWLC_fnc_groupMen) >= ([_other] call SWLC_fnc_groupMen));
			private _small = [_g, _other] select (_big isEqualTo _g);
			private _movers = (units _small) select {alive _x && {!isPlayer _x} && {!([_x] call SWLC_fnc_adIsWarlord)}};
			if (_movers isNotEqualTo []) then {_movers joinSilent _big};
			_g setVariable ["SWLC_broke", false];
			[_cmd, "break", "merge", [["group", groupId _g], ["with", groupId _other], ["moved", count _movers]]] call SWLC_fnc_smartLog;
		};
	} forEach (_groups select {(_x getVariable ["SWLC_broke", false]) && {([_x] call SWLC_fnc_state) == "Staging"}});
};
