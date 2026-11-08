// Spending and kit: the CP reserve, the side's shopping list, sector scans, and kit swaps at the muster crate.
#include "macros.hpp"

// Buy lists come from Warlords' own requisition data, read once it exists.
SWLC_fnc_logInit = {
	params ["_cmd"];
	if (!isNil {_cmd get "catalog"}) exitWith {};
	private _side = _cmd get "side";
	if (([_side, 1] call SWLC_fnc_adPurchasable) isEqualTo []) exitWith {};
	private _catalog = [_side] call SWLC_fnc_adCatalog;
	_cmd set ["catalog", _catalog];
	_cmd set ["infantry", [_side] call SWLC_fnc_adInfantryList];
	_cmd set ["kitTable", [_side] call SWLC_fnc_adKitTable];
	{
		_x params ["_cls", "_cost", "_seats", "_role", "_heavy"];
		["C_CATALOG", [["side", _side], ["class", _cls], ["cost", _cost], ["seats", _seats], ["role", _role], ["heavy", _heavy]]] call SWLC_fnc_log;
	} forEach _catalog;
	["C_CATALOG", [["side", _side], ["kit", str (_cmd get "kitTable")], ["infantry", count (_cmd get "infantry")]]] call SWLC_fnc_log;
};

SWLC_fnc_cpReserve = {
	params ["_side"];
	(CFG("cpReserveMinutes") * ([_side] call SWLC_fnc_adSideIncome)) min CFG("cpReserveMax")
};

// CP the commander may spend right now.
SWLC_fnc_cpFree = {
	params ["_side"];
	([_side] call SWLC_fnc_adSideCP) - ([_side] call SWLC_fnc_cpReserve)
};

