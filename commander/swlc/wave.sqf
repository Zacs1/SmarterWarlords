// The attack on the current target. Groups muster at their own sectors (staging.sqf), meet at one rally
// point outside the target on the side they're coming from, and go in together. Later arrivals reinforce.
#include "macros.hpp"

// Bearing from the target towards where the attackers are coming from.
SWLC_fnc_opBearing = {
	params ["_cmd", "_target"];
	private _side = _cmd get "side";
	private _tpos = [_target] call SWLC_fnc_adPos;
	private _groups = (_cmd get "groups") select {!(([_x] call SWLC_fnc_state) in ["Reserve", "Defending", "Raiding", "Probing", "Picket", "Borrowed", "Pickup"])};
	private _sx = 0;
	private _sy = 0;
	{
		private _b = [_tpos, getPosATL leader _x] call SWLC_fnc_bearing;
		_sx = _sx + sin _b;
		_sy = _sy + cos _b;
	} forEach _groups;
	// Groups on opposite sides cancel out; then the side's nearest ground is the better guide.
	if (_groups isNotEqualTo [] && {sqrt (_sx * _sx + _sy * _sy) >= CFG("rallyMinAgreement") * (count _groups)}) exitWith {_sx atan2 _sy};
	private _owned = [_side] call SWLC_fnc_adOwned;
	private _from = if (_owned isEqualTo []) then {[[_side] call SWLC_fnc_adBase] call SWLC_fnc_adPos} else {
		[([_owned, _tpos] call SWLC_fnc_adNearest)] call SWLC_fnc_adPos
	};
	[_tpos, _from] call SWLC_fnc_bearing
};

