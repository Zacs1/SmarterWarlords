// Defence: reserve groups, counterattack response, the staging-sector abort, stand-down, and player requests.
#include "macros.hpp"

SWLC_fnc_defCompass = {
	params ["_bearing"];
	private _b = ((_bearing mod 360) + 360) mod 360;
	["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"] select ((round (_b / 45)) mod 8)
};

SWLC_fnc_defReserveSize = {
	params ["_side"];
	private _rebuildCmd = missionNamespace getVariable [format ["SWLC_cmd_%1", _side], createHashMap];
	if (count _rebuildCmd > 0 && {[_rebuildCmd] call SWLC_fnc_rebuilding}) exitWith {1000};
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
	if (_owned isEqualTo (_cmd getOrDefault ["centralOwned", []])) exitWith {_cmd get "centralSector"};
	private _best = objNull;
	private _bestSum = 1e12;
	{
		private _p = [_x] call SWLC_fnc_adPos;
		private _sum = 0;
		{_sum = _sum + (_p distance2D ([_x] call SWLC_fnc_adPos))} forEach _owned;
		if (_sum < _bestSum) then {_bestSum = _sum; _best = _x};
	} forEach _owned;
	_cmd set ["centralOwned", _owned];
	_cmd set ["centralSector", _best];
	_best
};

// Board entries fresh enough to count as a threat to a sector.
SWLC_fnc_defRecent = {
	params ["_cmd"];
	private _minConf = CFG("intelThreatMinConf");
	private _maxAge = CFG("defenceSightAge");
	private _delay = CFG("reactionDelay");
	private _now = time;
	(_cmd get "board") select {
		(_x get "cat") in ["infantry", "tank", "apc", "light"] && {(_x get "conf") >= _minConf} && {(_now - (_x get "seen")) <= _maxAge} && {(_now - (_x get "born")) >= _delay}
	}
};

