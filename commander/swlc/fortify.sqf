// Defenders fortify. Server only. [_cmd] call SWLC_fnc_fortifyTick as a commander stage.
//
// Reads the alert record (_cmd getOrDefault ["alert", createHashMap]) and nothing else for the threat. No alert, no spending.
// Buys Warlords Defences statics on the side of the sector the attack is coming from, seats men from the alert's main
// position in them, replaces a dead gunner, and puts AT soldiers beside the approach road. When the alert ends the guns
// stay and the men go back to their group.
//
// Men stay in their own group the whole time, so SWLC_order and the group's waypoints are never touched.
// A man on a gun carries SWLC_fortGun, a man on the road carries SWLC_fortAT; upkeep.sqf leaves both alone.
// Every number is in settings.sqf under fortify*. Spec and decisions: docs/runs/2026-11-09-front-line/notes/part-fortify.md.

#include "macros.hpp"

SWLC_fnc_fortLog = {
	params ["_cmd", "_event", ["_fields", []]];
	["C_FORT", [["side", _cmd get "side"], ["event", _event]] + _fields] call SWLC_fnc_log;
};

// A hashmap kept on the commander record, made the first time it is asked for.
SWLC_fnc_fortMap = {
	params ["_cmd", "_key"];
	private _m = _cmd getOrDefault [_key, []];
	if (_m isEqualType []) then {_m = createHashMap; _cmd set [_key, _m]};
	_m
};

// One line per sector and reason per minute: the same refusal repeats every tick while nothing has changed.
SWLC_fnc_fortRefuse = {
	params ["_cmd", "_sName", "_reason", ["_extra", []]];
	private _seen = [_cmd, "fortRefused"] call SWLC_fnc_fortMap;
	private _key = format ["%1|%2", _sName, _reason];
	if ((time - (_seen getOrDefault [_key, -1e6])) < CFG("fortifyRefuseLogSeconds")) exitWith {};
	_seen set [_key, time];
	[_cmd, "refuse", [["sector", _sName], ["reason", _reason]] + _extra] call SWLC_fnc_fortLog;
};

// The stance module may not be merged yet: until it is, the stance is whatever the commander record says.
SWLC_fnc_fortStance = {
	params ["_cmd"];
	if (isNil "SWLC_fnc_stanceOf") exitWith {_cmd getOrDefault ["stance", "attack"]};
	[_cmd] call SWLC_fnc_stanceOf
};

// A tunable with one value per stance: fortifyStaticsHold and so on. An unknown stance reads as attack, the cheapest.
SWLC_fnc_fortStanceNum = {
	params ["_cmd", "_stem"];
	private _stance = [_cmd] call SWLC_fnc_fortStance;
	private _name = _stem + (toUpper (_stance select [0, 1])) + (_stance select [1, 99]);
	SWLC_settings getOrDefault [_name, SWLC_settings get (_stem + "Attack")]
};

// Smallest angle between two bearings, 0 to 180.
SWLC_fnc_fortAngle = {
	params ["_a", "_b"];
	abs ((((_a - _b) + 540) % 360) - 180)
};

// "MG", "GL", "AT" or "" for anything the defence doesn't use (autonomous guns, AA, radar, mortars).
// By class name, because Warlords' list says only "Defences". The catalog line in the log shows how each class was read.
SWLC_fnc_fortKindOf = {
	params ["_class"];
	private _cfg = configFile >> "CfgVehicles" >> _class;
	if !(isClass _cfg) exitWith {""};
	if !(_class isKindOf "StaticWeapon") exitWith {""};
	if ((getNumber (_cfg >> "isUav")) == 1) exitWith {""};
	private _low = toLower _class;
	if ("_aa_" in _low || {"sam_" in _low} || {"radar" in _low}) exitWith {""};
	if ("_at_" in _low) exitWith {"AT"};
	if ("gmg" in _low) exitWith {"GL"};
	if ("mg" in _low) exitWith {"MG"};
	""
};

