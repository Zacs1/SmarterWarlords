// Defence: reserve groups, counterattack response, the staging-sector abort, stand-down, and player requests.
#include "macros.hpp"

SWLC_fnc_defCompass = {
	params ["_bearing"];
	private _b = ((_bearing mod 360) + 360) mod 360;
	["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"] select ((round (_b / 45)) mod 8)
};

SWLC_fnc_defReserveSize = {
	params ["_side"];
	private _n = count ([_side] call SWLC_fnc_adOwned);
	private _size = 1;
	{
		if (_n <= (_x # 0)) exitWith {_size = _x # 1};
	} forEach CFG("reserveBySectors");
	_size
};

// The owned sector with the smallest total distance to the side's other sectors.
SWLC_fnc_defCentralSector = {
	params ["_cmd"];
	private _side = _cmd get "side";
	private _owned = ([_side] call SWLC_fnc_adOwned) select {[_x] call SWLC_fnc_adPos isNotEqualTo []};
	if (_owned isEqualTo []) exitWith {objNull};
	private _best = objNull;
	private _bestSum = 1e12;
	{
		private _p = [_x] call SWLC_fnc_adPos;
		private _sum = 0;
		{_sum = _sum + (_p distance2D ([_x] call SWLC_fnc_adPos))} forEach _owned;
		if (_sum < _bestSum) then {_bestSum = _sum; _best = _x};
	} forEach _owned;
	_best
};

// Enemy strength the side knows of near an owned sector.
// Returns [infantry, armour, light, bearing from the sector to the enemy].
SWLC_fnc_defThreatAt = {
	params ["_cmd", "_s"];
	private _c = [_s] call SWLC_fnc_adPos;
	private _r = (([_s] call SWLC_fnc_adSize) / 2) + CFG("defenceRadius");
	private _minConf = CFG("intelThreatMinConf");
	private _maxAge = CFG("defenceSightAge");
	private _inf = 0;
	private _arm = 0;
	private _light = 0;
	private _sx = 0;
	private _sy = 0;
	private _weight = 0;
	{
		private _e = _x;
		private _cat = _e get "cat";
		if (_cat in ["infantry", "tank", "apc", "light"] && {(_e get "conf") >= _minConf} && {(time - (_e get "seen")) <= _maxAge} && {(time - (_e get "born")) >= CFG("reactionDelay")}) then {
			private _p = _e get "pos";
			if ((_p distance2D _c) <= _r) then {
				private _n = _e get "count";
				switch (_cat) do {
					case "infantry": {_inf = _inf + _n};
					case "light": {_light = _light + _n};
					default {_arm = _arm + _n};
				};
				_sx = _sx + (_p # 0) * _n;
				_sy = _sy + (_p # 1) * _n;
				_weight = _weight + _n;
			};
		};
	} forEach (_cmd get "board");
	private _bearing = if (_weight > 0) then {[_c, [_sx / _weight, _sy / _weight]] call SWLC_fnc_bearing} else {random 360};
	[_inf, _arm, _light, _bearing]
};

// Spots in the threatened sector on the side the enemy is coming from: edges and cover, not the middle.
SWLC_fnc_defSpots = {
	params ["_cmd", "_s", "_bearing"];
	private _c = [_s] call SWLC_fnc_adPos;
	private _size = [_s] call SWLC_fnc_adSize;
	// buildStagingSpots prefers the far side from its reference point, so put that point opposite the enemy.
	private _ref = [_c, _bearing + 180, 1000] call SWLC_fnc_offset;
	private _spots = [_cmd get "side", _c, _ref, (_size / 2 + 30) max 60] call SWLC_fnc_buildStagingSpots;
	if (_spots isEqualTo []) then {_spots = [[_c, _bearing, _size / 4] call SWLC_fnc_offset]};
	_spots
};

// Fast travels the group when it's far, then walks it to the spot.
SWLC_fnc_defMoveTo = {
	params ["_g", "_s", "_spot", "_awayBearing"];
	if ((leader _g distance2D _spot) > CFG("stagingFarThreshold")) then {
		private _sp = [_s] call SWLC_fnc_adPos;
		private _landing = [_sp, _awayBearing + (random 80 - 40), 30 + random 30] call SWLC_fnc_offset;
		if (surfaceIsWater _landing) then {_landing = _sp};
		[_g, _s, _landing] call SWLC_fnc_adFastTravel;
	};
};

SWLC_fnc_defSend = {
	params ["_cmd", "_rec", "_g", "_reason"];
	private _s = _rec get "sector";
	private _spots = _rec get "spots";
	private _i = _rec get "slot";
	_rec set ["slot", _i + 1];
	private _spot = _spots # (_i mod count _spots);
	private _from = [_g] call SWLC_fnc_state;
	[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
	[_g, "Defending", _spot, "counterattack"] call SWLC_fnc_setState;
	_g setVariable ["SWLC_patrolAt", time];
	[_g, [[_spot, "MOVE", 15]], "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
	[_g, _s, _spot, (_rec get "bearing") + 180] call SWLC_fnc_defMoveTo;
	_g setVariable ["SWLC_defRetry", [_s, _spot, (_rec get "bearing") + 180]];
	(_rec get "groups") pushBackUnique _g;
	["C_DEF", [["side", _cmd get "side"], ["event", "respond"], ["sector", [_s] call SWLC_fnc_adName], ["group", groupId _g], ["from", _from], ["reason", _reason], ["after", round (time - (_rec get "first"))]]] call SWLC_fnc_log;
};

// The value of holding a sector: income, plus being the staging sector or the base.
SWLC_fnc_defSectorValue = {
	params ["_cmd", "_s"];
	private _v = [_s] call SWLC_fnc_adValue;
	if (_s isEqualTo (_cmd get "stagingSector")) then {_v = _v + CFG("defenceValueStaging")};
	if ([_s] call SWLC_fnc_adIsBase) then {_v = _v + CFG("defenceValueBase")};
	_v
};

SWLC_fnc_defRespond = {
	params ["_cmd", "_rec"];
	private _side = _cmd get "side";
	private _s = _rec get "sector";
	private _groups = (_rec get "groups") select {({alive _x} count units _x) > 0 && {([_x] call SWLC_fnc_state) == "Defending"}};
	_rec set ["groups", _groups];
	private _need = ((ceil ((_rec get "strength") / CFG("defenceMenPerGroup"))) max 1) min CFG("defenceMaxGroups");
	private _c = [_s] call SWLC_fnc_adPos;
	private _nearest = {
		params ["_list"];
		[_list, [], {leader _x distance2D _c}, "ASCEND"] call BIS_fnc_sortBy
	};

	// 1. Reserve first.
	private _reserve = [(_cmd get "groups") select {([_x] call SWLC_fnc_state) == "Reserve"}] call _nearest;
	{
		if ((count (_rec get "groups")) >= _need) exitWith {};
		[_cmd, _rec, _x, "reserve"] call SWLC_fnc_defSend;
	} forEach _reserve;

	// 2. The staging sector: every staging group defends at once.
	private _isStaging = _s isEqualTo (_cmd get "stagingSector");
	if (_isStaging && {!isNil {_cmd get "gather"}}) then {
		private _staged = ((_cmd get "gather") get "groups") select {([_x] call SWLC_fnc_state) in ["Staging", "Travelling"]};
		if (_staged isNotEqualTo []) then {
			{[_cmd, _rec, _x, "staging_abort"] call SWLC_fnc_defSend} forEach _staged;
			(_cmd get "gather") set ["firstArrive", -1];
			["C_DEF", [["side", _side], ["event", "staging_abort"], ["sector", [_s] call SWLC_fnc_adName], ["groups", count _staged]]] call SWLC_fnc_log;
			[_side, "stagingattack"] call SWLC_fnc_radio;
		};
	};

	// 3. Still short: pull attackers only if this sector is worth more than the attack.
	if ((count (_rec get "groups")) < _need) then {
		private _attack = _cmd get "target";
		private _worth = isNull _attack || {([_cmd, _s] call SWLC_fnc_defSectorValue) > ([_attack] call SWLC_fnc_adValue)};
		if !(_worth) then {
			if !(_rec getOrDefault ["shortLogged", false]) then {
				_rec set ["shortLogged", true];
				["C_DEF", [["side", _side], ["event", "not_pulling"], ["sector", [_s] call SWLC_fnc_adName], ["need", _need], ["have", count (_rec get "groups")]]] call SWLC_fnc_log;
			};
		} else {
			private _pool = [];
			if (!isNil {_cmd get "gather"}) then {_pool append (((_cmd get "gather") get "groups") select {([_x] call SWLC_fnc_state) in ["Staging", "Travelling"]})};
			{
				if ((_x get "phase") in ["MOUNT", "TO_HOLD"]) then {_pool append ((_x get "groups") select {({alive _x} count units _x) > 0})};
			} forEach (_cmd get "flying");
			{
				if ((count (_rec get "groups")) >= _need) exitWith {};
				[_cmd, _rec, _x, "pulled"] call SWLC_fnc_defSend;
			} forEach ([_pool] call _nearest);
		};
	};
};

SWLC_fnc_defStandDown = {
	params ["_cmd", "_name", "_rec", "_why"];
	{
		if (({alive _x} count units _x) > 0 && {([_x] call SWLC_fnc_state) == "Defending"}) then {
			[_x] call SWLC_fnc_adClearOrder;
			[_x, "Unassigned", [], "stand_down"] call SWLC_fnc_setState;
		};
	} forEach (_rec get "groups");
	["C_DEF", [["side", _cmd get "side"], ["event", "stand_down"], ["sector", _name], ["why", _why], ["groups", count (_rec get "groups")], ["duration", round (time - (_rec get "first"))]]] call SWLC_fnc_log;
	if (_why == "clear") then {[_cmd get "side", "standdown", [_name]] call SWLC_fnc_radio};
	(_cmd get "threats") deleteAt _name;
};

// Keeps the reserve at its size and its groups at the post, moving now and then so Warlords
// doesn't treat a waiting leader as stuck.
SWLC_fnc_defReserveTick = {
	params ["_cmd"];
	private _side = _cmd get "side";
	private _size = [_side] call SWLC_fnc_defReserveSize;
	private _reserve = (_cmd get "groups") select {([_x] call SWLC_fnc_state) == "Reserve"};
	private _post = [_cmd] call SWLC_fnc_defCentralSector;
	if (isNull _post) exitWith {};

	if ((count _reserve) > _size) then {
		{
			[_x] call SWLC_fnc_adClearOrder;
			[_x, "Unassigned", [], "reserve_shrunk"] call SWLC_fnc_setState;
			_reserve = _reserve - [_x];
		} forEach (_reserve select [_size, count _reserve]);
	};
	{
		if ((count _reserve) >= _size) exitWith {};
		private _g = _x;
		_g setVariable ["SWLC_patrolAt", -1e6];
		_reserve pushBack _g;
		[_g, "Reserve", [_post] call SWLC_fnc_adPos, "reserve"] call SWLC_fnc_setState;
		["C_DEF", [["side", _side], ["event", "reserve_join"], ["group", groupId _g], ["post", [_post] call SWLC_fnc_adName], ["size", _size]]] call SWLC_fnc_log;
	} forEach ((_cmd get "groups") select {([_x] call SWLC_fnc_state) == "Unassigned"});

	private _c = [_post] call SWLC_fnc_adPos;
	{
		private _g = _x;
		if ((time - (_g getVariable ["SWLC_patrolAt", -1e6])) >= CFG("reservePatrolSeconds")) then {
			_g setVariable ["SWLC_patrolAt", time];
			private _spot = [_c, random 360, 15 + random 45] call SWLC_fnc_offset;
			if (surfaceIsWater _spot) then {_spot = +_c};
			_g setVariable ["SWLC_goal", _spot];
			[_g, [[_spot, "MOVE", 15]], "SAFE", "LIMITED", "WEDGE", "YELLOW"] call SWLC_fnc_adSetOrder;
			[_g, _post, _spot, random 360] call SWLC_fnc_defMoveTo;
		};
	} forEach _reserve;

	// A group that was still seated when it was pulled couldn't fast travel. Try again once it's on foot.
	{
		private _g = _x;
		private _retry = _g getVariable ["SWLC_defRetry", []];
		if (_retry isNotEqualTo []) then {
			if (([_g] call SWLC_fnc_state) != "Defending") then {
				_g setVariable ["SWLC_defRetry", []];
			} else {
				if (vehicle leader _g == leader _g) then {
					_g setVariable ["SWLC_defRetry", []];
					([_g] + _retry) call SWLC_fnc_defMoveTo;
				};
			};
		};
	} forEach (_cmd get "groups");

	// Defenders holding a spot shuffle as well.
	{
		private _g = _x;
		if (([_g] call SWLC_fnc_state) == "Defending" && {(time - (_g getVariable ["SWLC_patrolAt", -1e6])) >= CFG("reservePatrolSeconds")}) then {
			_g setVariable ["SWLC_patrolAt", time];
			private _goal = _g getVariable ["SWLC_goal", []];
			if (_goal isNotEqualTo []) then {
				private _spot = [_goal, random 360, 5 + random 10] call SWLC_fnc_offset;
				[_g, [[_spot, "MOVE", 15]], "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
			};
		};
	} forEach (_cmd get "groups");
};

SWLC_fnc_defenceTick = {
	params ["_cmd"];
	if !(CFG("defenceEnabled")) exitWith {};
	private _side = _cmd get "side";
	private _threats = _cmd get "threats";
	private _owned = [_side] call SWLC_fnc_adOwned;

	// Detect
	{
		private _s = _x;
		([_cmd, _s] call SWLC_fnc_defThreatAt) params ["_inf", "_arm", "_light", "_bearing"];
		private _seizing = [_side, _s] call SWLC_fnc_adEnemySeizing;
		if (_seizing || {_arm > 0} || {(_inf + 3 * _light) >= CFG("defenceMinInfantry")}) then {
			private _name = [_s] call SWLC_fnc_adName;
			private _rec = _threats getOrDefault [_name, createHashMap];
			private _new = count _rec == 0;
			if (_new) then {
				_rec = createHashMapFromArray [["sector", _s], ["first", time], ["groups", []], ["slot", 0], ["requestedUntil", -1]];
				_threats set [_name, _rec];
			};
			_rec set ["last", time];
			_rec set ["strength", (_inf + 3 * _light + 6 * _arm) max CFG("defenceMinInfantry")];
			_rec set ["bearing", _bearing];
			if (_new || {isNil {_rec get "spots"}}) then {_rec set ["spots", [_cmd, _s, _bearing] call SWLC_fnc_defSpots]};
			if (_new) then {
				private _what = if (_arm > 0) then {"armour"} else {if (_light > 0) then {"vehicles"} else {"infantry"}};
				["C_DEF", [["side", _side], ["event", "detect"], ["sector", _name], ["inf", _inf], ["arm", _arm], ["light", _light], ["seizing", _seizing], ["bearing", round _bearing]]] call SWLC_fnc_log;
				[_side, "defend", [_name, _what, [_bearing] call SWLC_fnc_defCompass]] call SWLC_fnc_radio;
			};
		};
	} forEach _owned;

	// Respond and stand down
	{
		private _name = _x;
		private _rec = _threats get _name;
		private _s = _rec get "sector";
		if (([_s] call SWLC_fnc_adOwner) != _side) then {
			[_cmd, _name, _rec, "lost"] call SWLC_fnc_defStandDown;
		} else {
			if ((time - (_rec get "last")) >= CFG("defenceStandDownSeconds") && {time >= (_rec get "requestedUntil")}) then {
				[_cmd, _name, _rec, "clear"] call SWLC_fnc_defStandDown;
			} else {
				[_cmd, _rec] call SWLC_fnc_defRespond;
			};
		};
	} forEach (keys _threats);

	[_cmd] call SWLC_fnc_defReserveTick;
};

// ---- Player messages. Every function here is called only when a human uses a scroll action. ----

SWLC_fnc_playerMsg = {
	params ["_kind", "_player", "_data"];
	if (isNull _player || {!isPlayer _player}) exitWith {};
	// A request can only speak for its sender. Owner 0 means the host's own local call, which is fine.
	if (isRemoteExecuted && {remoteExecutedOwner != 0} && {remoteExecutedOwner != owner _player}) exitWith {};
	private _side = side group _player;
	private _cmd = missionNamespace getVariable [format ["SWLC_cmd_%1", _side], createHashMap];
	if (count _cmd == 0) exitWith {};
	switch (_kind) do {
		case "report": {[_cmd, _player, _data] call SWLC_fnc_playerReport};
		case "attack": {[_cmd, _player] call SWLC_fnc_playerAttack};
		case "defend": {[_cmd, _player] call SWLC_fnc_playerDefend};
	};
};

SWLC_fnc_playerReport = {
	params ["_cmd", "_player", "_items"];
	private _g = group _player;
	private _sightings = [];
	{
		_x params ["_cls", "_pos"];
		if (isClass (configFile >> "CfgVehicles" >> _cls) && {(_player distance2D _pos) <= CFG("playerReportRange")}) then {
			private _cat = [_cls] call SWLC_fnc_intelCategory;
			if (_cat != "") then {_sightings pushBack [_cat, [_pos # 0, _pos # 1, 0], objNull, CFG("playerReportConf"), _g, 4]};
		};
	} forEach (_items select [0, CFG("playerReportMax")]);
	["C_REQ", [["side", _cmd get "side"], ["kind", "report"], ["player", name _player], ["items", count _sightings]]] call SWLC_fnc_log;
	if (_sightings isEqualTo []) exitWith {};
	[_cmd, _sightings, "player"] call SWLC_fnc_intelPost;
	[_cmd get "side", "report", [], _g] call SWLC_fnc_radio;
};

SWLC_fnc_playerAttack = {
	params ["_cmd", "_player"];
	private _side = _cmd get "side";
	private _w = _cmd get "gather";
	private _ok = false;
	if (!isNil "_w") then {
		private _staged = ([_w] call SWLC_fnc_waveLive) select {([_x] call SWLC_fnc_state) == "Staging"};
		if ((count _staged) >= CFG("requestGoMinGroups")) then {
			_w set ["forceGo", true];
			_ok = true;
		};
	};
	["C_REQ", [["side", _side], ["kind", "attack"], ["player", name _player], ["ok", _ok]]] call SWLC_fnc_log;
	[_side, ["reqno", "reqok"] select _ok] call SWLC_fnc_radio;
};

SWLC_fnc_playerDefend = {
	params ["_cmd", "_player"];
	private _side = _cmd get "side";
	private _owned = ([_side] call SWLC_fnc_adOwned) select {(_player distance2D ([_x] call SWLC_fnc_adPos)) <= CFG("requestDefendRange")};
	private _ok = false;
	private _name = "-";
	if (_owned isNotEqualTo []) then {
		private _s = ([_owned, [], {_player distance2D ([_x] call SWLC_fnc_adPos)}, "ASCEND"] call BIS_fnc_sortBy) # 0;
		_name = [_s] call SWLC_fnc_adName;
		private _free = {([_x] call SWLC_fnc_state) == "Reserve"} count (_cmd get "groups");
		private _threats = _cmd get "threats";
		if (_free > 0 || {_name in _threats}) then {
			private _rec = _threats getOrDefault [_name, createHashMap];
			if (count _rec == 0) then {
				private _bearing = [[_s] call SWLC_fnc_adPos, [[_side] call SWLC_fnc_adBase] call SWLC_fnc_adPos] call SWLC_fnc_bearing;
				_rec = createHashMapFromArray [["sector", _s], ["first", time], ["last", time], ["groups", []], ["slot", 0], ["strength", CFG("defenceMenPerGroup")], ["bearing", _bearing + 180]];
				_rec set ["spots", [_cmd, _s, _bearing + 180] call SWLC_fnc_defSpots];
				_threats set [_name, _rec];
			};
			_rec set ["requestedUntil", time + CFG("requestDefendSeconds")];
			[_cmd, _rec] call SWLC_fnc_defRespond;
			_ok = true;
		};
	};
	["C_REQ", [["side", _side], ["kind", "defend"], ["player", name _player], ["sector", _name], ["ok", _ok]]] call SWLC_fnc_log;
	[_side, ["reqno", "reqok"] select _ok] call SWLC_fnc_radio;
};

// What players on a side see of the plan, as public data their client draws as local markers.
SWLC_fnc_planPublish = {
	params ["_cmd"];
	private _side = _cmd get "side";
	if ((time - (_cmd getOrDefault ["planAt", -1e6])) < CFG("planPublishSeconds")) exitWith {};
	if (!CFG("planAlwaysPublish") && {!([_side] call SWLC_fnc_adSideHasPlayers)}) exitWith {};
	_cmd set ["planAt", time];
	private _target = _cmd get "target";
	private _plan = [];
	if (!isNull _target) then {
		private _w = _cmd get "gather";
		private _eta = -1;
		if (!isNil "_w" && {(_w get "firstArrive") >= 0}) then {_eta = round ((CFG("goMaxWait") - (time - (_w get "firstArrive"))) max 0)};
		private _approaches = [];
		{
			if ((_x get "phase") in ["MOUNT", "TO_HOLD", "ASSAULT"]) then {
				_approaches append ((_x get "approaches") apply {[_x get "hold", _x get "bearing"]});
			};
		} forEach (_cmd get "flying");
		_plan = [[_target] call SWLC_fnc_adPos, [_target] call SWLC_fnc_adName, _cmd get "stagingPos", [_cmd] call SWLC_fnc_stagingName, _eta, _approaches];
	};
	missionNamespace setVariable [format ["SWLC_plan_%1", _side], _plan, true];
};
