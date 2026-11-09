// Part C of the rules variant: economy and capabilities. Server only.
// [] call SWLC_fnc_econInit once after adInit; [_cmd] call SWLC_fnc_econTick as a commander stage.
//
// Warlords keeps paying income and gating purchases. This module changes the numbers it reads:
// BIS_WL_value for income, BIS_WL_sectorSpecial for what a sector unlocks, and BIS_WL_funds for
// bonuses. Everything a client needs is published, because a client never compiles this file.
// Every rule checks rulesVariant and its own switch.

#include "macros.hpp"

#define ECON_ON(key) (CFG("rulesVariant") && {CFG(key)})

// Letters in BIS_WL_sectorSpecial. A, H and W are Warlords' own.
SWLC_econTypeLetters = createHashMapFromArray [
	["airfield", "A"],
	["harbour", "W"],
	["military", "M"],
	["industrial", "I"],
	["town", "T"],
	["radio", "R"]
];

// Helpers

SWLC_fnc_econLog = {
	params ["_event", "_side", ["_fields", []]];
	["C_ECON", [["event", _event], ["side", _side]] + _fields] call SWLC_fnc_log;
};

// True at most once per interval, for work slower than the commander tick.
SWLC_fnc_econDue = {
	params ["_key", "_every"];
	private _v = format ["SWLC_econAt_%1", _key];
	if (time < (missionNamespace getVariable [_v, -1])) exitWith {false};
	missionNamespace setVariable [_v, time + _every];
	true
};

SWLC_fnc_econCaps = {
	params ["_side"];
	missionNamespace getVariable [format ["SWLC_caps_%1", _side], []]
};

// The sectors that count for this side, from the last tick.
SWLC_fnc_econConn = {
	params ["_side"];
	missionNamespace getVariable [format ["SWLC_econConn_%1", _side], []]
};

// Side number from config, because a corpse or an empty vehicle no longer reports its own side.
SWLC_fnc_econCfgSide = {
	params ["_class"];
	[east, west, resistance, civilian] param [getNumber (configFile >> "CfgVehicles" >> _class >> "side"), sideUnknown]
};

SWLC_fnc_econIsArmour = {
	params ["_class"];
	_class isKindOf "Tank" || {_class isKindOf "Wheeled_APC_F"}
};

SWLC_fnc_econIsVehicle = {
	params ["_class"];
	_class isKindOf "LandVehicle" && {!(_class isKindOf "StaticWeapon")}
};

SWLC_fnc_econIsResupply = {
	params ["_class"];
	private _c = configFile >> "CfgVehicles" >> _class;
	getNumber (_c >> "transportAmmo") > 0 || {getNumber (_c >> "transportRepair") > 0} || {getNumber (_c >> "transportFuel") > 0}
};

// Better infantry kit: launcher carriers, marksmen and snipers.
SWLC_fnc_econIsKit = {
	params ["_class"];
	private _known = SWLC_econKitCache getOrDefault [_class, -1];
	if (_known isNotEqualTo -1) exitWith {_known};
	private _c = configFile >> "CfgVehicles" >> _class;
	private _kit = (getText (_c >> "role")) in ["Marksman", "Sniper"]
		|| {(getArray (_c >> "weapons")) findIf {getNumber (configFile >> "CfgWeapons" >> _x >> "type") == 4 && {([_x] call SWLC_fnc_adLauncherKind) != ""}} >= 0};
	SWLC_econKitCache set [_class, _kit];
	_kit
};

SWLC_fnc_econAtBase = {
	params ["_side", "_pos"];
	private _base = [_side] call SWLC_fnc_adBase;
	!isNull _base && {[_base, _pos, CFG("corneredBaseMargin")] call SWLC_fnc_adInSquare}
};

SWLC_fnc_econCornered = {
	params ["_side"];
	private _base = [_side] call SWLC_fnc_adBase;
	if (isNull _base) exitWith {false};
	([[_side] call SWLC_fnc_adEnemySide] call SWLC_fnc_adTarget) isEqualTo _base || {[_side, _base] call SWLC_fnc_adEnemySeizing}
};

// Set up

