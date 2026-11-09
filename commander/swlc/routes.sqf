// Route network and destination checks.
// Every order passes through routePlan (adapter.sqf calls it): destinations are snapped to open ground, land moves
// across water are refused or become fast travel, and long moves are broken into short hops along roads and tracks.
// SWLC_order stays what the caller asked for; the hops and snapped points live in SWLC_orderLegs, which is what the
// engine gets and what the guard compares against.
#include "macros.hpp"

SWLC_routeNodes = [];        // [x, y, 0] per node
SWLC_routeAdj = [];          // [[neighbour, metres], ...] per node
SWLC_routeComp = [];         // connected component per node: two sectors in different ones are not joined by road
SWLC_routeGrid = createHashMap;
SWLC_routeCellSize = 300;
SWLC_routesReady = false;
SWLC_routeCaches = createHashMapFromArray [["safe", createHashMap], ["land", createHashMap], ["near", createHashMap], ["path", createHashMap]];

SWLC_routeBlockTypes = ["BUILDING", "HOUSE", "CHURCH", "CHAPEL", "BUNKER", "FORTRESS", "VIEW-TOWER", "LIGHTHOUSE", "FUELSTATION", "HOSPITAL", "RUIN", "TOURISM", "WATERTOWER", "TRANSMITTER", "STACK", "SHIPWRECK", "ROCK", "ROCKS"];

// Stores one cache entry; a full cache is emptied rather than trimmed.
SWLC_fnc_routeCacheSet = {
	params ["_name", "_key", "_value"];
	private _cache = SWLC_routeCaches get _name;
	if (count _cache >= CFG("routeCacheMax")) then {
		_cache = createHashMap;
		SWLC_routeCaches set [_name, _cache];
	};
	_cache set [_key, _value];
};

// ------------------------------------------------------------------ ground checks

// A bridge deck counts as dry: surfaceIsWater looks only at what's underneath it.
SWLC_fnc_routeWet = {
	params ["_p"];
	(surfaceIsWater _p) && {!(isOnRoad _p)}
};

