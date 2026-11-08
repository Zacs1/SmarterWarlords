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
	// SMART_CALLS
};

SWLC_fnc_smartOnSeized = {
	params ["_cmd", "_w", "_live"];
	// SMART_SEIZED
};