SWLC_fnc_econInit = {
	if (!isNil "SWLC_econReady") exitWith {};
	SWLC_econReady = true;
	SWLC_econKitCache = createHashMap;

	private _lobby = ["SWLC_RoundTimeLimit", -1] call BIS_fnc_getParamValue;
	if (_lobby >= 0) then {SWLC_settings set ["roundTimeLimitMinutes", _lobby]};
	SWLC_econScanNominal = [] call SWLC_fnc_adScanCost;
	SWLC_econRoundEnd = -1;
	SWLC_econSuddenDeaths = 0;
	SWLC_econValueRev = 0;

	// A map with no sector-type table has no military sector to unlock armour with, so the rule is off there.
	// Done before anything below reads it, so the clients get the same answer.
	if (ECON_ON("ruleCapabilities") && {CFG("sectorTypes") isEqualTo []}) then {
		SWLC_settings set ["ruleCapabilities", false];
		["capsoff", "-", [["reason", "no_sector_types"], ["world", worldName]]] call SWLC_fnc_econLog;
	};

	private _range = CFG("sectorTypeMatchMetres");
	private _table = CFG("sectorTypes");
	private _default = CFG("sectorTypeDefault");
	{
		private _s = _x;
		private _pos = _s getVariable "SWLC_pos";
		private _i = _table findIf {(_pos distance2D [_x # 0, _x # 1, 0]) <= _range};
		private _types = if (_i >= 0) then {+((_table # _i) # 2)} else {[[_default], []] select (_default == "")};
		if ([_s] call SWLC_fnc_adIsBase) then {_types = []};
		private _letters = [];
		{_letters pushBackUnique (SWLC_econTypeLetters getOrDefault [_x, ""])} forEach _types;
		_letters = _letters - [""];
		_s setVariable ["SWLC_econLetters", _letters];
		_s setVariable ["SWLC_econNative", +(_s getVariable ["BIS_WL_sectorSpecial", []])];
		_s setVariable ["SWLC_econValue", [_s] call SWLC_fnc_adValue];
		_s setVariable ["SWLC_econOwner", [_s] call SWLC_fnc_adOwner];
		_s setVariable ["SWLC_econHeldSince", time];
		["sectortype", "-", [["sector", [_s] call SWLC_fnc_adName], ["types", if (_types isEqualTo []) then {"none"} else {_types joinString "+"}],["letters", _letters joinString "+"], ["value", _s getVariable "SWLC_econValue"]]] call SWLC_fnc_econLog;
	} forEach SWLC_sectors;

	{
		private _side = _x;
		missionNamespace setVariable [format ["SWLC_econCounter_%1", _side], []];
		private _base = [_side] call SWLC_fnc_adBase;
		if (!isNull _base) then {
			missionNamespace setVariable [format ["SWLC_econBase_%1", _side], [[_base] call SWLC_fnc_adPos, [_base] call SWLC_fnc_adSize], true];
		};
		[_side] call SWLC_fnc_econFortressBuild;
	} forEach [west, east];

	if (CFG("rulesVariant")) then {
		addMissionEventHandler ["EntityKilled", {_this call SWLC_fnc_econOnKilled}];
	};

	// Clients take their numbers from this. They wait for it, so it is published last.
	missionNamespace setVariable ["SWLC_econCfg", [
		["on", CFG("rulesVariant")],
		["caps", ECON_ON("ruleCapabilities")],
		["fortress", ECON_ON("ruleFortressBase")],
		["cornered", ECON_ON("ruleCornered")],
		["counter", ECON_ON("ruleCounterattack")],
		["stretched", ECON_ON("ruleStretchedSupply")],
		["industrialVehicleDiscount", CFG("industrialVehicleDiscount")],
		["corneredDiscount", CFG("corneredDiscount")],
		["counterattackDiscount", CFG("counterattackDiscount")],
		["counterattackRadius", CFG("counterattackRadius")],
		["priceMultFloor", CFG("priceMultFloor")],
		["corneredBaseMargin", CFG("corneredBaseMargin")],
		["radioScanDiscount", CFG("radioScanDiscount")],
		["townSquadBonus", CFG("townSquadBonus")],
		["townRespawnTime", CFG("townRespawnTime")]
	], true];
};

// Supply lines

// Owned sectors reachable from the base through owned sectors.
SWLC_fnc_econConnected = {
	params ["_side"];
	private _base = [_side] call SWLC_fnc_adBase;
	if (isNull _base || {([_base] call SWLC_fnc_adOwner) != _side}) exitWith {[]};
	private _seen = [_base];
	private _queue = [_base];
	while {_queue isNotEqualTo []} do {
		private _s = _queue deleteAt 0;
		{
			if (!(_x in _seen) && {([_x] call SWLC_fnc_adOwner) == _side}) then {
				_seen pushBack _x;
				_queue pushBack _x;
			};
		} forEach ([_s] call SWLC_fnc_adLinks);
	};
	_seen
};

// Writes what each owned sector unlocks. A cut-off sector unlocks nothing, so Warlords' own check
// on BIS_WL_servicesAvailable does the gating for players without any change to its menu code.
SWLC_fnc_econUpdateCaps = {
	params ["_side"];
	private _owned = [_side] call SWLC_fnc_adOwned;
	private _conn = if (ECON_ON("ruleSupplyLines")) then {[_side] call SWLC_fnc_econConnected} else {_owned};
	missionNamespace setVariable [format ["SWLC_econConn_%1", _side], _conn];
	private _useCaps = ECON_ON("ruleCapabilities");

	private _caps = [];
	{
		private _s = _x;
		private _want = [];
		if (_s in _conn) then {
			_want = +(_s getVariable ["SWLC_econNative", []]);
			if (_useCaps) then {_want append (_s getVariable ["SWLC_econLetters", []])};
			_want = _want arrayIntersect _want;
		};
		if ((_s getVariable ["BIS_WL_sectorSpecial", []]) isNotEqualTo _want) then {
			_s setVariable ["BIS_WL_sectorSpecial", _want, true];
		};
		{_caps pushBackUnique _x} forEach _want;
	} forEach _owned;
	_caps sort true;

	private _key = format ["SWLC_caps_%1", _side];
	private _old = missionNamespace getVariable _key;
	if (isNil "_old" || {_old isNotEqualTo _caps}) then {
		missionNamespace setVariable [_key, _caps, true];
		private _cut = _owned - _conn;
		["caps", _side, [
			["caps", if (_caps isEqualTo []) then {"none"} else {_caps joinString "+"}],
			["owned", count _owned],
			["connected", count _conn],
			["cut", if (_cut isEqualTo []) then {"-"} else {(_cut apply {[_x] call SWLC_fnc_adName}) joinString ","}]
		]] call SWLC_fnc_econLog;
		if (!isNil "_old" && {_cut isNotEqualTo []}) then {
			[_side, "econcut", [[_cut # 0] call SWLC_fnc_adName]] call SWLC_fnc_radio;
		};
	};
};

// Zones the clients test against: [[[pos, radius], ...] supply, [[pos, radius], ...] towns].
SWLC_fnc_econPublishZones = {
	params ["_side"];
	private _conn = [_side] call SWLC_fnc_econConn;
	private _supply = [];
	private _towns = [];
	private _base = [_side] call SWLC_fnc_adBase;
	if (!isNull _base) then {_supply pushBack [[_base] call SWLC_fnc_adPos, CFG("supplyBaseRadius")]};
	{
		private _p = [_x] call SWLC_fnc_adPos;
		_supply pushBack [_p, CFG("stretchedSupplyRange")];
		if (_x in _conn) then {
			private _letters = _x getVariable ["SWLC_econLetters", []];
			if ("I" in _letters) then {_supply pushBack [_p, CFG("supplyBaseRadius")]};
			if ("T" in _letters) then {_towns pushBack [_p, CFG("townRespawnRadius")]};
		};
	} forEach ([_side] call SWLC_fnc_adOwned);

	missionNamespace setVariable [format ["SWLC_econSupply_%1", _side], _supply];
	private _zones = [_supply, _towns];
	private _key = format ["SWLC_zones_%1", _side];
	if ((missionNamespace getVariable [_key, []]) isNotEqualTo _zones) then {
		missionNamespace setVariable [_key, _zones, true];
	};

	private _cornered = ECON_ON("ruleCornered") && {[_side] call SWLC_fnc_econCornered};
	private _cKey = format ["SWLC_cornered_%1", _side];
	if ((missionNamespace getVariable [_cKey, false]) isNotEqualTo _cornered) then {
		missionNamespace setVariable [_cKey, _cornered, true];
		["cornered", _side, [["active", _cornered]]] call SWLC_fnc_econLog;
		if (_cornered) then {[_side, "econcornered", []] call SWLC_fnc_radio};
	};
};

// Queries for the commander's own buying, which Warlords never checks

// True if the side may use this capability. With the rule off nothing is restricted.
SWLC_fnc_econHasCapability = {
	params ["_side", "_cap"];
	if !(ECON_ON("ruleCapabilities")) exitWith {true};
	_cap in ([_side] call SWLC_fnc_econCaps)
};

// The same question for a bonus, where a rule that is off must give nothing.
SWLC_fnc_econBonus = {
	params ["_side", "_cap"];
	ECON_ON("ruleCapabilities") && {_cap in ([_side] call SWLC_fnc_econCaps)}
};

SWLC_fnc_econPriceMult = {
	params ["_side", "_class", "_pos"];
	if !(CFG("rulesVariant")) exitWith {1};
	private _m = 1;
	if ([_class] call SWLC_fnc_econIsVehicle && {[_side, "I"] call SWLC_fnc_econBonus}) then {
		_m = _m * CFG("industrialVehicleDiscount");
	};
	if (ECON_ON("ruleCornered") && {[_side] call SWLC_fnc_econCornered} && {[_side, _pos] call SWLC_fnc_econAtBase}) then {
		_m = _m * CFG("corneredDiscount");
	};
	if (ECON_ON("ruleCounterattack")) then {
		private _r = CFG("counterattackRadius");
		private _list = missionNamespace getVariable [format ["SWLC_econCounter_%1", _side], []];
		if (_list findIf {(_pos distance2D (_x # 0)) <= _r} >= 0) then {_m = _m * CFG("counterattackDiscount")};
	};
	_m max CFG("priceMultFloor")
};

SWLC_fnc_econKitAllowed = {
	params ["_side", "_pos"];
	if !(ECON_ON("ruleCapabilities")) exitWith {true};
	("M" in ([_side] call SWLC_fnc_econCaps)) || {ECON_ON("ruleFortressBase") && {[_side, _pos] call SWLC_fnc_econAtBase}}
};

// True if the side may buy this class at this place.
SWLC_fnc_econAssetAllowed = {
	params ["_side", "_class", "_pos"];
	if !(CFG("rulesVariant")) exitWith {true};
	if (ECON_ON("ruleCapabilities") && {[_class] call SWLC_fnc_econIsArmour} && {!("M" in ([_side] call SWLC_fnc_econCaps))}) exitWith {false};
	if ([_class] call SWLC_fnc_econIsKit && {!([_side, _pos] call SWLC_fnc_econKitAllowed)}) exitWith {false};
	if (ECON_ON("ruleStretchedSupply") && {[_class] call SWLC_fnc_econIsResupply} && {!([_side, _pos] call SWLC_fnc_econResupplyAllowed)}) exitWith {false};
	true
};

SWLC_fnc_econScanCost = {
	params ["_side"];
	if ([_side, "R"] call SWLC_fnc_econBonus) exitWith {ceil (SWLC_econScanNominal * CFG("radioScanDiscount"))};
	if (isNil "SWLC_econScanNominal") exitWith {[] call SWLC_fnc_adScanCost};
	SWLC_econScanNominal
};

SWLC_fnc_econSquadCap = {
	params ["_side"];
	CFG("shopGroupSize") + ([0, CFG("townSquadBonus")] select ([_side, "T"] call SWLC_fnc_econBonus))
};

// Rearm and repair work near the base, a connected industrial sector, or any owned sector.
SWLC_fnc_econResupplyAllowed = {
	params ["_side", "_pos"];
	if !(ECON_ON("ruleStretchedSupply")) exitWith {true};
	(missionNamespace getVariable [format ["SWLC_econSupply_%1", _side], []]) findIf {(_pos distance2D (_x # 0)) <= (_x # 1)} >= 0
};

// Income

// Pays every living warlord of the side, or just _to. The amount is per person.
SWLC_fnc_econPay = {
	params ["_side", "_amount", "_reason", ["_to", objNull], ["_fields", []]];
	if (_amount <= 0) exitWith {};
	private _cap = missionNamespace getVariable ["BIS_WL_maxCP", 10e10];
	private _list = if (isNull _to) then {[_side] call SWLC_fnc_adWarlords} else {[_to]};
	{
		_x setVariable ["BIS_WL_funds", ((_x getVariable ["BIS_WL_funds", 0]) + _amount) min _cap, true];
	} forEach _list;
	[_reason, _side, [["amount", round _amount], ["paid", count _list]] + _fields] call SWLC_fnc_econLog;
};

// The base pays the flat income. Other sectors pay their own value times a falling multiplier,
// with the richest sector counted first. The payoff reads these values live.
SWLC_fnc_econApplyIncome = {
	params ["_side"];
	if !(ECON_ON("ruleIncome")) exitWith {};
	private _base = [_side] call SWLC_fnc_adBase;
	private _curve = CFG("incomeSectorCurve");
	// A sector taken since the last econSectors keeps its value until then: the capture top-up needs what Warlords paid on.
	private _rest = (([_side] call SWLC_fnc_adOwned) - [_base]) select {(_x getVariable ["SWLC_econOwner", sideUnknown]) == _side};
	_rest = [_rest, [], {_x getVariable "SWLC_econValue"}, "DESCEND"] call BIS_fnc_sortBy;

	private _writes = 0;
	if (!isNull _base && {([_base] call SWLC_fnc_adValue) != CFG("incomeFlatBase")}) then {
		_base setVariable ["BIS_WL_value", CFG("incomeFlatBase"), true];
		_writes = _writes + 1;
	};
	private _values = [];
	{
		private _v = round ((_x getVariable "SWLC_econValue") * (_curve select (_forEachIndex min ((count _curve) - 1))));
		_values pushBack _v;
		if (([_x] call SWLC_fnc_adValue) != _v) then {
			_x setVariable ["BIS_WL_value", _v, true];
			_writes = _writes + 1;
		};
	} forEach _rest;

	if (_writes > 0) then {
		SWLC_econValueRev = SWLC_econValueRev + 1;
		publicVariable "SWLC_econValueRev";
		["income", _side, [["base", CFG("incomeFlatBase")], ["sectors", count _rest], ["values", if (_values isEqualTo []) then {"-"} else {_values joinString ","}]]] call SWLC_fnc_econLog;
	};
};

// Pays for kills: the group leader if the group is a warlord's, otherwise split across the side.
SWLC_fnc_econOnKilled = {
	params ["_unit", "_killer", "_instigator"];
	if !(ECON_ON("ruleCombatIncome")) exitWith {};
	private _who = if (isNull _instigator) then {_killer} else {_instigator};
	if (isNull _who || {_who isEqualTo _unit}) exitWith {};
	if !(_who isKindOf "CAManBase") then {_who = effectiveCommander _who};
	if (isNull _who) exitWith {};

	private _kSide = side group _who;
	private _class = typeOf _unit;
	private _vSide = [_class] call SWLC_fnc_econCfgSide;
	if !(_kSide in [west, east]) exitWith {};
	if !(_vSide in [west, east]) exitWith {};
	if (_kSide == _vSide) exitWith {};

	private _pay = switch (true) do {
		case (_unit isKindOf "CAManBase"): {CFG("incomeKillInfantry")};
		case ([_class] call SWLC_fnc_econIsArmour): {CFG("incomeKillArmour")};
		case (_unit isKindOf "Air"): {CFG("incomeKillAir")};
		case (_unit isKindOf "LandVehicle" || {_unit isKindOf "Ship"}): {CFG("incomeKillLight")};
		default {0};
	};

	private _wiped = false;
	if (_unit isKindOf "CAManBase") then {
		private _g = group _unit;
		if (!isNull _g) then {
			// A group shrinks as its dead are removed, so remember the largest it was seen.
			private _size = (_g getVariable ["SWLC_econSize", 0]) max (count units _g);
			_g setVariable ["SWLC_econSize", _size];
			if (_size >= 2 && {(units _g) findIf {alive _x} < 0} && {time >= (_g getVariable ["SWLC_econWipeAt", -1])}) then {
				_g setVariable ["SWLC_econWipeAt", time + CFG("incomeSquadWipeCooldown")];
				_pay = _pay + CFG("incomeSquadWipe");
				_wiped = true;
			};
		};
	};
	if (_pay <= 0) exitWith {};

	private _fields = [["class", _class], ["wipe", [0, 1] select _wiped]];
	private _leader = leader group _who;
	if (_leader in BIS_WL_allWarlords && {alive _leader}) exitWith {
		[_kSide, _pay, "kill", _leader, _fields] call SWLC_fnc_econPay;
	};
	private _n = count ([_kSide] call SWLC_fnc_adWarlords);
	if (_n > 0) then {[_kSide, ceil (_pay / _n), "kill", objNull, _fields] call SWLC_fnc_econPay};
};

// Sector changes, once per tick for both sides: capture payouts, the counterattack window,
// fortifications coming down, and defended sectors.
SWLC_fnc_econSectors = {
	private _sides = [west, east];
	{
		private _s = _x;
		private _owner = [_s] call SWLC_fnc_adOwner;
		private _old = _s getVariable ["SWLC_econOwner", sideUnknown];
		private _name = [_s] call SWLC_fnc_adName;

		if (_owner != _old) then {
			_s setVariable ["SWLC_econOwner", _owner];
			_s setVariable ["SWLC_econHeldSince", time];
			_s setVariable ["SWLC_econSeizedAt", -1];
			_s setVariable ["SWLC_econSeizedMen", 0];
			[_s] call SWLC_fnc_econDropFort;
			// Warlords pays 10 x value x income multiplier, once per side per sector, on the discounted value. Top up the difference.
			private _paidBy = _s getVariable ["SWLC_econPaidBy", []];
			if (_owner in _sides && {ECON_ON("ruleIncome")} && {!(_owner in _paidBy)}) then {
				_s setVariable ["SWLC_econPaidBy", _paidBy + [_owner]];
				private _short = (_s getVariable ["SWLC_econValue", 0]) - ([_s] call SWLC_fnc_adValue);
				[_owner, round (10 * _short * (missionNamespace getVariable ["BIS_WL_CPIncomeMult", 1])), "capturetopup", objNull, [["sector", _name]]] call SWLC_fnc_econPay;
			};
			if (_owner in _sides && {ECON_ON("ruleCombatIncome")}) then {
				[_owner, CFG("incomeCaptureBonus"), "capture", objNull, [["sector", _name]]] call SWLC_fnc_econPay;
			};
			if (_old in _sides && {ECON_ON("ruleCounterattack")} && {!([_s] call SWLC_fnc_adIsBase)}) then {
				private _key = format ["SWLC_econCounter_%1", _old];
				(missionNamespace getVariable _key) pushBack [[_s] call SWLC_fnc_adPos, time + CFG("counterattackSeconds")];
				["counteropen", _old, [["sector", _name]]] call SWLC_fnc_econLog;
				[_old, "econcounter", [_name, round (CFG("counterattackSeconds") / 60)]] call SWLC_fnc_radio;
			};
		};

		// A defence counts once the enemy's countdown has been stopped for a while.
		if (_owner in _sides && {ECON_ON("ruleCombatIncome")}) then {
			if ([_owner, _s] call SWLC_fnc_adEnemySeizing) then {
				_s setVariable ["SWLC_econSeizedAt", time];
				private _enemy = [_owner] call SWLC_fnc_adEnemySide;
				private _men = {side group _x == _enemy && {[_s, getPosATL _x] call SWLC_fnc_adInSquare}} count allUnits;
				_s setVariable ["SWLC_econSeizedMen", (_s getVariable ["SWLC_econSeizedMen", 0]) max _men];
			} else {
				private _at = _s getVariable ["SWLC_econSeizedAt", -1];
				if (_at >= 0 && {(time - _at) >= CFG("defenceSuccessQuietSeconds")}) then {
					_s setVariable ["SWLC_econSeizedAt", -1];
					private _peak = _s getVariable ["SWLC_econSeizedMen", 0];
					_s setVariable ["SWLC_econSeizedMen", 0];
					if (_peak >= CFG("defencePayoutMinEnemies") && {time >= (_s getVariable ["SWLC_econDefendPayAt", -1])}) then {
						_s setVariable ["SWLC_econDefendPayAt", time + CFG("defencePayoutCooldown")];
						[_owner, CFG("incomeDefencePayout"), "defended", objNull, [["sector", _name], ["enemies", _peak]]] call SWLC_fnc_econPay;
						[_owner, "econdefended", [_name, CFG("incomeDefencePayout")]] call SWLC_fnc_radio;
					} else {
						["defendnopay", _owner, [["sector", _name], ["enemies", _peak]]] call SWLC_fnc_econLog;
					};
				};
			};
		};
	} forEach SWLC_sectors;

	// Counterattack windows that have run out.
	{
		private _key = format ["SWLC_econCounter_%1", _x];
		private _list = (missionNamespace getVariable _key) select {time < (_x # 1)};
		missionNamespace setVariable [_key, _list];
		private _shown = _list apply {_x # 0};
		private _pub = format ["SWLC_counter_%1", _x];
		if ((missionNamespace getVariable [_pub, []]) isNotEqualTo _shown) then {
			missionNamespace setVariable [_pub, _shown, true];
		};
	} forEach _sides;
};

// Fortress base

SWLC_fnc_econSpotFor = {
	params ["_class", "_centre", "_bearing", "_radius"];
	private _found = [];
	{
		private _p = _centre getPos [_radius, _bearing + _x];
		private _f = _p findEmptyPosition [0, 30, _class];
		if (_f isNotEqualTo [] && {!surfaceIsWater _f} && {!isOnRoad _f}) exitWith {_found = _f};
	} forEach [0, 20, -20, 40, -40, 60, -60, 90, -90];
	_found
};

SWLC_fnc_econSpawnStatic = {
	params ["_class", "_pos", "_dir"];
	private _v = createVehicle [_class, _pos, [], 0, "CAN_COLLIDE"];
	_v setDir _dir;
	_v setPosATL [_pos # 0, _pos # 1, 0];
	createVehicleCrew _v;
	_v setVariable ["SWLC_econCrew", crew _v];
	_v
};

// Removes a gun we built and only the crew we made for it. If anyone else is manning it, the gun stays.
SWLC_fnc_econRemoveStatic = {
	params ["_o"];
	if (isNull _o) exitWith {};
	private _own = _o getVariable ["SWLC_econCrew", []];
	private _others = ((crew _o) select {alive _x}) - _own;
	{
		if (!isNull _x) then {
			if (_x in (crew _o)) then {_o deleteVehicleCrew _x} else {deleteVehicle _x};
		};
	} forEach _own;
	if (_others isEqualTo []) then {deleteVehicle _o};
};

SWLC_fnc_econFortressBuild = {
	params ["_side"];
	if !(ECON_ON("ruleFortressBase")) exitWith {};
	private _base = [_side] call SWLC_fnc_adBase;
	private _enemyBase = [[_side] call SWLC_fnc_adEnemySide] call SWLC_fnc_adBase;
	if (isNull _base || {isNull _enemyBase}) exitWith {};

	private _centre = [_base] call SWLC_fnc_adPos;
	private _bearing = _centre getDir ([_enemyBase] call SWLC_fnc_adPos);
	private _radius = ([_base] call SWLC_fnc_adSize) * 0.35;
	private _key = format ["fortressStatics%1", _side];
	private _classes = SWLC_settings getOrDefault [_key, []];
	private _slots = [];
	{
		private _b = _bearing + (_forEachIndex - ((count _classes) - 1) / 2) * CFG("fortressArcDegrees");
		private _p = [_x, _centre, _b, _radius] call SWLC_fnc_econSpotFor;
		if (_p isNotEqualTo []) then {
			_slots pushBack [_x, _p, _b, [_x, _p, _b] call SWLC_fnc_econSpawnStatic, -1];
		};
	} forEach _classes;
	missionNamespace setVariable [format ["SWLC_econFortress_%1", _side], _slots];
	["fortress", _side, [["statics", count _slots], ["wanted", count _classes]]] call SWLC_fnc_econLog;
};

// A lost gun comes back after a while, but not during an attack on the base.
SWLC_fnc_econFortressTick = {
	params ["_side"];
	if !(ECON_ON("ruleFortressBase")) exitWith {};
	if !([format ["fort_%1", _side], 20] call SWLC_fnc_econDue) exitWith {};
	private _cornered = [_side] call SWLC_fnc_econCornered;
	{
		_x params ["_class", "_pos", "_dir", "_veh", "_deadAt"];
		if (!alive _veh || {(crew _veh) findIf {alive _x} < 0}) then {
			if (_deadAt < 0) then {
				_x set [4, time];
			} else {
				if (!_cornered && {(time - _deadAt) >= CFG("fortressRebuildSeconds")}) then {
					[_veh] call SWLC_fnc_econRemoveStatic;
					_x set [3, [_class, _pos, _dir] call SWLC_fnc_econSpawnStatic];
					_x set [4, -1];
					["fortrebuilt", _side, [["class", _class]]] call SWLC_fnc_econLog;
				};
			};
		} else {
			if (_deadAt >= 0) then {_x set [4, -1]};
		};
	} forEach (missionNamespace getVariable [format ["SWLC_econFortress_%1", _side], []]);
};

// Sectors dig in

SWLC_fnc_econDropFort = {
	params ["_s"];
	{[_x] call SWLC_fnc_econRemoveStatic} forEach (_s getVariable ["SWLC_econFort", []]);
	_s setVariable ["SWLC_econFort", []];
};

SWLC_fnc_econBuildFort = {
	params ["_side", "_s"];
	private _centre = [_s] call SWLC_fnc_adPos;
	private _links = ([_s] call SWLC_fnc_adLinks) select {([_x] call SWLC_fnc_adOwner) != _side};
	private _toward = if (_links isEqualTo []) then {
		[[_side] call SWLC_fnc_adEnemySide] call SWLC_fnc_adBase
	} else {
		private _sorted = [_links, [], {_centre distance2D ([_x] call SWLC_fnc_adPos)}] call BIS_fnc_sortBy;
		_sorted # 0
	};
	private _bearing = if (isNull _toward) then {random 360} else {_centre getDir ([_toward] call SWLC_fnc_adPos)};
	private _key = format ["sectorFortStatic%1", _side];
	private _class = SWLC_settings getOrDefault [_key, ""];
	private _spot = if (_class == "") then {[]} else {[_class, _centre, _bearing, ([_s] call SWLC_fnc_adSize) * 0.3] call SWLC_fnc_econSpotFor};
	if (_spot isEqualTo []) exitWith {
		// One attempt only. An empty list would be tried again every tick.
		_s setVariable ["SWLC_econFort", [objNull]];
		["fortfailed", _side, [["sector", [_s] call SWLC_fnc_adName]]] call SWLC_fnc_econLog;
	};

	private _built = [[_class, _spot, _bearing] call SWLC_fnc_econSpawnStatic];
	{
		_x params ["_bagClass", "_offset", "_dist"];
		private _p = _spot getPos [_dist, _bearing + _offset];
		if !(surfaceIsWater _p) then {
			private _bag = createVehicle [_bagClass, _p, [], 0, "CAN_COLLIDE"];
			_bag setDir (_bearing + _offset);
			_bag setPosATL [_p # 0, _p # 1, 0];
			_built pushBack _bag;
		};
	} forEach [["Land_BagFence_Long_F", 0, 3.5], ["Land_BagFence_Round_F", 60, 4], ["Land_BagFence_Round_F", -60, 4]];
	_s setVariable ["SWLC_econFort", _built];
	["fort", _side, [["sector", [_s] call SWLC_fnc_adName], ["objects", count _built]]] call SWLC_fnc_econLog;
	[_side, "econdugin", [[_s] call SWLC_fnc_adName]] call SWLC_fnc_radio;
};

SWLC_fnc_econSectorForts = {
	params ["_side"];
	if !(ECON_ON("ruleSectorFort")) exitWith {};
	private _hold = CFG("sectorFortHoldSeconds");
	{
		if (!([_x] call SWLC_fnc_adIsBase)
			&& {(_x getVariable ["SWLC_econFort", []]) isEqualTo []}
			&& {(time - (_x getVariable ["SWLC_econHeldSince", time])) >= _hold}
			&& {!([_side, _x] call SWLC_fnc_adEnemySeizing)}) then {
			[_side, _x] call SWLC_fnc_econBuildFort;
		};
	} forEach ([_side] call SWLC_fnc_adOwned);
};

// Stretched supply: support vehicles stop supplying outside the zones

SWLC_fnc_econSupplyTick = {
	params ["_side"];
	if !(ECON_ON("ruleStretchedSupply")) exitWith {};
	if !([format ["supply_%1", _side], CFG("supplyCheckSeconds")] call SWLC_fnc_econDue) exitWith {};
	{
		private _veh = _x;
		private _class = typeOf _veh;
		if (alive _veh && {[_class] call SWLC_fnc_econIsResupply} && {([_class] call SWLC_fnc_econCfgSide) == _side}) then {
			private _allowed = [_side, getPosATL _veh] call SWLC_fnc_econResupplyAllowed;
			if ((_veh getVariable ["SWLC_econSupplyOn", true]) isNotEqualTo _allowed) then {
				_veh setVariable ["SWLC_econSupplyOn", _allowed];
				private _c = configFile >> "CfgVehicles" >> _class;
				// Leaving range stores what the truck has left. Coming back restores that amount, not a full load.
				private _held = _veh getVariable ["SWLC_econSupplyHeld", createHashMap];
				_veh setVariable ["SWLC_econSupplyHeld", _held];
				{
					_x params ["_cfg", "_get", "_set"];
					if (getNumber (_c >> _cfg) > 0) then {
						if (_allowed) then {
							[_veh, _held getOrDefault [_cfg, 1]] remoteExecCall [_set, _veh];
						} else {
							_held set [_cfg, _veh call _get];
							[_veh, 0] remoteExecCall [_set, _veh];
						};
					};
				} forEach [["transportAmmo", {getAmmoCargo _this}, "setAmmoCargo"], ["transportRepair", {getRepairCargo _this}, "setRepairCargo"], ["transportFuel", {getFuelCargo _this}, "setFuelCargo"]];
				["supply", _side, [["class", _class], ["allowed", _allowed]]] call SWLC_fnc_econLog;
			};
		};
	} forEach vehicles;
};

// Radio tower: the contacts this side has actually seen, for the map

SWLC_fnc_econContacts = {
	params ["_cmd"];
	private _side = _cmd get "side";
	if !([format ["contacts_%1", _side], CFG("contactPublishSeconds")] call SWLC_fnc_econDue) exitWith {};
	private _key = format ["SWLC_contacts_%1", _side];
	private _rows = [];
	if ([_side, "R"] call SWLC_fnc_econBonus && {[_side] call SWLC_fnc_adSideHasPlayers}) then {
		private _maxAge = CFG("contactMaxAge");
		{
			private _age = time - (_x get "seen");
			if (_age <= _maxAge) then {
				private _p = _x get "pos";
				_rows pushBack [round (_p # 0), round (_p # 1), _x get "cat", round _age];
			};
		} forEach (_cmd get "board");
		_rows = ([_rows, [], {_x # 3}] call BIS_fnc_sortBy) select [0, CFG("contactMaxRows")];
	};
	if ((missionNamespace getVariable [_key, []]) isNotEqualTo _rows) then {
		missionNamespace setVariable [_key, _rows, true];
	};
};

// An all-AI side gets a little more CP for each human on the other side.
SWLC_fnc_econScale = {
	params ["_side"];
	if !(ECON_ON("ruleScaleAI")) exitWith {};
	if !([format ["scale_%1", _side], 60] call SWLC_fnc_econDue) exitWith {};
	if ([_side] call SWLC_fnc_adSideHasPlayers) exitWith {};
	private _other = [_side] call SWLC_fnc_adEnemySide;
	private _humans = ({side group _x == _other} count allPlayers) max CFG("scaleFakeHumans");
	if (_humans <= 0) exitWith {};
	private _amount = CFG("scaleCpPerHumanPerMin") * (_humans min CFG("scaleMaxHumans"));
	[_side, _amount, "scale", objNull, [["humans", _humans]]] call SWLC_fnc_econPay;
};

// Once a minute for the soak comparison.
SWLC_fnc_econSnapshot = {
	params ["_side"];
	if !([format ["snap_%1", _side], 60] call SWLC_fnc_econDue) exitWith {};
	private _wl = [_side] call SWLC_fnc_adWarlords;
	private _cp = 0;
	{_cp = _cp + (_x getVariable ["BIS_WL_funds", 0])} forEach _wl;
	private _men = allUnits select {side group _x == _side};
	private _at = {([secondaryWeapon _x] call SWLC_fnc_adLauncherKind) == "AT"} count _men;
	private _veh = {
		alive _x && {_x isKindOf "LandVehicle"} && {!(_x isKindOf "StaticWeapon")} && {(crew _x) findIf {side group _x == _side} >= 0}
	} count vehicles;
	["snapshot", _side, [
		["sectors", count ([_side] call SWLC_fnc_adOwned)],
		["income", round ([_side] call SWLC_fnc_adSideIncome)],
		["cp", round _cp],
		["warlords", count _wl],
		["men", count _men],
		["at", _at],
		["vehicles", _veh]
	]] call SWLC_fnc_econLog;
};

// Round time limit

SWLC_fnc_econSectorValueSum = {
	params ["_side"];
	private _sum = 0;
	{_sum = _sum + (_x getVariable ["SWLC_econValue", 0])} forEach ([_side] call SWLC_fnc_adOwned);
	_sum
};

SWLC_fnc_econRoundLimit = {
	if (SWLC_econRoundEnd == -2 || {CFG("roundTimeLimitMinutes") <= 0}) exitWith {};
	if (SWLC_econRoundEnd < 0) then {SWLC_econRoundEnd = time + CFG("roundTimeLimitMinutes") * 60};
	private _left = SWLC_econRoundEnd - time;
	{
		_x params ["_seconds", "_key"];
		private _flag = format ["SWLC_econWarned_%1", _key];
		if (_left <= _seconds && {_left > 0} && {isNil _flag}) then {
			missionNamespace setVariable [_flag, true];
			[west, _key, []] call SWLC_fnc_radio;
			[east, _key, []] call SWLC_fnc_radio;
		};
	} forEach [[300, "econlimit5"], [60, "econlimit1"]];
	if (_left > 0) exitWith {};

	private _w = count ([west] call SWLC_fnc_adOwned);
	private _e = count ([east] call SWLC_fnc_adOwned);
	private _winner = sideUnknown;
	private _rule = "sectors";
	if (_w != _e) then {
		_winner = [east, west] select (_w > _e);
	} else {
		private _wv = [west] call SWLC_fnc_econSectorValueSum;
		private _ev = [east] call SWLC_fnc_econSectorValueSum;
		_rule = "value";
		if (_wv != _ev) then {
			_winner = [east, west] select (_wv > _ev);
		} else {
			if (SWLC_econSuddenDeaths < CFG("roundSuddenDeathMax")) exitWith {
				SWLC_econSuddenDeaths = SWLC_econSuddenDeaths + 1;
				SWLC_econRoundEnd = time + CFG("roundSuddenDeathSeconds");
				["roundlimit", "-", [["result", "suddendeath"], ["count", SWLC_econSuddenDeaths]]] call SWLC_fnc_econLog;
				[west, "econsuddendeath", [round (CFG("roundSuddenDeathSeconds") / 60)]] call SWLC_fnc_radio;
				[east, "econsuddendeath", [round (CFG("roundSuddenDeathSeconds") / 60)]] call SWLC_fnc_radio;
			};
			private _wm = {side group _x == west} count allUnits;
			private _em = {side group _x == east} count allUnits;
			_rule = "men";
			_winner = if (_wm == _em) then {_rule = "coin"; selectRandom [west, east]} else {[east, west] select (_wm > _em)};
		};
	};
	if (_winner == sideUnknown) exitWith {};

	SWLC_econRoundEnd = -2;
	private _loserBase = [[_winner] call SWLC_fnc_adEnemySide] call SWLC_fnc_adBase;
	["roundlimit", _winner, [["result", "win"], ["rule", _rule], ["west", _w], ["east", _e]]] call SWLC_fnc_econLog;
	[_winner, "econlimitwin", []] call SWLC_fnc_radio;
	[[_winner] call SWLC_fnc_adEnemySide, "econlimitloss", []] call SWLC_fnc_radio;
	// Warlords ends the round when a base changes hands.
	_loserBase setVariable ["BIS_WL_sectorSide", _winner, true];
};

// Commander stage

SWLC_fnc_econTick = {
	params ["_cmd"];
	if !(CFG("rulesVariant")) exitWith {};
	private _side = _cmd get "side";
	[_side] call SWLC_fnc_econUpdateCaps;
	[_side] call SWLC_fnc_econApplyIncome;
	[_side] call SWLC_fnc_econPublishZones;
	[_side] call SWLC_fnc_econFortressTick;
	[_side] call SWLC_fnc_econSectorForts;
	[_side] call SWLC_fnc_econSupplyTick;
	[_cmd] call SWLC_fnc_econContacts;
	[_side] call SWLC_fnc_econScale;
	[_side] call SWLC_fnc_econSnapshot;
	if (_side == west) then {
		[] call SWLC_fnc_econSectors;
		[] call SWLC_fnc_econRoundLimit;
	};
};