// Every purchase goes through here so the reserve always holds. Returns the spawned objects, or [].
SWLC_fnc_logBuy = {
	params ["_cmd", "_buyer", "_classes", "_cost", "_what"];
	private _side = _cmd get "side";
	private _reserve = [_side] call SWLC_fnc_cpReserve;
	private _cp = [_side] call SWLC_fnc_adSideCP;
	if ((_cp - _cost) < _reserve) exitWith {[]};
	private _items = [_side, _buyer, _classes, _cost, _cmd get "dropHelper"] call SWLC_fnc_adBuy;
	if (_items isNotEqualTo []) then {
		["C_BUY", [["side", _side], ["what", _what], ["class", _classes # 0], ["cost", _cost], ["cp_before", round _cp], ["cp_after", round ([_side] call SWLC_fnc_adSideCP)], ["reserve", round _reserve], ["buyer", groupId group _buyer]]] call SWLC_fnc_log;
	};
	_items
};

// The shopping list for groups mustering at a sector, most important first. Never delays the go signal.
SWLC_fnc_shopTick = {
	params ["_cmd", "_w", "_staged", "_musterPos"];
	if (isNil {_cmd get "catalog"}) exitWith {};
	private _side = _cmd get "side";
	private _plan = _w get "plan";
	private _target = _w get "target";

	// A scan comes first when there's money for it and for the wave's transport too.
	private _scanWanted = CFG("scanBuying") && {_plan get "scan"} && {!(_w getOrDefault ["scanned", false])};
	private _transportCost = 0;
	if (CFG("vehiclesEnabled") && {[_cmd, _w, _musterPos] call SWLC_fnc_vehWorthDriving}) then {
		{
			private _men = [_x] call SWLC_fnc_groupMen;
			private _pick = [_cmd, _men] call SWLC_fnc_vehCheapestTransport;
			if (_pick isNotEqualTo [] && {count ([_x] call SWLC_fnc_vehRecOf) == 0}) then {_transportCost = _transportCost + (_pick # 1)};
		} forEach _staged;
	};
	if (_scanWanted && {([_side] call SWLC_fnc_cpFree) >= ([] call SWLC_fnc_adScanCost) + _transportCost}) then {
		[_cmd, _w] call SWLC_fnc_shopScan;
		_scanWanted = false;
	};

	[_cmd, _w, _staged] call SWLC_fnc_shopInfantry;
	[_cmd, _w, _staged, _musterPos] call SWLC_fnc_vehShop;

	if (_scanWanted && {([_side] call SWLC_fnc_cpFree) >= ([] call SWLC_fnc_adScanCost)}) then {
		[_cmd, _w] call SWLC_fnc_shopScan;
	};

	private _sig = [_scanWanted && {!(_w getOrDefault ["scanned", false])}, _transportCost, _plan get "combatVehicle", round ([_side] call SWLC_fnc_cpFree) / 100];
	if (_sig isNotEqualTo (_w getOrDefault ["shopSig", []])) then {
		_w set ["shopSig", _sig];
		["C_SHOP", [["side", _side], ["wave", _w get "id"], ["target", [_target] call SWLC_fnc_adName], ["scan", _sig # 0], ["transport_cost", _sig # 1], ["combat", _sig # 2],
			["cp", round ([_side] call SWLC_fnc_adSideCP)], ["reserve", round ([_side] call SWLC_fnc_cpReserve)]]] call SWLC_fnc_log;
	};
};

SWLC_fnc_shopScan = {
	params ["_cmd", "_w"];
	if ([_cmd get "side", _w get "target", SWLC_fnc_intelPostScan] call SWLC_fnc_adScan) then {
		_w set ["scanned", true];
	};
};

// Tops groups up with riflemen. Kit comes first, so these are general reinforcements.
SWLC_fnc_shopInfantry = {
	params ["_cmd", "_w", "_staged"];
	private _side = _cmd get "side";
	private _list = _cmd get "infantry";
	if (_list isEqualTo []) exitWith {};
	private _cheapest = _list select 0;
	{if ((_x # 1) < (_cheapest # 1)) then {_cheapest = _x}} forEach _list;
	private _bought = 0;
	{
		private _g = _x;
		private _leader = leader _g;
		private _men = [_g] call SWLC_fnc_groupMen;
		private _rec = [_g] call SWLC_fnc_vehRecOf;
		private _room = if (count _rec > 0) then {(_rec get "seats") - _men} else {1e6};
		private _missing = (CFG("shopGroupSize") - _men) min _room;
		if (_missing > 0 && {alive _leader} && {[_leader] call SWLC_fnc_adIsWarlord} && {!isPlayer _leader}) then {
			for "_i" from 1 to _missing do {
				if (_bought >= CFG("shopMaxInfantryPerTick")) exitWith {};
				private _items = [_cmd, _leader, [_cheapest # 0], _cheapest # 1, "infantry"] call SWLC_fnc_logBuy;
				if (_items isEqualTo []) exitWith {_bought = 1e6};
				_bought = _bought + 1;
			};
		};
		if (_bought >= CFG("shopMaxInfantryPerTick")) exitWith {};
	} forEach _staged;
};

// Kit swaps at the crate. Tasks are per unit; a unit walks to the crate, the swap is applied there.
SWLC_fnc_kitTick = {
	params ["_cmd", "_w", "_groups"];
	if !(CFG("kitEnabled")) exitWith {};
	if (isNil {_cmd get "kitTable"}) exitWith {};
	private _plan = _w get "plan";
	if (isNil "_plan") exitWith {};
	private _units = [];
	{_units append (([_x] call SWLC_fnc_alive) select {!isPlayer _x && {vehicle _x == _x}})} forEach _groups;
	if (_units isEqualTo []) exitWith {};

	private _table = _cmd get "kitTable";
	private _haveAT = {([secondaryWeapon _x] call SWLC_fnc_adLauncherKind) == "AT"} count _units;
	private _haveAA = {([secondaryWeapon _x] call SWLC_fnc_adLauncherKind) == "AA"} count _units;
	private _wantAT = _plan get "atWanted";
	private _wantAA = [0, 1] select (_plan get "aa");
	private _pendingAT = {(_x getVariable ["SWLC_kitTask", ""]) == "AT"} count _units;
	private _pendingAA = {(_x getVariable ["SWLC_kitTask", ""]) == "AA"} count _units;
	private _free = _units select {(_x getVariable ["SWLC_kitTask", ""]) == "" && {secondaryWeapon _x == ""}};
	_free = [_free, [], {[1, 0] select (_x == leader group _x)}, "DESCEND"] call BIS_fnc_sortBy;

	private _needAT = (_wantAT - _haveAT - _pendingAT) min ((count _free) max 0);
	if (_needAT > 0 && {"AT" in _table}) then {
		for "_i" from 1 to _needAT do {
			private _u = _free deleteAt 0;
			[_cmd, _w, _u, "AT"] call SWLC_fnc_kitAssign;
		};
		[_cmd get "side", "kit"] call SWLC_fnc_radio;
	};
	if ((_wantAA - _haveAA - _pendingAA) > 0 && {"AA" in _table} && {_free isNotEqualTo []}) then {
		[_cmd, _w, _free deleteAt 0, "AA"] call SWLC_fnc_kitAssign;
	};

	// Smoke and ammo: one trip per group, once per wave.
	if (_plan get "smoke" || {_plan get "ammo"}) then {
		{
			private _g = _x;
			if ((_g getVariable ["SWLC_kitGeneral", -1]) != (_w get "id")) then {
				_g setVariable ["SWLC_kitGeneral", _w get "id"];
				private _men = ([_g] call SWLC_fnc_alive) select {!isPlayer _x && {vehicle _x == _x} && {(_x getVariable ["SWLC_kitTask", ""]) == ""}};
				if (_men isNotEqualTo []) then {[_cmd, _w, selectRandom _men, "GEN"] call SWLC_fnc_kitAssign};
			};
		} forEach _groups;
	};

	// Walkers who've reached the crate get their kit.
	private _crate = _cmd get "crate";
	{
		private _u = _x;
		private _task = _u getVariable ["SWLC_kitTask", ""];
		if (_task != "") then {
			if ((_u distance _crate) <= CFG("kitCrateRadius")) then {
				[_cmd, _w, _u, false] call SWLC_fnc_kitApply;
			} else {
				if ((time - (_u getVariable ["SWLC_kitSince", time])) >= CFG("kitWalkTimeout")) then {
					[_cmd, _w, _u, true] call SWLC_fnc_kitApply;
				};
			};
		};
	} forEach _units;
};

SWLC_fnc_kitAssign = {
	params ["_cmd", "_w", "_u", "_task"];
	_u setVariable ["SWLC_kitTask", _task];
	_u setVariable ["SWLC_kitSince", time];
	_u doMove getPosATL (_cmd get "crate");
	["C_KIT", [["side", _cmd get "side"], ["wave", _w get "id"], ["group", groupId group _u], ["event", "assign"], ["kit", _task]]] call SWLC_fnc_log;
};

SWLC_fnc_kitApply = {
	params ["_cmd", "_w", "_u", "_forced"];
	private _task = _u getVariable ["SWLC_kitTask", ""];
	_u setVariable ["SWLC_kitTask", ""];
	private _table = _cmd get "kitTable";
	switch (_task) do {
		case "AT";
		case "AA": {
			(_table getOrDefault [_task, ["", "", ""]]) params ["_launcher", "_mag", "_pack"];
			if (_launcher != "") then {
				if (secondaryWeapon _u != "") then {_u removeWeapon secondaryWeapon _u};
				if (backpack _u == "" && {_pack != ""}) then {_u addBackpackGlobal _pack};
				_u addMagazines [_mag, CFG("kitRounds")];
				_u addWeapon _launcher;
			};
		};
		case "GEN": {
			private _plan = _w get "plan";
			if (_plan get "smoke") then {_u addMagazines ["SmokeShell", CFG("kitSmokePerGroup")]};
			if (_plan get "ammo") then {
				private _pm = primaryWeaponMagazine _u;
				if (_pm isNotEqualTo []) then {_u addMagazines [_pm # 0, CFG("kitExtraMags")]};
				_u addMagazines ["HandGrenade", CFG("kitExtraGrenades")];
			};
		};
	};
	if (_u != leader group _u) then {_u doFollow leader group _u};
	["C_KIT", [["side", _cmd get "side"], ["wave", _w get "id"], ["group", groupId group _u], ["event", "applied"], ["kit", _task], ["forced", _forced], ["launcher", secondaryWeapon _u]]] call SWLC_fnc_log;
};

// At the cap, anyone still walking gets their kit on the spot so the wave leaves equipped.
SWLC_fnc_kitFinish = {
	params ["_cmd", "_w", "_groups"];
	{
		{
			if ((_x getVariable ["SWLC_kitTask", ""]) != "" && {alive _x}) then {[_cmd, _w, _x, true] call SWLC_fnc_kitApply};
		} forEach units _x;
	} forEach _groups;
};

SWLC_fnc_kitPending = {
	params ["_g"];
	(units _g findIf {alive _x && {(_x getVariable ["SWLC_kitTask", ""]) != ""}}) >= 0
};

SWLC_fnc_kitCountAT = {
	params ["_groups"];
	private _n = 0;
	{
		_n = _n + ({alive _x && {([secondaryWeapon _x] call SWLC_fnc_adLauncherKind) == "AT"}} count units _x);
	} forEach _groups;
	_n
};
