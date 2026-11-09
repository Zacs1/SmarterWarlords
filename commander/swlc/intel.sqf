// The intel board: each side's shared picture of the enemy. It is the only enemy information the
// commander uses. Everything on it comes from a group's own knowledge, a scan, a player's report or
// an unexplained loss.
#include "macros.hpp"

SWLC_fnc_intelStart = {
	params ["_cmd"];
	_cmd set ["board", []];
	_cmd set ["boardCounter", 0];
	_cmd set ["threat", createHashMap];
	_cmd set ["presence", createHashMap];
	[_cmd] spawn SWLC_fnc_intelLoop;
};

SWLC_fnc_intelLoop = {
	params ["_cmd"];
	scriptName format ["SWLC intel %1", _cmd get "side"];
	if ((_cmd get "side") == east) then {sleep (CFG("intelPollSeconds") / 2)};
	while {true} do {
		sleep CFG("intelPollSeconds");
		private _pollOk = false;
		isNil {
			private _t0 = diag_tickTime;
			[_cmd] call SWLC_fnc_intelPoll;
			_cmd set ["pollCost", (_cmd getOrDefault ["pollCost", 0]) + (diag_tickTime - _t0) * 1000];
			_pollOk = true;
		};
		if (!_pollOk) then {[_cmd, "intelPoll"] call SWLC_fnc_resStageFault};
		_cmd set ["pollCount", (_cmd getOrDefault ["pollCount", 0]) + 1];
	};
};

// Installed once, for both sides.
SWLC_fnc_intelInstallHandlers = {
	addMissionEventHandler ["EntityKilled", {
		params ["_killed", "_killer", "_instigator"];
		[_killed, _killer, _instigator] call SWLC_fnc_intelOnKilled;
	}];
};

// Worked out once per class: this runs for every target every group can see.
SWLC_intelCats = createHashMap;

SWLC_fnc_intelCategory = {
	params ["_cls"];
	private _known = SWLC_intelCats getOrDefault [_cls, -1];
	if (_known isEqualType "") exitWith {_known};
	private _cat = switch (true) do {
		case (_cls isKindOf "ParachuteBase"): {""};    // Warlords airdrops: parachutes are Helicopter-class
		case (_cls isKindOf "Man"): {"infantry"};
		case (_cls isKindOf "StaticWeapon"): {"static"};
		case (_cls isKindOf "Helicopter"): {"heli"};
		case (_cls isKindOf "Plane"): {"jet"};
		case (_cls isKindOf "Ship"): {"boat"};
		case (_cls isKindOf "APC_Tracked_01_base_F"): {"apc"};
		case (_cls isKindOf "APC_Tracked_02_base_F"): {"apc"};
		case (_cls isKindOf "APC_Tracked_03_base_F"): {"apc"};
		case (_cls isKindOf "Wheeled_APC_F"): {"apc"};
		case (_cls isKindOf "Tank"): {"tank"};
		case (_cls isKindOf "Car"): {"light"};
		default {""};
	};
	SWLC_intelCats set [_cls, _cat];
	_cat
};

SWLC_fnc_intelHalfLife = {
	params ["_cat"];
	(switch (_cat) do {
		case "infantry": {CFG("intelHalfLifeInfantry")};
		case "static": {CFG("intelHalfLifeStatic")};
		default {CFG("intelHalfLifeVehicle")};
	}) * CFG("intelDecayMultiplier")
};

SWLC_fnc_intelSector = {
	params ["_pos"];
	private _best = objNull;
	private _d = CFG("intelSectorRadius");
	{
		private _dx = ([_x] call SWLC_fnc_adPos) distance2D _pos;
		if (_dx < _d) then {_d = _dx; _best = _x};
	} forEach SWLC_sectors;
	_best
};

