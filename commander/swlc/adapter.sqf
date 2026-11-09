// Warlords adapter: the only file that reads or writes BIS_WL_* state or calls BIS_fnc_WL*.
// If a Bohemia patch breaks something, this is the file to fix. Everything else talks to these functions.
// Notes on why each hook works this way are in the design doc's Integration section.
#include "macros.hpp"

SWLC_fnc_adReady = {
	!isNil "BIS_WL_sectors"
	&& {!isNil "BIS_WL_scenarioServices"}
	&& {!isNil "BIS_WL_base_WEST"}
	&& {!isNil "BIS_WL_base_EAST"}
	&& {!isNil "BIS_WL_allWarlords"}
	&& {count BIS_WL_allWarlords > 0}
};

// Sector data never changes, so read it once. Warlords moves a sector's logic object to [100,100]
// for a moment during capture, so positions must be cached, never read live.
SWLC_fnc_adInit = {
	{
		private _p = getPosWorld _x;
		_x setVariable ["SWLC_pos", [_p # 0, _p # 1, 0]];
		_x setVariable ["SWLC_size", _x getVariable ["Size", 300]];
		_x setVariable ["SWLC_value", _x getVariable ["BIS_WL_value", 1]];
		_x setVariable ["SWLC_isBase", typeOf _x == "ModuleWLBase_F"];
		_x setVariable ["SWLC_links", _x getVariable ["BIS_WL_connectedSectors", []]];
		_x setVariable ["SWLC_timeoutT", _x getVariable ["BIS_WL_timeoutBase", 60]];
	} forEach BIS_WL_sectors;
	SWLC_sectors = +BIS_WL_sectors;
};

SWLC_fnc_adPos = { (_this # 0) getVariable "SWLC_pos" };
SWLC_fnc_adSize = { (_this # 0) getVariable "SWLC_size" };
SWLC_fnc_adValue = { (_this # 0) getVariable ["BIS_WL_value", (_this # 0) getVariable "SWLC_value"] };
// What a sector is worth to plan around. BIS_WL_value carries the income curve's discount, which depends on the owner's other sectors.
SWLC_fnc_adWorth = { (_this # 0) getVariable ["SWLC_econValue", [_this # 0] call SWLC_fnc_adValue] };
SWLC_fnc_adIsBase = { (_this # 0) getVariable "SWLC_isBase" };
SWLC_fnc_adLinks = { (_this # 0) getVariable "SWLC_links" };

SWLC_fnc_adName = {
	params ["_s"];
	private _n = _s getVariable "SWLC_name";
	if (!isNil "_n") exitWith {_n};
	_n = _s getVariable ["Name", ""];
	if (_n == "") then {_n = format ["grid %1", mapGridPosition (_s getVariable "SWLC_pos")]};
	_s setVariable ["SWLC_name", _n];
	_n
};

// The sector in a non-empty list nearest a position.
SWLC_fnc_adNearest = {
	params ["_list", "_pos"];
	private _best = _list # 0;
	private _bestD = 1e12;
	{
		private _d = (_x getVariable "SWLC_pos") distance2D _pos;
		if (_d < _bestD) then {_bestD = _d; _best = _x};
	} forEach _list;
	_best
};

SWLC_fnc_adOwner = { (_this # 0) getVariable ["BIS_WL_sectorSide", sideUnknown] };

SWLC_fnc_adTarget = {
	params ["_side"];
	missionNamespace getVariable [format ["BIS_WL_currentSector_%1", _side], objNull]
};

SWLC_fnc_adBase = {
	params ["_side"];
	missionNamespace getVariable [format ["BIS_WL_base_%1", _side], objNull]
};

SWLC_fnc_adEnemySide = {
	params ["_side"];
	[west, east] select (_side == west)
};

SWLC_fnc_adOwned = {
	params ["_side"];
	SWLC_sectors select {(_x getVariable ["BIS_WL_sectorSide", sideUnknown]) == _side}
};

// [owned, available, linked] from Warlords itself.
SWLC_fnc_adAvailable = {
	params ["_side"];
	([_side] call BIS_fnc_WLSectorListing) # 1
};

// The capture area is a square of half-side Size/2 centred on the sector.
SWLC_fnc_adInSquare = {
	params ["_s", "_pos", ["_margin", 0]];
	private _c = _s getVariable "SWLC_pos";
	private _h = (_s getVariable "SWLC_size") / 2 + _margin;
	abs ((_pos # 0) - (_c # 0)) <= _h && {abs ((_pos # 1) - (_c # 1)) <= _h}
};

// True if an AI of this side standing at _pos could be killed by Warlords' restricted-area loop:
// inside a sector neither owned by the side nor its current target.
SWLC_fnc_adRestricted = {
	params ["_side", "_pos", ["_margin", 25]];
	private _target = [_side] call SWLC_fnc_adTarget;
	private _hit = false;
	{
		if (_x != _target && {(_x getVariable ["BIS_WL_sectorSide", sideUnknown]) != _side} && {[_x, _pos, _margin] call SWLC_fnc_adInSquare}) exitWith {_hit = true};
	} forEach SWLC_sectors;
	_hit
};

// Warlords
SWLC_fnc_adWarlords = {
	params ["_side"];
	BIS_WL_allWarlords select {alive _x && {side group _x == _side}}
};

SWLC_fnc_adAIWarlords = {
	params ["_side"];
	([_side] call SWLC_fnc_adWarlords) select {!isPlayer _x}
};

SWLC_fnc_adSideHasPlayers = {
	params ["_side"];
	({isPlayer _x && {side group _x == _side}} count allPlayers) > 0
};

// Groups the commander may order: AI-led warlord groups with no human in them.
// A group that had a human in it within the grace period is left alone, which also
// covers a player's own AI while the player is waiting to respawn.
SWLC_fnc_adOwnableGroups = {
	params ["_side"];
	private _groups = [];
	{
		if (alive _x && {side group _x == _side}) then {_groups pushBackUnique (group _x)};
	} forEach BIS_WL_allWarlords;
	_groups
};

SWLC_fnc_adGroupHasPlayer = {
	params ["_g"];
	private _has = (units _g findIf {isPlayer _x}) >= 0;
	if (_has) then {_g setVariable ["SWLC_playerAt", time]};
	if (_has) exitWith {true};
	(time - (_g getVariable ["SWLC_playerAt", -1000])) < CFG("playerGroupGrace")
};

SWLC_fnc_adIsWarlord = {
	(_this # 0) in BIS_WL_allWarlords
};

// Waypoints. Warlords' AI loop appends SAD waypoints to the same groups, so every order the
// commander gives is remembered and restored by the guard if something else changes it.
//
// Order: array of [pos, type, radius(optional)].
// Standing orders the commander issues are "signed" with the types of its waypoints.
SWLC_fnc_adSetOrder = {
	params ["_g", "_wps", ["_behaviour", "AWARE"], ["_speed", "FULL"], ["_formation", "WEDGE"], ["_combat", "YELLOW"]];
	_g setVariable ["SWLC_order", [_wps, _behaviour, _speed, _formation, _combat]];
	[_g, 0] call SWLC_fnc_adApplyOrder;
};

// Writes the remembered order to the group, resuming at waypoint _from.
// Behaviour, speed, formation and combat mode wait while LAMBS has the group.
SWLC_fnc_adApplyStance = {
	params ["_g"];
	private _order = _g getVariable ["SWLC_order", []];
	if (_order isEqualTo []) exitWith {};
	if ([_g] call SWLC_fnc_lambsBusy) exitWith {_g setVariable ["SWLC_stanceDirty", true]};
	_g setVariable ["SWLC_stanceDirty", false];
	_g setBehaviour (_order # 1);
	_g setSpeedMode (_order # 2);
	_g setFormation (_order # 3);
	_g setCombatMode (_order # 4);
};

SWLC_fnc_adApplyOrder = {
	params ["_g", ["_from", 0]];
	private _order = _g getVariable ["SWLC_order", []];
	if (_order isEqualTo []) exitWith {};
	_order params ["_wps", "_behaviour", "_speed", "_formation", "_combat"];
	isNil {
		for "_i" from (count waypoints _g - 1) to 0 step -1 do {deleteWaypoint [_g, _i]};
		// The engine can move a waypoint from where it was asked for, so the guard compares with where it really went.
		private _actual = [];
		{
			_x params ["_p", "_type", ["_radius", 0]];
			private _wp = _g addWaypoint [_p, 0];
			_wp setWaypointType _type;
			if (_radius > 0) then {_wp setWaypointCompletionRadius _radius};
			_actual pushBack (waypointPosition _wp);
		} forEach _wps;
		_g setVariable ["SWLC_wpActual", _actual];
		private _first = (count waypoints _g) - count _wps;
		_g setVariable ["SWLC_wpBase", _first];
		_g setCurrentWaypoint [_g, (_first + _from) min (count waypoints _g - 1)];
		[_g] call SWLC_fnc_adApplyStance;
		_g setVariable ["SWLC_wpProgress", _from];
	};
};

SWLC_fnc_adClearOrder = {
	params ["_g"];
	_g setVariable ["SWLC_order", []];
	_g setVariable ["SWLC_wpActual", []];
};

// Number of the commander's waypoints the group has finished.
SWLC_fnc_adOrderProgress = {
	params ["_g"];
	(currentWaypoint _g) - (_g getVariable ["SWLC_wpBase", 0])
};

// All waypoints of the current order done.
SWLC_fnc_adOrderDone = {
	params ["_g"];
	private _order = _g getVariable ["SWLC_order", []];
	if (_order isEqualTo []) exitWith {true};
	// Warlords can append waypoints and jump ahead; only trust progress on an intact order.
	if ((count waypoints _g) != (_g getVariable ["SWLC_wpBase", 0]) + count (_order # 0)) exitWith {false};
	([_g] call SWLC_fnc_adOrderProgress) >= count (_order # 0)
};

// Guard: true if Warlords (or anything else) changed the group's waypoints since we wrote them.
// Called every few seconds. Restores the order at the progress last seen.
SWLC_fnc_adGuardOrder = {
	params ["_g"];
	private _order = _g getVariable ["SWLC_order", []];
	if (_order isEqualTo []) exitWith {false};
	if ([_g] call SWLC_fnc_adGroupHasPlayer) exitWith {false};
	private _wps = _order # 0;
	private _base = _g getVariable ["SWLC_wpBase", 0];
	private _count = count waypoints _g;
	private _intact = _count == _base + count _wps;
	private _why = "count";
	private _off = -1;
	if (_intact) then {
		private _actual = _g getVariable ["SWLC_wpActual", []];
		private _useActual = (count _actual) == (count _wps);
		{
			private _want = if (_useActual) then {_actual # _forEachIndex} else {_x # 0};
			private _dist = (waypointPosition [_g, _base + _forEachIndex]) distance2D _want;
			if (waypointType [_g, _base + _forEachIndex] != (_x # 1) || {_dist > 1}) exitWith {
				_intact = false;
				_why = ["pos", "type"] select (waypointType [_g, _base + _forEachIndex] != (_x # 1));
				_off = round _dist;
			};
		} forEach _wps;
	};
	if (_intact) exitWith {
		if (_g getVariable ["SWLC_stanceDirty", false]) then {[_g] call SWLC_fnc_adApplyStance};
		_g setVariable ["SWLC_wpProgress", (((currentWaypoint _g) - _base) max 0) min (count _wps)];
		false
	};
	private _from = (_g getVariable ["SWLC_wpProgress", 0]) min ((count _wps - 1) max 0);
	_g setVariable ["SWLC_guardWhy", format ["%1|have=%2|want=%3|off=%4", _why, _count, _base + count _wps, _off]];
	[_g, _from] call SWLC_fnc_adApplyOrder;
	true
};

// CP. Warlords keeps funds on each warlord unit; there is no side pool. The commander only
// ever spends AI warlords' funds, never a player's.
SWLC_fnc_adSideCP = {
	params ["_side"];
	private _sum = 0;
	{_sum = _sum + (_x getVariable ["BIS_WL_funds", 0])} forEach ([_side] call SWLC_fnc_adAIWarlords);
	_sum
};

// Debit _amount from AI warlords, richest first. Returns true if paid in full.
SWLC_fnc_adDebit = {
	params ["_side", "_amount", ["_preferred", objNull]];
	private _paid = false;
	isNil {
		private _payers = ([_side] call SWLC_fnc_adAIWarlords) apply {[_x getVariable ["BIS_WL_funds", 0], _x]};
		_payers sort false;
		private _total = 0;
		{_total = _total + (_x # 0)} forEach _payers;
		if (_total < _amount) exitWith {};
		private _left = _amount;
		if (!isNull _preferred && {!isPlayer _preferred} && {_preferred getVariable ["BIS_WL_funds", 0] >= _amount}) then {
			_preferred setVariable ["BIS_WL_funds", (_preferred getVariable ["BIS_WL_funds", 0]) - _amount, true];
			_left = 0;
		};
		{
			if (_left <= 0) exitWith {};
			_x params ["_f", "_u"];
			private _take = _f min _left;
			if (_take > 0) then {
				_u setVariable ["BIS_WL_funds", (_u getVariable ["BIS_WL_funds", 0]) - _take, true];
				_left = _left - _take;
			};
		} forEach _payers;
		_paid = true;
	};
	_paid
};

// Fast travel
SWLC_fnc_adFTAllowedParam = {
	(missionNamespace getVariable ["BIS_WL_FTEnabled", 0]) in CFG("ftAllowedParamValues")
};

SWLC_fnc_adFTCost = {
	if (CFG("ftChargeCost")) then {missionNamespace getVariable ["BIS_WL_FTCost", 50]} else {0}
};

// Can _side fast travel to sector _s at all (owned, not disabled, own base not under attack)?
SWLC_fnc_adCanFTTo = {
	params ["_side", "_s"];
	if !([] call SWLC_fnc_adFTAllowedParam) exitWith {false};
	if (([_s] call SWLC_fnc_adOwner) != _side) exitWith {false};
	if (_s getVariable ["FastTravelEnabled", true] isEqualTo false) exitWith {false};
	if (_s == ([_side] call SWLC_fnc_adBase) && {[_side] call SWLC_fnc_adBaseThreatened}) exitWith {false};
	if (CFG("rulesVariant") && {CFG("ruleNoRespawnSeized")} && {[_side, _s] call SWLC_fnc_capBeingSeized}) exitWith {false};
	true
};

SWLC_fnc_adBaseThreatened = {
	params ["_side"];
	private _base = [_side] call SWLC_fnc_adBase;
	(([west] call SWLC_fnc_adTarget) == _base) || {([east] call SWLC_fnc_adTarget) == _base}
};

// Vanilla's AI check: any crewed enemy object close to the group blocks fast travel.
// True while the enemy's seize countdown is running on this owned sector (Warlords shows this to players too).
SWLC_fnc_adEnemySeizing = {
	params ["_side", "_s"];
	(_s getVariable [format ["BIS_WL_timeoutCur_%1", [_side] call SWLC_fnc_adEnemySide], 0]) > 0
};

SWLC_fnc_adEnemyNear = {
	params ["_side", "_pos"];
	private _r = CFG("ftEnemyCheckRadius");
	private _hit = false;
	{
		if (side group _x != _side && {side group _x in [west, east, resistance]} && {[side group _x, _side] call BIS_fnc_sideIsEnemy}) exitWith {_hit = true};
	} forEach (_pos nearEntities [["Man", "Car", "Tank", "Air", "Ship", "StaticWeapon"], _r]);
	_hit
};

// [group, sector, landingPos]. Moves the group's on-foot units to landingPos.
// Returns true if it happened. Refuses silently (returns false) if any rule isn't met.
SWLC_fnc_adFastTravel = {
	params ["_g", "_s", "_landing"];
	private _side = side _g;
	if !([_side, _s] call SWLC_fnc_adCanFTTo) exitWith {false};
	private _units = [_g] call SWLC_fnc_alive;
	if (_units isEqualTo []) exitWith {false};
	if ((_units findIf {vehicle _x != _x}) >= 0) exitWith {false};
	private _leader = leader _g;
	if ((_leader distance2D _landing) < CFG("ftMinDistance")) exitWith {false};
	if ([_side, getPosATL _leader] call SWLC_fnc_adEnemyNear) exitWith {false};
	if ((time - (_g getVariable ["SWLC_lastFT", -1000])) < CFG("ftGroupCooldown")) exitWith {false};

	private _cost = [] call SWLC_fnc_adFTCost;
	if (_cost > 0 && {!([_side, _cost, _leader] call SWLC_fnc_adDebit)}) exitWith {false};

	isNil {
		private _prev = +_landing;
		{
			private _spot = _prev findEmptyPosition [2, 25 + CFG("ftLandingScatter"), "CAManBase"];
			if (_spot isEqualTo []) then {_spot = _prev};
			_x setPosATL [_spot # 0, _spot # 1, 0];
			_x doFollow _leader;
			_prev = _spot getPos [4 + random CFG("ftLandingScatter"), random 360];
		} forEach _units;
	};
	_g setVariable ["SWLC_lastFT", time];
	["C_FT", [["side", _side], ["group", groupId _g], ["sector", [_s] call SWLC_fnc_adName], ["x", round (_landing # 0)], ["y", round (_landing # 1)], ["cost", _cost]]] call SWLC_fnc_log;
	true
};

// Votes. Writing BIS_WL_selectedSector on the side's AI warlords before they vote is exactly how
// Warlords' AI votes; a real player's vote is never touched.
SWLC_fnc_adCastVotes = {
	params ["_side", "_sector", ["_overwrite", false]];
	{
		private _have = _x getVariable ["BIS_WL_selectedSector", objNull];
		if (isNull _have || {_overwrite && {_have isNotEqualTo _sector}}) then {
			_x setVariable ["BIS_WL_selectedSector", _sector, true];
		};
	} forEach ([_side] call SWLC_fnc_adAIWarlords);
};

SWLC_fnc_adClearVotes = {
	params ["_side"];
	{
		if !(isNull (_x getVariable ["BIS_WL_selectedSector", objNull])) then {
			_x setVariable ["BIS_WL_selectedSector", objNull, true];
		};
	} forEach ([_side] call SWLC_fnc_adAIWarlords);
};

// Force a new vote (breaks deadlocks). Free when done by the server.
// Set while the target is empty, the flag would instantly cancel the next target, so it needs a target.
// The name is what Warlords' popup shows on human clients as who reset the vote.
SWLC_fnc_adForceRevote = {
	params ["_side"];
	if (isNull ([_side] call SWLC_fnc_adTarget)) exitWith {};
	missionNamespace setVariable [format ["BIS_WL_sectorVotingResetName_%1", _side], "the Commander", true];
	missionNamespace setVariable [format ["BIS_WL_sectorVotingReset_%1", _side], true, true];
	// Warlords clears this flag on the server only, so a client joining later would act on the old value.
	[_side] spawn {
		params ["_side"];
		private _flag = format ["BIS_WL_sectorVotingReset_%1", _side];
		private _until = time + 60;
		waitUntil {sleep 1; !(missionNamespace getVariable [_flag, false]) || {time > _until}};
		sleep 5;
		if !(missionNamespace getVariable [_flag, false]) then {publicVariable _flag};
	};
};

// Purchases. classes = array of class names. Returns the spawned objects, or [] on failure.
// The commander pays with AI warlords' funds, then calls Warlords' own airdrop path.
SWLC_fnc_adPurchasable = {
	params ["_side", "_index"];
	(missionNamespace getVariable [format ["BIS_WL_purchasable%1", _side], []]) param [_index, []]
};

SWLC_fnc_adBuy = {
	params ["_side", "_buyer", "_classes", "_cost", "_dropObject"];
	if (!alive _buyer || {isNull _dropObject}) exitWith {[]};
	if !([_side, _cost, _buyer] call SWLC_fnc_adDebit) exitWith {[]};
	_buyer setVariable ["BIS_WL_dropPos", _dropObject];
	// The AI flag adds a script that kills infantry far from their leader, so only vehicles get it.
	[_buyer, _classes, (_classes findIf {_x isKindOf "Man"}) < 0] call BIS_fnc_WLAirdrop
};

// Vanilla AI buying: stop it buying vehicles. See design doc. Reapplied after respawns.
// Infantry top-ups stay with Warlords' FSM until the commander takes them over.
SWLC_fnc_adSuppressVanillaVehicles = {
	params ["_u"];
	private _fsm = _u getVariable ["BIS_WL_AIPurchasesHandle", -1];
	if (_fsm < 0) exitWith {};
	// An unaffordable entry, not an empty list: the FSM can be past its "list not empty" check already.
	_fsm setFSMVariable ["_purchasableVehs", [["", 1e10]]];
	_fsm setFSMVariable ["_cheapest", ["", 1e10]];
};

// Stops all vanilla AI buying for this unit (the commander does the buying).
SWLC_fnc_adSuppressVanillaAll = {
	params ["_u"];
	private _fsm = _u getVariable ["BIS_WL_AIPurchasesHandle", -1];
	if (_fsm < 0) exitWith {};
	_fsm setFSMVariable ["_purchasableVehs", [["", 1e10]]];
	_fsm setFSMVariable ["_purchasableUnits", [["", 1e10]]];
	_fsm setFSMVariable ["_cheapest", ["", 1e10]];
	_fsm setFSMVariable ["_cheapestInf", ["", 1e10]];
};

// Income per minute for the whole side: every AI warlord receives the full sector income.
SWLC_fnc_adSideIncome = {
	params ["_side"];
	private _sum = 0;
	{_sum = _sum + ([_x] call SWLC_fnc_adValue)} forEach ([_side] call SWLC_fnc_adOwned);
	_sum * (missionNamespace getVariable ["BIS_WL_CPIncomeMult", 1]) * count ([_side] call SWLC_fnc_adAIWarlords)
};

// Ground vehicles the side can buy: [class, cost, seats, role, heavy].
SWLC_fnc_adCatalog = {
	params ["_side"];
	private _out = [];
	{
		_x params ["_cls", "_cost"];
		private _cfg = configFile >> "CfgVehicles" >> _cls;
		if (isClass _cfg && {_cls isKindOf "Car" || {_cls isKindOf "Tank"}}
			&& {getNumber (_cfg >> "isUav") != 1}
			&& {getNumber (_cfg >> "transportAmmo") == 0 && {getNumber (_cfg >> "transportFuel") == 0} && {getNumber (_cfg >> "transportRepair") == 0} && {getNumber (_cfg >> "attendant") == 0}}) then {
			private _armed = isClass (_cfg >> "Turrets") && {(getArray (_cfg >> "threat")) findIf {_x > 0.5} >= 0};
			private _heavy = _cls isKindOf "Tank" || {_cls isKindOf "Wheeled_APC_F"};
			private _seats = [_cls, true] call BIS_fnc_crewCount;
			_out pushBack [_cls, _cost, _seats, ["transport", "combat"] select _armed, _heavy];
		};
	} forEach ([_side, 1] call SWLC_fnc_adPurchasable);
	_out
};

// Infantry the side can buy: [class, cost], without crew and pilots.
SWLC_fnc_adInfantryList = {
	params ["_side"];
	private _out = [];
	{
		_x params ["_cls", "_cost"];
		private _l = toLower _cls;
		if (isClass (configFile >> "CfgVehicles" >> _cls) && {_cls isKindOf "Man"}
			&& {!("crew" in _l)} && {!("pilot" in _l)} && {!("uav" in _l)}) then {
			_out pushBack [_cls, _cost];
		};
	} forEach ([_side, 0] call SWLC_fnc_adPurchasable);
	_out
};

// "AT", "AA" or "" for a launcher class, read from its ammunition's AI usage flags.
// Looked up in the config once per launcher: the kit and rearm checks ask about every soldier.
SWLC_launcherKinds = createHashMap;

SWLC_fnc_adLauncherKind = {
	params ["_w"];
	if (_w == "") exitWith {""};
	private _known = SWLC_launcherKinds getOrDefault [_w, -1];
	if (_known isEqualType "") exitWith {_known};
	private _kind = "";
	private _mags = getArray (configFile >> "CfgWeapons" >> _w >> "magazines");
	if (_mags isNotEqualTo []) then {
		private _ammo = getText (configFile >> "CfgMagazines" >> (_mags # 0) >> "ammo");
		private _flags = getText (configFile >> "CfgAmmo" >> _ammo >> "aiAmmoUsageFlags");
		if ("256" in _flags) then {
			_kind = "AA";
		} else {
			if ("512" in _flags || {"128" in _flags}) then {_kind = "AT"};
		};
	};
	SWLC_launcherKinds set [_w, _kind];
	_kind
};

// Launchers from the side's own infantry: "AT" and "AA" -> [launcher, magazine, backpack].
SWLC_fnc_adKitTable = {
	params ["_side"];
	private _table = createHashMap;
	{
		_x params ["_cls"];
		private _cfg = configFile >> "CfgVehicles" >> _cls;
		private _pack = getText (_cfg >> "backpack");
		{
			private _w = _x;
			private _wc = configFile >> "CfgWeapons" >> _w;
			if (getNumber (_wc >> "type") == 4) then {
				private _mags = getArray (_wc >> "magazines");
				if (_mags isNotEqualTo []) then {
					private _kind = [_w] call SWLC_fnc_adLauncherKind;
					if (_kind != "" && {!(_kind in _table)}) then {_table set [_kind, [_w, _mags # 0, _pack]]};
				};
			};
		} forEach (getArray (_cfg >> "weapons"));
	} forEach ([_side, 0] call SWLC_fnc_adPurchasable);
	_table
};

// Sector scan: pay, set the two public variables same-side players watch, then read the area
// on the server ourselves (Warlords' own AI path doesn't work for an all-AI side when hosted).
SWLC_fnc_adScanCost = { missionNamespace getVariable ["BIS_WL_scanCost", 350] };

SWLC_fnc_adCanScan = {
	params ["_side", "_s"];
	if ((missionNamespace getVariable ["BIS_WL_scanEnabled", 0]) != 1) exitWith {false};
	if (_s != ([_side] call SWLC_fnc_adTarget) && {([_s] call SWLC_fnc_adOwner) != _side}) exitWith {false};
	private _dur = missionNamespace getVariable ["BIS_WL_scanDuration", 30];
	private _since = _s getVariable [format ["BIS_WL_sectorScanActiveSince_%1", _side], -1];
	// On a host nothing resets a vanilla scan's ActiveSince, so it only counts while it could be running.
	if (_since > 0 && {(call BIS_fnc_WLSyncedTime) - _since < _dur + 10}) exitWith {false};
	private _last = _s getVariable [format ["BIS_WL_sectorScanLastRequest_%1", _side], -1];
	// Our own future stamp (see adBlockVanillaScan) doesn't count as a scan.
	if (_last == (_s getVariable [format ["SWLC_scanStamp_%1", _side], -2])) then {_last = -1};
	private _cd = missionNamespace getVariable ["BIS_WL_scanCooldown", 0];
	if (_last > 0 && {(call BIS_fnc_WLSyncedTime) - _last < _dur + _cd + 5}) exitWith {false};
	true
};

// Returns true if the scan was bought. _onDone receives [side, sector, foundUnits] after the lead-in.
SWLC_fnc_adScan = {
	params ["_side", "_s", "_onDone"];
	if !([_side, _s] call SWLC_fnc_adCanScan) exitWith {false};
	private _cost = [_side] call SWLC_fnc_econScanCost;
	if !([_side, _cost] call SWLC_fnc_adDebit) exitWith {false};
	private _now = call BIS_fnc_WLSyncedTime;
	_s setVariable [format ["BIS_WL_sectorScanActiveSince_%1", _side], _now, true];
	_s setVariable [format ["BIS_WL_sectorScanLastRequest_%1", _side], _now, true];
	["C_SCAN", [["side", _side], ["sector", [_s] call SWLC_fnc_adName], ["cost", _cost]]] call SWLC_fnc_log;
	[_side, _s, _onDone] spawn {
		params ["_side", "_s", "_onDone"];
		scriptName "SWLC scan";
		sleep 5;
		private _found = ([_s] call SWLC_fnc_adUnitsInSquare) select {
			(side group _x) != _side && {(side group _x) in [west, east, resistance]}
		};
		[_side, _s, _found] call _onDone;
		sleep ((missionNamespace getVariable ["BIS_WL_scanDuration", 30]));
		_s setVariable [format ["BIS_WL_sectorScanActiveSince_%1", _side], -1, true];
		[_side, _s] call SWLC_fnc_adBlockVanillaScan;
	};
	true
};

// Stops Warlords' own random AI scan of this sector (it refuses when the last request looks recent).
// Only for sides with no players, because it also blocks a player's scan for the same window.
SWLC_fnc_adBlockVanillaScan = {
	params ["_side", "_s"];
	if ([_side] call SWLC_fnc_adSideHasPlayers) exitWith {};
	private _stamp = (call BIS_fnc_WLSyncedTime) + CFG("scanStampSeconds");
	_s setVariable [format ["BIS_WL_sectorScanLastRequest_%1", _side], _stamp, true];
	_s setVariable [format ["SWLC_scanStamp_%1", _side], _stamp];
};

SWLC_fnc_adUnitsInSquare = {
	params ["_s", ["_margin", 0]];
	private _c = _s getVariable "SWLC_pos";
	private _h = (_s getVariable "SWLC_size") / 2 + _margin;
	(_c nearEntities [["Man", "Car", "Tank", "Air", "Ship", "StaticWeapon"], _h * 1.5]) select {
		alive _x && {[_s, getPosATL _x, _margin] call SWLC_fnc_adInSquare}
	}
};
