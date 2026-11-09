// SWL observer: passive round logger for the automated test mission.
// Server only. It reads game state and writes SWL| lines to the RPT with diag_log.
// It has no gameplay effect. The line format is documented in tests/README.md.

if (!isServer) exitWith {};

#define SWL_TICK_SECONDS 30

SWL_fnc_emit = {
	params ["_type", "_fields"];
	private _line = (["SWL", _type, format ["t=%1", round time]] + _fields) joinString "|";
	diag_log text _line;
};

// Warlords moves a sector's logic to [100,100] for a moment when it changes hands,
// so each position is read once, before any capture, and cached.
SWL_sectorCache = createHashMap;

SWL_fnc_sectorPos = {
	params ["_sector"];
	private _key = netId _sector;
	private _cached = SWL_sectorCache getOrDefault [_key, []];
	if (_cached isNotEqualTo []) exitWith {_cached};
	private _pos = getPosWorld _sector;
	_cached = [round (_pos # 0), round (_pos # 1)];
	SWL_sectorCache set [_key, _cached];
	_cached
};

// Sectors without a location name have an empty localised name on a dedicated server.
SWL_fnc_sectorName = {
	params ["_sector"];
	private _name = _sector getVariable ["Name", ""];
	if (_name != "") exitWith {_name};
	private _pos = [_sector] call SWL_fnc_sectorPos;
	format ["Sector_%1_%2", _pos # 0, _pos # 1]
};

SWL_fnc_sectorOwner = {
	params ["_sector"];
	str (_sector getVariable ["BIS_WL_sectorSide", sideUnknown])
};

SWL_fnc_targetName = {
	params ["_side"];
	private _target = missionNamespace getVariable [format ["BIS_WL_currentSector_%1", _side], objNull];
	if (isNull _target) exitWith {"-"};
	[_target] call SWL_fnc_sectorName
};

SWL_fnc_logGroup = {
	params ["_group"];
	private _leader = leader _group;
	private _pos = getPosWorld _leader;
	private _wpIndex = currentWaypoint _group;
	private _waypoints = waypoints _group;
	private _wpX = "-";
	private _wpY = "-";
	private _wpType = "-";
	if (_wpIndex < count _waypoints) then {
		private _wpPos = waypointPosition [_group, _wpIndex];
		_wpX = round (_wpPos # 0);
		_wpY = round (_wpPos # 1);
		_wpType = waypointType [_group, _wpIndex];
	};
	private _dest = expectedDestination _leader;
	private _destPos = _dest # 0;
	private _vehicle = vehicle _leader;
	private _isWarlord = !isNil "BIS_WL_allWarlords" && {_leader in BIS_WL_allWarlords};

	["GRP", [
		format ["id=%1", netId _group],
		format ["name=%1", str _group],
		format ["side=%1", side _group],
		format ["leader=%1", ["ai", "player"] select (isPlayer _leader)],
		format ["x=%1", round (_pos # 0)],
		format ["y=%1", round (_pos # 1)],
		format ["units=%1", {alive _x} count units _group],
		format ["wp=%1/%2", _wpIndex, count _waypoints],
		format ["wpx=%1", _wpX],
		format ["wpy=%1", _wpY],
		format ["wptype=%1", _wpType],
		format ["destx=%1", round (_destPos # 0)],
		format ["desty=%1", round (_destPos # 1)],
		format ["plan=%1", _dest # 1],
		format ["combat=%1", [0, 1] select (behaviour _leader == "COMBAT")],
		format ["fighting=%1", [0, 1] select (!isNil "SWLC_fnc_groupFighting" && {[_group] call SWLC_fnc_groupFighting})],
		format ["beh=%1", behaviour _leader],
		format ["veh=%1", ["-", typeOf _vehicle] select (_vehicle != _leader)],
		format ["warlord=%1", [0, 1] select _isWarlord],
		format ["state=%1", _group getVariable ["SWLC_state", "-"]],
		format ["wave=%1", _group getVariable ["SWLC_waveId", "-"]]
	]] call SWL_fnc_emit;
};

SWL_fnc_tick = {
	private _groups = allGroups select {
		(side _x in [west, east]) && {{alive _x} count units _x > 0}
	};
	private _west = _groups select {side _x == west};
	private _east = _groups select {side _x == east};
	private _ready = !isNil "BIS_WL_sectors";

	["TICK", [
		format ["wl_ready=%1", [0, 1] select _ready],
		format ["west_groups=%1", count _west],
		format ["east_groups=%1", count _east],
		format ["west_units=%1", west countSide allUnits],
		format ["east_units=%1", east countSide allUnits],
		format ["guer_units=%1", resistance countSide allUnits],
		format ["players=%1", count allPlayers],
		format ["west_target=%1", [west] call SWL_fnc_targetName],
		format ["east_target=%1", [east] call SWL_fnc_targetName],
		format ["fps=%1", round diag_fps]
	]] call SWL_fnc_emit;

	{[_x] call SWL_fnc_logGroup} forEach _groups;

	if (_ready) then {
		{
			private _pos = [_x] call SWL_fnc_sectorPos;
			["SEC", [
				format ["name=%1", [_x] call SWL_fnc_sectorName],
				format ["owner=%1", [_x] call SWL_fnc_sectorOwner],
				format ["x=%1", _pos # 0],
				format ["y=%1", _pos # 1],
				format ["base=%1", [0, 1] select (typeOf _x == "ModuleWLBase_F")],
				format ["size=%1", _x getVariable ["Size", -1]]
			]] call SWL_fnc_emit;
		} forEach BIS_WL_sectors;
	};
};

["START", [
	format ["world=%1", worldName],
	format ["mission=%1", missionName],
	format ["dedicated=%1", [0, 1] select isDedicated],
	format ["version=%1", (productVersion # 2)],
	format ["build=%1", (productVersion # 3)],
	format ["params=%1", (paramsArray apply {str _x}) joinString ","]
]] call SWL_fnc_emit;

addMissionEventHandler ["Ended", {
	params ["_endType"];
	["ENDED", [format ["type=%1", _endType]]] call SWL_fnc_emit;
}];
addMissionEventHandler ["MPEnded", {
	["ENDED", ["type=MPEnded"]] call SWL_fnc_emit;
}];

// Periodic snapshot.
[] spawn {
	scriptName "SWL observer (tick)";
	while {true} do {
		call SWL_fnc_tick;
		sleep SWL_TICK_SECONDS;
	};
};

// Sector captures and vote targets, the moment they change.
[] spawn {
	scriptName "SWL observer (events)";
	waitUntil {sleep 0.5; !isNil "BIS_WL_sectors"};

	{
		private _pos = [_x] call SWL_fnc_sectorPos;
		["SECTORINIT", [
			format ["name=%1", [_x] call SWL_fnc_sectorName],
			format ["owner=%1", [_x] call SWL_fnc_sectorOwner],
			format ["x=%1", _pos # 0],
			format ["y=%1", _pos # 1],
			format ["base=%1", [0, 1] select (typeOf _x == "ModuleWLBase_F")]
		]] call SWL_fnc_emit;
	} forEach BIS_WL_sectors;

	private _owners = BIS_WL_sectors apply {[_x] call SWL_fnc_sectorOwner};
	private _targets = [[west] call SWL_fnc_targetName, [east] call SWL_fnc_targetName];

	while {true} do {
		{
			private _owner = [_x] call SWL_fnc_sectorOwner;
			private _old = _owners # _forEachIndex;
			if (_owner != _old) then {
				_owners set [_forEachIndex, _owner];
				private _pos = [_x] call SWL_fnc_sectorPos;
				["CAPTURE", [
					format ["sector=%1", [_x] call SWL_fnc_sectorName],
					format ["from=%1", _old],
					format ["to=%1", _owner],
					format ["x=%1", _pos # 0],
					format ["y=%1", _pos # 1],
					format ["base=%1", [0, 1] select (typeOf _x == "ModuleWLBase_F")]
				]] call SWL_fnc_emit;
			};
		} forEach BIS_WL_sectors;

		{
			private _target = [_x] call SWL_fnc_targetName;
			if (_target != (_targets # _forEachIndex)) then {
				_targets set [_forEachIndex, _target];
				["TARGET", [format ["side=%1", _x], format ["sector=%1", _target]]] call SWL_fnc_emit;
			};
		} forEach [west, east];

		sleep 1;
	};
};

// Round end: same condition the mode uses, polled every frame so it logs before the mission ends.
[] spawn {
	scriptName "SWL observer (round end)";
	waitUntil {sleep 0.5; !isNil "BIS_WL_base_WEST" && {!isNil "BIS_WL_base_EAST"}};
	waitUntil {
		(BIS_WL_base_WEST getVariable "BIS_WL_sectorSide") != west
		|| (BIS_WL_base_EAST getVariable "BIS_WL_sectorSide") != east
	};
	private _westLost = (BIS_WL_base_WEST getVariable "BIS_WL_sectorSide") != west;
	["ROUNDEND", [format ["winner=%1", ["WEST", "EAST"] select _westLost]]] call SWL_fnc_emit;
};