// Enemy strength the side knows of near an owned sector. Pass defRecent's list when checking many sectors.
// Returns [infantry, armour, light, bearing from the sector to the enemy].
SWLC_fnc_defThreatAt = {
	params ["_cmd", "_s", ["_recent", 0]];
	if !(_recent isEqualType []) then {_recent = [_cmd] call SWLC_fnc_defRecent};
	private _c = [_s] call SWLC_fnc_adPos;
	private _r = (([_s] call SWLC_fnc_adSize) / 2) + CFG("defenceRadius");
	private _inf = 0;
	private _arm = 0;
	private _light = 0;
	private _sx = 0;
	private _sy = 0;
	private _weight = 0;
	{
		private _e = _x;
		private _p = _e get "pos";
		if ((_p distance2D _c) <= _r) then {
			private _n = _e get "count";
			switch (_e get "cat") do {
				case "infantry": {_inf = _inf + _n};
				case "light": {_light = _light + _n};
				default {_arm = _arm + _n};
			};
			_sx = _sx + (_p # 0) * _n;
			_sy = _sy + (_p # 1) * _n;
			_weight = _weight + _n;
		};
	} forEach _recent;
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
	private _spots = [_cmd get "side", _c, _ref, [_s] call SWLC_fnc_defenceSpotRadius] call SWLC_fnc_buildStagingSpots;
	if (_spots isEqualTo []) then {_spots = [[_c, _bearing, _size / 4] call SWLC_fnc_offset]};
	_spots
};

// Where a responder should fast travel to. Never into a sector under attack: the nearest safe owned sector instead.
SWLC_fnc_defHop = {
	params ["_g", "_s"];
	private _side = side _g;
	if !([] call SWLC_fnc_propOn) exitWith {_s};
	private _cmd = missionNamespace getVariable [format ["SWLC_cmd_%1", _side], createHashMap];
	private _threats = _cmd getOrDefault ["threats", createHashMap];
	private _hot = {
		params ["_x1"];
		[_threats, _x1] call SWLC_fnc_frontHot || {[_side, _x1] call SWLC_fnc_capBeingSeized}
	};
	if !([_s] call _hot) exitWith {_s};
	private _safe = ([_side] call SWLC_fnc_adOwned) select {!([_x] call _hot) && {[_side, _x] call SWLC_fnc_adCanFTTo}};
	if (_safe isEqualTo []) exitWith {objNull};
	private _c = [_s] call SWLC_fnc_adPos;
	([_safe, _c] call SWLC_fnc_adNearest)
};

// Fast travels the group when it's far, then walks it to the spot.
SWLC_fnc_defMoveTo = {
	params ["_g", "_s", "_spot", "_awayBearing"];
	if ((leader _g distance2D _spot) > CFG("stagingFarThreshold")) then {
		private _hop = [_g, _s] call SWLC_fnc_defHop;
		if (isNull _hop) exitWith {};
		if (((([_hop] call SWLC_fnc_adPos) distance2D _spot) + CFG("defHopMinGain")) > (leader _g distance2D _spot)) exitWith {};
		private _sp = [_hop] call SWLC_fnc_adPos;
		private _away = if (_hop isEqualTo _s) then {_awayBearing + (random 80 - 40)} else {[_sp, [_s] call SWLC_fnc_adPos] call SWLC_fnc_bearing};
		private _landing = [_sp, _away, 30 + random 30] call SWLC_fnc_offset;
		if (surfaceIsWater _landing) then {_landing = _sp};
		if ([_g, _hop, _landing] call SWLC_fnc_adFastTravel) then {[_g] call SWLC_fnc_routeAfterHop};
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
	private _v = [_s] call SWLC_fnc_adWorth;
	private _rec = (_cmd get "musters") getOrDefault [[_s] call SWLC_fnc_adName, createHashMap];
	if (count _rec > 0 && {(_rec get "groups") isNotEqualTo [] || {(_rec get "batch") isNotEqualTo []}}) then {_v = _v + CFG("defenceValueStaging")};
	if ([_s] call SWLC_fnc_adIsBase) then {_v = _v + CFG("defenceValueBase")};
	_v + ([_cmd get "side", _s] call SWLC_fnc_stratWorth) + ([_cmd, _s] call SWLC_fnc_menuDefendBonus)
};

SWLC_fnc_defRespond = {
	params ["_cmd", "_rec"];
	private _side = _cmd get "side";
	private _s = _rec get "sector";
	private _groups = (_rec get "groups") select {({alive _x} count units _x) > 0 && {([_x] call SWLC_fnc_state) == "Defending"}};
	_rec set ["groups", _groups];
	private _prop = [] call SWLC_fnc_propOn;
	private _margin = [1, CFG("responseMargin")] select _prop;
	private _need = ((ceil (((_rec get "strength") * _margin) / CFG("defenceMenPerGroup"))) max 1) min CFG("defenceMaxGroups");
	// A warning, not a sighting: the enemy has picked this sector but nobody has seen it yet. Groups already in a fight stay in it.
	private _alertOnly = _rec getOrDefault ["alertOnly", false];
	_need = _need max (_rec getOrDefault ["alertNeed", 0]);
	private _calm = {!_alertOnly || {!([_x] call SWLC_fnc_groupFighting)}};
	private _limit = _prop || _alertOnly;
	private _peak = _rec getOrDefault ["needPeak", _need];
	if (_prop && {_need > _peak} && {_groups isNotEqualTo []}) then {
		["C_DEF", [["side", _side], ["event", "escalate"], ["sector", [_s] call SWLC_fnc_adName], ["need", _need], ["was", _peak], ["strength", _rec get "strength"]]] call SWLC_fnc_log;
		[_side, "escalate", [[_s] call SWLC_fnc_adName], _groups # 0] call SWLC_fnc_radio;
	};
	_rec set ["needPeak", _peak max _need];
	_rec set ["need", _need];
	private _c = [_s] call SWLC_fnc_adPos;
	private _nearest = {
		params ["_list"];
		[_list, [], {leader _x distance2D _c}, "ASCEND"] call BIS_fnc_sortBy
	};

	private _big = !_alertOnly && {(_rec get "strength") >= CFG("responseCounterattackMen")};
	private _attack = _cmd get "target";
	private _worth = isNull _attack || {([_cmd, _s] call SWLC_fnc_defSectorValue) > (([_attack] call SWLC_fnc_adWorth) + ([_side, _attack] call SWLC_fnc_stratWorth))};
	private _opNow = _cmd get "op";

	// A picket on this sector is already there.
	{
		if ((count (_rec get "groups")) >= _need) exitWith {};
		[_cmd, _x, "defPicket", {
			_x setVariable ["SWLC_picketSector", nil];
			[_cmd, _rec, _x, "picket"] call SWLC_fnc_defSend;
		}] call SWLC_fnc_resGuarded;
	} forEach ((_cmd get "groups") select {([_x] call SWLC_fnc_state) == "Picket" && {(_x getVariable ["SWLC_picketSector", objNull]) isEqualTo _s}});

	// 1. Reserve first.
	private _reserve = [((_cmd get "groups") select {([_x] call SWLC_fnc_state) == "Reserve" && {isNull (_x getVariable ["SWLC_counterFor", objNull])}}) select _calm] call _nearest;
	{
		if ((count (_rec get "groups")) >= _need) exitWith {};
		[_cmd, _x, "defReserve", {
			[_cmd, _rec, _x, "reserve"] call SWLC_fnc_defSend;
		}] call SWLC_fnc_resGuarded;
	} forEach _reserve;

	// Saving the holdouts comes first: only real fighting here may take groups that are on their way to X.
	if (([_cmd] call SWLC_fnc_holdPriority) && {!([_s] call SWLC_fnc_frontFighting)}) exitWith {};

	// 2. A sector with a muster in progress: its groups defend at once.
	private _muster = (_cmd get "musters") getOrDefault [[_s] call SWLC_fnc_adName, createHashMap];
	if (count _muster > 0) then {
		private _staged = (((_muster get "groups") + (_muster get "batch")) select {([_x] call SWLC_fnc_state) in ["Mustering", "Travelling", "Mounting"]}) select _calm;
		if (_limit && {!_big}) then {
			_staged = ([_staged] call _nearest) select [0, (_need - (count (_rec get "groups"))) max 0];
		};
		if (_staged isNotEqualTo []) then {
			{
				[_cmd, _x, "defStaged", {
					if (_prop && {!isNil "_opNow"}) then {_x setVariable ["SWLC_peeledOp", _opNow get "id"]};
					[_cmd, _rec, _x, "staging_abort"] call SWLC_fnc_defSend;
				}] call SWLC_fnc_resGuarded;
			} forEach _staged;
			// A warning takes only the groups it needs and the muster carries on.
			if (!_alertOnly) then {
				_muster set ["firstArrive", -1];
				["C_DEF", [["side", _side], ["event", "staging_abort"], ["sector", [_s] call SWLC_fnc_adName], ["groups", count _staged]]] call SWLC_fnc_log;
				[_side, "stagingattack"] call SWLC_fnc_radio;
			};
		};
	};

	// 3. A raid-sized threat: the attack's least-engaged groups, never ones in a fight, up to a third of the attack.
	// A bigger force is a counterattack and falls through to the full defence rules below.
	if (_limit && {!_big} && {(count (_rec get "groups")) < _need}) exitWith {
		private _op = _cmd get "op";
		if (isNil "_op") exitWith {};
		private _live = [_op] call SWLC_fnc_waveLive;
		private _cap = floor ((count _live) * CFG("responseCapFraction"));
		private _peeled = {(_x getVariable ["SWLC_peeledOp", -1]) == (_op get "id") && {([_x] call SWLC_fnc_state) == "Defending"}} count (_cmd get "groups");
		private _pool = (_live select {([_x] call SWLC_fnc_state) in ["Mustering", "Travelling", "Waiting", "Advancing"] && {(behaviour leader _x) != "COMBAT"}}) select _calm;
		{
			if ((count (_rec get "groups")) >= _need || {_peeled >= _cap}) exitWith {};
			[_cmd, _x, "defPeel", {
				_x setVariable ["SWLC_peeledOp", _op get "id"];
				[_cmd, _rec, _x, "peeled"] call SWLC_fnc_defSend;
				_peeled = _peeled + 1;
				["C_DEF", [["side", _side], ["event", "peel"], ["sector", [_s] call SWLC_fnc_adName], ["group", groupId _x], ["peeled", _peeled], ["cap", _cap], ["need", _need]]] call SWLC_fnc_log;
			}] call SWLC_fnc_resGuarded;
		} forEach ([_pool] call _nearest);
	};

	// 4. Still short: pull attackers only if this sector is worth more than the attack.
	if ((count (_rec get "groups")) < _need) then {
		if !(_worth) then {
			if !(_rec getOrDefault ["shortLogged", false]) then {
				_rec set ["shortLogged", true];
				["C_DEF", [["side", _side], ["event", "not_pulling"], ["sector", [_s] call SWLC_fnc_adName], ["need", _need], ["have", count (_rec get "groups")]]] call SWLC_fnc_log;
			};
		} else {
			private _op = _cmd get "op";
			private _pool = if (isNil "_op") then {[]} else {([_op] call SWLC_fnc_waveLive) select {([_x] call SWLC_fnc_state) in ["Mustering", "Travelling", "Mounting", "Advancing"]}};
			{
				if ((count (_rec get "groups")) >= _need) exitWith {};
				[_cmd, _x, "defPull", {
					if (_prop) then {_x setVariable ["SWLC_peeledOp", _op get "id"]};
					[_cmd, _rec, _x, "pulled"] call SWLC_fnc_defSend;
				}] call SWLC_fnc_resGuarded;
			} forEach ([_pool] call _nearest);
		};
	};
};

SWLC_fnc_defStandDown = {
	params ["_cmd", "_name", "_rec", "_why"];
	private _returned = false;
	{
		[_cmd, _x, "defStandDown", {
			if (({alive _x} count units _x) > 0 && {([_x] call SWLC_fnc_state) == "Defending"}) then {
				if ((_x getVariable ["SWLC_peeledOp", -1]) >= 0) then {
					_x setVariable ["SWLC_peeledOp", -1];
					_x setVariable ["SWLC_peeledBackAt", time];
					_returned = true;
				};
				[_x] call SWLC_fnc_adClearOrder;
				[_x, "Unassigned", [], "stand_down"] call SWLC_fnc_setState;
			};
		}] call SWLC_fnc_resGuarded;
	} forEach (_rec get "groups");
	if (_returned && {_why == "clear"}) then {[_cmd get "side", "defreturn", [_name]] call SWLC_fnc_radio};
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
	// Groups held as an alert's counterattack reserve are on a job: not rotated, shrunk or moved here, but they count towards the size.
	private _reserve = (_cmd get "groups") select {([_x] call SWLC_fnc_state) == "Reserve" && {isNull (_x getVariable ["SWLC_counterFor", objNull])}};
	private _counters = {!isNull (_x getVariable ["SWLC_counterFor", objNull])} count (_cmd get "groups");
	private _post = [_cmd] call SWLC_fnc_defCentralSector;
	if (isNull _post) exitWith {};

	// Everyone is in the reserve during a rebuild, so that time doesn't count as anyone's turn.
	private _rebuilding = _size >= 1000;
	if (!_rebuilding) then {_size = (_size - _counters) max 0};
	if (!_rebuilding && {[_cmd] call SWLC_fnc_holdPriority}) then {_size = 0};
	if (CFG("reserveRotate")) then {
		private _since = time - (_cmd getOrDefault ["reserveTickAt", time]);
		_cmd set ["reserveTickAt", time];
		if (!_rebuilding) then {
			{_x setVariable ["SWLC_reserveServed", (_x getVariable ["SWLC_reserveServed", 0]) + _since]} forEach _reserve;
		};
		_reserve = [_reserve, [], {_x getVariable ["SWLC_reserveServed", 0]}, "ASCEND"] call BIS_fnc_sortBy;
	};

	if ((count _reserve) > _size) then {
		{
			[_cmd, _x, "reserveShrink", {
				[_x] call SWLC_fnc_adClearOrder;
				[_x, "Unassigned", [], "reserve_shrunk"] call SWLC_fnc_setState;
				_reserve = _reserve - [_x];
			}] call SWLC_fnc_resGuarded;
		} forEach (_reserve select [_size, count _reserve]);
	};

	// A wave is out and this group has done its turn: it goes to the fight, and a group coming back takes over.
	if (CFG("reserveRotate") && {!_rebuilding} && {!isNil {_cmd get "op"}}) then {
		{
			private _g = _x;
			if ((time - (_g getVariable ["SWLC_stateSince", time])) >= CFG("reserveStintSeconds")) then {
				[_cmd, _g, "reserveRotate", {
					_g setVariable ["SWLC_reserveRestUntil", time + CFG("reserveRestSeconds")];
					[_g] call SWLC_fnc_adClearOrder;
					[_g, "Unassigned", [], "reserve_rotated"] call SWLC_fnc_setState;
					_reserve = _reserve - [_g];
					["C_DEF", [["side", _side], ["event", "reserve_rotated"], ["group", groupId _g], ["served", round (_g getVariable ["SWLC_reserveServed", 0])]]] call SWLC_fnc_log;
				}] call SWLC_fnc_resGuarded;
			};
		} forEach (+_reserve);
	};

	{
		if ((count _reserve) >= _size) exitWith {};
		private _g = _x;
		[_cmd, _g, "reserveJoin", {
			_g setVariable ["SWLC_patrolAt", -1e6];
			_reserve pushBack _g;
			[_g, "Reserve", [_post] call SWLC_fnc_adPos, "reserve"] call SWLC_fnc_setState;
			["C_DEF", [["side", _side], ["event", "reserve_join"], ["group", groupId _g], ["post", [_post] call SWLC_fnc_adName], ["size", _size]]] call SWLC_fnc_log;
		}] call SWLC_fnc_resGuarded;
	} forEach ((_cmd get "groups") select {([_x] call SWLC_fnc_state) == "Unassigned" && {_rebuilding || {time >= (_x getVariable ["SWLC_reserveRestUntil", -1])}}});

	private _c = [_post] call SWLC_fnc_adPos;
	{
		private _g = _x;
		[_cmd, _g, "reservePatrol", {
			if ((time - (_g getVariable ["SWLC_patrolAt", -1e6])) >= CFG("reservePatrolSeconds")) then {
				_g setVariable ["SWLC_patrolAt", time];
				private _spot = [_c, random 360, 15 + random 45] call SWLC_fnc_offset;
				if (surfaceIsWater _spot) then {_spot = +_c};
				_g setVariable ["SWLC_goal", _spot];
				[_g, [[_spot, "MOVE", 15]], "SAFE", "LIMITED", "WEDGE", "YELLOW"] call SWLC_fnc_adSetOrder;
				[_g, _post, _spot, random 360] call SWLC_fnc_defMoveTo;
			};
		}] call SWLC_fnc_resGuarded;
	} forEach _reserve;

	// A group that was still seated when it was pulled couldn't fast travel. Try again once it's on foot.
	{
		private _g = _x;
		[_cmd, _g, "defRetry", {
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
		}] call SWLC_fnc_resGuarded;
	} forEach (_cmd get "groups");

	// Defenders holding a spot shuffle as well.
	{
		private _g = _x;
		[_cmd, _g, "defShuffle", {
			if (([_g] call SWLC_fnc_state) == "Defending" && {(_g getVariable ["SWLC_lambsTask", ""]) == ""} && {(time - (_g getVariable ["SWLC_patrolAt", -1e6])) >= CFG("reservePatrolSeconds")}) then {
				_g setVariable ["SWLC_patrolAt", time];
				private _goal = _g getVariable ["SWLC_goal", []];
				if (_goal isNotEqualTo []) then {
					private _spot = [_goal, _g] call SWLC_fnc_shuffleSpot;
					// Holdouts move as they must to stay alive in Warlords' eyes, but stay dug in.
					private _hold = _g getVariable ["SWLC_holdout", false];
					[_g, [[[_spot, "MOVE", 8]], [[_spot, "MOVE", 8], [_spot, "HOLD", 0]]] select _hold, "AWARE", "FULL", "WEDGE", ["RED", "YELLOW"] select _hold] call SWLC_fnc_adSetOrder;
				};
			};
		}] call SWLC_fnc_resGuarded;
	} forEach (_cmd get "groups");
};

SWLC_fnc_defenceTick = {
	params ["_cmd"];
	if !(CFG("defenceEnabled")) exitWith {};
	private _side = _cmd get "side";
	private _threats = _cmd get "threats";
	private _owned = [_side] call SWLC_fnc_adOwned;
	private _recent = [_cmd] call SWLC_fnc_defRecent;

	// Detect
	{
		private _s = _x;
		([_cmd, _s, _recent] call SWLC_fnc_defThreatAt) params ["_inf", "_arm", "_light", "_bearing"];
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
			_rec set ["alertOnly", false];
			_rec set ["strength", (_inf + 3 * _light + 6 * _arm) max CFG("defenceMinInfantry")];
			_rec set ["bearing", _bearing];
			if (_new || {isNil {_rec get "spots"}}) then {_rec set ["spots", [_cmd, _s, _bearing] call SWLC_fnc_defSpots]};
			if (_new) then {
				private _what = if (_arm > 0) then {"armour"} else {if (_light > 0) then {"vehicles"} else {"infantry"}};
				["C_DEF", [["side", _side], ["event", "detect"], ["sector", _name], ["inf", _inf], ["arm", _arm], ["light", _light], ["seizing", _seizing], ["bearing", round _bearing]]] call SWLC_fnc_log;
				[_side, "defend", [_name, _what, [_bearing] call SWLC_fnc_defCompass]] call SWLC_fnc_radio;
			};
			if (_seizing && {!(_rec getOrDefault ["seizeCalled", false])} && {[] call SWLC_fnc_propOn}) then {
				_rec set ["seizeCalled", true];
				["C_DEF", [["side", _side], ["event", "seizing"], ["sector", _name]]] call SWLC_fnc_log;
				[_side, "seizing", [_name]] call SWLC_fnc_radio;
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

// What players on a side see of the plan, as public data their client draws as local markers.
SWLC_fnc_planPublish = {
	params ["_cmd"];
	private _side = _cmd get "side";
	if ((time - (_cmd getOrDefault ["planAt", -1e6])) < CFG("planPublishSeconds")) exitWith {};
	if (!CFG("planAlwaysPublish") && {!([_side] call SWLC_fnc_adSideHasPlayers)}) exitWith {};
	_cmd set ["planAt", time];
	private _target = _cmd get "target";
	private _plan = [];
	private _op = _cmd get "op";
	if (!isNull _target && {!isNil "_op"}) then {
		private _eta = -1;
		if ((_op get "firstAtRally") >= 0) then {_eta = round (((_op get "firstAtRally") + ([_cmd, _op] call SWLC_fnc_rallyLoneWait) - time) max 0)};
		private _musters = [];
		{
			if ((_y get "groups") isNotEqualTo [] || {(_y get "batch") isNotEqualTo []}) then {_musters pushBack [_y get "pos", _y get "name"]};
		} forEach (_cmd get "musters");
		_plan = [[_target] call SWLC_fnc_adPos, [_target] call SWLC_fnc_adName, _op get "rally", _op get "bearing", _eta, _musters];
	};
	missionNamespace setVariable [format ["SWLC_plan_%1", _side], _plan, true];
};
