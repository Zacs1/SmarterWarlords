// Defence starts when the enemy picks the target, and in three layers. Warlords tells a side when one of its sectors
// becomes the enemy's target: that warning is the only thing used here, never what the enemy is doing out of sight.
//
// alertTick runs before defenceTick and writes a threat record for the sector, with spots on the approach side and a
// floor on how many groups it needs, so defRespond's normal order (pickets, Reserve, muster, peel) sends the main
// position. alertLayers runs after defenceTick and adds what defRespond doesn't: the screen, the counterattack reserve,
// the facing, and the break-in.
//
// _cmd get "alert" (empty when none): sector, since, approach [bearing, pointOnApproach, roadPoints], groups (main position),
// screen, counter. "groups" is the threat record's own list, so fortify's crews stay current.
#include "macros.hpp"

{SWLC_radioLines set _x} forEach [
	["alert", ["Enemy has picked %1. Expect them from the %2, get set up.", "Warning order: %1 is next, approach from the %2. Take positions.", "They're coming for %1, likely from the %2. Defenders move."]],
	["alertcounter", ["They're in %1. Reserve, hit them now.", "Break-in at %1, counterattack go.", "%1 is breached. Reserve, clear them out."]]
];
{CFG("radioCooldowns") set _x} forEach [["alert", 30], ["alertcounter", 30]];

SWLC_fnc_alertOn = { CFG("defenceEnabled") && {CFG("alertEnabled")} };

SWLC_fnc_alertStance = {
	params ["_cmd"];
	if (!isNil "SWLC_fnc_stanceOf") exitWith {[_cmd] call SWLC_fnc_stanceOf};
	_cmd getOrDefault ["stance", "attack"]
};

// Smallest angle between two bearings.
SWLC_fnc_alertAngle = {
	params ["_a", "_b"];
	abs ((((_a - _b) mod 360) + 540) mod 360 - 180)
};

