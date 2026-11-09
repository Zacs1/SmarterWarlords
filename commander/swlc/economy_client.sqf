// Part C of the rules variant, on every machine with a player: prices, what can be bought, squad cap,
// respawn time and map markers. Plain SQF with no server functions, because a client never compiles
// the commander. The server publishes SWLC_econCfg once, then the per-side data this file reads.
// Keeps its own copy of the buy list, so the list AI units share with a host is never touched.
if (!hasInterface) exitWith {};

waitUntil {sleep 1; !isNil "SWLC_econCfg" && {!isNull player}};
SWLC_clEcon = createHashMapFromArray SWLC_econCfg;
if !(SWLC_clEcon get "on") exitWith {};

SWLC_clEconPub = {
	params ["_name", "_default"];
	missionNamespace getVariable [format ["SWLC_%1_%2", _name, side group player], _default]
};

SWLC_clEconIsArmour = {
	params ["_class"];
	_class isKindOf "Tank" || {_class isKindOf "Wheeled_APC_F"}
};

SWLC_clEconIsKit = {
	params ["_class"];
	private _known = SWLC_clEconKitCache getOrDefault [_class, -1];
	if (_known isNotEqualTo -1) exitWith {_known};
	private _c = configFile >> "CfgVehicles" >> _class;
	private _kit = (getText (_c >> "role")) in ["Marksman", "Sniper"]
		|| {(getArray (_c >> "weapons")) findIf {
			private _w = configFile >> "CfgWeapons" >> _x;
			getNumber (_w >> "type") == 4 && {
				private _mags = getArray (_w >> "magazines");
				_mags isNotEqualTo [] && {
					private _flags = getText (configFile >> "CfgAmmo" >> getText (configFile >> "CfgMagazines" >> (_mags # 0) >> "ammo") >> "aiAmmoUsageFlags");
					"256" in _flags || {"512" in _flags} || {"128" in _flags}
				}
			}
		} >= 0};
	SWLC_clEconKitCache set [_class, _kit];
	_kit
};

SWLC_clEconIsResupply = {
	params ["_class"];
	private _c = configFile >> "CfgVehicles" >> _class;
	getNumber (_c >> "transportAmmo") > 0 || {getNumber (_c >> "transportRepair") > 0} || {getNumber (_c >> "transportFuel") > 0}
};

SWLC_clEconAtBase = {
	params ["_pos"];
	(["econBase", []] call SWLC_clEconPub) params [["_c", []], ["_size", 0]];
	if (_c isEqualTo []) exitWith {false};
	private _h = _size / 2 + (SWLC_clEcon get "corneredBaseMargin");
	abs ((_pos # 0) - (_c # 0)) <= _h && {abs ((_pos # 1) - (_c # 1)) <= _h}
};

SWLC_clEconInZone = {
	params ["_zones", "_pos"];
	_zones findIf {(_pos distance2D (_x # 0)) <= (_x # 1)} >= 0
};

// The price multiplier at this spot, for one purchase category.
SWLC_clEconMult = {
	params ["_cat", "_caps", "_pos"];
	private _m = 1;
	if (_cat == 1 && {SWLC_clEcon get "caps"} && {"I" in _caps}) then {_m = _m * (SWLC_clEcon get "industrialVehicleDiscount")};
	if ((SWLC_clEcon get "cornered") && {["cornered", false] call SWLC_clEconPub} && {[_pos] call SWLC_clEconAtBase}) then {
		_m = _m * (SWLC_clEcon get "corneredDiscount");
	};
	if (SWLC_clEcon get "counter") then {
		private _r = SWLC_clEcon get "counterattackRadius";
		if ((["counter", []] call SWLC_clEconPub) findIf {(_pos distance2D _x) <= _r} >= 0) then {_m = _m * (SWLC_clEcon get "counterattackDiscount")};
	};
	_m max (SWLC_clEcon get "priceMultFloor")
};

// Patches our copy of the buy list in place. Only touches what has changed.
// Entry: [class, cost, requirements, name, preview, text, ...]. Category 7 is services.
SWLC_clEconApply = {
	private _caps = ["caps", []] call SWLC_clEconPub;
	private _pos = getPosATL player;
	private _atBase = [_pos] call SWLC_clEconAtBase;
	private _capsOn = SWLC_clEcon get "caps";
	private _zones = (["zones", [[], []]] call SWLC_clEconPub) # 0;
	private _canSupply = !(SWLC_clEcon get "stretched") || {[_zones, _pos] call SWLC_clEconInZone};
	private _fortress = SWLC_clEcon get "fortress";

	{
		private _cat = _forEachIndex;
		private _nominal = SWLC_clEconNominal # _cat;
		if (_cat < 7) then {
			private _mult = [_cat, _caps, _pos] call SWLC_clEconMult;
			{
				private _n = _nominal # _forEachIndex;
				private _class = _n # 0;
				private _req = +(_n # 2);
				private _note = "";
				if (_capsOn) then {
					private _kit = (_cat == 0 && {[_class] call SWLC_clEconIsKit}) || {_cat in [2, 6] && {"launch" in toLower _class}};
					if (_cat == 1 && {[_class] call SWLC_clEconIsArmour}) then {
						_req pushBack "M";
						_note = "Needs a military sector connected to your base.";
					};
					if (_kit && {!(_fortress && _atBase)}) then {
						_req pushBack "M";
						_note = "Needs a military sector connected to your base, or being at your own base.";
					};
				};
				if (_cat == 1 && {!_canSupply} && {[_class] call SWLC_clEconIsResupply}) then {
					_req pushBack "X";
					_note = "Out of supply range. Move closer to your base, an industrial sector or a held sector.";
				};
				if ((_x # 2) isNotEqualTo _req) then {_x set [2, _req]};
				private _text = if (_note == "") then {_n # 5} else {format ["%1<br/><br/><t color='#ffb000'>%2</t>", _n # 5, _note]};
				if ((_x # 5) isNotEqualTo _text) then {_x set [5, _text]};
				// Warlords charges these two from its own globals, whatever the list says.
				private _cost = if ((_n # 1) > 0 && {!(_class in ["Arsenal", "LastLoadout"])}) then {(round ((_n # 1) * _mult)) max 1} else {_n # 1};
				if ((_x # 1) != _cost) then {_x set [1, _cost]};
			} forEach _x;
		} else {
			private _i = _nominal findIf {(_x # 0) isEqualTo "Scan"};
			if (_i >= 0) then {
				private _scan = SWLC_clEconScan;
				if (_capsOn && {"R" in _caps}) then {_scan = ceil (_scan * (SWLC_clEcon get "radioScanDiscount"))};
				BIS_WL_scanCost = _scan;
				if (((_x # _i) # 1) != _scan) then {(_x # _i) set [1, _scan]};
			};
		};
	} forEach SWLC_clEconList;

	BIS_WL_maxSubordinates = SWLC_clEconMaxSubs + ([0, SWLC_clEcon get "townSquadBonus"] select (_capsOn && {"T" in _caps}));
};

// Map markers: contacts this side has seen, and sectors the commander may not vote for.
SWLC_clEconMarkers = {
	private _side = side group player;
	private _colour = ["ColorWEST", "ColorEAST"] select (_side == west);
	private _contacts = ["contacts", []] call SWLC_clEconPub;
	{
		_x params ["_px", "_py", "_cat", "_age"];
		private _m = format ["swlc_ct_%1", _forEachIndex];
		if (markerType _m == "") then {createMarkerLocal [_m, [_px, _py]]};
		_m setMarkerPosLocal [_px, _py];
		_m setMarkerTypeLocal "mil_warning";
		_m setMarkerColorLocal _colour;
		_m setMarkerSizeLocal [0.6, 0.6];
		_m setMarkerTextLocal format ["Contact: %1", _cat];
		_m setMarkerAlphaLocal (1 - ((_age / 300) min 0.6));
	} forEach _contacts;
	for "_i" from (count _contacts) to (SWLC_clEconContactsShown - 1) do {deleteMarkerLocal format ["swlc_ct_%1", _i]};
	SWLC_clEconContactsShown = count _contacts;

	private _banned = missionNamespace getVariable [format ["SWLC_banned_%1", _side], []];
	private _shown = 0;
	{
		private _name = _x getVariable ["Name", ""];
		if (_name == "") then {_name = format ["grid %1", mapGridPosition _x]};
		if (_name in _banned) then {
			private _m = format ["swlc_bn_%1", _shown];
			if (markerType _m == "") then {createMarkerLocal [_m, getPosATL _x]};
			_m setMarkerPosLocal getPosATL _x;
			_m setMarkerTypeLocal "mil_objective";
			_m setMarkerColorLocal "ColorGrey";
			_m setMarkerTextLocal format ["Banned: %1", _name];
			_shown = _shown + 1;
		};
	} forEach (missionNamespace getVariable ["BIS_WL_sectors", []]);
	for "_i" from _shown to (SWLC_clEconBannedShown - 1) do {deleteMarkerLocal format ["swlc_bn_%1", _i]};
	SWLC_clEconBannedShown = _shown;
};

SWLC_clEconKitCache = createHashMap;
SWLC_clEconContactsShown = 0;
SWLC_clEconBannedShown = 0;

// A faster respawn after dying near a connected town. The mission's own delay comes back after respawning.
addMissionEventHandler ["EntityKilled", {
	params ["_unit"];
	if (_unit isNotEqualTo player) exitWith {};
	if !(SWLC_clEcon get "caps") exitWith {};
	if !("T" in (["caps", []] call SWLC_clEconPub)) exitWith {};
	if ([(["zones", [[], []]] call SWLC_clEconPub) # 1, getPosATL _unit] call SWLC_clEconInZone) then {
		SWLC_clEconRespawnDelay = getMissionConfigValue ["respawnDelay", 5];
		setPlayerRespawnTime ((SWLC_clEcon get "townRespawnTime") min SWLC_clEconRespawnDelay);
	};
}];

addMissionEventHandler ["EntityRespawned", {
	params ["_new"];
	if (_new isEqualTo player && {!isNil "SWLC_clEconRespawnDelay"}) then {
		setPlayerRespawnTime SWLC_clEconRespawnDelay;
		SWLC_clEconRespawnDelay = nil;
	};
}];

[] spawn {
	scriptName "SWLC economy client";
	waitUntil {sleep 1; !isNil {player getVariable "BIS_WL_purchasable"} && {!isNil "BIS_WL_scanCost"}};
	SWLC_clEconNominal = +(player getVariable "BIS_WL_purchasable");
	SWLC_clEconList = +SWLC_clEconNominal;
	SWLC_clEconScan = BIS_WL_scanCost;
	SWLC_clEconMaxSubs = missionNamespace getVariable ["BIS_WL_maxSubordinates", 9];
	private _lastCaps = ["?"];
	private _lastRev = -1;
	private _nextMarkers = 0;

	while {true} do {
		sleep 2.5;
		if (!isNull player && {alive player}) then {
			// A respawned unit is a new object, and starts without our copy.
			private _current = player getVariable "BIS_WL_purchasable";
			if (isNil "_current" || {_current isNotEqualTo SWLC_clEconList}) then {
				player setVariable ["BIS_WL_purchasable", SWLC_clEconList];
			};
			call SWLC_clEconApply;

			private _caps = ["caps", []] call SWLC_clEconPub;
			if (_caps isNotEqualTo _lastCaps) then {
				_lastCaps = _caps;
				call BIS_fnc_WLrecalculateServices;
			};
			private _rev = missionNamespace getVariable ["SWLC_econValueRev", 0];
			if (_rev != _lastRev) then {
				_lastRev = _rev;
				BIS_WL_recalculateIncome = true;
			};
			if (time >= _nextMarkers) then {
				_nextMarkers = time + 5;
				call SWLC_clEconMarkers;
			};
		};
	};
};