SWLC_fnc_waveNew = {
	params ["_cmd"];
	private _id = (_cmd get "waveCounter") + 1;
	_cmd set ["waveCounter", _id];
	private _target = _cmd get "target";
	private _tpos = [_target] call SWLC_fnc_adPos;
	private _bearing = [_cmd, _target, [_cmd, _target] call SWLC_fnc_opBearing] call SWLC_fnc_smartAvoid;
	private _d = ([_target] call SWLC_fnc_adSize) / 2 + CFG("rallyOutside");
	private _rally = [_cmd get "side", _tpos, _bearing, _d] call SWLC_fnc_validHoldPoint;
	["C_WAVE", [["side", _cmd get "side"], ["wave", _id], ["event", "new"], ["target", [_target] call SWLC_fnc_adName], ["bearing", round _bearing], ["x", round (_rally # 0)], ["y", round (_rally # 1)]]] call SWLC_fnc_log;
	createHashMapFromArray [
		["id", _id],
		["target", _target],
		["tpos", _tpos],
		["bearing", _bearing],
		["rally", _rally],
		["phase", "RALLY"],
		["groups", []],
		["firstAtRally", -1],
		["launched", -1],
		["launchStrength", 0],
		["lastProgress", time],
		["created", time]
	]
};

SWLC_fnc_waveRemoveGroup = {
	params ["_cmd", "_g"];
	private _op = _cmd get "op";
	if (!isNil "_op") then {
		private _i = (_op get "groups") find _g;
		if (_i >= 0) then {(_op get "groups") deleteAt _i};
		if (([_g] call SWLC_fnc_state) == "Assaulting") then {
			_op set ["launchStrength", ((_op get "launchStrength") - ([_g] call SWLC_fnc_groupMen)) max 0];
		};
	};
	{
		private _rec = _y;
		{
			private _list = _rec get _x;
			private _i = _list find _g;
			if (_i >= 0) then {_list deleteAt _i};
		} forEach ["groups", "batch"];
	} forEach (_cmd get "musters");
	_g setVariable ["SWLC_waveId", -1];
	[_cmd, _g] call SWLC_fnc_vehRelease;
};

// Live groups of the operation that are still its own.
SWLC_fnc_waveLive = {
	params ["_w"];
	(_w get "groups") select {({alive _x} count units _x) > 0 && {(_x getVariable ["SWLC_waveId", -1]) == (_w get "id")}}
};

// The operation's tick comes in three parts, each in its own frame: this, each muster (cmdMusterSlices), then waveTail.
SWLC_fnc_waveHead = {
	params ["_cmd"];
	[_cmd] call SWLC_fnc_musterSweep;
	private _op = _cmd get "op";
	if (isNil "_op") exitWith {};
	private _target = _op get "target";
	if (([_target] call SWLC_fnc_adOwner) == (_cmd get "side")) exitWith {[_cmd, "seized"] call SWLC_fnc_waveResolve};
	if ((_cmd get "target") isNotEqualTo _target) exitWith {[_cmd, "target_changed"] call SWLC_fnc_waveResolve};
	[_cmd, _op] call SWLC_fnc_wavePlan;
	[_cmd, _op] call SWLC_fnc_musterArrivals;
};

SWLC_fnc_waveTail = {
	params ["_cmd"];
	private _op = _cmd get "op";
	if (isNil "_op") exitWith {};
	private _live = [_op] call SWLC_fnc_waveLive;
	[_cmd, _op, _live] call SWLC_fnc_waveVehicleLegs;
	[_cmd, _op, _live] call SWLC_fnc_rallyArrivals;
	[_cmd, _op, _live] call SWLC_fnc_rallyTick;
};

// What the groups should bring, from the threat summary. Never affects how long they wait.
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
	[_w, _plan] call SWLC_fnc_stratPlan;
	private _sig = [_plan get "atWanted", _plan get "combatVehicle", _plan get "aa", _plan get "smoke", _plan get "scan"];
	if (_sig isNotEqualTo (_w getOrDefault ["planSig", []])) then {
		_w set ["planSig", _sig];
		["C_PLAN", [["side", _cmd get "side"], ["wave", _w get "id"], ["at_wanted", _sig # 0], ["combat_vehicle", _sig # 1], ["aa", _sig # 2], ["smoke", _sig # 3], ["scan", _sig # 4]]] call SWLC_fnc_log;
	};
	_w set ["plan", _plan];
	_plan
};

// Rotates up to +-75 degrees to keep the point on land and out of restricted sectors.
SWLC_fnc_validHoldPoint = {
	params ["_side", "_tpos", "_bearing", "_d"];
	private _found = [];
	{
		private _p = [_tpos, _bearing + _x, _d] call SWLC_fnc_offset;
		if (!surfaceIsWater _p && {!([_side, _p, 50] call SWLC_fnc_adRestricted)}) exitWith {_found = _p};
	} forEach [0, 15, -15, 30, -30, 45, -45, 60, -60, 75, -75];
	if (_found isEqualTo []) then {_found = [_tpos, _bearing, _d] call SWLC_fnc_offset};
	_found
};

// Resets what a group remembers from its last attack.
SWLC_fnc_waveGroupStart = {
	params ["_g"];
	_g setVariable ["SWLC_leg", ""];
	_g setVariable ["SWLC_legLost", false];
	_g setVariable ["SWLC_legAbandon", false];
	_g setVariable ["SWLC_launchMen", [_g] call SWLC_fnc_groupMen];
	_g setVariable ["SWLC_broke", false];
	_g setVariable ["SWLC_restUntil", -1];
	_g setVariable ["SWLC_reinforced", false];
	_g setVariable ["SWLC_bestD", 1e9];
	_g setVariable ["SWLC_bestAt", time];
	_g setVariable ["SWLC_heavyCalled", false];
	if (CFG("smartSmoke") && {alive leader _g} && {((magazines leader _g) findIf {_x isKindOf ["SmokeShell", configFile >> "CfgMagazines"]}) < 0}) then {
		(leader _g) addMagazines ["SmokeShell", 2];
	};
};

SWLC_fnc_groupReady = {
	params ["_g"];
	!([_g] call SWLC_fnc_kitPending) && {[_g] call SWLC_fnc_vehAboard}
};

// Sends a group off on its leg: driving to the dismount point, a combat vehicle to the rally, or walking.
SWLC_fnc_waveSendGroup = {
	params ["_cmd", "_op", "_g"];
	private _rec = [_g] call SWLC_fnc_vehRecOf;
	if (count _rec > 0 && {(_rec get "role") == "combat"}) exitWith {
		_g setVariable ["SWLC_leg", "FOLLOW"];
		_rec set ["state", "moving"];
		[_g, "Advancing", _op get "rally", "to_rally"] call SWLC_fnc_setState;
		[_g, [[_op get "rally", "MOVE", 40]], "AWARE", "NORMAL", "COLUMN", "RED"] call SWLC_fnc_adSetOrder;
	};
	if (count _rec > 0) exitWith {
		private _dismount = [_cmd, _op] call SWLC_fnc_waveDismount;
		_g setVariable ["SWLC_leg", "DRIVE"];
		_g setVariable ["SWLC_dismount", _dismount];
		_rec set ["state", "moving"];
		[_g, "Advancing", _dismount, "drive"] call SWLC_fnc_setState;
		[_g, [[_dismount, "MOVE", 30]], "SAFE", "NORMAL", "COLUMN", "YELLOW"] call SWLC_fnc_adSetOrder;
	};
	[_cmd, _op, _g] call SWLC_fnc_waveFootOrder;
};

// Where vehicles stop. Worked out from current intel, and reused for a minute.
SWLC_fnc_waveDismount = {
	params ["_cmd", "_op"];
	if ((time - (_op getOrDefault ["dismountAt", -1e6])) >= 60) then {
		_op set ["dismount", [_cmd, _op get "target", _op get "bearing"] call SWLC_fnc_makeDismount];
		_op set ["dismountAt", time];
	};
	_op get "dismount"
};

SWLC_fnc_waveFootOrder = {
	params ["_cmd", "_op", "_g"];
	_g setVariable ["SWLC_leg", "FOOT"];
	[_g, "Advancing", _op get "rally", "to_rally"] call SWLC_fnc_setState;
	[_g, [[_op get "rally", "MOVE", 30]]] call SWLC_fnc_adSetOrder;
};

// One sector's groups leave together. Anyone not ready at the cap follows when it can.
SWLC_fnc_waveDepart = {
	params ["_cmd", "_op", "_rec", "_batch"];
	if (_batch isEqualTo []) exitWith {_rec set ["batch", []]};
	// A copy: a group that fails while it's being sent is taken out of the real list.
	_batch = +_batch;
	[_cmd, _op, _batch] call SWLC_fnc_kitFinish;
	private _riding = 0;
	private _walking = 0;
	private _late = 0;
	{
		private _g = _x;
		[_cmd, _g, "waveDepart", {
			if ([_g] call SWLC_fnc_groupReady) then {
				[_cmd, _op, _g] call SWLC_fnc_waveSendGroup;
				if (count ([_g] call SWLC_fnc_vehRecOf) > 0) then {_riding = _riding + 1} else {_walking = _walking + 1};
			} else {
				_g setVariable ["SWLC_leg", "LATE"];
				_late = _late + 1;
			};
		}] call SWLC_fnc_resGuarded;
	} forEach _batch;
	_rec set ["batch", []];
	["C_WAVE", [["side", _cmd get "side"], ["wave", _op get "id"], ["event", "depart"], ["sector", _rec get "name"], ["mount_s", round (time - (_rec get "goTime"))], ["riding", _riding], ["walking", _walking], ["late", _late],
		["worth_driving", [_cmd, _op, _rec get "pos"] call SWLC_fnc_vehWorthDriving], ["at_launchers", [_batch] call SWLC_fnc_kitCountAT], ["at_wanted", (_op get "plan") get "atWanted"]]] call SWLC_fnc_log;
	[_cmd get "side", "leaving", [_rec get "name", [_op get "target"] call SWLC_fnc_adName], _batch # 0] call SWLC_fnc_radio;
};

// Per-group vehicle legs, run throughout the attack.
SWLC_fnc_waveVehicleLegs = {
	params ["_cmd", "_op", "_live"];
	{
		private _g = _x;
		[_cmd, _g, "waveLegs", {
			// Fighting on the way: the legs carry on when the fight is over.
			if (([_g] call SWLC_fnc_state) == "Engaged") exitWith {};
			switch (_g getVariable ["SWLC_leg", ""]) do {
				case "LATE": {
					[_cmd, _g] call SWLC_fnc_vehMountGroup;
					private _deadline = (_g getVariable ["SWLC_mountGo", time]) + CFG("mountCapSeconds") + CFG("mountLateExtra");
					if ([_g] call SWLC_fnc_groupReady) then {
						[_cmd, _op, _g] call SWLC_fnc_waveSendGroup;
					} else {
						if (time >= _deadline) then {
							private _rec = [_g] call SWLC_fnc_vehRecOf;
							if (count _rec > 0 && {(_rec get "state") != "arriving"}) then {
								[_g] call SWLC_fnc_vehForceBoard;
								[_cmd, _op, _g] call SWLC_fnc_waveSendGroup;
							} else {
								if (count _rec > 0) then {
									["C_VEH", [["side", _cmd get "side"], ["id", _rec get "id"], ["event", "left_unused"], ["group", groupId _g]]] call SWLC_fnc_log;
									_rec set ["group", grpNull];
									_rec set ["state", "parked"];
									_g setVariable ["SWLC_rec", createHashMap];
								};
								[_cmd, _op, _g] call SWLC_fnc_waveFootOrder;
							};
						};
					};
				};
				case "DRIVE": {
					if ((_g getVariable ["SWLC_legAbandon", false]) || {_g getVariable ["SWLC_legLost", false]}) then {
						_g setVariable ["SWLC_legAbandon", false];
						_g setVariable ["SWLC_legLost", false];
						[_cmd, _g, "abandoned"] call SWLC_fnc_vehDismount;
						[_cmd get "side", "stuck", [], _g] call SWLC_fnc_radio;
						[_cmd, _op, _g] call SWLC_fnc_waveFootOrder;
					} else {
						if (((leader _g) distance2D (_g getVariable "SWLC_dismount")) <= CFG("dismountArriveRadius") || {[_g] call SWLC_fnc_adOrderDone}) then {
							[_cmd, _g, "dismount"] call SWLC_fnc_vehDismount;
							[_cmd, _op, _g] call SWLC_fnc_waveFootOrder;
						};
					};
				};
				case "FOLLOW": {
					if ((_g getVariable ["SWLC_legLost", false]) || {_g getVariable ["SWLC_legAbandon", false]}) then {
						_g setVariable ["SWLC_legAbandon", false];
						_g setVariable ["SWLC_legLost", false];
						[_cmd, _g, "abandoned"] call SWLC_fnc_vehDismount;
						if (([_g] call SWLC_fnc_state) == "Assaulting") then {
							_g setVariable ["SWLC_leg", "FOOT"];
							[_g, [_op get "target"] call SWLC_fnc_sweepOrder, "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
						} else {
							[_cmd, _op, _g] call SWLC_fnc_waveFootOrder;
						};
					};
				};
			};
		}] call SWLC_fnc_resGuarded;
	} forEach _live;
	[_cmd, _op, _live] call SWLC_fnc_vehFollowTick;
};

// Who has reached the rally.
SWLC_fnc_rallyArrivals = {
	params ["_cmd", "_op", "_live"];
	private _rally = _op get "rally";
	private _r = CFG("holdArriveRadius");
	{
		private _g = _x;
		[_cmd, _g, "rallyArrivals", {
			private _st = [_g] call SWLC_fnc_state;
			if (_st == "Regrouping" || {_st == "Advancing" && {(_g getVariable ["SWLC_leg", ""]) in ["FOOT", "FOLLOW"]}}) then {
				if ((leader _g distance2D _rally) <= _r || {[_g] call SWLC_fnc_adOrderDone}) then {
					if (_st == "Regrouping") then {_g setVariable ["SWLC_restUntil", time + CFG("breakRestSeconds")]};
					[_g, "Waiting", _rally, "at_rally"] call SWLC_fnc_setState;
					["C_WAVE", [["side", _cmd get "side"], ["wave", _op get "id"], ["event", "rally_arrival"], ["group", groupId _g], ["from", _st]]] call SWLC_fnc_log;
					[_cmd get "side", "rally", [], _g] call SWLC_fnc_radio;
				};
			};
		}] call SWLC_fnc_resGuarded;
	} forEach _live;
};

// True while a player of this side is in or right next to the sector.
SWLC_fnc_playersFighting = {
	params ["_side", "_target"];
	(allPlayers findIf {alive _x && {side group _x == _side} && {[_target, getPosATL _x, 100] call SWLC_fnc_adInSquare}}) >= 0
};

// The go rule. Two groups ready go together; with friends already fighting, a group goes in on its own;
// a lone group with nobody to join waits, then goes anyway.
// Groups peeled off to answer a raid can leave too few to attack. The wave then waits at the rally for them,
// for a limited time. A push already in progress carries on.
SWLC_fnc_rallyPeelHold = {
	params ["_cmd", "_op", "_live"];
	if !([] call SWLC_fnc_propOn) exitWith {false};
	if ((_op get "phase") == "ASSAULT") exitWith {false};
	private _away = {
		((_x getVariable ["SWLC_peeledOp", -1]) == (_op get "id") && {([_x] call SWLC_fnc_state) == "Defending"})
		|| {(time - (_x getVariable ["SWLC_peeledBackAt", -1e6])) < CFG("peelReturnGrace") && {!(_x in _live)}}
	} count (_cmd get "groups");
	if (_away == 0 || {(count _live) >= CFG("peelWorkableGroups")}) exitWith {false};
	private _max = CFG("peelHoldMaxSeconds");
	if ((time - (_op getOrDefault ["peelHoldSince", -1e6])) >= 3 * _max) then {
		_op set ["peelHoldSince", time];
		["C_WAVE", [["side", _cmd get "side"], ["wave", _op get "id"], ["event", "peel_hold"], ["away", _away], ["live", count _live]]] call SWLC_fnc_log;
		[_cmd get "side", "peelhold", [[_op get "target"] call SWLC_fnc_adName]] call SWLC_fnc_radio;
	};
	(time - (_op get "peelHoldSince")) < _max
};

SWLC_fnc_rallyTick = {
	params ["_cmd", "_op", "_live"];
	private _side = _cmd get "side";
	private _target = _op get "target";
	private _attackers = _live select {([_x] call SWLC_fnc_state) == "Assaulting"};
	private _waiting = _live select {([_x] call SWLC_fnc_state) == "Waiting"};

	if ((_op get "phase") == "ASSAULT") then {
		private _over = [_cmd, _op, _attackers] call SWLC_fnc_assaultTick;
		if (_over != "") then {
			[_cmd, _op, _attackers, _over] call SWLC_fnc_pushOver;
		};
	};

	if (_op getOrDefault ["holdGo", false]) exitWith {};
	if (time < (_op getOrDefault ["playerHoldUntil", -1])) exitWith {};
	if ([_cmd, _op, _live] call SWLC_fnc_rallyPeelHold) exitWith {};
	private _ready = _waiting select {time >= (_x getVariable ["SWLC_restUntil", -1])};
	if (_ready isEqualTo []) exitWith {
		if (_waiting isEqualTo []) then {_op set ["firstAtRally", -1]};
	};

	if ((_op get "phase") == "ASSAULT" || {[_side, _target] call SWLC_fnc_playersFighting}) exitWith {
		_op set ["forceGo", false];
		_op set ["firstAtRally", -1];
		if ((_op get "phase") != "ASSAULT") then {[_cmd, _op] call SWLC_fnc_pushStart};
		{
			[_cmd, _x, "waveReinforce", {
				[_cmd, _op, _x] call SWLC_fnc_waveGoIn;
				["C_WAVE", [["side", _side], ["wave", _op get "id"], ["event", "reinforce"], ["group", groupId _x]]] call SWLC_fnc_log;
				[_side, "reinforce", [[_target] call SWLC_fnc_adName], _x] call SWLC_fnc_radio;
			}] call SWLC_fnc_resGuarded;
		} forEach _ready;
	};

	if ((_op get "firstAtRally") < 0) then {_op set ["firstAtRally", time]};
	private _waited = time - (_op get "firstAtRally");
	private _forced = _op getOrDefault ["forceGo", false];
	private _byCount = (count _ready) >= ([_cmd, _op] call SWLC_fnc_stratGoCount);
	private _byTimer = _waited >= ([_cmd, _op] call SWLC_fnc_rallyLoneWait);
	if !(_byCount || {_byTimer} || {_forced}) exitWith {};
	if ([_cmd, _op] call SWLC_fnc_smartPrepFire) exitWith {};

	_op set ["forceGo", false];
	_op set ["firstAtRally", -1];
	[_cmd, _op] call SWLC_fnc_pushStart;
	{[_cmd, _x, "waveGoIn", {[_cmd, _op, _g] call SWLC_fnc_waveGoIn}] call SWLC_fnc_resGuarded} forEach _ready;
	[_cmd, _op, _ready] call SWLC_fnc_smartSmoke;
	["C_WAVE", [["side", _side], ["wave", _op get "id"], ["event", "assault"], ["groups", count _ready], ["men", _op get "launchStrength"], ["target", [_target] call SWLC_fnc_adName],
		["by_timer", _byTimer && {!_byCount}], ["forced", _forced], ["wait", round _waited]]] call SWLC_fnc_log;
	[_side, "moveout", [count _ready, [_target] call SWLC_fnc_adName]] call SWLC_fnc_radio;
};

// How long a lone group waits at the rally before going in anyway.
SWLC_fnc_rallyLoneWait = {
	params ["_cmd", "_op"];
	private _momentum = _cmd getOrDefault ["momentum", []];
	if (_momentum isNotEqualTo [] && {(_momentum # 0) isEqualTo (_op get "target")} && {time < (_momentum # 1) + CFG("momentumGoWindow")}) exitWith {CFG("momentumGoWait")};
	private _base = ([] call SWLC_fnc_stratFortressOn) && {[_op get "target"] call SWLC_fnc_adIsBase};
	CFG("rallyLoneWait") * ([_cmd, "goWait"] call SWLC_fnc_persona) * ([1, CFG("stratBaseLoneWaitMult")] select _base)
};

SWLC_fnc_pushStart = {
	params ["_cmd", "_op"];
	_op set ["phase", "ASSAULT"];
	_op set ["launchStrength", 0];
	_op set ["assaultStart", time];
	_op set ["lastProgress", time];
	if ((_op get "launched") < 0) then {_op set ["launched", time]};
};

SWLC_fnc_waveGoIn = {
	params ["_cmd", "_op", "_g"];
	private _target = _op get "target";
	private _men = [_g] call SWLC_fnc_groupMen;
	_g setVariable ["SWLC_launchMen", _men];
	_op set ["launchStrength", (_op get "launchStrength") + _men];
	if ((_g getVariable ["SWLC_leg", ""]) == "FOLLOW") then {
		[_g, "Assaulting", getPosATL leader _g, "follow"] call SWLC_fnc_setState;
	} else {
		[_g, "Assaulting", [_target] call SWLC_fnc_adPos, "assault"] call SWLC_fnc_setState;
		[_g, [_target] call SWLC_fnc_sweepOrder, "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
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

// Returns "" while the assault goes on, or why it's over.
SWLC_fnc_assaultTick = {
	params ["_cmd", "_op", "_attackers"];
	if (_attackers isEqualTo []) exitWith {"wiped"};
	if (([_attackers] call SWLC_fnc_groupsMen) < CFG("waveFailStrength") * (_op get "launchStrength")) exitWith {"attrition"};
	private _target = _op get "target";
	private _active = false;
	{
		private _g = _x;
		[_cmd, _g, "assault", {
			if (([_target, getPosATL leader _g] call SWLC_fnc_adInSquare) || {(behaviour leader _g) == "COMBAT"}) then {_active = true};
			// Waypoints used up: keep sweeping until the sector flips.
			if ((_g getVariable ["SWLC_leg", ""]) == "FOOT" && {[_g] call SWLC_fnc_adOrderDone}) then {
				[_g, [_target] call SWLC_fnc_sweepOrder, "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
			};
		}] call SWLC_fnc_resGuarded;
	} forEach _attackers;
	if (_active) then {_op set ["lastProgress", time]};
	if ((time - (_op get "lastProgress")) >= CFG("waveNoProgressSeconds")) exitWith {"no_progress"};
	""
};

// An assault has failed but the target stands: survivors fall back to the rally for the next go.
SWLC_fnc_pushOver = {
	params ["_cmd", "_op", "_attackers", "_result"];
	private _side = _cmd get "side";
	[_cmd, _op, _attackers] call SWLC_fnc_smartRemember;
	["C_WAVE", [["side", _side], ["wave", _op get "id"], ["event", "push_over"], ["result", _result], ["men_left", [_attackers] call SWLC_fnc_groupsMen], ["men_launched", _op get "launchStrength"],
		["duration", round (time - (_op getOrDefault ["assaultStart", time]))]]] call SWLC_fnc_log;
	_cmd set ["lastResult", _result];
	if (_result in ["wiped", "attrition", "no_progress"]) then {_op set ["pushFails", (_op getOrDefault ["pushFails", 0]) + 1]};
	if (_result in ["attrition", "no_progress"]) then {[_side, "failed"] call SWLC_fnc_radio};
	_op set ["phase", "RALLY"];
	_op set ["launchStrength", 0];
	_op set ["firstAtRally", -1];
	_op set ["prepDone", false];
	_op set ["forceGo", false];
	{
		[_cmd, _x, "pushOver", {
			[_x, "Regrouping", _op get "rally", "fall_back"] call SWLC_fnc_setState;
			[_x, [[_op get "rally", "MOVE", 30]], "AWARE", "FULL", "WEDGE", "YELLOW"] call SWLC_fnc_adSetOrder;
		}] call SWLC_fnc_resGuarded;
	} forEach _attackers;
};

// The operation ends: the sector fell or the target changed. Every group goes back to the commander.
SWLC_fnc_waveResolve = {
	params ["_cmd", "_result"];
	private _op = _cmd get "op";
	if (isNil "_op") exitWith {};
	private _side = _cmd get "side";
	private _live = [_op] call SWLC_fnc_waveLive;
	private _near = _live select {(leader _x distance2D (_op get "tpos")) <= CFG("waveNearRadius")};
	[_cmd, _op, _live select {([_x] call SWLC_fnc_state) == "Assaulting"}] call SWLC_fnc_smartRemember;
	["C_WAVE", [["side", _side], ["wave", _op get "id"], ["event", "resolved"], ["result", _result], ["men_left", [_near] call SWLC_fnc_groupsMen], ["men_launched", _op get "launchStrength"],
		["duration", round (time - ((_op get "launched") max (_op get "created")))]]] call SWLC_fnc_log;
	_cmd set ["lastResult", _result];
	if (_result == "seized") then {
		_cmd set ["lastCaptureAt", time];
		[_side, "seized", [[_op get "target"] call SWLC_fnc_adName]] call SWLC_fnc_radio;
	};
	{
		[_cmd, _x, "waveResolve", {
			_x setVariable ["SWLC_waveId", -1];
			[_cmd, _x] call SWLC_fnc_vehRelease;
			[_x] call SWLC_fnc_adClearOrder;
			[_x, "Unassigned", [], "wave_over"] call SWLC_fnc_setState;
		}] call SWLC_fnc_resGuarded;
	} forEach (_live select {([_x] call SWLC_fnc_state) != "Engaged"}); // a fight on the road finishes first, and ends itself
	{
		private _rec = _y;
		_rec set ["groups", []];
		_rec set ["batch", []];
		_rec set ["firstArrive", -1];
	} forEach (_cmd get "musters");
	if (_result == "seized") then {[_cmd, _op, _near] call SWLC_fnc_smartOnSeized};
	_cmd deleteAt "op";
};
