// The wave cycle: gather at staging, go signal, launch on approaches, hold points, assault, resolve.
#include "macros.hpp"

SWLC_fnc_waveNew = {
	params ["_cmd"];
	private _id = (_cmd get "waveCounter") + 1;
	_cmd set ["waveCounter", _id];
	createHashMapFromArray [
		["id", _id],
		["target", _cmd get "target"],
		["phase", "GATHER"],
		["groups", []],
		["firstArrive", -1],
		["created", time]
	]
};

SWLC_fnc_waveRemoveGroup = {
	params ["_cmd", "_g"];
	private _waves = (_cmd get "flying") select {true};
	if (!isNil {_cmd get "gather"}) then {_waves pushBack (_cmd get "gather")};
	{
		private _i = (_x get "groups") find _g;
		if (_i >= 0) then {
			(_x get "groups") deleteAt _i;
			if (!isNil {_x get "launchStrength"}) then {
				_x set ["launchStrength", ((_x get "launchStrength") - ([_g] call SWLC_fnc_groupMen)) max 0];
			};
		};
	} forEach _waves;
	_g setVariable ["SWLC_waveId", -1];
	[_cmd, _g] call SWLC_fnc_vehRelease;
};

// Live groups of a wave that are still its own.
SWLC_fnc_waveLive = {
	params ["_w"];
	(_w get "groups") select {({alive _x} count units _x) > 0 && {(_x getVariable ["SWLC_waveId", -1]) == (_w get "id")}}
};

SWLC_fnc_waveTick = {
	params ["_cmd"];
	{
		[_cmd, _x] call SWLC_fnc_waveAdvance;
	} forEach ((_cmd get "flying") select {true});
	_cmd set ["flying", (_cmd get "flying") select {(_x get "phase") != "DONE"}];
	[_cmd] call SWLC_fnc_gatherTick;
};

// Go signal: 3+ groups at staging, or 4 minutes after the first arrival. No extensions.
SWLC_fnc_gatherTick = {
	params ["_cmd"];
	private _w = _cmd get "gather";
	if (isNil "_w") exitWith {};
	if (([_w get "target"] call SWLC_fnc_adOwner) == (_cmd get "side")) exitWith {};
	[_cmd, _w] call SWLC_fnc_wavePlan;
	[_cmd] call SWLC_fnc_stagingArrivals;
	private _live = [_w] call SWLC_fnc_waveLive;
	private _staged = _live select {([_x] call SWLC_fnc_state) == "Staging"};
	[_cmd, _w, _staged] call SWLC_fnc_shopTick;
	[_cmd, _w, _staged] call SWLC_fnc_kitTick;
	private _first = _w get "firstArrive";
	private _capReached = _first >= 0 && {(time - _first) >= CFG("goMaxWait")};
	private _countReached = (count _staged) >= CFG("goMinGroups") || {_w getOrDefault ["forceGo", false]};
	if !(_capReached || _countReached) exitWith {};
	if (_staged isEqualTo []) exitWith {};

	// A short hold after the first arrival while top-ups are affordable, so groups don't leave as lone men.
	if (!_capReached && {_first >= 0} && {(time - _first) < CFG("goMinGatherSeconds")} && {!(_w getOrDefault ["forceGo", false])}
		&& {([_cmd get "side"] call SWLC_fnc_cpFree) >= 100}
		&& {(_staged findIf {([_x] call SWLC_fnc_groupMen) < CFG("shopGroupSize")}) >= 0}) exitWith {};

	// Let the previous wave get to its assault first, but the 4-minute cap always wins.
	private _prevMoving = ((_cmd get "flying") findIf {(_x get "phase") in ["MOUNT", "TO_HOLD"]}) >= 0;
	if (_prevMoving && {!_capReached}) exitWith {};

	[_cmd, _w, _staged, _capReached && {!_countReached}] call SWLC_fnc_waveLaunch;
};

