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
	player addAction ["<t color='#66ccff'>AI commanders (Insert)</t>", {call SWLC_clPanelToggle}, nil, 0.21, false, false, "", _cond];
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
	_plan params ["_tPos", "_tName", "_rally", "_bearing", "_eta", "_musters"];
	["SWLC_pm_target", _tPos, "mil_objective", "ColorRed", format ["Target: %1", _tName]] call SWLC_clMarker;
	private _timer = if (_eta >= 0) then {format [" (alone in %1)", [_eta] call SWLC_clClock]} else {""};
	["SWLC_pm_rally", _rally, "mil_arrow", "ColorOrange", format ["Rally%1", _timer], _bearing + 180] call SWLC_clMarker;
	{
		_x params ["_pos", "_name"];
		[format ["SWLC_pm_m%1", _forEachIndex], _pos, "mil_flag", "ColorBlue", format ["Muster: %1", _name]] call SWLC_clMarker;
	} forEach _musters;
};

SWLC_clClock = {
	params ["_s"];
	private _t = floor (_s max 0);
	format ["%1:%2%3", floor (_t / 60), ["", "0"] select ((_t mod 60) < 10), _t mod 60]
};

// ---- The AI commanders panel. The list comes from the server every few seconds; the clocks count here between updates.

SWLC_clPanelOpen = false;
SWLC_clPanelSeen = createHashMap;

SWLC_clEsc = {
	params ["_s"];
	{_s = (_s splitString (_x # 0)) joinString (_x # 1)} forEach [["&", "&amp;"], ["<", "&lt;"], [">", "&gt;"]];
	_s
};

SWLC_clPad = {
	params ["_s", "_n"];
	private _out = [_s] call SWLC_clEsc;
	for "_i" from 1 to (_n - count _s) do {_out = _out + "&#160;"};
	_out + "&#160;"
};

SWLC_clJobColour = {
	params ["_job"];
	switch (_job) do {
		case "Attacking": {"#ff7766"};
		case "Moving";
		case "Boarding": {"#ffdd77"};
		case "Mustering";
		case "Waiting": {"#ffb060"};
		case "Defending": {"#77bbff"};
		case "Idle": {"#999999"};
		default {"#dddddd"};
	}
};

SWLC_clPanelSide = {
	params ["_side"];
	private _data = missionNamespace getVariable [format ["SWLC_status_%1", _side], []];
	if (_data isEqualTo []) exitWith {format ["<t color='#aaaaaa'>AI COMMANDERS - %1: no data yet</t><br/>", _side]};
	_data params ["_stamp", "_target", "_rows"];
	private _seen = SWLC_clPanelSeen getOrDefault [str _side, [-1, 0]];
	if ((_seen # 0) != _stamp) then {
		_seen = [_stamp, time];
		SWLC_clPanelSeen set [str _side, _seen];
	};
	private _age = time - (_seen # 1);
	private _text = format ["<t color='#ffffff'>AI COMMANDERS - %1</t>&#160;&#160;&#160;<t color='#ffcc66'>target: %2</t><br/>", _side, [_target] call SWLC_clEsc];
	{
		_x params ["_name", "_job", "_place", "_reason", "_since"];
		_text = _text + format ["%1<t color='%2'>%3</t>%4<t color='#bbbbbb'>%5</t><br/>&#160;&#160;<t color='#aaaaaa'>%6</t><br/>",
			[_name, 12] call SWLC_clPad, [_job] call SWLC_clJobColour, [_job, 12] call SWLC_clPad, [_place, 16] call SWLC_clPad, [_since + _age] call SWLC_clClock, [_reason] call SWLC_clEsc];
	} forEach _rows;
	_text
};

SWLC_clPanelDraw = {
	private _side = side group player;
	private _text = [_side] call SWLC_clPanelSide;
	if (missionNamespace getVariable ["SWLC_statusDebug", false]) then {
		_text = _text + "<br/>" + ([[west, east] select (_side == west)] call SWLC_clPanelSide);
	};
	_text = parseText format ["<t font='EtelkaMonospacePro' size='0.75'>%1</t>", _text];
	{
		private _d = findDisplay _x;
		if (!isNull _d) then {
			private _c = _d getVariable ["SWLC_panelCtrl", controlNull];
			if (isNull _c) then {
				_c = _d ctrlCreate ["RscStructuredText", -1];
				_c ctrlSetBackgroundColor [0, 0, 0, 0.65];
				_c ctrlSetPosition [safeZoneX + 0.02, safeZoneY + 0.25 * safeZoneH, 0.72, 0.1];
				_c ctrlCommit 0;
				_d setVariable ["SWLC_panelCtrl", _c];
			};
			_c ctrlSetStructuredText _text;
			_c ctrlSetPositionH ((ctrlTextHeight _c) min (0.7 * safeZoneH));
			_c ctrlCommit 0;
			_c ctrlShow true;
		};
	} forEach [46, 12];
};

SWLC_clPanelHide = {
	{
		private _d = findDisplay _x;
		if (!isNull _d) then {(_d getVariable ["SWLC_panelCtrl", controlNull]) ctrlShow false};
	} forEach [46, 12];
};

SWLC_clPanelToggle = {
	SWLC_clPanelOpen = !SWLC_clPanelOpen;
	if (SWLC_clPanelOpen) then {call SWLC_clPanelDraw} else {call SWLC_clPanelHide};
};

SWLC_clKeyDown = {
	params ["_d", "_key"];
	if (_key == 210) exitWith {call SWLC_clPanelToggle; true};
	false
};

[] spawn {
	scriptName "SWLC panel";
	while {true} do {
		sleep 1;
		if (SWLC_clPanelOpen && {!isNull player}) then {call SWLC_clPanelDraw};
	};
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
		{
			private _d = findDisplay _x;
			if (!isNull _d && {!(_d getVariable ["SWLC_keyed", false])}) then {
				_d setVariable ["SWLC_keyed", true];
				_d displayAddEventHandler ["KeyDown", {_this call SWLC_clKeyDown}];
			};
		} forEach [46, 12];
		private _plan = missionNamespace getVariable [format ["SWLC_plan_%1", side group player], []];
		if (_plan isNotEqualTo _last) then {
			_last = _plan;
			[_plan] call SWLC_clDrawPlan;
		};
		sleep 5;
	};
};
