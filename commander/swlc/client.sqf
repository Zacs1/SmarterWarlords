// Runs on every machine with a player. Adds the scroll actions and draws the plan as local map markers.
// Plain SQF with no server functions, because a client never compiles the commander.
if (!hasInterface) exitWith {};

SWLC_clSend = {
	params ["_kind", ["_data", []]];
	[_kind, player, _data] remoteExecCall ["SWLC_fnc_playerMsg", 2];
};

// Reports what's under the crosshair, or else the enemies this player's unit knows about close by.
SWLC_clReport = {
	private _side = side group player;
	private _items = [];
	private _isEnemy = {
		params ["_o"];
		!isNull _o && {alive _o} && {(side group _o) in [west, east, resistance]} && {(_side getFriend (side group _o)) < 0.6}
	};
	private _c = cursorTarget;
	if ([_c] call _isEnemy) then {
		private _p = getPosATL _c;
		_items pushBack [typeOf _c, [_p # 0, _p # 1]];
	} else {
		{
			_x params ["_pos", "_type", "_tSide", "_cost", "_obj"];
			if ([_obj] call _isEnemy && {(player knowsAbout _obj) >= 1}) then {
				_items pushBack [typeOf _obj, [_pos # 0, _pos # 1]];
			};
		} forEach (player nearTargets 800);
	};
	if (_items isEqualTo []) exitWith {hint "No enemy to report."};
	["report", _items] call SWLC_clSend;
};

SWLC_clAddActions = {
	private _cond = "alive _target && {_this == _target}";
	player addAction ["<t color='#ffcc66'>Report contact to commander</t>", {[] call SWLC_clReport}, nil, 0.2, false, true, "", _cond];
	player addAction ["<t color='#ffcc66'>Attack with me</t>", {["attack"] call SWLC_clSend}, nil, 0.19, false, true, "", _cond];
	player addAction ["<t color='#ffcc66'>Defend this sector</t>", {["defend"] call SWLC_clSend}, nil, 0.18, false, true, "", _cond];
};

SWLC_clMarkers = [];

SWLC_clMarker = {
	params ["_name", "_pos", "_type", "_colour", "_text", ["_dir", 0]];
	if !(_name in SWLC_clMarkers) then {
		createMarkerLocal [_name, _pos];
		SWLC_clMarkers pushBack _name;
	};
	_name setMarkerPosLocal _pos;
	_name setMarkerTypeLocal _type;
	_name setMarkerColorLocal _colour;
	_name setMarkerDirLocal _dir;
	_name setMarkerTextLocal _text;
};

SWLC_clDrawPlan = {
	params ["_plan"];
	{deleteMarkerLocal _x} forEach SWLC_clMarkers;
	SWLC_clMarkers = [];
	if (_plan isEqualTo []) exitWith {};
	_plan params ["_tPos", "_tName", "_sPos", "_sName", "_eta", "_approaches"];
	["SWLC_pm_target", _tPos, "mil_objective", "ColorRed", format ["Target: %1", _tName]] call SWLC_clMarker;
	if (_sPos isNotEqualTo []) then {
		private _timer = if (_eta >= 0) then {format [" (go in %1:%2%3)", floor (_eta / 60), ["", "0"] select ((_eta mod 60) < 10), floor (_eta mod 60)]} else {""};
		["SWLC_pm_staging", _sPos, "mil_flag", "ColorBlue", format ["Staging: %1%2", _sName, _timer]] call SWLC_clMarker;
	};
	{
		_x params ["_hold", "_bearing"];
		[format ["SWLC_pm_app%1", _forEachIndex], _hold, "mil_arrow", "ColorOrange", format ["Approach %1", _forEachIndex + 1], _bearing + 180] call SWLC_clMarker;
	} forEach _approaches;
};

[] spawn {
	scriptName "SWLC client";
	waitUntil {!isNull player};
	private _unit = objNull;
	private _last = [];
	while {true} do {
		if (player isNotEqualTo _unit && {alive player}) then {
			_unit = player;
			call SWLC_clAddActions;
		};
		private _plan = missionNamespace getVariable [format ["SWLC_plan_%1", side group player], []];
		if (_plan isNotEqualTo _last) then {
			_last = _plan;
			[_plan] call SWLC_clDrawPlan;
		};
		sleep 5;
	};
};
