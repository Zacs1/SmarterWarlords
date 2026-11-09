// Rules variant, part F: the "Commander..." menu, on every machine with a player.
// Plain SQF with no server functions, because a client never compiles the commander. The server checks everything.
if (!hasInterface) exitWith {};

SWLC_menuSend = {
	params ["_kind", ["_data", []]];
	[_kind, player, _data] remoteExecCall ["SWLC_fnc_playerMsg", 2];
};

// Reports what's under the crosshair, or else the enemies this player's unit knows about close by.
SWLC_menuReport = {
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
	["report", _items] call SWLC_menuSend;
};

// The list the scroll action opens. Number keys pick an item; the mouse wheel and Enter also work.
SWLC_menuItems = [
	["Commander", false],
	["Order raid on sector", [2], "", -5, [["expression", "['raid'] call SWLC_menuPick"]], "1", "1"],
	["Send groups with me", [3], "", -5, [["expression", "['borrow'] call SWLC_menuSend"]], "1", "1"],
	["Hold the wave for us", [4], "", -5, [["expression", "['hold'] call SWLC_menuSend"]], "1", "1"],
	["Go now", [5], "", -5, [["expression", "['go'] call SWLC_menuSend"]], "1", "1"],
	["Report contact", [6], "", -5, [["expression", "[] call SWLC_menuReport"]], "1", "1"],
	["Defend this sector", [7], "", -5, [["expression", "['defend'] call SWLC_menuPick"]], "1", "1"],
	["Request a pickup", [8], "", -5, [["expression", "['pickup'] call SWLC_menuSend"]], "1", "1"],
	["Release my groups", [9], "", -5, [["expression", "['release'] call SWLC_menuSend"]], "1", "1"],
	["What's the plan?", [10], "", -5, [["expression", "['plan'] call SWLC_menuSend"]], "1", "1"],
	["AI commanders panel (Insert)", [11], "", -5, [["expression", "call SWLC_clPanelToggle"]], "1", "1"]
];

// One frame later, so the closing action menu doesn't take this list with it.
SWLC_menuOpen = {
	[] spawn {
		sleep 0.05;
		showCommandingMenu "#USER:SWLC_menuItems";
	};
};

// ---- Picking a sector on the map ----

SWLC_menuPicking = "";
SWLC_menuPickEH = -1;

SWLC_menuPickSector = {
	params ["_pos"];
	private _best = objNull;
	private _bestD = 300;
	{
		private _d = _x distance2D _pos;
		if (_d < _bestD) then {_bestD = _d; _best = _x};
	} forEach (missionNamespace getVariable ["BIS_WL_sectors", []]);
	_best
};

SWLC_menuPickClick = {
	params ["_pos"];
	if (SWLC_menuPicking == "") exitWith {};
	private _s = [_pos] call SWLC_menuPickSector;
	if (isNull _s) exitWith {hint "Click on a sector."};
	[SWLC_menuPicking, [_s]] call SWLC_menuSend;
	SWLC_menuPicking = "";
	hint "Request sent to the commander.";
};

SWLC_menuFrontMarkers = {
	private _names = [];
	{
		_x params ["_pos", "_name"];
		private _m = format ["SWLC_pf_%1", _forEachIndex];
		createMarkerLocal [_m, _pos];
		_m setMarkerTypeLocal "mil_warning";
		_m setMarkerColorLocal "ColorYellow";
		_m setMarkerTextLocal format ["Raid: %1", _name];
		_names pushBack _m;
	} forEach (missionNamespace getVariable [format ["SWLC_front_%1", side group player], []]);
	_names
};

SWLC_menuPick = {
	params ["_kind"];
	if (SWLC_menuPicking != "") exitWith {};
	// Warlords reads map clicks for votes, drops, scans and defences, so a click here would also land there.
	// Once this player has voted nothing is waiting on a click, the same test Warlords uses for its buy menu.
	if !((missionNamespace getVariable ["BIS_WL_currentSelection", ""]) in ["", "voted"]) exitWith {hint "Finish what you're selecting on the map first."};
	SWLC_menuPicking = _kind;
	[_kind] spawn {
		params ["_kind"];
		// Warlords' vote handler stays attached after voting, so a click on a sector's icon here could change the vote.
		private _voted = (missionNamespace getVariable ["BIS_WL_currentSelection", ""]) == "voted";
		private _vote = player getVariable ["BIS_WL_selectedSector", objNull];
		openMap [true, false];
		hint (["Click the owned sector to defend. Close the map to cancel.", "Click an enemy front-line sector to raid. Close the map to cancel."] select (_kind == "raid"));
		private _markers = if (_kind == "raid") then {[] call SWLC_menuFrontMarkers} else {[]};
		SWLC_menuPickEH = addMissionEventHandler ["MapSingleClick", {
			params ["_units", "_pos", "_alt", "_shift"];
			[_pos] call SWLC_menuPickClick;
		}];
		private _opened = time + 2;
		waitUntil {sleep 0.1; visibleMap || {time > _opened}};
		waitUntil {sleep 0.1; SWLC_menuPicking == "" || {!visibleMap}};
		removeMissionEventHandler ["MapSingleClick", SWLC_menuPickEH];
		{deleteMarkerLocal _x} forEach _markers;
		if (_voted && {(missionNamespace getVariable ["BIS_WL_currentSelection", ""]) == "voted"}) then {player setVariable ["BIS_WL_selectedSector", _vote, true]};
		if (SWLC_menuPicking == "") then {
			openMap [false, false];
		} else {
			SWLC_menuPicking = "";
			hint "Cancelled.";
		};
	};
};