// True if every sample on the straight line is dry.
SWLC_fnc_routeStraightLand = {
	params ["_a", "_b"];
	private _n = ceil ((_a distance2D _b) / CFG("routeWaterSample"));
	private _dry = true;
	for "_i" from 0 to _n do {
		private _f = if (_n == 0) then {0} else {_i / _n};
		private _p = [(_a # 0) + ((_b # 0) - (_a # 0)) * _f, (_a # 1) + ((_b # 1) - (_a # 1)) * _f, 0];
		if ([_p] call SWLC_fnc_routeWet) exitWith {_dry = false};
	};
	_dry
};

// The point itself if dry, otherwise the nearest dry point within _radius, otherwise [].
SWLC_fnc_routeDrySnap = {
	params ["_p", "_radius"];
	private _c = [_p # 0, _p # 1, 0];
	if !([_c] call SWLC_fnc_routeWet) exitWith {_c};
	private _found = [];
	private _r = 10;
	while {_found isEqualTo [] && {_r <= _radius}} do {
		for "_i" from 0 to 11 do {
			private _q = [_c, _i * 30, _r] call SWLC_fnc_offset;
			if !([_q] call SWLC_fnc_routeWet) exitWith {_found = _q};
		};
		_r = _r + 10;
	};
	_found
};

// Network nodes within _r metres, nearest first.
SWLC_fnc_routeNodesNear = {
	params ["_p", "_r"];
	private _cell = SWLC_routeCellSize;
	private _cx = floor ((_p # 0) / _cell);
	private _cy = floor ((_p # 1) / _cell);
	private _ring = ceil (_r / _cell);
	private _found = [];
	for "_i" from (_cx - _ring) to (_cx + _ring) do {
		for "_j" from (_cy - _ring) to (_cy + _ring) do {
			{
				private _d = (SWLC_routeNodes # _x) distance2D _p;
				if (_d <= _r) then {_found pushBack [_d, _x]};
			} forEach (SWLC_routeGrid getOrDefault [format ["%1:%2", _i, _j], []]);
		};
	};
	_found sort true;
	_found apply {_x # 1}
};

// The nearest node with a dry straight line from _p, or -1.
SWLC_fnc_routeNearestNode = {
	params ["_p"];
	private _key = format ["%1:%2", round ((_p # 0) / 25), round ((_p # 1) / 25)];
	private _hit = (SWLC_routeCaches get "near") get _key;
	if (!isNil "_hit") exitWith {_hit};
	private _res = -1;
	private _c = [_p # 0, _p # 1, 0];
	{
		if ([_c, SWLC_routeNodes # _x] call SWLC_fnc_routeStraightLand) exitWith {_res = _x};
	} forEach (([_c, CFG("routeAttachMetres")] call SWLC_fnc_routeNodesNear) select [0, 8]);
	["near", _key, _res] call SWLC_fnc_routeCacheSet;
	_res
};

// Open ground: dry, not a cliff, not inside a rock or building, and not on an islet cut off from the roads around it.
SWLC_fnc_routeSpotGood = {
	params ["_p"];
	if ([_p] call SWLC_fnc_routeWet) exitWith {false};
	if (((surfaceNormal _p) # 2) < cos CFG("routeSafeMaxSlopeDeg")) exitWith {false};
	private _hits = nearestTerrainObjects [_p, SWLC_routeBlockTypes, 25, false, true];
	_hits append (nearestObjects [_p, ["House"], 25]);
	private _margin = CFG("routeSafeMargin");
	private _inside = false;
	{
		private _bb = boundingBoxReal _x;
		private _m = _x worldToModel _p;
		if ((_m # 0) > ((_bb # 0 # 0) - _margin) && {(_m # 0) < ((_bb # 1 # 0) + _margin)} && {(_m # 1) > ((_bb # 0 # 1) - _margin)} && {(_m # 1) < ((_bb # 1 # 1) + _margin)}) exitWith {_inside = true};
	} forEach _hits;
	if (_inside) exitWith {false};
	if (SWLC_routesReady && {([_p] call SWLC_fnc_routeNearestNode) < 0} && {([_p, CFG("routeAttachMetres")] call SWLC_fnc_routeNodesNear) isNotEqualTo []}) exitWith {false};
	true
};

// [_pos, _radius] -> the nearest open, reachable ground, or [] if there is none within _radius. Cached by position.
SWLC_fnc_routeSafePos = {
	params ["_pos", ["_radius", CFG("routeSafeSearchMetres")]];
	private _key = format ["%1:%2:%3", round ((_pos # 0) / 5), round ((_pos # 1) / 5), round _radius];
	private _hit = (SWLC_routeCaches get "safe") get _key;
	if (!isNil "_hit") exitWith {_hit};
	private _centre = [_pos # 0, _pos # 1, 0];
	private _found = [];
	if ([_centre] call SWLC_fnc_routeSpotGood) then {
		_found = _centre;
	} else {
		private _step = (_radius / 8) max CFG("routeSafeStep");
		private _r = _step;
		while {_found isEqualTo [] && {_r <= _radius}} do {
			for "_i" from 0 to 11 do {
				private _c = [_centre, _i * 30, _r] call SWLC_fnc_offset;
				if ([_c] call SWLC_fnc_routeSpotGood) exitWith {_found = _c};
			};
			_r = _r + _step;
		};
	};
	["safe", _key, _found] call SWLC_fnc_routeCacheSet;
	_found
};

// True if a land unit can get from _from to _to: same road or track component, or an all-land straight line.
// Without the network, only the straight line counts.
// A fast travel moved the group after its order was set: plan the rest of the way from where it landed, or it
// walks back to the first hop of the route it had.
SWLC_fnc_routeAfterHop = {
	params ["_g"];
	if !(CFG("resilience")) exitWith {};
	_g setVariable ["SWLC_orderLegsOf", []];
	[_g, 0] call SWLC_fnc_adApplyOrder;
};

SWLC_fnc_routeLandReachable = {
	params ["_from", "_to"];
	private _key = format ["%1:%2:%3:%4", round ((_from # 0) / 25), round ((_from # 1) / 25), round ((_to # 0) / 25), round ((_to # 1) / 25)];
	private _hit = (SWLC_routeCaches get "land") get _key;
	if (!isNil "_hit") exitWith {_hit};
	private _snap = CFG("routeOriginSnapMetres");
	private _a = [_from, _snap] call SWLC_fnc_routeDrySnap;
	private _b = [_to, _snap] call SWLC_fnc_routeDrySnap;
	private _reach = false;
	if (_a isNotEqualTo [] && {_b isNotEqualTo []}) then {
		if (SWLC_routesReady) then {
			private _na = [_a] call SWLC_fnc_routeNearestNode;
			private _nb = [_b] call SWLC_fnc_routeNearestNode;
			if (_na >= 0 && {_nb >= 0} && {(SWLC_routeComp # _na) == (SWLC_routeComp # _nb)}) then {_reach = true};
		};
		if (!_reach) then {_reach = [_a, _b] call SWLC_fnc_routeStraightLand};
	};
	["land", _key, _reach] call SWLC_fnc_routeCacheSet;
	_reach
};

// ------------------------------------------------------------------ path finding

// A* over the network. Returns node indices from _a to _b, or [] if there is no path within the expansion limit.
// _avoid: hashmap of nodes that cost routeAvoidPenalty times as much to enter; those searches are not cached.
SWLC_fnc_routeFindPath = {
	params ["_a", "_b", ["_avoid", createHashMap]];
	if (_a == _b) exitWith {[_a]};
	private _plain = count _avoid == 0;
	private _key = format ["%1:%2", _a, _b];
	private "_hit";
	if (_plain) then {_hit = (SWLC_routeCaches get "path") get _key};
	if (!isNil "_hit") exitWith {_hit};
	private _goal = SWLC_routeNodes # _b;
	private _penalty = CFG("routeAvoidPenalty");
	private _max = CFG("routeMaxExpansions");
	private _cost = createHashMapFromArray [[_a, 0]];
	private _came = createHashMap;
	private _closed = createHashMap;
	// The open list is a row of buckets by estimated total length, which saves scanning it for the best node on every
	// step. These searches run inside a commander slice. The route may be up to one bucket longer than the best one.
	private _bucketSize = CFG("routeHopMetres");
	private _cursor = floor (((SWLC_routeNodes # _a) distance2D _goal) / _bucketSize);
	private _buckets = createHashMapFromArray [[_cursor, [_a]]];
	private _pending = 1;
	private _expanded = 0;
	private _found = false;
	while {_pending > 0 && {!_found} && {_expanded < _max}} do {
		private _list = _buckets getOrDefault [_cursor, []];
		if (_list isEqualTo []) then {
			_cursor = _cursor + 1;
		} else {
			private _cur = _list deleteAt (count _list - 1);
			_pending = _pending - 1;
			if (_cur == _b) then {
				_found = true;
			} else {
				if !(_cur in _closed) then {
					_closed set [_cur, true];
					_expanded = _expanded + 1;
					private _gc = _cost get _cur;
					{
						_x params ["_n", "_len"];
						if !(_n in _closed) then {
							private _t = _gc + _len * ([1, _penalty] select (_n in _avoid));
							if (_t < (_cost getOrDefault [_n, 1e12])) then {
								_cost set [_n, _t];
								_came set [_n, _cur];
								private _k = floor ((_t + ((SWLC_routeNodes # _n) distance2D _goal)) / _bucketSize);
								private _into = _buckets getOrDefault [_k, []];
								_into pushBack _n;
								_buckets set [_k, _into];
								_pending = _pending + 1;
								_cursor = _cursor min _k;
							};
						};
					} forEach (SWLC_routeAdj # _cur);
				};
			};
		};
	};
	private _path = [];
	if (_found) then {
		private _n = _b;
		_path pushBack _n;
		while {_n != _a} do {
			_n = _came get _n;
			_path pushBack _n;
		};
		reverse _path;
	};
	if (_plain) then {["path", _key, _path] call SWLC_fnc_routeCacheSet};
	_path
};

// Hop positions for a long move, excluding _to. [] means the move stays direct.
SWLC_fnc_routeHops = {
	params ["_from", "_to", ["_avoid", createHashMap], ["_force", false]];
	if !(SWLC_routesReady) exitWith {[]};
	private _na = [_from] call SWLC_fnc_routeNearestNode;
	private _nb = [_to] call SWLC_fnc_routeNearestNode;
	if (_na < 0 || {_nb < 0} || {(SWLC_routeComp # _na) != (SWLC_routeComp # _nb)}) exitWith {[]};
	private _path = [_na, _nb, _avoid] call SWLC_fnc_routeFindPath;
	if (_path isEqualTo []) exitWith {[]};
	private _pts = _path apply {SWLC_routeNodes # _x};

	// Nodes behind the group or past the destination would mean walking back.
	while {count _pts >= 2 && {(_from distance2D (_pts # 1)) < ((_pts # 0) distance2D (_pts # 1))}} do {_pts deleteAt 0};
	while {count _pts >= 2 && {(_to distance2D (_pts # (count _pts - 2))) < ((_pts # (count _pts - 1)) distance2D (_pts # (count _pts - 2)))}} do {_pts deleteAt (count _pts - 1)};

	// A road far longer than the straight line isn't worth following when the straight line is open ground.
	private _length = (_from distance2D (_pts # 0)) + ((_pts # (count _pts - 1)) distance2D _to);
	for "_i" from 0 to (count _pts - 2) do {_length = _length + ((_pts # _i) distance2D (_pts # (_i + 1)))};
	if (!_force && {_length > CFG("routeMaxDetour") * (_from distance2D _to)} && {[_from, _to] call SWLC_fnc_routeStraightLand}) exitWith {[]};

	private _spacing = CFG("routeHopMetres") * 0.7;
	private _hops = [];
	private _last = _from;
	{
		if ((_last distance2D _x) >= _spacing) then {
			_hops pushBack _x;
			_last = _x;
		};
	} forEach _pts;
	if (_hops isNotEqualTo [] && {((_hops # (count _hops - 1)) distance2D _to) < _spacing * 0.7}) then {_hops deleteAt (count _hops - 1)};
	_hops
};

// ------------------------------------------------------------------ orders

// Fast travel towards a destination the group can't walk to: the owned sector nearest it with a land route to it.
SWLC_fnc_routeFastTravel = {
	params ["_g", "_dest"];
	private _side = side _g;
	if (isNull leader _g) exitWith {false};
	private _scored = (([_side] call SWLC_fnc_adOwned) select {[_side, _x] call SWLC_fnc_adCanFTTo}) apply {[([_x] call SWLC_fnc_adPos) distance2D _dest, _x]};
	_scored sort true;
	private _sector = objNull;
	{
		if ((_x # 0) < CFG("routeFTNearMetres") || {[[_x # 1] call SWLC_fnc_adPos, _dest] call SWLC_fnc_routeLandReachable}) exitWith {_sector = _x # 1};
	} forEach (_scored select [0, 8]);
	if (isNull _sector) exitWith {false};
	private _sp = [_sector] call SWLC_fnc_adPos;
	private _land = [_sp, [_sp, _dest] call SWLC_fnc_bearing, 40 + random 30] call SWLC_fnc_offset;
	private _safe = [_land, 60] call SWLC_fnc_routeSafePos;
	if (_safe isEqualTo []) then {_safe = _sp};
	private _moved = [_g, _sector, _safe] call SWLC_fnc_adFastTravel;
	if (_moved) then {
		["C_ROUTE", [["action", "water_ft"], ["group", groupId _g], ["side", _side], ["sector", [_sector] call SWLC_fnc_adName]]] call SWLC_fnc_log;
	};
	_moved
};

// The engine's waypoints for the group's order: the hops of a routed move, or the order itself.
// A stale record, from something writing SWLC_order directly, means the order as written.
SWLC_fnc_adLegs = {
	params ["_g", "_order"];
	if ((_g getVariable ["SWLC_orderLegsOf", []]) isNotEqualTo (_order # 0)) exitWith {_order # 0};
	_g getVariable ["SWLC_orderLegs", _order # 0]
};

// Works out the group's legs from where it stands. Called for each new order and whenever an order has to be rebuilt.
SWLC_fnc_routePlan = {
	params ["_g", ["_ftTried", false]];
	private _order = _g getVariable ["SWLC_order", []];
	if (_order isEqualTo []) exitWith {};
	private _wps = _order # 0;
	private _leader = leader _g;
	private _veh = vehicle _leader;
	// A LAMBS garrison's waypoint is inside a building on purpose.
	private _exempt = isNull _leader || {!CFG("resilience")} || {([_g] call SWLC_fnc_adGroupHasPlayer)} || {([_g] call SWLC_fnc_state) in ["Borrowed", "Pickup"]}
		|| {(_g getVariable ["SWLC_lambsTask", ""]) != ""} || {_veh isKindOf "Air"} || {_veh isKindOf "Ship"};
	if (_exempt) exitWith {
		_g setVariable ["SWLC_orderLegs", _wps];
		_g setVariable ["SWLC_orderLegsOf", _wps];
		_g setVariable ["SWLC_orderBlocked", false];
	};

	private _validate = CFG("validateDestinations");
	private _noWater = CFG("noWaterMoves");
	private _network = CFG("routeNetwork");
	private _long = CFG("routeMinMetres");
	private _here = getPosATL _leader;
	private _prev = [_here # 0, _here # 1, 0];

	private _avoid = createHashMap;
	private _force = false;
	private _avoidRec = _g getVariable ["SWLC_routeAvoid", []];
	if (_avoidRec isNotEqualTo [] && {time < (_avoidRec # 1)}) then {
		_avoid = createHashMapFromArray ((_avoidRec # 0) apply {[_x, true]});
		_force = _avoidRec # 2;
	};

	private _legs = [];
	private _blocked = false;
	private _blockedAt = [];
	{
		_x params ["_p", "_type", ["_radius", 0]];
		private _dest = [_p # 0, _p # 1, 0];
		// An order to stay about here is left alone, or a group holding in a building would be sent out of it.
		if (_validate && {(_leader distance2D _dest) > CFG("routeSafeSkipNearMetres")}) then {
			private _safe = [_dest, CFG("routeSafeSearchMetres")] call SWLC_fnc_routeSafePos;
			if (_safe isNotEqualTo []) then {
				_dest = _safe;
			} else {
				if (_noWater && {[_dest] call SWLC_fnc_routeWet}) then {_blocked = true};
			};
		};
		if (_blocked) exitWith {_blockedAt = _dest};
		if (_noWater && {!([_prev, _dest] call SWLC_fnc_routeLandReachable)}) exitWith {
			_blocked = true;
			_blockedAt = _dest;
		};
		if (_network && {_type == "MOVE"} && {(_prev distance2D _dest) > _long}) then {
			private _hopRadius = CFG("routeHopRadius");
			{_legs pushBack [_x, "MOVE", _hopRadius]} forEach ([_prev, _dest, _avoid, _force] call SWLC_fnc_routeHops);
		};
		_legs pushBack [_dest, _type, _radius];
		_prev = _dest;
	} forEach _wps;

	if (_blocked) exitWith {
		// Not while the network is still building: the road it can't yet see may be there, and fast travel costs CP.
		private _moved = !_ftTried && {SWLC_routesReady || {!_network}} && {[_g, _blockedAt] call SWLC_fnc_routeFastTravel};
		if (_moved) then {
			[_g, true] call SWLC_fnc_routePlan;
		} else {
			// Nowhere to go by land and no fast travel: it holds here, and the watchdog's ladder takes it from there.
			_g setVariable ["SWLC_orderLegs", [[_here, "HOLD", 20]]];
			_g setVariable ["SWLC_orderLegsOf", _wps];
			_g setVariable ["SWLC_orderBlocked", true];
			_g setVariable ["SWLC_orderRetryAt", time + CFG("routeBlockedRetrySeconds")];
			if ((time - (_g getVariable ["SWLC_orderBlockedLog", -1000])) >= 60) then {
				_g setVariable ["SWLC_orderBlockedLog", time];
				["C_ROUTE", [["action", "blocked"], ["group", groupId _g], ["side", side _g], ["x", round (_blockedAt # 0)], ["y", round (_blockedAt # 1)]]] call SWLC_fnc_log;
			};
		};
	};

	_g setVariable ["SWLC_orderLegs", _legs];
	_g setVariable ["SWLC_orderLegsOf", _wps];
	_g setVariable ["SWLC_orderBlocked", false];
	// Arrival checks measure from SWLC_goal, so when its destination was moved to open ground the goal moves too.
	private _goal = _g getVariable ["SWLC_goal", []];
	if (_goal isNotEqualTo [] && {(_goal distance2D ((_wps # (count _wps - 1)) # 0)) <= 1}) then {
		_g setVariable ["SWLC_goal", (_legs # (count _legs - 1)) # 0];
	};
	if (CFG("verboseLog") && {count _legs > count _wps}) then {
		["C_ROUTE", [["action", "plan"], ["group", groupId _g], ["side", side _g], ["hops", (count _legs) - (count _wps)]]] call SWLC_fnc_log;
	};
};

// Called as the order is written to the engine. Returns the leg to start from: a routed group resumes at the hop
// nearest it, so a repeat of the order never sends it back, and one that has been moved far off its route gets a new one.
SWLC_fnc_routeRefresh = {
	params ["_g", "_from"];
	private _order = _g getVariable ["SWLC_order", []];
	private _wasBlocked = _g getVariable ["SWLC_orderBlocked", false];
	private _fresh = (_g getVariable ["SWLC_orderLegsOf", []]) isEqualTo (_order # 0);
	if (_wasBlocked || {!_fresh}) then {[_g] call SWLC_fnc_routePlan};
	if (_wasBlocked || {_g getVariable ["SWLC_orderBlocked", false]}) exitWith {0};
	private _legs = _g getVariable ["SWLC_orderLegs", []];
	if ((count _legs) <= count (_order # 0)) exitWith {_from};
	// _from came from the legs of an order that has just been replaced, so it says nothing about these.
	if (!_fresh) then {_from = 0};
	private _here = getPosATL leader _g;
	private _start = (_from max 0) min (count _legs - 1);
	private _best = _start;
	private _bestD = 1e9;
	for "_i" from _start to (count _legs - 1) do {
		private _d = ((_legs # _i) # 0) distance2D _here;
		if (_d < _bestD) then {_bestD = _d; _best = _i};
	};
	if (_bestD > CFG("routeOffRouteMetres")) exitWith {[_g] call SWLC_fnc_routePlan; 0};
	_best
};

// Metres still to travel to the group's goal, along its route if it has one.
SWLC_fnc_routeRemaining = {
	params ["_g"];
	private _leader = leader _g;
	if (isNull _leader) exitWith {0};
	private _goal = _g getVariable ["SWLC_goal", []];
	if (_goal isEqualTo []) exitWith {0};
	private _straight = _leader distance2D _goal;
	private _order = _g getVariable ["SWLC_order", []];
	if (_order isEqualTo []) exitWith {_straight};
	private _legs = [_g, _order] call SWLC_fnc_adLegs;
	if ((count _legs) <= count (_order # 0)) exitWith {_straight};
	private _end = (_legs # (count _legs - 1)) # 0;
	if ((_end distance2D _goal) > CFG("routeGoalMatchMetres")) exitWith {_straight};
	private _i = (([_g] call SWLC_fnc_adOrderProgress) max 0) min (count _legs - 1);
	private _total = (_leader distance2D ((_legs # _i) # 0)) + (_end distance2D _goal);
	for "_k" from _i to (count _legs - 2) do {
		_total = _total + (((_legs # _k) # 0) distance2D ((_legs # (_k + 1)) # 0));
	};
	_total
};

// Makes the group's next route avoid its current one. True if a different route exists; false sends the ladder to its next rung.
SWLC_fnc_routeAlternate = {
	params ["_g", ["_reason", ""]];
	if !(SWLC_routesReady && {CFG("resilience")} && {CFG("routeNetwork")}) exitWith {false};
	private _order = _g getVariable ["SWLC_order", []];
	private _leader = leader _g;
	if (_order isEqualTo [] || {isNull _leader}) exitWith {false};
	private _wps = _order # 0;
	if ((_wps findIf {(_x # 1) == "MOVE"}) < 0) exitWith {false};
	private _here = getPosATL _leader;
	private _dest = (_wps # (count _wps - 1)) # 0;
	if ((_here distance2D _dest) <= CFG("routeMinMetres")) exitWith {false};
	private _na = [_here] call SWLC_fnc_routeNearestNode;
	private _nb = [_dest] call SWLC_fnc_routeNearestNode;
	if (_na < 0 || {_nb < 0} || {(SWLC_routeComp # _na) != (SWLC_routeComp # _nb)}) exitWith {false};

	private _legs = [_g, _order] call SWLC_fnc_adLegs;
	private _hopCount = ((count _legs) - (count _wps)) max 0;
	private _direct = _hopCount == 0;
	private _avoidNodes = [];
	{
		private _n = [_x # 0] call SWLC_fnc_routeNearestNode;
		if (_n >= 0 && {_n != _na} && {_n != _nb}) then {_avoidNodes pushBackUnique _n};
	} forEach (_legs select [0, _hopCount]);

	// A direct order's alternative is simply the road network. A routed one needs at least one node it wasn't using.
	private _path = [_na, _nb, createHashMapFromArray (_avoidNodes apply {[_x, true]})] call SWLC_fnc_routeFindPath;
	if (_path isEqualTo []) exitWith {false};
	if (!_direct && {(_path - _avoidNodes - [_na, _nb]) isEqualTo []}) exitWith {false};

	_g setVariable ["SWLC_routeAvoid", [_avoidNodes, time + CFG("routeAvoidSeconds"), _direct]];
	_g setVariable ["SWLC_orderLegsOf", []];
	["C_ROUTE", [["action", "alternate"], ["group", groupId _g], ["side", side _g], ["reason", _reason], ["avoided", count _avoidNodes], ["nodes", count _path]]] call SWLC_fnc_log;
	true
};

// ------------------------------------------------------------------ building the network

// Loads the map's stored network if there is one, otherwise generates it. Orders use the fallback until this finishes.
SWLC_fnc_routeStart = {
	scriptName "SWLC routes";
	if !(CFG("resilience") && {CFG("routeNetwork")}) exitWith {};
	private _file = format ["swlc\maps\%1_routes.sqf", worldName];
	if (fileExists _file) then {
		private _data = call compile preprocessFileLineNumbers _file;
		_data params ["_world", "", "_nodes", "_edges"];
		if (_world != worldName) exitWith {
			["C_ROUTE", [["action", "bad_file"], ["file", _file], ["world", _world]]] call SWLC_fnc_log;
		};
		[_nodes apply {[_x # 0, _x # 1, 0]}, _edges, "file"] call SWLC_fnc_routeInstall;
	} else {
		[] call SWLC_fnc_routeGenerate;
	};
};

// Takes [[x, y, 0], ...] and [[a, b], ...]. Spread over frames; the network goes live only when complete.
SWLC_fnc_routeInstall = {
	params ["_nodes", "_edges", "_source"];
	private _adj = _nodes apply {[]};
	{
		_x params ["_a", "_b"];
		private _len = (_nodes # _a) distance2D (_nodes # _b);
		(_adj # _a) pushBack [_b, _len];
		(_adj # _b) pushBack [_a, _len];
		if (_forEachIndex mod 200 == 0) then {sleep 0.01};
	} forEach _edges;

	private _comp = _nodes apply {-1};
	private _comps = 0;
	{
		if ((_comp # _forEachIndex) < 0) then {
			private _stack = [_forEachIndex];
			_comp set [_forEachIndex, _comps];
			while {_stack isNotEqualTo []} do {
				private _n = _stack deleteAt (count _stack - 1);
				{
					private _m = _x # 0;
					if ((_comp # _m) < 0) then {
						_comp set [_m, _comps];
						_stack pushBack _m;
					};
				} forEach (_adj # _n);
			};
			_comps = _comps + 1;
		};
		if (_forEachIndex mod 200 == 0) then {sleep 0.01};
	} forEach _nodes;

	private _cell = (CFG("routeAttachMetres") / 2) max 100;
	private _grid = createHashMap;
	{
		private _k = format ["%1:%2", floor ((_x # 0) / _cell), floor ((_x # 1) / _cell)];
		private _list = _grid getOrDefault [_k, []];
		_list pushBack _forEachIndex;
		_grid set [_k, _list];
		if (_forEachIndex mod 200 == 0) then {sleep 0.01};
	} forEach _nodes;

	isNil {
		SWLC_routeNodes = _nodes;
		SWLC_routeAdj = _adj;
		SWLC_routeComp = _comp;
		SWLC_routeGrid = _grid;
		SWLC_routeCellSize = _cell;
		{SWLC_routeCaches set [_x, createHashMap]} forEach (keys SWLC_routeCaches);
		SWLC_routesReady = true;
	};

	private _unconnected = 0;
	{
		private _n = [[_x] call SWLC_fnc_adPos] call SWLC_fnc_routeNearestNode;
		if (_n < 0) then {_unconnected = _unconnected + 1};
		["C_ROUTE", [["action", "sector"], ["sector", [_x] call SWLC_fnc_adName], ["node", _n], ["comp", if (_n < 0) then {-1} else {_comp # _n}]]] call SWLC_fnc_log;
	} forEach SWLC_sectors;
	["C_ROUTE", [["action", "ready"], ["source", _source], ["world", worldName], ["nodes", count _nodes], ["edges", count _edges], ["components", _comps], ["sectors_without_road", _unconnected]]] call SWLC_fnc_log;
};

// Walks the road graph out from each sector's nearest road, then thins it.
// A node is one connected piece of road inside one grid square of routeHopMetres; two roads that merely pass through
// the same square stay separate nodes, so a thinned link is always a real road link.
SWLC_fnc_routeGenerate = {
	private _started = diag_tickTime;
	private _hop = CFG("routeHopMetres");
	private _batch = CFG("routeBuildBatch");
	private _max = CFG("routeMaxSegments");
	private _gapJoin = CFG("routeGapJoinMetres");

	private _keys = createHashMap;
	private _pos = [];
	private _nbr = [];
	private _road = [];
	private _queue = [];

	private _register = {
		params ["_seg"];
		private _p = getPosWorld _seg;
		private _k = format ["%1,%2", round (_p # 0), round (_p # 1)];
		private _idx = _keys getOrDefault [_k, -1];
		if (_idx < 0 && {count _pos < _max}) then {
			_idx = count _pos;
			_keys set [_k, _idx];
			_pos pushBack [_p # 0, _p # 1, 0];
			_nbr pushBack [];
			_road pushBack _seg;
			_queue pushBack _idx;
		};
		_idx
	};

	{
		private _c = [_x] call SWLC_fnc_adPos;
		private _roads = [];
		{
			_roads = _c nearRoads _x;
			if (_roads isNotEqualTo []) exitWith {};
		} forEach [200, 500, CFG("routeSectorRoadRadius")];
		if (_roads isNotEqualTo []) then {
			private _near = _roads # 0;
			{if ((_x distance2D _c) < (_near distance2D _c)) then {_near = _x}} forEach _roads;
			[_near] call _register;
		};
		sleep 0.01;
	} forEach SWLC_sectors;

	private _qi = 0;
	while {_qi < count _queue} do {
		for "_b" from 1 to _batch do {
			if (_qi >= count _queue) exitWith {};
			private _i = _queue # _qi;
			_qi = _qi + 1;
			private _seg = _road # _i;
			private _conns = roadsConnectedTo _seg;
			// A dead end in the data is often just a break in it: join any road across the gap.
			if (count _conns <= 1) then {
				private _p = _pos # _i;
				{
					if (_x isNotEqualTo _seg && {!(_x in _conns)}) then {
						private _q = getPosWorld _x;
						if ([_p, [_q # 0, _q # 1, 0]] call SWLC_fnc_routeStraightLand) then {_conns pushBack _x};
					};
				} forEach (_p nearRoads _gapJoin);
			};
			{
				private _j = [_x] call _register;
				if (_j >= 0 && {_j != _i}) then {
					(_nbr # _i) pushBackUnique _j;
					(_nbr # _j) pushBackUnique _i;
				};
			} forEach _conns;
		};
		sleep 0.01;
	};
	if ((count _pos) >= _max) then {
		["C_ROUTE", [["action", "limit"], ["segments", count _pos]]] call SWLC_fnc_log;
	};

	// Pieces: union of segments linked inside one grid square.
	private _count = count _pos;
	private _cells = [];
	_cells resize _count;
	private _parent = [];
	_parent resize _count;
	for "_i" from 0 to (_count - 1) do {
		_parent set [_i, _i];
		_cells set [_i, format ["%1:%2", floor (((_pos # _i) # 0) / _hop), floor (((_pos # _i) # 1) / _hop)]];
		if (_i mod _batch == 0) then {sleep 0.01};
	};
	private _find = {
		params ["_k"];
		while {(_parent # _k) != _k} do {
			_parent set [_k, _parent # (_parent # _k)];
			_k = _parent # _k;
		};
		_k
	};
	for "_i" from 0 to (_count - 1) do {
		{
			if (_x > _i && {(_cells # _i) == (_cells # _x)}) then {
				private _ra = [_i] call _find;
				private _rb = [_x] call _find;
				if (_ra != _rb) then {_parent set [_ra, _rb]};
			};
		} forEach (_nbr # _i);
		if (_i mod _batch == 0) then {sleep 0.01};
	};

	private _members = createHashMap;
	for "_i" from 0 to (_count - 1) do {
		private _root = [_i] call _find;
		private _list = _members getOrDefault [_root, []];
		_list pushBack _i;
		_members set [_root, _list];
		if (_i mod _batch == 0) then {sleep 0.01};
	};

	// Each piece's node sits on its segment nearest the piece's centre.
	private _nodeOf = [];
	_nodeOf resize _count;
	private _nodes = [];
	private _done = 0;
	{
		private _list = _y;
		private _sx = 0;
		private _sy = 0;
		{
			_sx = _sx + ((_pos # _x) # 0);
			_sy = _sy + ((_pos # _x) # 1);
		} forEach _list;
		private _c = [_sx / count _list, _sy / count _list, 0];
		private _best = _list # 0;
		private _bestD = 1e12;
		{
			private _d = (_pos # _x) distance2D _c;
			if (_d < _bestD) then {_bestD = _d; _best = _x};
		} forEach _list;
		private _id = count _nodes;
		_nodes pushBack [round ((_pos # _best) # 0), round ((_pos # _best) # 1), 0];
		{_nodeOf set [_x, _id]} forEach _list;
		_done = _done + 1;
		if (_done mod _batch == 0) then {sleep 0.01};
	} forEach _members;

	private _seen = createHashMap;
	private _edges = [];
	for "_i" from 0 to (_count - 1) do {
		{
			if (_x > _i) then {
				private _a = _nodeOf # _i;
				private _b = _nodeOf # _x;
				if (_a != _b) then {
					private _k = format ["%1:%2", _a min _b, _a max _b];
					if !(_k in _seen) then {
						_seen set [_k, true];
						_edges pushBack [_a min _b, _a max _b];
					};
				};
			};
		} forEach (_nbr # _i);
		if (_i mod _batch == 0) then {sleep 0.01};
	};

	[_nodes, _edges, "generated"] call SWLC_fnc_routeInstall;
	["C_ROUTE", [["action", "generated"], ["segments", _count], ["nodes", count _nodes], ["edges", count _edges], ["seconds", round (diag_tickTime - _started)]]] call SWLC_fnc_log;
	if (CFG("routeLogNetwork")) then {[_nodes, _edges] call SWLC_fnc_routeDump};
};

// Writes the generated network to the RPT in short lines. tools/extract_routes.py turns them into maps\<world>_routes.sqf.
SWLC_fnc_routeDump = {
	params ["_nodes", "_edges"];
	["C_ROUTE", [["action", "dump_begin"], ["world", worldName], ["hop", CFG("routeHopMetres")], ["nodes", count _nodes], ["edges", count _edges]]] call SWLC_fnc_log;
	private _chunk = 40;
	for "_i" from 0 to (count _nodes - 1) step _chunk do {
		private _data = (_nodes select [_i, _chunk]) apply {format ["%1,%2", _x # 0, _x # 1]};
		["C_ROUTE", [["action", "nodes"], ["from", _i], ["data", _data joinString ";"]]] call SWLC_fnc_log;
		sleep 0.01;
	};
	for "_i" from 0 to (count _edges - 1) step _chunk do {
		private _data = (_edges select [_i, _chunk]) apply {format ["%1,%2", _x # 0, _x # 1]};
		["C_ROUTE", [["action", "edges"], ["from", _i], ["data", _data joinString ";"]]] call SWLC_fnc_log;
		sleep 0.01;
	};
	["C_ROUTE", [["action", "dump_end"], ["world", worldName], ["nodes", count _nodes], ["edges", count _edges]]] call SWLC_fnc_log;
};
