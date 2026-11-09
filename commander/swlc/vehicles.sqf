// Motor pool: buying, reusing, boarding, driving to dismount points, combat vehicle follow, abandoning.
// A vehicle only ever moves with the group riding in it, as part of a wave leg.
#include "macros.hpp"

SWLC_fnc_vehRecOf = { (_this # 0) getVariable ["SWLC_rec", createHashMap] };

SWLC_fnc_vehWorthDriving = {
	params ["_cmd", "_w", "_from"];
	private _d = _from distance2D ([_w get "target"] call SWLC_fnc_adPos);
	// Measured from the far dismount distance: a shorter hop loses more to the mount-up than it saves.
	(_d - CFG("dismountDistMax")) >= CFG("vehMinDriveDist")
};

SWLC_fnc_vehCheapestTransport = {
	params ["_cmd", "_men", ["_assetPos", []]];
	private _side = _cmd get "side";
	private _best = [];
	{
		// With a position, only what the side's asset rules allow there counts.
		if ((_x # 3) == "transport" && {(_x # 2) >= _men} && {_best isEqualTo [] || {(_x # 1) < (_best # 1)}}
			&& {_assetPos isEqualTo [] || {[_side, _x # 0, _assetPos] call SWLC_fnc_econAssetAllowed}}) then {_best = _x};
	} forEach (_cmd get "catalog");
	_best
};

SWLC_fnc_vehFleetCount = {
	params ["_cmd"];
	{alive (_x get "obj")} count (_cmd get "vehicles")
};

// Records bought for a wave: logged so the analyser can follow each one.
SWLC_fnc_vehBuy = {
	params ["_cmd", "_entry", "_g", "_w"];
	_entry params ["_cls", "_cost", "_seats", "_role", "_heavy"];
	private _side = _cmd get "side";
	private _items = [_cmd, leader _g, [_cls], _cost, _role] call SWLC_fnc_logBuy;
	if (_items isEqualTo []) exitWith {false};
	private _v = _items # 0;
	_v removeAllEventHandlers "GetIn";          // Warlords' 20 s "move to own position" would cancel a drive order
	_v setVariable ["SWLC_side", _side];
	private _id = (_cmd get "vehCounter") + 1;
	_cmd set ["vehCounter", _id];
	private _r = createHashMapFromArray [["id", _id], ["obj", _v], ["cls", _cls], ["role", _role], ["heavy", _heavy], ["seats", _seats], ["state", "arriving"],
		["group", _g], ["wave", _w get "id"], ["boughtAt", time], ["stuck", 0], ["mounted", false]];
	(_cmd get "vehicles") pushBack _r;
	_g setVariable ["SWLC_rec", _r];
	["C_VEH", [["side", _side], ["id", _id], ["event", "bought"], ["class", _cls], ["role", _role], ["wave", _w get "id"], ["group", groupId _g], ["seats", _seats], ["cost", _cost]]] call SWLC_fnc_log;
	true
};

SWLC_fnc_vehClaimParked = {
	params ["_cmd", "_r", "_g", "_w"];
	_r set ["state", "ready"];
	_r set ["group", _g];
	_r set ["wave", _w get "id"];
	_r set ["stuck", 0];
	_r set ["mounted", false];
	_g setVariable ["SWLC_rec", _r];
	["C_VEH", [["side", _cmd get "side"], ["id", _r get "id"], ["event", "reused"], ["class", _r get "cls"], ["role", _r get "role"], ["wave", _w get "id"], ["group", groupId _g]]] call SWLC_fnc_log;
};

// Before the go: combat vehicle first if the threat calls for one, then transport for everyone else.
SWLC_fnc_vehShop = {
	params ["_cmd", "_w", "_staged", "_musterPos"];
	if !(CFG("vehiclesEnabled")) exitWith {};
	if !([_cmd, _w, _musterPos] call SWLC_fnc_vehWorthDriving) exitWith {};
	private _side = _cmd get "side";
	private _plan = _w get "plan";
	private _buys = 0;
	private _radius = CFG("vehReuseRadius");
	private _catalog = (_cmd get "catalog") select {[_side, _x # 0, _musterPos] call SWLC_fnc_econAssetAllowed};

	private _candidates = _staged select {count ([_x] call SWLC_fnc_vehRecOf) == 0 && {leader _x call SWLC_fnc_adIsWarlordUnit}};

	// Combat
	private _plentiful = ([_side] call SWLC_fnc_cpFree) >= CFG("cpPlentiful");
	private _combatInWave = {(_x get "role") == "combat" && {(_x get "wave") == (_w get "id")} && {alive (_x get "obj")}} count (_cmd get "vehicles");
	if ((_plan get "combatVehicle" || {_plentiful}) && {_combatInWave < CFG("vehMaxCombatPerWave")} && {([_cmd] call SWLC_fnc_vehFleetCount) < CFG("vehMaxFleet")}) then {
		private _heavyWanted = (_plan get "atWanted") > 0;
		private _budget = ([_side] call SWLC_fnc_cpFree) * CFG("cpCombatFraction") * ([_cmd, "combat"] call SWLC_fnc_persona);
		private _options = _catalog select {(_x # 3) == "combat" && {(_x # 1) <= _budget} && {!_heavyWanted || {_x # 4}}};
		if (_options isEqualTo []) then {_options = _catalog select {(_x # 3) == "combat" && {(_x # 1) <= _budget}}};
		_options = [_options, [], {_x # 1}, "DESCEND"] call BIS_fnc_sortBy;
		private _byMen = [_candidates, [], {[_x] call SWLC_fnc_groupMen}, "ASCEND"] call BIS_fnc_sortBy;
		{
			private _g = _x;
			private _men = [_g] call SWLC_fnc_groupMen;
			private _fit = _options findIf {(_x # 2) >= _men};
			if (_fit >= 0) exitWith {
				if ([_cmd, _options # _fit, _g, _w] call SWLC_fnc_vehBuy) then {
					_candidates = _candidates - [_g];
					_buys = _buys + 1;
				};
			};
		} forEach _byMen;
	};

	// Transport: reuse anything parked nearby, then buy the cheapest that seats the group.
	{
		if (_buys >= CFG("vehBuyPerTick")) exitWith {};
		private _g = _x;
		private _men = [_g] call SWLC_fnc_groupMen;
		private _parked = (_cmd get "vehicles") select {
			(_x get "state") == "parked" && {alive (_x get "obj")} && {canMove (_x get "obj")} && {(_x get "seats") >= _men} && {((_x get "obj") distance2D _musterPos) <= _radius}
		};
		if (_parked isNotEqualTo []) then {
			[_cmd, _parked # 0, _g, _w] call SWLC_fnc_vehClaimParked;
		} else {
			private _need = if (([_side] call SWLC_fnc_cpFree) >= CFG("vehSeatForFullGroupCP")) then {_men max CFG("shopGroupSize")} else {_men};
			private _entry = [_cmd, _need] call SWLC_fnc_vehCheapestTransport;
			if (_entry isNotEqualTo [] && {([_cmd] call SWLC_fnc_vehFleetCount) < CFG("vehMaxFleet")} && {[_cmd, _entry, _g, _w] call SWLC_fnc_vehBuy}) then {_buys = _buys + 1};
		};
	} forEach _candidates;
};

SWLC_fnc_adIsWarlordUnit = {
	alive _this && {!isPlayer _this} && {[_this] call SWLC_fnc_adIsWarlord}
};

// Each tick: landings, stuck checks, holding-crew nudges, position logging, dead vehicles.
SWLC_fnc_vehTick = {
	params ["_cmd"];
	private _side = _cmd get "side";
	private _keep = [];
	{
		private _r = _x;
		private _v = _r get "obj";
		if (isNull _v || {!alive _v}) then {
			private _g = _r get "group";
			["C_VEH", [["side", _side], ["id", _r get "id"], ["event", "destroyed"], ["state", _r get "state"], ["role", _r get "role"], ["wave", _r get "wave"]]] call SWLC_fnc_log;
			if (!isNull _g && {([_g] call SWLC_fnc_vehRecOf) isEqualTo _r}) then {
				_g setVariable ["SWLC_rec", createHashMap];
				if ((_g getVariable ["SWLC_leg", ""]) in ["DRIVE", "FOLLOW", "LATE"]) then {_g setVariable ["SWLC_legLost", true]};
			};
		} else {
			_keep pushBack _r;
			if ((_r get "state") == "arriving" && {isNull attachedTo _v} && {((getPosATL _v) # 2) < 2}) then {
				_r set ["state", "ready"];
				["C_VEH", [["side", _side], ["id", _r get "id"], ["event", "landed"], ["after", round (time - (_r get "boughtAt"))], ["x", round ((getPosATL _v) # 0)], ["y", round ((getPosATL _v) # 1)]]] call SWLC_fnc_log;
			};
			[_cmd, _r get "group", "vehStuck", {
				[_cmd, _r] call SWLC_fnc_vehStuckCheck;
				[_r] call SWLC_fnc_vehSlowCheck;
			}] call SWLC_fnc_resGuarded;
			if (CFG("verboseLog")) then {
				private _p = getPosATL _v;
				["C_VTRK", [["side", _side], ["id", _r get "id"], ["state", _r get "state"], ["wave", _r get "wave"], ["x", round (_p # 0)], ["y", round (_p # 1)]]] call SWLC_fnc_log;
			};
		};
	} forEach (_cmd get "vehicles");
	_cmd set ["vehicles", _keep];
};

// Well clear of any fight? A lift must never be something a player sees, or a way out of trouble.
SWLC_fnc_vehSafeToLift = {
	params ["_cmd", "_g", "_v"];
	private _side = _cmd get "side";
	private _p = getPosATL _v;
	if ((behaviour leader _g) == "COMBAT") exitWith {false};
	if ([_g] call SWLC_fnc_groupFighting) exitWith {false};
	if (((crew _v) findIf {isPlayer _x}) >= 0) exitWith {false};
	if ((allPlayers findIf {alive _x && {(_x distance2D _p) < CFG("vehUnstickPlayerRadius")}}) >= 0) exitWith {false};
	private _enemy = (_p nearEntities [["Man", "Car", "Tank", "Air", "Ship", "StaticWeapon"], CFG("vehUnstickEnemyRadius")]) findIf {
		alive _x && {(side group _x) in [west, east, resistance]} && {[side group _x, _side] call BIS_fnc_sideIsEnemy}
	};
	if (_enemy >= 0) exitWith {false};
	private _zone = [west, east] findIf {
		private _t = [_x] call SWLC_fnc_adTarget;
		!isNull _t && {[_t, _p, CFG("vehUnstickZoneRadius")] call SWLC_fnc_adInSquare}
	};
	_zone < 0
};

// A vehicle that isn't getting anywhere. Returns true if this dealt with it.
SWLC_fnc_vehStuckRescue = {
	params ["_cmd", "_g", "_r", "_v"];
	private _flipped = ((vectorUp _v) # 2) < 0.4;
	private _safe = [_cmd, _g, _v] call SWLC_fnc_vehSafeToLift;
	// A tank that has lost its tracks in a fight is still a gun.
	if ((_r get "role") == "combat" && {(behaviour leader _g) == "COMBAT"} && {canFire _v} && {!_flipped}) exitWith {false};
	// It can't drive: nobody sits in it waiting for a timer, under fire or not.
	if (!canMove _v || {(fuel _v) <= 0} || {_flipped && {!_safe}}) exitWith {
		_g setVariable ["SWLC_legAbandon", true];
		["C_VEH", [["side", _cmd get "side"], ["id", _r get "id"], ["event", "wreck"], ["group", groupId _g], ["canmove", canMove _v], ["flipped", _flipped]]] call SWLC_fnc_log;
		true
	};
	if !(CFG("vehUnstick") && {_safe}) exitWith {false};
	if ((_r getOrDefault ["lifts", 0]) >= CFG("vehUnstickMax")) exitWith {false};
	if ((time - (_r getOrDefault ["liftAt", -1e6])) < CFG("vehUnstickCooldown")) exitWith {false};

	private _p = getPosATL _v;
	private _goal = _g getVariable ["SWLC_goal", []];
	private _dir = if (_goal isEqualTo []) then {getDir _v} else {_p getDir _goal};
	private _probe = _p getPos [CFG("vehUnstickAhead"), _dir];
	private _roads = _probe nearRoads 80;
	private _spot = _probe;
	if (_roads isNotEqualTo []) then {
		_spot = getPosATL (([_roads, [], {_x distance2D _probe}, "ASCEND"] call BIS_fnc_sortBy) # 0);
	};
	_spot = _spot findEmptyPosition [0, 30, typeOf _v];
	if (_spot isEqualTo [] || {surfaceIsWater _spot}) exitWith {false};

	_v setVelocity [0, 0, 0];
	_v setVehiclePosition [_spot, [], 0, "NONE"];
	_v setDir _dir;
	_v setVectorUp (surfaceNormal (getPosATL _v));
	_r set ["lifts", (_r getOrDefault ["lifts", 0]) + 1];
	_r set ["liftAt", time];
	_r set ["stuck", 0];
	_r set ["sample", [time, getPosATL _v]];
	[_g, _g getVariable ["SWLC_wpProgress", 0]] call SWLC_fnc_adApplyOrder;
	["C_VEH", [["side", _cmd get "side"], ["id", _r get "id"], ["event", "lifted"], ["group", groupId _g], ["count", _r get "lifts"], ["flipped", _flipped],
		["x", round (_p # 0)], ["y", round (_p # 1)], ["tox", round (_spot # 0)], ["toy", round (_spot # 1)]]] call SWLC_fnc_log;
	true
};

// Slow down where the pile-ups happen: behind another vehicle and around sectors. Off again everywhere else.
SWLC_fnc_vehSlowCheck = {
	params ["_r"];
	if !(CFG("vehSlowNearby")) exitWith {};
	private _v = _r get "obj";
	private _g = _r get "group";
	if (isNull _g || {!alive _v}) exitWith {};
	private _want = -1;
	if (((_g getVariable ["SWLC_leg", ""]) in ["DRIVE", "FOLLOW"]) && {(behaviour leader _g) != "COMBAT"}) then {
		private _ahead = ((_v nearEntities [["Car", "Tank"], CFG("vehSlowRadius")]) - [_v]) findIf {
			private _rel = _v getRelDir _x;
			alive _x && {_rel < 60 || {_rel > 300}}
		};
		private _p = getPosATL _v;
		private _atSector = SWLC_sectors findIf {[_x, _p, CFG("vehSlowSectorRadius")] call SWLC_fnc_adInSquare};
		if (_ahead >= 0 || {_atSector >= 0}) then {_want = CFG("vehSlowSpeed")};
	};
	if (_want != (_r getOrDefault ["slow", -1])) then {
		_r set ["slow", _want];
		_v forceSpeed _want;
	};
};

// A driver that barely moves: lifted clear if that's safe, otherwise reset once, then abandon the vehicle and walk.
SWLC_fnc_vehStuckCheck = {
	params ["_cmd", "_r"];
	private _g = _r get "group";
	if (isNull _g) exitWith {};
	private _leg = _g getVariable ["SWLC_leg", ""];
	if !(([_g] call SWLC_fnc_vehRecOf) isEqualTo _r) exitWith {};
	if !(_leg in ["DRIVE", "FOLLOW"]) exitWith {_r deleteAt "sample"};
	// Stopped to fight on purpose; the clock starts again when it moves off.
	if (([_g] call SWLC_fnc_state) == "Engaged") exitWith {_r deleteAt "sample"};
	private _v = _r get "obj";
	private _p = getPosATL _v;
	private _s = _r getOrDefault ["sample", []];
	if (_s isEqualTo []) exitWith {_r set ["sample", [time, _p]]};
	_s params ["_t0", "_p0"];
	if ((time - _t0) < CFG("vehStuckWindow")) exitWith {};
	private _moved = _p distance2D _p0;
	_r set ["sample", [time, _p]];
	if (_moved >= CFG("vehUnstickResetMetres")) then {_r set ["lifts", 0]};
	private _rescued = false;
	// A combat vehicle following the infantry is meant to crawl and stop, so only a driving leg is ever rescued.
	if (_leg == "DRIVE" && {_moved < CFG("vehStuckMinMetres")}) then {_rescued = [_cmd, _g, _r, _v] call SWLC_fnc_vehStuckRescue};
	if (_rescued) exitWith {};

	if (_leg == "FOLLOW") exitWith {
		if (_moved < 1 && {(time - (_r getOrDefault ["nudged", -1000])) >= CFG("combatNudgeSeconds")}) then {
			_r set ["nudged", time];
			(driver _v) doMove ((getPosATL _v) getPos [4, random 360]);
		};
	};

	if (_moved >= CFG("vehStuckMinMetres") || {(_r get "role") == "combat" && {(behaviour leader _g) == "COMBAT"}}) exitWith {};
	private _n = (_r get "stuck") + 1;
	_r set ["stuck", _n];
	["C_VEH", [["side", _cmd get "side"], ["id", _r get "id"], ["event", "stuck"], ["count", _n], ["group", groupId _g], ["x", round (_p # 0)], ["y", round (_p # 1)]]] call SWLC_fnc_log;
	if (_n < CFG("vehStuckLimit")) exitWith {
		[_g, _g getVariable ["SWLC_wpProgress", 0]] call SWLC_fnc_adApplyOrder;
	};
	_g setVariable ["SWLC_legAbandon", true];
};

// Assign seats and order the group aboard. Safe to call repeatedly: only acts once per claim.
SWLC_fnc_vehMountGroup = {
	params ["_cmd", "_g"];
	private _r = [_g] call SWLC_fnc_vehRecOf;
	if (count _r == 0 || {(_r get "state") == "arriving"}) exitWith {};
	if ((_r get "mounted") && {!isNull assignedDriver (_r get "obj")}) exitWith {
		// Men who joined the group after boarding started (bought top-ups) get a seat too.
		private _v = _r get "obj";
		private _new = ([_g] call SWLC_fnc_alive) select {(assignedVehicle _x) isNotEqualTo _v};
		if (_new isNotEqualTo []) then {
			{_x assignAsCargo _v} forEach _new;
			_new orderGetIn true;
		};
	};
	_r set ["mounted", true];
	_r set ["state", "boarding"];
	private _v = _r get "obj";
	private _units = [_g] call SWLC_fnc_alive;
	private _others = _units - [leader _g];
	private _driver = if (_others isEqualTo []) then {leader _g} else {_others # 0};
	_g addVehicle _v;
	_driver assignAsDriver _v;
	private _rest = _units - [_driver];
	if ((_r get "role") == "combat" && {_rest isNotEqualTo []} && {(_v emptyPositions "Gunner") > 0}) then {
		(_rest deleteAt 0) assignAsGunner _v;
	};
	if ((_r get "role") == "combat" && {_rest isNotEqualTo []} && {(_v emptyPositions "Commander") > 0}) then {
		(_rest deleteAt 0) assignAsCommander _v;
	};
	{_x assignAsCargo _v} forEach _rest;
	_units orderGetIn true;
	["C_VEH", [["side", side _g], ["id", _r get "id"], ["event", "mounting"], ["group", groupId _g]]] call SWLC_fnc_log;
};

SWLC_fnc_vehAboard = {
	params ["_g"];
	private _r = [_g] call SWLC_fnc_vehRecOf;
	if (count _r == 0) exitWith {true};
	private _v = _r get "obj";
	((units _g) findIf {alive _x && {vehicle _x != _v}}) < 0
};

// Everyone still on foot gets put in their seat (used at the end of a late element's grace period).
SWLC_fnc_vehForceBoard = {
	params ["_g"];
	private _r = [_g] call SWLC_fnc_vehRecOf;
	if (count _r == 0) exitWith {};
	private _v = _r get "obj";
	{
		if (alive _x && {vehicle _x != _v}) then {_x moveInAny _v};
	} forEach units _g;
};

// Dismount, park the vehicle where it stops. It waits there for the next wave.
SWLC_fnc_vehDismount = {
	params ["_cmd", "_g", "_reason"];
	private _r = [_g] call SWLC_fnc_vehRecOf;
	if (count _r == 0) exitWith {};
	private _v = _r get "obj";
	_r set ["state", "parked"];
	_r set ["group", grpNull];
	_r deleteAt "sample";
	_g leaveVehicle _v;
	private _units = (units _g) select {alive _x};
	{unassignVehicle _x} forEach _units;
	_units orderGetIn false;
	{if (vehicle _x == _v) then {doGetOut _x}} forEach _units;
	_g setVariable ["SWLC_rec", createHashMap];
	private _p = getPosATL _v;
	["C_VEH", [["side", side _g], ["id", _r get "id"], ["event", "parked"], ["reason", _reason], ["group", groupId _g], ["x", round (_p # 0)], ["y", round (_p # 1)]]] call SWLC_fnc_log;
};

// Sent when a wave ends or a group leaves its wave.
SWLC_fnc_vehRelease = {
	params ["_cmd", "_g"];
	[_cmd, _g, "released"] call SWLC_fnc_vehDismount;
	_g setVariable ["SWLC_leg", ""];
};

SWLC_fnc_makeDismount = {
	params ["_cmd", "_target", "_bearing"];
	private _side = _cmd get "side";
	private _tpos = [_target] call SWLC_fnc_adPos;
	private _threat = [_cmd, _target] call SWLC_fnc_threatOf;
	private _dMax = CFG("dismountDistMax");
	private _dMin = if (_threat get "scouted") then {CFG("dismountDistMin")} else {_dMax - 100};
	private _danger = ((_cmd get "board") select {(_x get "cat") in ["static", "unknownAT", "tank", "apc"]}) apply {_x get "pos"};
	private _range = CFG("dismountThreatRange");
	private _tEye = (AGLToASL _tpos) vectorAdd [0, 0, 2];
	private _best = [];
	private _bestScore = -1e9;
	for "_d" from _dMin to _dMax step 50 do {
		{
			private _p = [_tpos, _bearing + _x, _d] call SWLC_fnc_offset;
			if (!surfaceIsWater _p && {!([_side, _p, 50] call SWLC_fnc_adRestricted)} && {(_danger findIf {_x distance2D _p < _range}) < 0}) then {
				private _hidden = terrainIntersectASL [(AGLToASL _p) vectorAdd [0, 0, 2], _tEye];
				private _score = ([0, 50] select _hidden) - (abs _x) * 0.3 - (_d - _dMin) * 0.02;
				if (_score > _bestScore) then {_bestScore = _score; _best = _p};
			};
		} forEach [0, 15, -15, 30, -30];
	};
	if (_best isEqualTo []) then {_best = [_tpos, _bearing, _dMax] call SWLC_fnc_offset};
	private _roads = _best nearRoads CFG("dismountRoadSnap");
	if (_roads isNotEqualTo []) then {
		private _nearest = _roads # 0;
		{if ((_x distance2D _best) < (_nearest distance2D _best)) then {_nearest = _x}} forEach _roads;
		private _rp = getPosATL _nearest;
		if (!([_side, _rp, 50] call SWLC_fnc_adRestricted) && {(_danger findIf {_x distance2D _rp < _range}) < 0}) then {
			_best = [_rp # 0, _rp # 1, 0];
		};
	};
	_best
};

// Combat vehicles stay 50 to 100 m behind the lead infantry and never push in alone.
SWLC_fnc_vehFollowTick = {
	params ["_cmd", "_w", "_live"];
	private _target = _w get "target";
	private _tpos = [_target] call SWLC_fnc_adPos;
	private _foot = _live select {(_x getVariable ["SWLC_leg", ""]) == "FOOT" && {([_x] call SWLC_fnc_state) == "Assaulting"}};
	{
		private _g = _x;
		[_cmd, _g, "vehFollow", {
			private _r = [_g] call SWLC_fnc_vehRecOf;
			if ((_g getVariable ["SWLC_leg", ""]) == "FOLLOW" && {count _r > 0} && {([_g] call SWLC_fnc_state) == "Assaulting"}) then {
				private _mine = _foot;
				private _v = _r get "obj";
				private _here = getPosATL _v;
				private _dest = +_here;
				private _leadDist = -1;
				if (_mine isNotEqualTo []) then {
					private _lead = _mine # 0;
					{if ((leader _x distance2D _tpos) < (leader _lead distance2D _tpos)) then {_lead = _x}} forEach _mine;
					private _lp = getPosATL leader _lead;
					_leadDist = _lp distance2D _tpos;
					private _behind = [_lp, [_lp, _here] call SWLC_fnc_bearing, CFG("combatFollowDist")] call SWLC_fnc_offset;
					// Only ever go forward to a spot behind the lead, and never into the sector ahead of the infantry.
					if (((_behind distance2D _tpos) >= _leadDist) && {(_here distance2D _tpos) > (_leadDist + 50) || {[_target, _lp, 0] call SWLC_fnc_adInSquare}}) then {
						_dest = _behind;
					};
				};
				private _order = _g getVariable ["SWLC_order", []];
				private _cur = if (_order isEqualTo []) then {[]} else {((_order # 0) # 0) # 0};
				if (_cur isEqualTo [] || {(_cur distance2D _dest) > CFG("combatReorderDist")}) then {
					_g setVariable ["SWLC_goal", _dest];
					[_g, [[_dest, "MOVE", 25]], "AWARE", "NORMAL", "COLUMN", "RED"] call SWLC_fnc_adSetOrder;
				};
				if (CFG("verboseLog")) then {
					["C_VPOS", [["side", side _g], ["wave", _w get "id"], ["id", _r get "id"], ["role", _r get "role"], ["x", round (_here # 0)], ["y", round (_here # 1)],
						["d_target", round (_here distance2D _tpos)], ["lead_d", round _leadDist], ["in_square", [_target, _here] call SWLC_fnc_adInSquare]]] call SWLC_fnc_log;
				};
			};
		}] call SWLC_fnc_resGuarded;
	} forEach _live;
};