// Road positions near points on a straight line out from the sector, for AT cover when there's no route to follow.
SWLC_fnc_alertRoadsOnLine = {
	params ["_c", "_bearing"];
	private _out = [];
	{
		private _p = [_c, _bearing, _x] call SWLC_fnc_offset;
		private _roads = _p nearRoads CFG("alertRoadSearch");
		if (_roads isNotEqualTo []) then {
			private _q = getPosATL (_roads # 0);
			_out pushBack [_q # 0, _q # 1, 0];
		};
	} forEach CFG("alertRoadLineMetres");
	_out
};

// [_cmd, _sector] -> [bearing from the sector towards the attacker, a point on the approach, road positions on the approach].
// The attacker is expected from the nearest enemy-owned sector by road where there's a route, otherwise in a straight line.
SWLC_fnc_alertApproach = {
	params ["_cmd", "_s"];
	private _enemy = [_cmd get "side"] call SWLC_fnc_adEnemySide;
	private _c = [_s] call SWLC_fnc_adPos;
	private _sample = CFG("alertApproachSample");
	private _list = ([_enemy] call SWLC_fnc_adOwned) - [_s];
	if (_list isEqualTo []) exitWith {
		private _b = random 360;
		[_b, [_c, _b, _sample] call SWLC_fnc_offset, []]
	};
	private _near = _list apply {[([_x] call SWLC_fnc_adPos) distance2D _c, _x]};
	_near = ([_near, [], {_x # 0}, "ASCEND"] call BIS_fnc_sortBy) select [0, CFG("alertApproachCandidates")];

	private _best = [];
	private _bestLen = 1e12;
	if (SWLC_routesReady) then {
		private _nb = [_c] call SWLC_fnc_routeNearestNode;
		if (_nb >= 0) then {
			{
				private _na = [[_x # 1] call SWLC_fnc_adPos] call SWLC_fnc_routeNearestNode;
				if (_na >= 0 && {(SWLC_routeComp # _na) == (SWLC_routeComp # _nb)}) then {
					private _path = [_na, _nb] call SWLC_fnc_routeFindPath;
					if (_path isNotEqualTo []) then {
						private _len = 0;
						for "_i" from 1 to (count _path - 1) do {
							_len = _len + ((SWLC_routeNodes # (_path # (_i - 1))) distance2D (SWLC_routeNodes # (_path # _i)));
						};
						if (_len < _bestLen) then {_bestLen = _len; _best = _path};
					};
				};
			} forEach _near;
		};
	};

	private _point = [];
	private _roads = [];
	if (_best isNotEqualTo []) then {
		// Out from the sector along the route.
		private _nodes = +_best;
		reverse _nodes;
		private _range = CFG("alertRoadRange");
		private _gap = CFG("alertRoadSpacing");
		private _last = [];
		{
			private _p = SWLC_routeNodes # _x;
			private _d = _p distance2D _c;
			if (_d <= _range && {_d > 20} && {_last isEqualTo [] || {(_p distance2D _last) >= _gap}}) then {
				_roads pushBack [_p # 0, _p # 1, 0];
				_last = _p;
			};
			if (_point isEqualTo [] && {_d >= _sample}) then {_point = [_p # 0, _p # 1, 0]};
		} forEach _nodes;
		_roads = _roads select [0, CFG("alertRoadMax")];
		// A short route never gets that far: use where it starts.
		if (_point isEqualTo [] && {(count _nodes) > 1}) then {
			private _p = SWLC_routeNodes # (_nodes # (count _nodes - 1));
			if ((_p distance2D _c) > 20) then {_point = [_p # 0, _p # 1, 0]};
		};
	};

	private _b = 0;
	if (_point isNotEqualTo []) then {
		_b = [_c, _point] call SWLC_fnc_bearing;
	} else {
		_b = [_c, [(_near # 0) # 1] call SWLC_fnc_adPos] call SWLC_fnc_bearing;
		_point = [_c, _b, _sample] call SWLC_fnc_offset;
		if (surfaceIsWater _point) then {
			private _dry = [_point, 150] call SWLC_fnc_routeDrySnap;
			_point = if (_dry isEqualTo []) then {[_c # 0, _c # 1, 0]} else {_dry};
		};
		_roads = [_c, _b] call SWLC_fnc_alertRoadsOnLine;
	};
	[((_b mod 360) + 360) mod 360, _point, _roads]
};

// [main, screen, counter] groups for this sector, from the side's stance and what the sector is worth.
SWLC_fnc_alertCounts = {
	params ["_cmd", "_s"];
	private _table = CFG("alertLayers");
	(_table getOrDefault [[_cmd] call SWLC_fnc_alertStance, _table get "attack"]) params ["_main", "_screen", "_counter", "_fraction"];
	if (([_cmd, _s] call SWLC_fnc_defSectorValue) >= CFG("alertValueHigh")) then {_main = _main + 1};
	if !(CFG("alertScreen")) then {_screen = 0};
	if !(CFG("alertCounter")) then {_counter = 0};
	private _room = (floor (({[_x] call SWLC_fnc_resMayTouch} count (_cmd get "groups")) * _fraction)) max 1;
	_main = _main min _room;
	_screen = _screen min ((_room - _main) max 0);
	_counter = _counter min ((_room - _main - _screen) max 0);
	[_main, _screen, _counter]
};

// Cover on the approach side of the sector: not the middle, and not outside the arc facing the enemy.
SWLC_fnc_alertSpots = {
	params ["_cmd", "_s", "_bearing"];
	private _side = _cmd get "side";
	private _c = [_s] call SWLC_fnc_adPos;
	private _size = [_s] call SWLC_fnc_adSize;
	private _bias = [_c, _bearing, (_size / 2) * CFG("alertCoverBias")] call SWLC_fnc_offset;
	private _arc = CFG("alertCoverArc");
	private _minDist = (_size / 2) * CFG("alertCoverMinFraction");
	private _spots = ([_s, _bias, CFG("alertCoverRadius")] call SWLC_fnc_holdCover) select {
		(_x distance2D _c) >= _minDist
		&& {[_s, _x, CFG("alertCoverOutside")] call SWLC_fnc_adInSquare}
		&& {([[_c, _x] call SWLC_fnc_bearing, _bearing] call SWLC_fnc_alertAngle) <= _arc}
		&& {!([_side, _x] call SWLC_fnc_adRestricted)}
	};
	if (_spots isEqualTo []) then {_spots = [_cmd, _s, _bearing] call SWLC_fnc_defSpots};
	_spots
};

// The first usable point out from the sector on a bearing, moving in if it's wet or inside enemy ground. [] if none.
SWLC_fnc_alertOutPoint = {
	params ["_cmd", "_s", "_bearing", "_beyond"];
	private _side = _cmd get "side";
	private _c = [_s] call SWLC_fnc_adPos;
	private _d = (([_s] call SWLC_fnc_adSize) / 2) + _beyond;
	private _out = [];
	for "_i" from 0 to 3 do {
		private _try = [_c, _bearing, _d] call SWLC_fnc_offset;
		if (!surfaceIsWater _try && {!([_side, _try, 50] call SWLC_fnc_adRestricted)}) exitWith {_out = _try};
		_d = _d * 0.75;
	};
	_out
};

// The screen stands a few hundred metres out on the approach, at cover if there's any close by.
SWLC_fnc_alertScreenSpot = {
	params ["_cmd", "_s", "_bearing"];
	private _p = [_cmd, _s, _bearing, CFG("alertScreenBeyond")] call SWLC_fnc_alertOutPoint;
	if (_p isEqualTo []) exitWith {[]};
	private _spots = ([_s, _p, CFG("alertScreenCover")] call SWLC_fnc_holdCover) select {!([_cmd get "side", _x, 50] call SWLC_fnc_adRestricted)};
	if (_spots isEqualTo []) exitWith {_p};
	_spots # 0
};

// The counterattack reserve waits behind the sector, out of the way of the first contact.
SWLC_fnc_alertCounterPost = {
	params ["_cmd", "_s", "_bearing"];
	private _p = [_cmd, _s, _bearing + 180, CFG("alertCounterBack")] call SWLC_fnc_alertOutPoint;
	if (_p isEqualTo []) exitWith {
		private _spots = [_cmd, _s, _bearing + 180] call SWLC_fnc_defSpots;
		_spots # 0
	};
	_p
};

// The threat record the rest of the defence works from. Kept alive for as long as the alert lasts.
SWLC_fnc_alertThreat = {
	params ["_cmd", "_rec"];
	private _s = _rec get "sector";
	private _name = [_s] call SWLC_fnc_adName;
	private _threats = _cmd get "threats";
	private _t = _threats getOrDefault [_name, createHashMap];
	(_rec get "approach") params ["_bearing"];
	if (count _t == 0) then {
		_t = createHashMapFromArray [["sector", _s], ["first", time], ["groups", []], ["slot", 0], ["requestedUntil", -1], ["alertOnly", true], ["strength", CFG("defenceMinInfantry")], ["bearing", _bearing]];
		_t set ["spots", [_cmd, _s, _bearing] call SWLC_fnc_alertSpots];
		_threats set [_name, _t];
	};
	_t set ["last", time];
	_t set ["alertNeed", (_rec get "counts") # 0];
	_t
};

SWLC_fnc_alertStart = {
	params ["_cmd", "_s"];
	private _side = _cmd get "side";
	private _name = [_s] call SWLC_fnc_adName;
	private _approach = [_cmd, _s] call SWLC_fnc_alertApproach;
	_approach params ["_bearing", "_point", "_roads"];
	private _counts = [_cmd, _s] call SWLC_fnc_alertCounts;
	private _rec = createHashMapFromArray [
		["sector", _s], ["since", time], ["approach", _approach], ["groups", []], ["screen", []], ["counter", []], ["counts", _counts], ["hit", false], ["seen", []], ["screenSent", 0],
		["screenSpot", [_cmd, _s, _bearing] call SWLC_fnc_alertScreenSpot], ["counterPost", [_cmd, _s, _bearing] call SWLC_fnc_alertCounterPost]
	];
	_cmd set ["alert", _rec];
	private _t = [_cmd, _rec] call SWLC_fnc_alertThreat;
	if !(_t getOrDefault ["alertOnly", false]) then {_t set ["spots", [_cmd, _s, _bearing] call SWLC_fnc_alertSpots]};
	["C_ALERT", [["side", _side], ["event", "start"], ["sector", _name], ["stance", [_cmd] call SWLC_fnc_alertStance], ["value", round ([_cmd, _s] call SWLC_fnc_defSectorValue)],
		["bearing", round _bearing], ["px", round (_point # 0)], ["py", round (_point # 1)], ["roads", count _roads], ["main", _counts # 0], ["screen", _counts # 1], ["counter", _counts # 2]]] call SWLC_fnc_log;
	[_side, "alert", [_name, [_bearing] call SWLC_fnc_defCompass]] call SWLC_fnc_radio;
};

SWLC_fnc_alertUnwatch = {
	params ["_g"];
	{_x doWatch objNull} forEach (units _g);
};

// The enemy changed its mind or the sector changed hands. Screen and counter groups were placed here, so they're released here.
// A threat record that only exists because of the warning goes at once; one with a real enemy on it stands down on its own timer.
SWLC_fnc_alertClear = {
	params ["_cmd", "_rec", "_why"];
	private _s = _rec get "sector";
	private _name = [_s] call SWLC_fnc_adName;
	private _release = {
		params ["_g", "_reason"];
		[_g] call SWLC_fnc_alertUnwatch;
		_g setVariable ["SWLC_alertRole", nil];
		_g setVariable ["SWLC_counterFor", nil];
		if ((_g getVariable ["SWLC_lambsTask", ""]) != "") then {[_g, false] call SWLC_fnc_lambsRelease};
		[_g] call SWLC_fnc_adClearOrder;
		[_g, "Unassigned", [], _reason] call SWLC_fnc_setState;
	};
	{
		[_cmd, _x, "alertRelease", {
			if (([_x] call SWLC_fnc_state) == "Defending") then {[_x, "alert_over"] call _release};
		}] call SWLC_fnc_resGuarded;
	} forEach (_rec get "screen");
	{
		[_cmd, _x, "alertRelease", {
			if (([_x] call SWLC_fnc_state) == "Reserve") then {
				[_x, "alert_over"] call _release;
			} else {
				_x setVariable ["SWLC_alertRole", nil];
				_x setVariable ["SWLC_counterFor", nil];
			};
		}] call SWLC_fnc_resGuarded;
	} forEach (_rec get "counter");

	private _t = (_cmd get "threats") getOrDefault [_name, createHashMap];
	if (count _t > 0) then {
		{
			_x setVariable ["SWLC_alertCover", nil];
			[_x] call SWLC_fnc_alertUnwatch;
		} forEach (_t get "groups");
		_t deleteAt "alertNeed";
		if (_t getOrDefault ["alertOnly", false]) then {
			[_cmd, _name, _t, "alert_off"] call SWLC_fnc_defStandDown;
		};
	};
	["C_ALERT", [["side", _cmd get "side"], ["event", "clear"], ["sector", _name], ["why", _why], ["duration", round (time - (_rec get "since"))]]] call SWLC_fnc_log;
	_cmd deleteAt "alert";
};

// Before defenceTick: start, clear and keep the threat record current.
SWLC_fnc_alertTick = {
	params ["_cmd"];
	if !([] call SWLC_fnc_alertOn) exitWith {};
	private _side = _cmd get "side";
	private _target = [[_side] call SWLC_fnc_adEnemySide] call SWLC_fnc_adTarget;
	private _rec = _cmd getOrDefault ["alert", createHashMap];
	if (count _rec > 0) then {
		private _s = _rec get "sector";
		private _why = "";
		if (([_s] call SWLC_fnc_adOwner) != _side) then {_why = "owner_changed"};
		if (_why == "" && {_target isNotEqualTo _s}) then {_why = "target_changed"};
		if (_why != "") then {
			[_cmd, _rec, _why] call SWLC_fnc_alertClear;
			_rec = createHashMap;
		};
	};
	if (count _rec > 0) exitWith {
		private _s = _rec get "sector";
		_rec set ["counts", [_cmd, _s] call SWLC_fnc_alertCounts];
		[_cmd, _rec] call SWLC_fnc_alertThreat;
	};
	if (!isNull _target && {([_target] call SWLC_fnc_adOwner) == _side}) then {[_cmd, _target] call SWLC_fnc_alertStart};
};

// Groups for the screen and the counter, best first, in defRespond's order: a picket already there, the reserve, then free
// groups and a muster at this sector, then the attack only if the side isn't attacking. Never a group in a fight.
SWLC_fnc_alertPool = {
	params ["_cmd", "_s", "_foot", "_small"];
	private _c = [_s] call SWLC_fnc_adPos;
	private _stance = [_cmd] call SWLC_fnc_alertStance;
	private _muster = (_cmd get "musters") getOrDefault [[_s] call SWLC_fnc_adName, createHashMap];
	private _staged = if (count _muster > 0) then {(_muster get "groups") + (_muster get "batch")} else {[]};
	// Saving the holdouts comes first: only the reserve, unless the fighting is here.
	private _reserveOnly = ([_cmd] call SWLC_fnc_holdPriority) && {!([_s] call SWLC_fnc_frontFighting)};
	private _scored = [];
	{
		private _g = _x;
		private _state = [_g] call SWLC_fnc_state;
		private _rank = -1;
		if (_state == "Picket" && {(_g getVariable ["SWLC_picketSector", objNull]) isEqualTo _s}) then {_rank = 0};
		if (_rank < 0 && {_state == "Reserve"}) then {_rank = 1};
		if (_rank < 0 && {!_reserveOnly}) then {
			if (_state == "Unassigned") then {_rank = 2};
			if (_rank < 0 && {_g in _staged} && {_state in ["Mustering", "Travelling"]}) then {_rank = 3};
			if (_rank < 0 && {_stance != "attack"} && {_state in ["Mustering", "Travelling", "Waiting", "Advancing"]} && {(behaviour leader _g) != "COMBAT"}) then {_rank = 4};
		};
		if (_rank >= 0) then {
			private _score = _rank * 1e6 + (leader _g distance2D _c);
			if (_small) then {_score = _score + ([_g] call SWLC_fnc_groupMen) * 150};
			_scored pushBack [_score, _g];
		};
	} forEach ((_cmd get "groups") select {
		[_x] call SWLC_fnc_resMayTouch
		&& {!([_x] call SWLC_fnc_groupFighting)}
		&& {(_x getVariable ["SWLC_lambsTask", ""]) == ""}
		&& {(_x getVariable ["SWLC_alertRole", ""]) == ""}
		&& {!_foot || {vehicle leader _x == leader _x}}
	});
	([_scored, [], {_x # 0}, "ASCEND"] call BIS_fnc_sortBy) apply {_x # 1}
};

SWLC_fnc_alertScreenAssign = {
	params ["_cmd", "_rec", "_g"];
	private _s = _rec get "sector";
	private _spot = _rec get "screenSpot";
	(_rec get "approach") params ["_bearing"];
	private _from = [_g] call SWLC_fnc_state;
	[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
	_g setVariable ["SWLC_picketSector", nil];
	_g setVariable ["SWLC_alertRole", "screen"];
	[_g, "Defending", _spot, "alert_screen"] call SWLC_fnc_setState;
	_g setVariable ["SWLC_patrolAt", time];
	[_g, [[_spot, "MOVE", 15]], "AWARE", "NORMAL", "WEDGE", "YELLOW"] call SWLC_fnc_adSetOrder;
	[_g, _s, _spot, _bearing + 180] call SWLC_fnc_defMoveTo;
	_g setVariable ["SWLC_defRetry", [_s, _spot, _bearing + 180]];
	(_rec get "screen") pushBack _g;
	_rec set ["screenSent", (_rec get "screenSent") + 1];
	["C_ALERT", [["side", _cmd get "side"], ["event", "screen"], ["sector", [_s] call SWLC_fnc_adName], ["group", groupId _g], ["men", [_g] call SWLC_fnc_groupMen], ["from", _from], ["x", round (_spot # 0)], ["y", round (_spot # 1)]]] call SWLC_fnc_log;
};

// Held in the state Reserve, so everything that reads the reserve still sees it; defReserveTick leaves these groups alone.
SWLC_fnc_alertCounterAssign = {
	params ["_cmd", "_rec", "_g"];
	private _s = _rec get "sector";
	private _post = _rec get "counterPost";
	(_rec get "approach") params ["_bearing"];
	private _from = [_g] call SWLC_fnc_state;
	[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
	_g setVariable ["SWLC_picketSector", nil];
	_g setVariable ["SWLC_alertRole", "counter"];
	_g setVariable ["SWLC_counterFor", _s];
	[_g, "Reserve", _post, "alert_counter"] call SWLC_fnc_setState;
	_g setVariable ["SWLC_patrolAt", time];
	[_g, [[_post, "MOVE", 15]], "AWARE", "FULL", "WEDGE", "YELLOW"] call SWLC_fnc_adSetOrder;
	[_g, _s, _post, _bearing + 180] call SWLC_fnc_defMoveTo;
	(_rec get "counter") pushBack _g;
	["C_ALERT", [["side", _cmd get "side"], ["event", "counter"], ["sector", [_s] call SWLC_fnc_adName], ["group", groupId _g], ["men", [_g] call SWLC_fnc_groupMen], ["from", _from], ["x", round (_post # 0)], ["y", round (_post # 1)]]] call SWLC_fnc_log;
};

// Attackers are in the sector: the seize countdown has started, or enough men are known to be inside the square.
SWLC_fnc_alertBreakIn = {
	params ["_cmd", "_s"];
	if ([_cmd get "side", _s] call SWLC_fnc_capBeingSeized) exitWith {"seizing"};
	private _margin = CFG("alertInsideMargin");
	private _inside = 0;
	{
		if ([_s, _x get "pos", _margin] call SWLC_fnc_adInSquare) then {_inside = _inside + (_x get "count")};
	} forEach ([_cmd] call SWLC_fnc_defRecent);
	if (_inside >= CFG("alertBreakInMen")) exitWith {"inside"};
	""
};

// The reserve goes in at once, as a search and destroy on the sector. From here the threat record owns these groups.
SWLC_fnc_alertCounterHit = {
	params ["_cmd", "_rec", "_t", "_why"];
	private _side = _cmd get "side";
	private _s = _rec get "sector";
	private _name = [_s] call SWLC_fnc_adName;
	private _c = [_s] call SWLC_fnc_adPos;
	(_rec get "approach") params ["_bearing"];
	private _sent = [];
	{
		private _g = _x;
		[_cmd, _g, "alertHit", {
			if (([_g] call SWLC_fnc_state) == "Reserve") then {
				_g setVariable ["SWLC_counterFor", nil];
				_g setVariable ["SWLC_alertRole", nil];
				[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
				[_g, "Defending", _c, "alert_counter_hit"] call SWLC_fnc_setState;
				_g setVariable ["SWLC_patrolAt", time];
				_g setVariable ["SWLC_alertHitUntil", time + CFG("alertCounterHitSeconds")];
				[_g, [[_c, "SAD", 60]], "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
				[_g, _s, _c, _bearing + 180] call SWLC_fnc_defMoveTo;
				_g setVariable ["SWLC_defRetry", [_s, _c, _bearing + 180]];
				(_t get "groups") pushBackUnique _g;
				_sent pushBack _g;
				["C_ALERT", [["side", _side], ["event", "counter_hit"], ["sector", _name], ["group", groupId _g], ["why", _why], ["after", round (time - (_rec get "since"))], ["dist", round (leader _g distance2D _c)]]] call SWLC_fnc_log;
			};
		}] call SWLC_fnc_resGuarded;
	} forEach (_rec get "counter");
	_rec set ["hit", true];
	_rec set ["counter", (_rec get "counter") - _sent];
	if (_sent isNotEqualTo []) then {
		_t set ["alertOnly", false];
		[_side, "alertcounter", [_name], _sent # 0] call SWLC_fnc_radio;
	};
};

// Faces the group up the approach once it's at its spot. LAMBS has its own ideas once it's garrisoned, and a fight overrides it.
SWLC_fnc_alertFace = {
	params ["_g", "_bearing", "_point"];
	if ((_g getVariable ["SWLC_lambsTask", ""]) != "" || {time < (_g getVariable ["SWLC_alertFaceAt", 0])} || {[_g] call SWLC_fnc_groupFighting}) exitWith {};
	private _goal = _g getVariable ["SWLC_goal", []];
	if (_goal isEqualTo [] || {(leader _g distance2D _goal) > CFG("lambsHoldReach")}) exitWith {};
	_g setVariable ["SWLC_alertFaceAt", time + CFG("alertFaceSeconds")];
	_g setFormDir _bearing;
	// AT men on the road are watching the road.
	{_x doWatch _point} forEach ((units _g) select {alive _x && {isNull objectParent _x} && {(_x getVariable ["SWLC_fortAT", []]) isEqualTo []}});
};

// After defenceTick, so the main position has had first pick of the groups.
SWLC_fnc_alertLayers = {
	params ["_cmd"];
	if !([] call SWLC_fnc_alertOn) exitWith {};
	private _rec = _cmd getOrDefault ["alert", createHashMap];
	if (count _rec == 0) exitWith {};
	private _s = _rec get "sector";
	private _name = [_s] call SWLC_fnc_adName;
	private _t = (_cmd get "threats") getOrDefault [_name, createHashMap];
	if (count _t == 0) exitWith {};
	private _side = _cmd get "side";
	(_rec get "approach") params ["_bearing", "_point"];
	(_rec get "counts") params ["_wantMain", "_wantScreen", "_wantCounter"];

	_rec set ["groups", _t get "groups"];
	private _prune = {
		params ["_key", "_keep"];
		private _old = _rec get _key;
		private _new = _old select _keep;
		{
			_x setVariable ["SWLC_alertRole", nil];
			_x setVariable ["SWLC_counterFor", nil];
		} forEach (_old - _new);
		_rec set [_key, _new];
	};
	["screen", {([_x] call SWLC_fnc_groupMen) > 0 && {([_x] call SWLC_fnc_state) == "Defending"}}] call _prune;
	["counter", {([_x] call SWLC_fnc_groupMen) > 0 && {([_x] call SWLC_fnc_state) in ["Reserve", "Engaged"]}}] call _prune;

	// Main position: log each group once, tell LAMBS where the group's cover is, and face it up the approach.
	private _seen = _rec get "seen";
	{
		private _g = _x;
		if !(_g in _seen) then {
			_seen pushBack _g;
			["C_ALERT", [["side", _side], ["event", "main"], ["sector", _name], ["group", groupId _g], ["men", [_g] call SWLC_fnc_groupMen]]] call SWLC_fnc_log;
		};
		[_cmd, _g, "alertMain", {
			private _goal = _g getVariable ["SWLC_goal", []];
			if (_goal isNotEqualTo []) then {_g setVariable ["SWLC_alertCover", [_s, _goal]]};
			[_g, _bearing, _point] call SWLC_fnc_alertFace;
		}] call SWLC_fnc_resGuarded;
	} forEach (_rec get "groups");

	// Screen.
	if ((_rec get "screenSent") < _wantScreen && {(_rec get "screenSpot") isNotEqualTo []}) then {
		private _pool = [_cmd, _s, true, true] call SWLC_fnc_alertPool;
		{
			if ((_rec get "screenSent") >= _wantScreen) exitWith {};
			[_cmd, _x, "alertScreen", {[_cmd, _rec, _x] call SWLC_fnc_alertScreenAssign}] call SWLC_fnc_resGuarded;
		} forEach _pool;
	};
	{
		private _g = _x;
		[_cmd, _g, "alertFace", {[_g, _bearing, _point] call SWLC_fnc_alertFace}] call SWLC_fnc_resGuarded;
	} forEach (_rec get "screen");

	// Counterattack reserve.
	if (!(_rec get "hit") && {(count (_rec get "counter")) < _wantCounter} && {(_rec get "counterPost") isNotEqualTo []}) then {
		private _pool = [_cmd, _s, false, false] call SWLC_fnc_alertPool;
		{
			if ((count (_rec get "counter")) >= _wantCounter) exitWith {};
			[_cmd, _x, "alertCounter", {[_cmd, _rec, _x] call SWLC_fnc_alertCounterAssign}] call SWLC_fnc_resGuarded;
		} forEach _pool;
	};

	// A waiting group moves now and then, or Warlords treats its leader as stuck.
	{
		private _g = _x;
		[_cmd, _g, "alertCounterShuffle", {
			private _since = time - (_g getVariable ["SWLC_patrolAt", -1e6]);
			if (([_g] call SWLC_fnc_state) == "Reserve" && {_since >= CFG("reservePatrolSeconds")} && {([_g] call SWLC_fnc_adOrderDone) || {_since >= 2 * CFG("reservePatrolSeconds")}}) then {
				_g setVariable ["SWLC_patrolAt", time];
				private _goal = _g getVariable ["SWLC_goal", []];
				if (_goal isNotEqualTo []) then {
					[_g, [[[_goal, _g] call SWLC_fnc_shuffleSpot, "MOVE", 8]], "AWARE", "NORMAL", "WEDGE", "YELLOW"] call SWLC_fnc_adSetOrder;
				};
			};
		}] call SWLC_fnc_resGuarded;
	} forEach (_rec get "counter");

	if (!(_rec get "hit") && {(_rec get "counter") isNotEqualTo []}) then {
		private _why = [_cmd, _s] call SWLC_fnc_alertBreakIn;
		if (_why != "") then {[_cmd, _rec, _t, _why] call SWLC_fnc_alertCounterHit};
	};
};
