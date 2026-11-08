// Debug overlay: map markers showing what the commander is thinking. Off by default.
// Turn on from the server: SWLC_debug = true (hosted: debug console; dedicated: admin exec).
#include "macros.hpp"

SWLC_fnc_debugLoop = {
	scriptName "SWLC debug";
	SWLC_debugMarkers = [];
	while {true} do {
		sleep CFG("debugRefreshSeconds");
		private _on = !isNil "SWLC_debug" && {SWLC_debug};
		if (_on) then {
			isNil {[] call SWLC_fnc_debugDraw};
		} else {
			if (SWLC_debugMarkers isNotEqualTo []) then {
				{deleteMarker _x} forEach SWLC_debugMarkers;
				SWLC_debugMarkers = [];
			};
		};
	};
};

SWLC_fnc_debugMarker = {
	params ["_name", "_pos", "_type", "_color", "_text", ["_alpha", 1]];
	if !(_name in SWLC_debugMarkers) then {
		createMarker [_name, _pos];
		SWLC_debugMarkers pushBack _name;
	};
	_name setMarkerPos _pos;
	_name setMarkerType _type;
	_name setMarkerColor _color;
	_name setMarkerText _text;
	_name setMarkerAlpha _alpha;
};

SWLC_fnc_debugPoly = {
	params ["_name", "_from", "_to", "_color"];
	if !(_name in SWLC_debugMarkers) then {
		createMarker [_name, _from];
		SWLC_debugMarkers pushBack _name;
	};
	_name setMarkerPolyline [_from # 0, _from # 1, _to # 0, _to # 1];
	_name setMarkerColor _color;
};

SWLC_fnc_debugDraw = {
	{
		private _side = _x;
		private _cmd = missionNamespace getVariable [format ["SWLC_cmd_%1", _side], createHashMap];
		if (count _cmd == 0) then {continue};
		private _color = ["ColorEAST", "ColorWEST"] select (_side == west);
		private _prefix = format ["SWLC_dbg_%1_", _side];

		// Target and staging
		private _t = _cmd get "target";
		if (!isNull _t) then {
			[_prefix + "target", [_t] call SWLC_fnc_adPos, "mil_objective", _color, format ["%1 TARGET", _side]] call SWLC_fnc_debugMarker;
		};
		private _sp = _cmd get "stagingPos";
		if (_sp isNotEqualTo []) then {
			[_prefix + "staging", _sp, "mil_flag", _color, format ["%1 STAGING", _side]] call SWLC_fnc_debugMarker;
		};

		// Approaches
		{
			private _w = _x;
			private _wid = _w get "id";
			{
				[_prefix + format ["ap_%1_%2", _wid, _forEachIndex], _x get "hold", [_w get "target"] call SWLC_fnc_adPos, _color] call SWLC_fnc_debugPoly;
				[_prefix + format ["hold_%1_%2", _wid, _forEachIndex], _x get "hold", "mil_circle", _color, format ["W%1 hold %2", _wid, _forEachIndex + 1]] call SWLC_fnc_debugMarker;
			} forEach (_w getOrDefault ["approaches", []]);
		} forEach (_cmd get "flying");

		// Groups
		{
			private _g = _x;
			private _st = [_g] call SWLC_fnc_state;
			private _since = round (time - (_g getVariable ["SWLC_stateSince", time]));
			[_prefix + format ["g_%1", netId _g], getPosATL leader _g, "mil_dot", _color, format ["%1 %2 %3s", groupId _g, _st, _since]] call SWLC_fnc_debugMarker;
		} forEach (_cmd get "groups");

		// Last decision text, top left of the map.
		[_prefix + "text", [worldSize * 0.02, worldSize * (0.98 - ([0, 0.03] select (_side == east))), 0], "mil_dot", _color, format ["%1: %2", _side, _cmd get "lastDecision"], 0.9] call SWLC_fnc_debugMarker;
	} forEach [west, east];
};
