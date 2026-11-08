// General helpers: logging, geometry. No Warlords knowledge here.
#include "macros.hpp"

// ["TYPE", [["key", value], ...]] call SWLC_fnc_log
SWLC_fnc_log = {
	params ["_kind", "_fields"];
	if (!(SWLC_settings get "verboseLog") && {_kind in ["C_GUARD", "C_VTRK"]}) exitWith {};
	private _parts = _fields apply {format ["%1=%2", _x # 0, _x # 1]};
	diag_log text ((["SWL", _kind, format ["t=%1", round time]] + _parts) joinString "|");
};

// [pos2d or 3d] -> [x, y, 0]
SWLC_fnc_pos2d = {
	params ["_p"];
	[_p # 0, _p # 1, 0]
};

// Bearing and offset helpers.
SWLC_fnc_bearing = {
	params ["_from", "_to"];
	((_to # 0) - (_from # 0)) atan2 ((_to # 1) - (_from # 1))
};

SWLC_fnc_offset = {
	params ["_pos", "_bearing", "_dist"];
	[(_pos # 0) + _dist * sin _bearing, (_pos # 1) + _dist * cos _bearing, 0]
};

SWLC_fnc_dist2d = {
	params ["_a", "_b"];
	sqrt (((_a # 0) - (_b # 0)) ^ 2 + ((_a # 1) - (_b # 1)) ^ 2)
};

// Living units of a group.
SWLC_fnc_alive = {
	params ["_g"];
	units _g select {alive _x}
};

SWLC_fnc_sectorLabel = {
	params ["_s"];
	[_s] call SWLC_fnc_adName
};