// Finds what a side's groups know right now.
SWLC_fnc_intelPoll = {
	params ["_cmd"];
	private _side = _cmd get "side";
	private _seen = createHashMap;
	private _maxAge = CFG("intelMaxKnowAge");
	private _minKnows = CFG("intelMinKnows");
	private _groups = allGroups select {side _x == _side && {(units _x findIf {alive _x}) >= 0}};
	// A group's target list is mostly its own side, so this comes first.
	private _hostile = [west, east, resistance] select {[_side, _x] call BIS_fnc_sideIsEnemy};

	{
		private _g = _x;
		private _l = leader _g;
		if (alive _l) then {
			{
				_x params ["_acc", "_t", "_tSide", "_type", "_pos", "_age"];
				if (_tSide in _hostile && {alive _t}) then {
					private _knows = _l knowsAbout _t;
					if (_knows >= _minKnows && {(_pos # 0) > 1 || {(_pos # 1) > 1}}) then {
						private _cat = [_type] call SWLC_fnc_intelCategory;
						if (_cat == "") then {_cat = [typeOf _t] call SWLC_fnc_intelCategory};
						if (_cat != "") then {
							private _key = netId _t;
							if (_key == "") then {_key = str _t};
							private _old = _seen getOrDefault [_key, [0]];
							if (_knows > (_old # 0)) then {
								_seen set [_key, [_knows, _cat, +_pos, _t, _g]];
							};
						};
					};
				};
			} forEach (_l targetsQuery [objNull, sideUnknown, "", [], _maxAge]);
		};
	} forEach _groups;

	private _sightings = [];
	{
		_y params ["_knows", "_cat", "_pos", "_t", "_g"];
		_sightings pushBack [_cat, _pos, _t, (_knows / 4) min 1 max 0.3, _g, _knows];
	} forEach _seen;

	private _touched = [_cmd, _sightings, "see"] call SWLC_fnc_intelPost;
	[_cmd, _groups, _touched] call SWLC_fnc_intelAge;
	[_cmd, _groups] call SWLC_fnc_intelPresence;
};

// Merges sightings into the board. Each sighting: [cat, pos, target, confidence, reporterGroup, knows].
// Returns the ids of the entries touched.
SWLC_fnc_intelPost = {
	params ["_cmd", "_sightings", "_source"];
	private _board = _cmd get "board";
	private _now = time;
	private _touched = createHashMap;
	private _entries = createHashMap;
	{
		_x params ["_cat", "_pos", "_t", "_conf", "_g", "_knows"];
		private _r = [CFG("intelMergeVehicle"), CFG("intelMergeInfantry")] select (_cat == "infantry");
		private _i = _board findIf {(_x get "cat") == _cat && {((_x get "pos") distance2D _pos) < _r}};
		private _e = createHashMap;
		if (_i < 0) then {
			_e = [_cmd, _cat, _pos, _t, _conf, _g, _source, _knows] call SWLC_fnc_intelNew;
			_board pushBack _e;
		} else {
			_e = _board # _i;
			_e set ["pos", +_pos];
			_e set ["seen", _now];
			_e set ["base", _conf max ((_e get "base") * 0.5 ^ ((_now - (_e get "baseAt")) / ([_cat] call SWLC_fnc_intelHalfLife)))];
			_e set ["baseAt", _now];
			if !(isNull _t) then {(_e get "units") pushBackUnique _t};
		};
		private _id = _e get "id";
		_entries set [_id, _e];
		_touched set [_id, (_touched getOrDefault [_id, []]) + [_t]];
	} forEach _sightings;

	// Count is the most seen at once, not the running total.
	{
		private _id = _x;
		private _n = if (_source == "player") then {count _y} else {count (_y arrayIntersect _y)};
		private _e = _entries get _id;
		private _new = (_e get "count") max _n;
		if (_new != (_e get "count")) then {
			_e set ["count", _new];
			["C_INTEL", [["side", _cmd get "side"], ["event", "count"], ["id", _id], ["cat", _e get "cat"], ["count", _new]]] call SWLC_fnc_log;
		};
	} forEach _touched;
	_touched
};

SWLC_fnc_intelNew = {
	params ["_cmd", "_cat", "_pos", "_t", "_conf", "_g", "_source", ["_knows", 0], ["_extra", ""]];
	private _id = (_cmd get "boardCounter") + 1;
	_cmd set ["boardCounter", _id];
	private _sector = [_pos] call SWLC_fnc_intelSector;
	private _e = createHashMapFromArray [
		["id", _id], ["cat", _cat], ["pos", +_pos], ["count", 1], ["born", time], ["seen", time], ["base", _conf], ["baseAt", time], ["conf", _conf],
		["units", if (isNull _t) then {[]} else {[_t]}],
		["source", _source], ["sector", _sector], ["reporter", if (isNull _g) then {""} else {groupId _g}]
	];
	private _tx = -1; private _ty = -1; private _rd = -1;
	if !(isNull _t) then {
		_tx = round ((getPosATL _t) # 0); _ty = round ((getPosATL _t) # 1);
		if !(isNull _g) then {_rd = round (leader _g distance2D _t)};
	};
	["C_INTEL", [["side", _cmd get "side"], ["event", "new"], ["id", _id], ["cat", _cat], ["src", _source], ["x", round (_pos # 0)], ["y", round (_pos # 1)],
		["conf", _conf toFixed 2], ["knows", _knows toFixed 2], ["sector", if (isNull _sector) then {"-"} else {[_sector] call SWLC_fnc_adName}],
		["reporter", _e get "reporter"], ["tclass", if (isNull _t) then {"-"} else {typeOf _t}], ["tnet", if (isNull _t) then {"-"} else {netId _t}], ["tx", _tx], ["ty", _ty], ["rdist", _rd], ["extra", _extra]]] call SWLC_fnc_log;

	if (_cat in ["tank", "apc", "static", "heli", "jet"]) then {
		private _place = if (isNull _sector) then {format ["grid %1", mapGridPosition _pos]} else {[_sector] call SWLC_fnc_adName};
		[_cmd get "side", "sighting", [[_cat] call SWLC_fnc_radioCatName, _place], _g] call SWLC_fnc_radio;
	};
	_e
};

// Decay, negative information, dropping dead entries.
SWLC_fnc_intelAge = {
	params ["_cmd", "_groups", "_touched"];
	private _now = time;
	private _board = _cmd get "board";
	private _r = CFG("intelNegativeRadius");
	private _leaders = _groups apply {leader _x};
	private _drop = [];
	{
		private _e = _x;
		private _id = _e get "id";
		private _age = _now - (_e get "seen");
		if !(_id in _touched) then {
			private _pos = _e get "pos";
			if (_age >= CFG("intelNegativeMinAge") && {(_leaders findIf {_x distance2D _pos < _r}) >= 0}) then {
				_e set ["base", (_e get "base") * CFG("intelNegativeFactor")];
				_e set ["negative", true];
			};
		};
		private _hl = [_e get "cat"] call SWLC_fnc_intelHalfLife;
		private _conf = (_e get "base") * 0.5 ^ ((_now - (_e get "baseAt")) / _hl);
		_e set ["conf", _conf];
		if (_conf < CFG("intelDropConf")) then {
			_drop pushBack _forEachIndex;
			["C_INTEL", [["side", _cmd get "side"], ["event", "drop"], ["id", _id], ["cat", _e get "cat"], ["reason", ["decay", "negative"] select (_e getOrDefault ["negative", false])], ["age", round _age]]] call SWLC_fnc_log;
		};
	} forEach _board;
	reverse _drop;
	{_board deleteAt _x} forEach _drop;
};

// Remembers when a friendly group last stood in each sector, for "unscouted".
SWLC_fnc_intelPresence = {
	params ["_cmd", "_groups"];
	private _presence = _cmd get "presence";
	private _at = _groups apply {getPosATL leader _x};
	{
		private _s = _x;
		private _c = _s getVariable "SWLC_pos";
		private _h = (_s getVariable "SWLC_size") / 2 + 80;
		if ((_at findIf {abs ((_x # 0) - (_c # 0)) <= _h && {abs ((_x # 1) - (_c # 1)) <= _h}}) >= 0) then {
			_presence set [[_s] call SWLC_fnc_adName, time];
		};
	} forEach SWLC_sectors;
};

// A kill: a group that destroyed a reported target removes it. A friendly vehicle lost to something
// nobody can see posts a low-confidence AT threat.
SWLC_fnc_intelOnKilled = {
	params ["_killed", "_killer", "_instigator"];
	private _by = if (isNull _instigator) then {_killer} else {_instigator};
	private _bySide = if (isNull _by) then {sideUnknown} else {side group _by};
	{
		private _side = _x;
		private _cmd = missionNamespace getVariable [format ["SWLC_cmd_%1", _side], createHashMap];
		if (count _cmd > 0 && {!isNil {_cmd get "board"}}) then {
			private _board = _cmd get "board";
			if (_bySide == _side) then {
				private _i = _board findIf {_killed in (_x get "units")};
				if (_i >= 0) then {
					private _e = _board # _i;
					private _units = _e get "units";
					_units deleteAt (_units find _killed);
					_e set ["count", ((_e get "count") - 1) max 0];
					if ((_e get "count") <= 0) then {
						["C_INTEL", [["side", _side], ["event", "drop"], ["id", _e get "id"], ["cat", _e get "cat"], ["reason", "kill"], ["age", round (time - (_e get "seen"))]]] call SWLC_fnc_log;
						_board deleteAt _i;
					};
				};
			};

			if (!(_killed isKindOf "Man") && {(_killed getVariable ["SWLC_side", sideUnknown]) == _side}) then {
				private _killerKnown = !isNull _by && {(_board findIf {_by in (_x get "units") || {(vehicle _by) in (_x get "units")}}) >= 0};
				if (!_killerKnown && {_bySide != _side}) then {
					private _p = getPosATL _killed;
					private _e = [_cmd, "unknownAT", _p, objNull, CFG("intelLossConf"), grpNull, "loss", 0, typeOf _killed] call SWLC_fnc_intelNew;
					_board pushBack _e;
					[_cmd, _p] call SWLC_fnc_smartHuntQueue;
				};
			};
		};
	} forEach [west, east];
};

SWLC_fnc_intelPostScan = {
	params ["_side", "_s", "_found"];
	private _cmd = missionNamespace getVariable [format ["SWLC_cmd_%1", _side], createHashMap];
	if (count _cmd == 0) exitWith {};
	private _sightings = [];
	{
		private _cat = [typeOf _x] call SWLC_fnc_intelCategory;
		if (_cat != "") then {
			private _p = getPosATL _x;
			_sightings pushBack [_cat, [_p # 0, _p # 1, 0], _x, 1, grpNull, 4];
		};
	} forEach _found;
	["C_INTEL", [["side", _side], ["event", "scan"], ["sector", [_s] call SWLC_fnc_adName], ["found", count _sightings]]] call SWLC_fnc_log;
	private _postOk = false;
	isNil {
		[_cmd, _sightings, "scan"] call SWLC_fnc_intelPost;
		_postOk = true;
	};
	if (!_postOk) then {[_cmd, "intelPost"] call SWLC_fnc_resStageFault};
};

// Rebuilt each commander tick. Sector name -> summary.
SWLC_fnc_intelSummarise = {
	params ["_cmd"];
	private _now = time;
	private _map = createHashMap;
	private _minConf = CFG("intelThreatMinConf");
	private _delay = CFG("reactionDelay");
	private _airRadius = CFG("intelAirRadius");
	// Sorted by sector first, so each sector only looks at its own entries.
	private _airBoard = [];
	private _bySector = createHashMap;
	{
		if ((_x get "conf") >= _minConf && {(_now - (_x get "born")) >= _delay}) then {
			if ((_x get "cat") in ["heli", "jet"]) then {
				_airBoard pushBack _x;
			} else {
				private _home = _x get "sector";
				if (!isNull _home) then {
					private _key = [_home] call SWLC_fnc_adName;
					private _list = _bySector getOrDefault [_key, []];
					_list pushBack _x;
					_bySector set [_key, _list];
				};
			};
		};
	} forEach (_cmd get "board");
	{
		private _s = _x;
		private _name = [_s] call SWLC_fnc_adName;
		private _c = [_s] call SWLC_fnc_adPos;
		private _infantry = 0; private _armour = 0; private _light = 0; private _static = 0; private _air = 0; private _at = 0;
		private _newest = 1e6;
		{
			if (((_x get "pos") distance2D _c) <= _airRadius) then {_air = _air + (_x get "count")};
		} forEach _airBoard;
		{
			private _e = _x;
			private _n = _e get "count";
			switch (_e get "cat") do {
				case "infantry": {_infantry = _infantry + _n};
				case "tank"; case "apc": {_armour = _armour + _n};
				case "light": {_light = _light + _n};
				case "static": {_static = _static + _n};
				case "unknownAT": {_at = _at + _n};
			};
			_newest = _newest min (_now - (_e get "seen"));
		} forEach (_bySector getOrDefault [_name, []]);
		private _presence = (_now - ((_cmd get "presence") getOrDefault [_name, -1e6]));
		private _scouted = _newest <= CFG("intelScoutedSeconds") || {_presence <= CFG("intelScoutedSeconds")};
		_map set [_name, createHashMapFromArray [["infantry", _infantry], ["armour", _armour], ["light", _light], ["static", _static], ["air", _air], ["at", _at],
			["newest", round _newest], ["scouted", _scouted]]];
	} forEach SWLC_sectors;
	_cmd set ["threat", _map];

	private _t = _cmd get "target";
	if (!isNull _t) then {
		private _sum = _map get ([_t] call SWLC_fnc_adName);
		private _sig = [_sum get "infantry", _sum get "armour", _sum get "light", _sum get "static", _sum get "air", _sum get "at", _sum get "scouted"];
		if (_sig isNotEqualTo (_cmd getOrDefault ["lastThreatSig", []])) then {
			_cmd set ["lastThreatSig", _sig];
			["C_THREAT", [["side", _cmd get "side"], ["sector", [_t] call SWLC_fnc_adName], ["infantry", _sig # 0], ["armour", _sig # 1], ["light", _sig # 2], ["static", _sig # 3], ["air", _sig # 4], ["at", _sig # 5], ["scouted", _sig # 6]]] call SWLC_fnc_log;
		};
	};
};

SWLC_fnc_threatOf = {
	params ["_cmd", "_sector"];
	(_cmd get "threat") getOrDefault [[_sector] call SWLC_fnc_adName, createHashMapFromArray [["infantry", 0], ["armour", 0], ["light", 0], ["static", 0], ["air", 0], ["at", 0], ["newest", 1e6], ["scouted", false]]]
};