// [[class, cost, kind], ...] for this side. Built once, and logged once whether or not an alert ever comes.
SWLC_fnc_fortCatalog = {
	params ["_cmd"];
	if (_cmd getOrDefault ["fortCatalogDone", false]) exitWith {_cmd getOrDefault ["fortCatalog", []]};
	private _list = [_cmd get "side", 3] call SWLC_fnc_adPurchasable;
	if (_list isEqualTo []) exitWith {[]};
	private _cat = [];
	{
		_x params ["_class", "_cost"];
		private _kind = [_class] call SWLC_fnc_fortKindOf;
		[_cmd, "catalog", [["class", _class], ["cost", _cost], ["kind", [_kind, "none"] select (_kind == "")]]] call SWLC_fnc_fortLog;
		if (_kind != "") then {_cat pushBack [_class, _cost, _kind]};
	} forEach _list;
	private _kinds = _cat apply {_x # 2};
	[_cmd, "catalog_summary", [["mg", "MG" in _kinds], ["gl", "GL" in _kinds], ["at", "AT" in _kinds], ["usable", count _cat]]] call SWLC_fnc_fortLog;
	_cmd set ["fortCatalog", _cat];
	_cmd set ["fortCatalogDone", true];
	_cat
};

// Guns bought for this sector, live and recently lost. The list is the one stored on the commander record.
SWLC_fnc_fortRecords = {
	params ["_cmd", "_sName"];
	private _all = [_cmd, "fort"] call SWLC_fnc_fortMap;
	private _list = _all getOrDefault [_sName, []];
	_all set [_sName, _list];
	_list
};

// What counts against the cap. A gun destroyed a moment ago still counts, so a contested sector can't be used to drain CP.
SWLC_fnc_fortCount = {
	params ["_recs"];
	private _keep = CFG("fortifyReplaceSeconds");
	{alive (_x get "gun") || {(time - (_x get "lostAt")) < _keep}} count _recs
};

SWLC_fnc_fortTrack = {
	params ["_cmd", "_sName"];
	private _recs = [_cmd, _sName] call SWLC_fnc_fortRecords;
	{
		private _rec = _x;
		if (!alive (_rec get "gun") && {(_rec get "lostAt") < 0}) then {
			_rec set ["lostAt", time];
			[_cmd, "gun_lost", [["sector", _sName], ["class", _rec get "class"], ["kind", _rec get "kind"]]] call SWLC_fnc_fortLog;
			[_cmd, _rec, "gun_lost"] call SWLC_fnc_fortReleaseGun;
		};
	} forEach _recs;
	private _keep = CFG("fortifyReplaceSeconds");
	private _still = _recs select {alive (_x get "gun") || {(time - (_x get "lostAt")) < _keep}};
	_recs resize 0;
	_recs append _still;
};

// Crew.

SWLC_fnc_fortEligible = {
	params ["_u"];
	alive _u
	&& {!isPlayer _u}
	&& {isNull objectParent _u}
	&& {!((leader group _u) isEqualTo _u)}
	&& {([secondaryWeapon _u] call SWLC_fnc_adLauncherKind) != "AT"}
	&& {(_u getVariable ["SWLC_kitTask", ""]) == ""}
	&& {isNull (_u getVariable ["SWLC_fortGun", objNull])}
	&& {(_u getVariable ["SWLC_fortAT", []]) isEqualTo []}
	&& {_u checkAIFeature "PATH"} // LAMBS has garrisoned him: he is holding a position already and can't walk to a gun
};

SWLC_fnc_fortCrewPool = {
	params ["_cmd", "_groups"];
	private _pool = [];
	private _max = CFG("fortifyMaxCrewPerGroup");
	{
		private _g = _x;
		if ([_g] call SWLC_fnc_resMayTouch) then {
			private _busy = {alive _x && {!isNull (_x getVariable ["SWLC_fortGun", objNull])}} count units _g;
			if (_busy < _max) then {
				{
					if ([_x] call SWLC_fnc_fortEligible) then {_pool pushBack _x};
				} forEach units _g;
			};
		};
	} forEach _groups;
	_pool
};

// Still a man this module is allowed to hold on a gun.
SWLC_fnc_fortStillOurs = {
	params ["_u", "_groups"];
	(group _u) in _groups && {[group _u] call SWLC_fnc_resMayTouch}
};

SWLC_fnc_fortManId = {
	params ["_u"];
	format ["%1/%2", groupId group _u, (units group _u) find _u]
};

SWLC_fnc_fortAssign = {
	params ["_cmd", "_rec", "_u"];
	private _gun = _rec get "gun";
	_u setVariable ["SWLC_fortGun", _gun];
	_u assignAsGunner _gun;
	[_u] orderGetIn true;
	private _d = _u distance2D _gun;
	_rec set ["gunner", _u];
	_rec set ["seated", false];
	_rec set ["tries", 0];
	_rec set ["walkUntil", time + CFG("fortifyCrewWalkSeconds") + (_d / CFG("fortifyCrewWalkSpeed"))];
	[_cmd, "crew_assign", [["sector", _rec get "sector"], ["class", _rec get "class"], ["man", [_u] call SWLC_fnc_fortManId], ["dist", round _d]]] call SWLC_fnc_fortLog;
};

// Frees the man the record holds, if any, and sends him back to his group unless his group has gone to a player since.
SWLC_fnc_fortReleaseGun = {
	params ["_cmd", "_rec", "_why"];
	private _u = _rec getOrDefault ["gunner", objNull];
	_rec set ["gunner", objNull];
	_rec set ["seated", false];
	_rec set ["tries", 0];
	if (isNull _u) exitWith {};
	_u setVariable ["SWLC_fortGun", nil];
	[_cmd, "crew_release", [["sector", _rec get "sector"], ["class", _rec get "class"], ["why", _why], ["man", [_u] call SWLC_fnc_fortManId]]] call SWLC_fnc_fortLog;
	if (!alive _u || {isPlayer _u}) exitWith {};
	private _g = group _u;
	if !([_g] call SWLC_fnc_resMayTouch) exitWith {};
	unassignVehicle _u;
	[_u] orderGetIn false;
	if (!isNull objectParent _u) then {doGetOut _u};
	if ((_g getVariable ["SWLC_lambsTask", ""]) == "") then {_u doFollow leader _g};
};

// One gun, one tick.
SWLC_fnc_fortCrewOne = {
	params ["_cmd", "_rec", "_groups", "_sName"];
	private _gun = _rec get "gun";
	private _man = _rec getOrDefault ["gunner", objNull];
	private _hadMan = !isNull _man;
	private _seat = gunner _gun;

	// A dead gunner's body holds the seat until it is taken out.
	if (!isNull _seat && {!alive _seat}) then {
		_gun deleteVehicleCrew _seat;
		_seat = objNull;
	};

	// Anyone alive on the gun, ours or not, means it is crewed.
	if (alive _seat) exitWith {
		if (_seat isEqualTo _man) then {
			if !(_rec getOrDefault ["seated", false]) then {
				_rec set ["seated", true];
				[_cmd, "crew_in", [["sector", _sName], ["class", _rec get "class"], ["man", [_man] call SWLC_fnc_fortManId], ["after", round (time - (_rec getOrDefault ["placedAt", time]))]]] call SWLC_fnc_fortLog;
			};
			if !([_man, _groups] call SWLC_fnc_fortStillOurs) then {[_cmd, _rec, "group_left"] call SWLC_fnc_fortReleaseGun};
		} else {
			if (_hadMan) then {[_cmd, _rec, "seat_taken"] call SWLC_fnc_fortReleaseGun};
		};
	};

	if (_hadMan) then {
		if (!alive _man) then {
			[_cmd, "crew_lost", [["sector", _sName], ["class", _rec get "class"]]] call SWLC_fnc_fortLog;
			_rec set ["gunner", objNull];
			_rec set ["seated", false];
			_rec set ["tries", 0];
		} else {
			private _why = "";
			if !([_man, _groups] call SWLC_fnc_fortStillOurs) then {
				_why = "group_left";
			} else {
				if (!isNull objectParent _man) then {_why = "in_other_vehicle"};
			};
			if (_why != "") then {
				[_cmd, _rec, _why] call SWLC_fnc_fortReleaseGun;
			} else {
				if (time >= (_rec get "walkUntil")) then {
					private _tries = _rec getOrDefault ["tries", 0];
					if ((_man distance2D _gun) <= CFG("fortifyCrewSeatDist") && {_tries < 2}) then {
						// He is right beside it and AI boarding has given up: put him in.
						_man moveInGunner _gun;
						_rec set ["tries", _tries + 1];
						_rec set ["walkUntil", time + 20];
					} else {
						[_cmd, "crew_timeout", [["sector", _sName], ["class", _rec get "class"], ["man", [_man] call SWLC_fnc_fortManId], ["dist", round (_man distance2D _gun)]]] call SWLC_fnc_fortLog;
						[_cmd, _rec, "timeout"] call SWLC_fnc_fortReleaseGun;
					};
				};
			};
		};
	};

	if !(isNull (_rec getOrDefault ["gunner", objNull])) exitWith {};

	private _reach = CFG("fortifyCrewReach");
	private _pool = ([_cmd, _groups] call SWLC_fnc_fortCrewPool) select {(_x distance2D _gun) <= _reach};
	if (_pool isEqualTo []) exitWith {
		[_cmd, _sName, "no_men", [["class", _rec get "class"]]] call SWLC_fnc_fortRefuse;
	};
	// Riflemen first: a man with no launcher at all, nearest of those, then the rest.
	private _ranked = _pool apply {[([0, 5000] select ((secondaryWeapon _x) != "")) + (_x distance2D _gun), _x]};
	_ranked sort true;
	[_cmd, _rec, (_ranked # 0) # 1] call SWLC_fnc_fortAssign;
};

// Buying.

// [[class, cost, kind] or [], anyAllowed]. Walks the mix from this gun's slot so a kind that can't be had gives way to the next.
SWLC_fnc_fortChoose = {
	params ["_cmd", "_cat", "_slot", "_budget", "_pos"];
	private _side = _cmd get "side";
	private _mix = CFG("fortifyMix");
	private _preferHigh = CFG("fortifyPreferHigh");
	private _anyAllowed = false;
	private _chosen = [];
	{
		private _kind = _mix # ((_slot + _forEachIndex) % (count _mix));
		private _opts = _cat select {(_x # 2) == _kind && {[_side, _x # 0, _pos] call SWLC_fnc_econAssetAllowed}};
		if (_opts isNotEqualTo []) then {_anyAllowed = true};
		private _priced = _opts apply {
			[
				[1, 0] select (_preferHigh && {"high" in (toLower (_x # 0))}),
				ceil ((_x # 1) * ([_side, _x # 0, _pos] call SWLC_fnc_econPriceMult)),
				_x # 0
			]
		};
		_priced = _priced select {(_x # 1) <= _budget};
		if (_priced isNotEqualTo []) exitWith {
			_priced sort true;
			_chosen = [(_priced # 0) # 2, (_priced # 0) # 1, _kind];
		};
	} forEach _mix;
	[_chosen, _anyAllowed]
};

// Clear terrain from gun height along the line of fire, out to fortifyCoverRange.
SWLC_fnc_fortSees = {
	params ["_p", "_aim"];
	private _to = _p getPos [CFG("fortifyCoverRange") min (_p distance2D _aim), _p getDir _aim];
	!(terrainIntersectASL [AGLToASL [_p # 0, _p # 1, 1.6], AGLToASL [_to # 0, _to # 1, 1.2]])
};

// [pos, seesTheApproach] or []. Walks out from the line of the approach; takes the first spot that can see along it,
// or if none can, the first valid one. Always in front of the centre, so never on the far side of the sector.
SWLC_fnc_fortFindSpot = {
	params ["_s", "_class", "_bearing", "_aim", "_recs", "_side"];
	private _c = [_s] call SWLC_fnc_adPos;
	private _r0 = ([_s] call SWLC_fnc_adSize) * CFG("fortifyEdgeFraction");
	private _minC = CFG("fortifyMinCentreDist");
	private _spacing = CFG("fortifySpacing");
	private _grad = CFG("fortifyMaxGradient");
	private _clear = CFG("fortifyRoadClear");
	private _existing = _recs apply {_x get "pos"};
	private _best = [];
	private _done = false;
	{
		if (_done) exitWith {};
		private _ang = _bearing + _x;
		{
			if (_done) exitWith {};
			private _cand = _c getPos [(_r0 + _x) max _minC, _ang];
			if (!surfaceIsWater _cand
				&& {[_s, _cand, -5] call SWLC_fnc_adInSquare}
				&& {!([_side, _cand, 10] call SWLC_fnc_adRestricted)}
				&& {!isOnRoad _cand}
				&& {(_cand nearRoads _clear) isEqualTo []}) then {
				private _p = _cand findEmptyPosition [0, 10, _class];
				if (_p isNotEqualTo []
					&& {!surfaceIsWater _p}
					&& {!isOnRoad _p}
					&& {(_p nearRoads _clear) isEqualTo []}
					&& {[_s, _p, -2] call SWLC_fnc_adInSquare}
					&& {(_p distance2D _c) >= _minC}
					&& {(_p isFlatEmpty [-1, -1, _grad, 3, 0, false]) isNotEqualTo []}
					&& {(_existing findIf {(_x distance2D _p) < _spacing}) < 0}
					&& {(_p nearEntities [["Man"], 4]) isEqualTo []}) then {
					if ([_p, _aim] call SWLC_fnc_fortSees) then {
						_best = [_p, true];
						_done = true;
					} else {
						if (_best isEqualTo []) then {_best = [_p, false]};
					};
				};
			};
		} forEach [0, -30, 30];
	} forEach [0, 20, -20, 40, -40, 60, -60];
	_best
};

// Straight at the approach point, unless that point is on top of the gun or off behind it: then along the bearing.
SWLC_fnc_fortDirFor = {
	params ["_p", "_bearing", "_aim"];
	private _d = _p getDir _aim;
	if ((_p distance2D _aim) < 15 || {([_d, _bearing] call SWLC_fnc_fortAngle) > 75}) then {_d = _bearing};
	_d
};

// Same creation as the economy's statics: CAN_COLLIDE and then set on the ground, so it doesn't spawn on top of something and get thrown.
SWLC_fnc_fortCreate = {
	params ["_class", "_pos", "_dir"];
	private _v = createVehicle [_class, _pos, [], 0, "CAN_COLLIDE"];
	if (isNull _v) exitWith {objNull};
	_v setDir _dir;
	_v setPosATL [_pos # 0, _pos # 1, 0];
	_v enableWeaponDisassembly false;
	_v
};

// Buys and places one gun if it can. True when it bought one.
SWLC_fnc_fortBuyOne = {
	params ["_cmd", "_s", "_sName", "_approach", "_groups"];
	private _side = _cmd get "side";
	_approach params ["_bearing", "_aim"];
	private _recs = [_cmd, _sName] call SWLC_fnc_fortRecords;
	private _cap = ([_cmd, "fortifyStatics"] call SWLC_fnc_fortStanceNum) min CFG("fortifyMaxPerSector");
	private _have = [_recs] call SWLC_fnc_fortCount;
	if (_have >= _cap) exitWith {
		[_cmd, _sName, "cap", [["have", _have], ["cap", _cap]]] call SWLC_fnc_fortRefuse;
		false
	};
	if (time < (([_cmd, "fortNextScan"] call SWLC_fnc_fortMap) getOrDefault [_sName, -1])) exitWith {false};
	private _c = [_s] call SWLC_fnc_adPos;
	private _front = _c getPos [([_s] call SWLC_fnc_adSize) * CFG("fortifyEdgeFraction"), _bearing];
	// Someone has to be near enough to get on it, or the gun stands empty for the enemy to take.
	private _reach = CFG("fortifyCrewReach");
	if ((([_cmd, _groups] call SWLC_fnc_fortCrewPool) findIf {(_x distance2D _front) <= _reach}) < 0) exitWith {
		[_cmd, _sName, "no_men"] call SWLC_fnc_fortRefuse;
		false
	};
	// The same rule Warlords holds a player to when placing a defence, and the same check as its fast travel.
	if (CFG("fortifyRespectEnemyNear") && {[_side, _front] call SWLC_fnc_adEnemyNear}) exitWith {
		[_cmd, _sName, "enemy_near"] call SWLC_fnc_fortRefuse;
		false
	};
	private _cat = _cmd getOrDefault ["fortCatalog", []];
	if (_cat isEqualTo []) exitWith {
		[_cmd, _sName, "catalog_empty"] call SWLC_fnc_fortRefuse;
		false
	};
	private _free = [_side] call SWLC_fnc_cpFree;
	private _budget = _free * ([_cmd, "fortifyCpFraction"] call SWLC_fnc_fortStanceNum);
	([_cmd, _cat, count _recs, _budget, _front] call SWLC_fnc_fortChoose) params ["_chosen", "_anyAllowed"];
	if (_chosen isEqualTo []) exitWith {
		[_cmd, _sName, ["not_allowed", "funds"] select _anyAllowed, [["budget", round _budget], ["free", round _free]]] call SWLC_fnc_fortRefuse;
		false
	};
	_chosen params ["_class", "_cost", "_kind"];

	private _found = [_s, _class, _bearing, _aim, _recs, _side] call SWLC_fnc_fortFindSpot;
	if (_found isEqualTo []) exitWith {
		([_cmd, "fortNextScan"] call SWLC_fnc_fortMap) set [_sName, time + CFG("fortifyNoSpotRetry")];
		[_cmd, _sName, "no_spot", [["class", _class]]] call SWLC_fnc_fortRefuse;
		false
	};
	_found params ["_spot", "_sees"];

	private _before = [_side] call SWLC_fnc_adSideCP;
	if !([_side, _cost] call SWLC_fnc_adDebit) exitWith {
		[_cmd, _sName, "funds", [["cost", _cost], ["cp", round _before]]] call SWLC_fnc_fortRefuse;
		false
	};
	private _dir = [_spot, _bearing, _aim] call SWLC_fnc_fortDirFor;
	private _gun = [_class, _spot, _dir] call SWLC_fnc_fortCreate;
	if (isNull _gun) exitWith {
		[_side, _cost] call SWLC_fnc_adCredit;
		[_cmd, _sName, "create_failed", [["class", _class]]] call SWLC_fnc_fortRefuse;
		false
	};

	_gun setVariable ["SWLC_fortSector", _sName];
	_recs pushBack createHashMapFromArray [
		["gun", _gun], ["class", _class], ["kind", _kind], ["cost", _cost], ["pos", _spot], ["dir", _dir], ["sector", _sName],
		["gunner", objNull], ["seated", false], ["tries", 0], ["walkUntil", 0], ["placedAt", time], ["lostAt", -1]
	];
	private _reserve = [_side] call SWLC_fnc_cpReserve;
	private _after = [_side] call SWLC_fnc_adSideCP;
	["C_BUY", [["side", _side], ["what", "static"], ["class", _class], ["cost", _cost], ["cp_before", round _before], ["cp_after", round _after], ["reserve", round _reserve], ["buyer", "fortify"]]] call SWLC_fnc_log;
	[_cmd, "buy", [["sector", _sName], ["class", _class], ["kind", _kind], ["cost", _cost], ["cp_after", round _after], ["stance", [_cmd] call SWLC_fnc_fortStance], ["count", _have + 1], ["cap", _cap]]] call SWLC_fnc_fortLog;
	[_cmd, "placed", [["sector", _sName], ["class", _class], ["x", round (_spot # 0)], ["y", round (_spot # 1)], ["dir", round _dir], ["sees", _sees], ["centre_dist", round (_spot distance2D _c)]]] call SWLC_fnc_fortLog;
	if ((_cmd getOrDefault ["fortAnnounced", ""]) != _sName) then {
		_cmd set ["fortAnnounced", _sName];
		[_side, "fortbuilt", [[_s] call SWLC_fnc_adName]] call SWLC_fnc_radio;
	};
	true
};

// AT soldiers on the approach road.

SWLC_fnc_fortATEligible = {
	params ["_u"];
	alive _u
	&& {!isPlayer _u}
	&& {isNull objectParent _u}
	&& {!((leader group _u) isEqualTo _u)}
	&& {([secondaryWeapon _u] call SWLC_fnc_adLauncherKind) == "AT"}
	&& {(_u getVariable ["SWLC_kitTask", ""]) == ""}
	&& {isNull (_u getVariable ["SWLC_fortGun", objNull])}
	&& {(_u getVariable ["SWLC_fortAT", []]) isEqualTo []}
	&& {_u checkAIFeature "PATH"}
};

// [spot, lookPoint] or []: a spot beside a road point on the approach, off the tarmac, looking along the road towards the enemy.
// With no road points, the same thing on the line of the approach.
SWLC_fnc_fortATSpot = {
	params ["_s", "_approach", "_slot"];
	_approach params ["_bearing", "_aim", ["_roads", []]];
	private _c = [_s] call SWLC_fnc_adPos;
	private _reach = ([_s] call SWLC_fnc_adSize) * CFG("fortifyATReachFraction");
	private _near = _roads select {(_x distance2D _c) <= _reach};
	private _rp = [];
	private _line = _bearing;
	if (_near isEqualTo []) then {
		_rp = _c getPos [(_aim distance2D _c) min _reach, _bearing];
	} else {
		private _ranked = _near apply {[_x distance2D _c, _x]};
		_ranked sort false; // furthest forward first
		private _ordered = _ranked apply {_x # 1};
		private _i = _slot % (count _ordered);
		_rp = _ordered # _i;
		if ((count _ordered) > 1) then {
			private _other = _ordered # ((_i + 1) % (count _ordered));
			_line = _rp getDir _other;
			if (([_line, _bearing] call SWLC_fnc_fortAngle) > 90) then {_line = _line + 180};
		};
	};
	private _sign = [-1, 1] select ((_slot % 2) == 0);
	private _spot = [];
	{
		private _p = _rp getPos [CFG("fortifyATRoadOffset"), _line + (90 * _x)];
		private _f = _p findEmptyPosition [0, 8, "CAManBase"];
		if (_f isNotEqualTo [] && {!surfaceIsWater _f} && {!isOnRoad _f}) exitWith {_spot = _f};
	} forEach [_sign, -_sign];
	if (_spot isEqualTo []) exitWith {[]};
	[_spot, _rp getPos [CFG("fortifyATLookRange"), _line]]
};

SWLC_fnc_fortATRelease = {
	params ["_cmd", "_u", "_sName", "_why"];
	if (isNull _u) exitWith {};
	_u setVariable ["SWLC_fortAT", nil];
	[_cmd, "at_release", [["sector", _sName], ["why", _why], ["man", [_u] call SWLC_fnc_fortManId]]] call SWLC_fnc_fortLog;
	if (!alive _u || {isPlayer _u}) exitWith {};
	private _g = group _u;
	if !([_g] call SWLC_fnc_resMayTouch) exitWith {};
	_u doWatch objNull;
	_u setUnitPos "AUTO";
	if ((_g getVariable ["SWLC_lambsTask", ""]) == "") then {_u doFollow leader _g};
};

// One man already on the job, one tick. True if he stays on it.
SWLC_fnc_fortATKeep = {
	params ["_cmd", "_u", "_sName", "_groups"];
	if (!alive _u) exitWith {
		if (!isNull _u) then {_u setVariable ["SWLC_fortAT", nil]};
		false
	};
	private _job = _u getVariable ["SWLC_fortAT", []];
	if (_job isEqualTo []) exitWith {false};
	private _g = group _u;
	// LAMBS has taken the group over. His orders belong to it now, so no commands from here.
	if ((_g getVariable ["SWLC_lambsTask", ""]) != "") exitWith {
		_u setVariable ["SWLC_fortAT", nil];
		[_cmd, "at_release", [["sector", _sName], ["why", "lambs"], ["man", [_u] call SWLC_fnc_fortManId]]] call SWLC_fnc_fortLog;
		false
	};
	if (!(_g in _groups) || {!([_g] call SWLC_fnc_resMayTouch)} || {!isNull objectParent _u}) exitWith {
		[_cmd, _u, _sName, "group_left"] call SWLC_fnc_fortATRelease;
		false
	};
	_job params ["_spot", "_look", "_holding", "_at", "_drift"];
	if (!_holding) exitWith {
		if ((_u distance2D _spot) <= CFG("fortifyATArrive")) then {
			doStop _u;
			_u doWatch _look;
			_u setUnitPos "MIDDLE";
			_job set [2, true];
			_u setVariable ["SWLC_fortAT", _job];
			[_cmd, "at_hold", [["sector", _sName], ["man", [_u] call SWLC_fnc_fortManId], ["x", round (_spot # 0)], ["y", round (_spot # 1)]]] call SWLC_fnc_fortLog;
			true
		} else {
			if ((time - _at) > CFG("fortifyATWalkSeconds")) then {
				[_cmd, _u, _sName, "timeout"] call SWLC_fnc_fortATRelease;
				false
			} else {
				true
			};
		};
	};
	if ((_u distance2D _spot) <= CFG("fortifyATDrift")) exitWith {true};
	if (_drift >= CFG("fortifyATDriftMax")) exitWith {
		[_cmd, _u, _sName, "drifted"] call SWLC_fnc_fortATRelease;
		false
	};
	// Something moved him off the spot, usually a squad order. Send him back a couple of times, then let it go.
	_u doMove _spot;
	_job set [2, false];
	_job set [3, time];
	_job set [4, _drift + 1];
	_u setVariable ["SWLC_fortAT", _job];
	[_cmd, "at_drift", [["sector", _sName], ["man", [_u] call SWLC_fnc_fortManId], ["times", _drift + 1]]] call SWLC_fnc_fortLog;
	true
};

SWLC_fnc_fortATTick = {
	params ["_cmd", "_s", "_sName", "_approach", "_groups"];
	private _keep = (_cmd getOrDefault ["fortATMen", []]) select {[_cmd, _x, _sName, _groups] call SWLC_fnc_fortATKeep};
	_cmd set ["fortATMen", _keep];
	private _want = CFG("fortifyATMen") - (count _keep);
	if (_want <= 0) exitWith {};

	private _cands = [];
	{
		private _g = _x;
		if ([_g] call SWLC_fnc_resMayTouch
			&& {(_g getVariable ["SWLC_lambsTask", ""]) == ""}
			&& {!([_g] call SWLC_fnc_groupFighting)}) then {
			{
				if ([_x] call SWLC_fnc_fortATEligible) then {_cands pushBack _x};
			} forEach units _g;
		};
	} forEach _groups;

	private _reach = CFG("fortifyCrewReach");
	for "_i" from 0 to (_want - 1) do {
		if (_cands isEqualTo []) exitWith {};
		private _info = [_s, _approach, (count _keep) + _i] call SWLC_fnc_fortATSpot;
		if (_info isEqualTo []) exitWith {[_cmd, _sName, "at_no_spot"] call SWLC_fnc_fortRefuse};
		_info params ["_spot", "_look"];
		private _best = objNull;
		private _bestD = 1e6;
		{
			private _d = _x distance2D _spot;
			if (_d < _bestD) then {_best = _x; _bestD = _d};
		} forEach _cands;
		if (isNull _best || {_bestD > _reach}) exitWith {};
		_cands deleteAt (_cands find _best);
		_best setVariable ["SWLC_fortAT", [_spot, _look, false, time, 0]];
		_best doMove _spot;
		_keep pushBack _best;
		[_cmd, "at_assign", [["sector", _sName], ["man", [_best] call SWLC_fnc_fortManId], ["dist", round _bestD], ["x", round (_spot # 0)], ["y", round (_spot # 1)]]] call SWLC_fnc_fortLog;
	};
};

// The alert is over or has moved. Guns stay where they are; every man goes back to his group.
SWLC_fnc_fortStandDown = {
	params ["_cmd", "_sName", "_why"];
	{[_cmd, _x, _why] call SWLC_fnc_fortReleaseGun} forEach ([_cmd, _sName] call SWLC_fnc_fortRecords);
	{[_cmd, _x, _sName, _why] call SWLC_fnc_fortATRelease} forEach (_cmd getOrDefault ["fortATMen", []]);
	_cmd set ["fortATMen", []];
	_cmd set ["fortActive", ""];
	_cmd set ["fortAnnounced", ""];
	[_cmd, "standdown", [["sector", _sName], ["why", _why]]] call SWLC_fnc_fortLog;
};

SWLC_fnc_fortifyTick = {
	params ["_cmd"];
	if !(CFG("fortifyEnabled")) exitWith {};
	[_cmd] call SWLC_fnc_fortCatalog;
	{[_cmd, _x] call SWLC_fnc_fortTrack} forEach (keys ([_cmd, "fort"] call SWLC_fnc_fortMap));

	private _side = _cmd get "side";
	private _alert = _cmd getOrDefault ["alert", createHashMap];
	private _active = _cmd getOrDefault ["fortActive", ""];
	if ((count _alert) == 0) exitWith {
		if (_active != "") then {[_cmd, _active, "alert_end"] call SWLC_fnc_fortStandDown};
	};

	private _s = _alert getOrDefault ["sector", objNull];
	if (isNull _s) exitWith {
		if (_active != "") then {[_cmd, _active, "alert_end"] call SWLC_fnc_fortStandDown};
	};
	private _sName = [_s] call SWLC_fnc_adName;
	if (_active != "" && {_active != _sName}) then {
		[_cmd, _active, "alert_moved"] call SWLC_fnc_fortStandDown;
		_active = "";
	};
	if (([_s] call SWLC_fnc_adOwner) != _side) exitWith {
		if (_active != "") then {[_cmd, _active, "sector_lost"] call SWLC_fnc_fortStandDown};
		[_cmd, _sName, "not_owned"] call SWLC_fnc_fortRefuse;
	};
	private _approach = _alert getOrDefault ["approach", []];
	if ((count _approach) < 2) exitWith {[_cmd, _sName, "no_approach"] call SWLC_fnc_fortRefuse};
	private _groups = (_alert getOrDefault ["groups", []]) select {!isNull _x};

	if (_active == "") then {
		_cmd set ["fortActive", _sName];
		[_cmd, "alert_seen", [["sector", _sName], ["groups", count _groups], ["stance", [_cmd] call SWLC_fnc_fortStance]]] call SWLC_fnc_fortLog;
	};

	for "_i" from 1 to CFG("fortifyBuyPerTick") do {
		if !([_cmd, _s, _sName, _approach, _groups] call SWLC_fnc_fortBuyOne) exitWith {};
	};
	{
		if (alive (_x get "gun")) then {[_cmd, _x, _groups, _sName] call SWLC_fnc_fortCrewOne};
	} forEach ([_cmd, _sName] call SWLC_fnc_fortRecords);
	[_cmd, _s, _sName, _approach, _groups] call SWLC_fnc_fortATTick;
};