// What the wave should bring, from the threat summary. Never affects how long it waits.
SWLC_fnc_wavePlan = {
	params ["_cmd", "_w"];
	private _threat = [_cmd, _w get "target"] call SWLC_fnc_threatOf;
	private _armour = _threat get "armour";
	private _plan = createHashMapFromArray [
		["atWanted", (_armour * CFG("planAtPerArmour")) max (([0, count (_w get "groups")] select ((_threat get "light") > 0)) * CFG("planAtPerLightGroup"))],
		["combatVehicle", _armour > 0 || {(_threat get "static") >= 2}],
		["aa", (_threat get "air") > 0],
		["smoke", (_threat get "static") > 0],
		["scan", !(_threat get "scouted")],
		["ammo", (_threat get "infantry") >= CFG("kitHeavyInfantryFactor") * (([[_w] call SWLC_fnc_waveLive] call SWLC_fnc_groupsMen) max 1)]
	];
	private _sig = [_plan get "atWanted", _plan get "combatVehicle", _plan get "aa", _plan get "smoke", _plan get "scan"];
	if (_sig isNotEqualTo (_w getOrDefault ["planSig", []])) then {
		_w set ["planSig", _sig];
		["C_PLAN", [["side", _cmd get "side"], ["wave", _w get "id"], ["at_wanted", _sig # 0], ["combat_vehicle", _sig # 1], ["aa", _sig # 2], ["smoke", _sig # 3], ["scan", _sig # 4]]] call SWLC_fnc_log;
	};
	_w set ["plan", _plan];
	_plan
};

SWLC_fnc_makeApproaches = {
	params ["_cmd", "_target", "_groupCount"];
	private _side = _cmd get "side";
	private _tpos = [_target] call SWLC_fnc_adPos;
	private _centre = [_tpos, _cmd get "stagingPos"] call SWLC_fnc_bearing;
	private _spread = CFG("approachSpreadMin") + random (CFG("approachSpreadMax") - CFG("approachSpreadMin"));
	private _offsets = if (_groupCount >= 4) then {[-_spread, 0, _spread]} else {[-_spread / 2, _spread / 2]};
	private _out = [];
	{
		private _bearing = _centre + _x;
		private _d = CFG("holdDistMin") + random (CFG("holdDistMax") - CFG("holdDistMin"));
		private _pos = [_side, _tpos, _bearing, _d] call SWLC_fnc_validHoldPoint;
		_out pushBack (createHashMapFromArray [["bearing", _bearing], ["hold", _pos], ["groups", []]]);
	} forEach _offsets;
	_out
};

// Rotates up to +-75 degrees to keep the hold point on land and out of restricted sectors.
SWLC_fnc_validHoldPoint = {
	params ["_side", "_tpos", "_bearing", "_d"];
	private _found = [];
	{
		private _p = [_tpos, _bearing + _x, _d] call SWLC_fnc_offset;
		if (!surfaceIsWater _p && {!([_side, _p] call SWLC_fnc_adRestricted)}) exitWith {_found = _p};
	} forEach [0, 15, -15, 30, -30, 45, -45, 60, -60, 75, -75];
	if (_found isEqualTo []) then {_found = [_tpos, _bearing, _d] call SWLC_fnc_offset};
	_found
};

// The go signal. Groups finish kit and board (capped), then all leave together in waveDepart.
SWLC_fnc_waveLaunch = {
	params ["_cmd", "_w", "_goers", "_byTimer"];
	private _side = _cmd get "side";
	private _target = _w get "target";
	private _others = (_w get "groups") - _goers;

	_w set ["groups", _goers];
	private _approaches = [_cmd, _target, count _goers] call SWLC_fnc_makeApproaches;
	{
		_x set ["dismount", [_cmd, _target, _x get "bearing"] call SWLC_fnc_makeDismount];
	} forEach _approaches;
	private _sorted = [_goers, [], {
		private _b = [getPosATL leader _x, [_target] call SWLC_fnc_adPos] call SWLC_fnc_bearing;
		_b
	}, "ASCEND"] call BIS_fnc_sortBy;
	{
		private _a = _approaches # (_forEachIndex mod count _approaches);
		(_a get "groups") pushBack _x;
		_x setVariable ["SWLC_atHold", false];
		_x setVariable ["SWLC_leg", ""];
		_x setVariable ["SWLC_legLost", false];
		_x setVariable ["SWLC_legAbandon", false];
		_x setVariable ["SWLC_launchMen", [_x] call SWLC_fnc_groupMen];
		_x setVariable ["SWLC_broke", false];
		if (CFG("smartSmoke") && {alive leader _x} && {((magazines leader _x) findIf {_x isKindOf ["SmokeShell", configFile >> "CfgMagazines"]}) < 0}) then {
			(leader _x) addMagazines ["SmokeShell", 2];
		};
		_x setVariable ["SWLC_reinforced", false];
		_x setVariable ["SWLC_bestD", 1e9];
		_x setVariable ["SWLC_bestAt", time];
		_x setVariable ["SWLC_heavyCalled", false];
		[_x, "Mounting", _a get "hold", "go"] call SWLC_fnc_setState;
	} forEach _sorted;

	_w set ["approaches", _approaches];
	_w set ["phase", "MOUNT"];
	_w set ["goTime", time];
	_w set ["launched", time];
	_w set ["launchStrength", [_goers] call SWLC_fnc_groupsMen];
	_w set ["firstHold", -1];
	_w set ["lastProgress", time];
	private _wait = if ((_w get "firstArrive") >= 0) then {round (time - (_w get "firstArrive"))} else {-1};
	["C_WAVE", [["side", _side], ["wave", _w get "id"], ["event", "go"], ["groups", count _goers], ["men", _w get "launchStrength"],
		["target", [_target] call SWLC_fnc_adName], ["approaches", count _approaches], ["by_timer", _byTimer], ["wait", _wait]]] call SWLC_fnc_log;

	(_cmd get "flying") pushBack _w;
	if (({count ([_x] call SWLC_fnc_vehRecOf) > 0} count _goers) > 0) then {[_side, "mount"] call SWLC_fnc_radio};

	private _next = [_cmd] call SWLC_fnc_waveNew;
	_next set ["groups", _others];
	{_x setVariable ["SWLC_waveId", _next get "id"]} forEach _others;
	_cmd set ["gather", _next];

	// Nothing to board and no kit to draw: the wave leaves on the same tick as the go.
	[_cmd, _w, _goers] call SWLC_fnc_waveMountTick;
};

SWLC_fnc_waveAdvance = {
	params ["_cmd", "_w"];
	private _side = _cmd get "side";
	private _target = _w get "target";
	private _live = [_w] call SWLC_fnc_waveLive;

	// Resolve
	if (([_target] call SWLC_fnc_adOwner) == _side) exitWith {[_cmd, _w, "seized"] call SWLC_fnc_waveResolve};
	if (!isNull (_cmd get "target") && {_target isNotEqualTo (_cmd get "target")}) exitWith {[_cmd, _w, "target_changed"] call SWLC_fnc_waveResolve};
	private _strength = [_live] call SWLC_fnc_groupsMen;
	if (_strength < CFG("waveFailStrength") * (_w get "launchStrength")) exitWith {[_cmd, _w, "attrition"] call SWLC_fnc_waveResolve};
	if (_live isEqualTo []) exitWith {[_cmd, _w, "wiped"] call SWLC_fnc_waveResolve};

	switch (_w get "phase") do {
		case "MOUNT": {
			[_cmd, _w, _live] call SWLC_fnc_waveMountTick;
		};
		case "TO_HOLD": {
			[_cmd, _w, _live] call SWLC_fnc_waveToHold;
		};
		case "ASSAULT": {
			[_cmd, _w, _live] call SWLC_fnc_waveAssault;
		};
	};
};

// Boarding and kit. Everyone ready, or the cap reached: the wave leaves together.
SWLC_fnc_groupReady = {
	params ["_g"];
	!([_g] call SWLC_fnc_kitPending) && {[_g] call SWLC_fnc_vehAboard}
};

SWLC_fnc_waveMountTick = {
	params ["_cmd", "_w", "_live"];
	[_cmd, _w, _live] call SWLC_fnc_kitTick;
	{
		// Kit first, then board, so nobody climbs in on the way to the crate.
		if !([_x] call SWLC_fnc_kitPending) then {[_cmd, _x] call SWLC_fnc_vehMountGroup};
	} forEach _live;
	private _capped = (time - (_w get "goTime")) >= CFG("mountCapSeconds");
	if (_capped || {(_live findIf {!([_x] call SWLC_fnc_groupReady)}) < 0}) then {
		[_cmd, _w, _live] call SWLC_fnc_waveDepart;
	};
};

// Sends a group off on its leg: driving to the dismount point, following the infantry, or walking.
SWLC_fnc_waveSendGroup = {
	params ["_cmd", "_w", "_a", "_g"];
	private _rec = [_g] call SWLC_fnc_vehRecOf;
	if (count _rec > 0 && {(_rec get "role") == "combat"}) exitWith {
		_g setVariable ["SWLC_leg", "FOLLOW"];
		_rec set ["state", "moving"];
		[_cmd, _w, [_g]] call SWLC_fnc_vehFollowTick;
	};
	if (count _rec > 0) exitWith {
		_g setVariable ["SWLC_leg", "DRIVE"];
		_rec set ["state", "moving"];
		[_g, "Assaulting", _a get "dismount", "drive"] call SWLC_fnc_setState;
		[_g, [[_a get "dismount", "MOVE", 30]], "SAFE", "NORMAL", "COLUMN", "YELLOW"] call SWLC_fnc_adSetOrder;
	};
	[_cmd, _w, _a, _g] call SWLC_fnc_waveFootOrder;
};

SWLC_fnc_waveFootOrder = {
	params ["_cmd", "_w", "_a", "_g"];
	_g setVariable ["SWLC_leg", "FOOT"];
	if ((_w get "phase") == "ASSAULT") then {
		[_g, "Assaulting", [_w get "target"] call SWLC_fnc_adPos, "assault"] call SWLC_fnc_setState;
		[_g, [_w get "target"] call SWLC_fnc_sweepOrder, "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
	} else {
		[_g, "Assaulting", _a get "hold", "launch"] call SWLC_fnc_setState;
		[_g, [[_a get "hold", "MOVE", 30]]] call SWLC_fnc_adSetOrder;
	};
};

// All orders together. Anyone not ready at the cap becomes a second element on the same approach.
SWLC_fnc_waveDepart = {
	params ["_cmd", "_w", "_live"];
	[_cmd, _w, _live] call SWLC_fnc_kitFinish;
	private _riding = 0;
	private _walking = 0;
	private _late = 0;
	private _unused = 0;
	{
		private _a = _x;
		{
			private _g = _x;
			if (_g in _live) then {
				if ([_g] call SWLC_fnc_groupReady) then {
					[_cmd, _w, _a, _g] call SWLC_fnc_waveSendGroup;
					if (count ([_g] call SWLC_fnc_vehRecOf) > 0) then {_riding = _riding + 1} else {_walking = _walking + 1};
				} else {
					_g setVariable ["SWLC_leg", "LATE"];
					_late = _late + 1;
				};
			};
		} forEach (_a get "groups");
	} forEach (_w get "approaches");
	_w set ["phase", "TO_HOLD"];
	_w set ["launched", time];
	_w set ["lastProgress", time];
	["C_WAVE", [["side", _cmd get "side"], ["wave", _w get "id"], ["event", "depart"], ["mount_s", round (time - (_w get "goTime"))], ["riding", _riding], ["walking", _walking], ["late", _late], ["worth_driving", [_cmd, _w] call SWLC_fnc_vehWorthDriving],
		["at_launchers", [_live] call SWLC_fnc_kitCountAT], ["at_wanted", (_w get "plan") get "atWanted"]]] call SWLC_fnc_log;
	[_cmd get "side", "moveout", [count (_w get "approaches"), _w get "id", [_w get "target"] call SWLC_fnc_adName]] call SWLC_fnc_radio;
};

// Per-group vehicle legs, run during both the approach and the assault.
SWLC_fnc_waveVehicleLegs = {
	params ["_cmd", "_w", "_live"];
	{
		private _a = _x;
		{
			private _g = _x;
			if (_g in _live) then {
				switch (_g getVariable ["SWLC_leg", ""]) do {
					case "LATE": {
						[_cmd, _g] call SWLC_fnc_vehMountGroup;
						private _deadline = (_w get "goTime") + CFG("mountCapSeconds") + CFG("mountLateExtra");
						if ([_g] call SWLC_fnc_groupReady) then {
							[_cmd, _w, _a, _g] call SWLC_fnc_waveSendGroup;
						} else {
							if (time >= _deadline) then {
								private _rec = [_g] call SWLC_fnc_vehRecOf;
								if (count _rec > 0 && {(_rec get "state") != "arriving"}) then {
									[_g] call SWLC_fnc_vehForceBoard;
									[_cmd, _w, _a, _g] call SWLC_fnc_waveSendGroup;
								} else {
									if (count _rec > 0) then {
										["C_VEH", [["side", _cmd get "side"], ["id", _rec get "id"], ["event", "left_unused"], ["group", groupId _g]]] call SWLC_fnc_log;
										_rec set ["group", grpNull];
										_rec set ["state", "parked"];
										_g setVariable ["SWLC_rec", createHashMap];
									};
									[_cmd, _w, _a, _g] call SWLC_fnc_waveFootOrder;
								};
							};
						};
					};
					case "DRIVE": {
						private _abandon = (_g getVariable ["SWLC_legAbandon", false]) || {_g getVariable ["SWLC_legLost", false]};
						if (_abandon) then {
							_g setVariable ["SWLC_legAbandon", false];
							_g setVariable ["SWLC_legLost", false];
							[_cmd, _g, "abandoned"] call SWLC_fnc_vehDismount;
							[_cmd get "side", "stuck", [], _g] call SWLC_fnc_radio;
							[_cmd, _w, _a, _g] call SWLC_fnc_waveFootOrder;
						} else {
							if (((leader _g) distance2D (_a get "dismount")) <= CFG("dismountArriveRadius") || {[_g] call SWLC_fnc_adOrderDone}) then {
								[_cmd, _g, "dismount"] call SWLC_fnc_vehDismount;
								[_cmd, _w, _a, _g] call SWLC_fnc_waveFootOrder;
							};
						};
					};
					case "FOLLOW": {
						if ((_g getVariable ["SWLC_legLost", false]) || {_g getVariable ["SWLC_legAbandon", false]}) then {
							_g setVariable ["SWLC_legAbandon", false];
							_g setVariable ["SWLC_legLost", false];
							[_cmd, _g, "abandoned"] call SWLC_fnc_vehDismount;
							[_cmd, _w, _a, _g] call SWLC_fnc_waveFootOrder;
						};
					};
				};
			};
		} forEach (_a get "groups");
	} forEach (_w get "approaches");
	[_cmd, _w, _live] call SWLC_fnc_vehFollowTick;
};

SWLC_fnc_waveToHold = {
	params ["_cmd", "_w", "_live"];
	private _approaches = _w get "approaches";
	private _r = CFG("holdArriveRadius");
	[_cmd, _w, _live] call SWLC_fnc_waveVehicleLegs;
	{
		private _a = _x;
		{
			if (_x in _live && {(_x getVariable ["SWLC_leg", ""]) == "FOOT"} && {!(_x getVariable ["SWLC_atHold", false])}) then {
				private _dist = (leader _x) distance2D (_a get "hold");
				if (_dist <= _r || {[_x] call SWLC_fnc_adOrderDone}) then {
					_x setVariable ["SWLC_atHold", true];
					if ((_w get "firstHold") < 0) then {_w set ["firstHold", time]};
				};
			};
		} forEach (_a get "groups");
	} forEach _approaches;

	private _allIn = true;
	{
		private _groups = (_x get "groups") select {_x in _live && {(_x getVariable ["SWLC_leg", ""]) != "FOLLOW"}};
		if (_groups isNotEqualTo [] && {(_groups findIf {_x getVariable ["SWLC_atHold", false]}) < 0}) exitWith {_allIn = false};
	} forEach _approaches;

	private _firstHold = _w get "firstHold";
	private _timeout = (_firstHold >= 0 && {(time - _firstHold) >= CFG("holdWaitMax")})
		|| {(time - (_w get "launched")) >= CFG("toHoldTimeout")};
	if (_allIn || _timeout) then {
		[_cmd, _w, _live, _allIn] call SWLC_fnc_waveGoIn;
	};
};

SWLC_fnc_sweepOrder = {
	params ["_target"];
	private _c = [_target] call SWLC_fnc_adPos;
	private _h = (([_target] call SWLC_fnc_adSize) / 2) * CFG("sweepInset");
	private _out = [];
	for "_i" from 1 to CFG("sweepPoints") do {
		private _p = [(_c # 0) + (random (2 * _h)) - _h, (_c # 1) + (random (2 * _h)) - _h, 0];
		if (surfaceIsWater _p) then {_p = +_c};
		_out pushBack [_p, "SAD", 30];
	};
	_out
};

SWLC_fnc_waveGoIn = {
	params ["_cmd", "_w", "_live", "_allIn"];
	private _target = _w get "target";
	{
		if ((_x getVariable ["SWLC_leg", ""]) == "FOOT") then {
			[_x, "Assaulting", [_target] call SWLC_fnc_adPos, "assault"] call SWLC_fnc_setState;
			[_x, [_target] call SWLC_fnc_sweepOrder, "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
		};
	} forEach _live;
	[_cmd, _w, _live] call SWLC_fnc_smartSmoke;
	_w set ["phase", "ASSAULT"];
	_w set ["assaultStart", time];
	_w set ["lastProgress", time];
	["C_WAVE", [["side", _cmd get "side"], ["wave", _w get "id"], ["event", "assault"], ["groups", count _live], ["all_in", _allIn], ["hold_time", round (time - (_w get "launched"))]]] call SWLC_fnc_log;
};

SWLC_fnc_waveAssault = {
	params ["_cmd", "_w", "_live"];
	private _target = _w get "target";
	private _active = false;
	[_cmd, _w, _live] call SWLC_fnc_waveVehicleLegs;
	{
		private _g = _x;
		private _inside = [_target, getPosATL leader _g] call SWLC_fnc_adInSquare;
		if (_inside || {(behaviour leader _g) == "COMBAT"}) then {_active = true};
		// Waypoints used up: keep sweeping until the sector flips.
		if ((_g getVariable ["SWLC_leg", ""]) == "FOOT" && {[_g] call SWLC_fnc_adOrderDone}) then {
			[_g, [_target] call SWLC_fnc_sweepOrder, "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
		};
	} forEach _live;
	if (_active) then {_w set ["lastProgress", time]};
	if ((time - (_w get "lastProgress")) >= CFG("waveNoProgressSeconds")) then {
		[_cmd, _w, "no_progress"] call SWLC_fnc_waveResolve;
	};
};

SWLC_fnc_waveResolve = {
	params ["_cmd", "_w", "_result"];
	private _side = _cmd get "side";
	private _live = [_w] call SWLC_fnc_waveLive;
	private _men = [_live] call SWLC_fnc_groupsMen;
	["C_WAVE", [["side", _side], ["wave", _w get "id"], ["event", "resolved"], ["result", _result], ["men_left", _men], ["men_launched", _w get "launchStrength"],
		["duration", round (time - (_w get "launched"))]]] call SWLC_fnc_log;
	_w set ["phase", "DONE"];
	_cmd set ["lastResult", _result];
	if (_result == "seized") then {
		_cmd set ["lastCaptureAt", time];
		[_side, "seized", [[_w get "target"] call SWLC_fnc_adName]] call SWLC_fnc_radio;
	};
	if (_result in ["attrition", "no_progress"]) then {[_side, "failed"] call SWLC_fnc_radio};

	{
		_x setVariable ["SWLC_waveId", -1];
		[_cmd, _x] call SWLC_fnc_vehRelease;
		if (_result in ["attrition", "no_progress"]) then {
			if (!isNil {_cmd get "gather"}) then {
				[_cmd, _x, "Regrouping"] call SWLC_fnc_sendToStaging;
			} else {
				[_x, "Unassigned", [], "wave_failed"] call SWLC_fnc_setState;
			};
		} else {
			[_x] call SWLC_fnc_adClearOrder;
			[_x, "Unassigned", [], "wave_over"] call SWLC_fnc_setState;
		};
	} forEach _live;
	if (_result == "seized") then {[_cmd, _w, _live] call SWLC_fnc_smartOnSeized};
};
