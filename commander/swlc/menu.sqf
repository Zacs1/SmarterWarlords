// Rules variant, part F: the "Commander..." menu, server side. menu_client.sqf is the half each player runs.
// Every option goes through SWLC_fnc_menuHandle, which applies the cooldown and logs C_MENU with the result.
// Each option's function returns "ok" or the reason it refused, and says that reason on the radio.
// All of this is called only when a human uses the menu, or by the gatef scenario with an AI stand-in.
#include "macros.hpp"

SWLC_menuKinds = ["raid", "borrow", "hold", "go", "report", "defend", "pickup", "release", "plan"];
// Answers that mean the player clicked the wrong thing. These don't start the option's cooldown.
SWLC_menuNoCharge = ["bad_sector", "not_front", "not_owned"];

// What a client sends. A request can only speak for its sender; owner 0 is the host's own local call.
SWLC_fnc_playerMsg = {
	params [["_kind", "", [""]], ["_player", objNull, [objNull]], ["_data", [], [[]]]];
	if (isNull _player || {!isPlayer _player}) exitWith {};
	if (isRemoteExecuted && {remoteExecutedOwner != 0} && {remoteExecutedOwner != owner _player}) exitWith {};
	private _cmd = missionNamespace getVariable [format ["SWLC_cmd_%1", side group _player], createHashMap];
	if (count _cmd == 0) exitWith {};
	[_cmd, _player, _kind, _data] call SWLC_fnc_menuHandle;
};

SWLC_fnc_menuHandle = {
	params ["_cmd", "_player", "_kind", ["_data", []]];
	private _log = {
		params ["_result"];
		private _who = if (isNull _player) then {"-"} else {((name _player) splitString "|=") joinString ""};
		["C_MENU", [["side", _cmd get "side"], ["kind", _kind], ["player", _who], ["result", _result]]] call SWLC_fnc_log;
		_result
	};
	if !(CFG("ruleCommanderMenu")) exitWith {["off"] call _log};
	if !(_kind in SWLC_menuKinds) exitWith {["unknown"] call _log};
	if (isNull _player || {!alive _player}) exitWith {["no_player"] call _log};

	private _cools = _cmd getOrDefault ["menuCools", createHashMap];
	_cmd set ["menuCools", _cools];
	private _id = if (isPlayer _player) then {getPlayerUID _player} else {str _player};
	private _key = format ["%1|%2", _id, _kind];
	if (time < (_cools getOrDefault [_key, -1])) exitWith {
		[_cools, _key, _player] call SWLC_fnc_menuTellWait;
		["cooldown"] call _log
	};
	private _result = [_cmd, _player, _data] call (missionNamespace getVariable format ["SWLC_fnc_menuDo_%1", _kind]);
	if !(_result in SWLC_menuNoCharge) then {
		_cools set [_key, time + (CFG("menuCooldowns") getOrDefault [_kind, CFG("menuCooldownSeconds")])];
	};
	[_result] call _log
};

// A cooldown is only told to the player who pressed the button, at most once every few seconds.
SWLC_fnc_menuTellWait = {
	params ["_cools", "_key", "_player"];
	private _told = _key + "|told";
	if (time < (_cools getOrDefault [_told, -1])) exitWith {};
	_cools set [_told, time + 5];
	if (isPlayer _player) then {
		[[side group _player, "HQ"], "Wait a moment before asking again."] remoteExec ["sideChat", owner _player];
	};
};

// The sector a request names, or objNull. A client can send anything, so nothing is trusted.
SWLC_fnc_menuSector = {
	params ["_data"];
	if !(_data isEqualType [] && {_data isNotEqualTo []}) exitWith {objNull};
	private _s = _data # 0;
	if !(_s isEqualType objNull && {_s in SWLC_sectors}) exitWith {objNull};
	_s
};

SWLC_fnc_menuList = {
	params ["_cmd", "_key"];
	private _list = _cmd getOrDefault [_key, []];
	_cmd set [_key, _list];
	_list
};

// A requester who still counts. Only the gatef scenario can make an AI count.
SWLC_fnc_menuValidBy = {
	params ["_by"];
	_by isEqualType objNull && {alive _by} && {isPlayer _by || {CFG("menuTestAllowAI")}}
};

// Groups the wave can do without: never ones in a fight, on the road in a vehicle or the requester's own.
SWLC_fnc_menuSpare = {
	params ["_cmd", "_player", "_near", "_want"];
	private _groups = _cmd get "groups";
	private _attack = {([_x] call SWLC_fnc_state) in ["Unassigned", "Mustering", "Travelling", "Advancing", "Waiting", "Assaulting", "Regrouping"]} count _groups;
	private _can = (_attack - CFG("menuKeepGroups")) min _want;
	if (_can <= 0) exitWith {[]};
	private _mine = group _player;
	private _free = _groups select {
		_x isNotEqualTo _mine
		&& {([_x] call SWLC_fnc_state) in ["Unassigned", "Mustering", "Travelling", "Waiting"]}
		&& {vehicle leader _x == leader _x}
		&& {(behaviour leader _x) != "COMBAT"}
	};
	_free = [_free, [], {(leader _x distance2D _near) + ([0, 2000] select (([_x] call SWLC_fnc_state) == "Waiting"))}, "ASCEND"] call BIS_fnc_sortBy;
	_free select [0, _can]
};

// True if a spot is inside a sector Warlords would kill the group for entering. An active raid's sector is open.
SWLC_fnc_menuBlocked = {
	params ["_cmd", "_pos", ["_margin", 50]];
	private _raid = [_cmd] call SWLC_fnc_raidOf;
	if (count _raid > 0 && {(_raid get "stage") == "active"} && {[_raid get "sector", _pos, _margin] call SWLC_fnc_adInSquare}) exitWith {false};
	[_cmd get "side", _pos, _margin] call SWLC_fnc_adRestricted
};

// Stops whatever the commander had a group doing. Clearing the remembered order alone would leave its waypoints running.
SWLC_fnc_menuDropOrder = {
	params ["_g"];
	[_g, [[getPosATL leader _g, "MOVE", 15]], "AWARE", "FULL", "WEDGE", "YELLOW"] call SWLC_fnc_adSetOrder;
};

// ---- Order raid on sector ----

SWLC_fnc_menuDo_raid = {
	params ["_cmd", "_player", "_data"];
	private _side = _cmd get "side";
	private _s = [_data] call SWLC_fnc_menuSector;
	if (isNull _s) exitWith {[_side, "menubad"] call SWLC_fnc_radio; "bad_sector"};
	private _funds = _player getVariable ["BIS_WL_funds", 0];
	private _why = [_cmd, _s, _funds] call SWLC_fnc_raidRefusal;
	if (_why != "") exitWith {
		[_side, "raidno_" + _why, [[_s] call SWLC_fnc_adName, CFG("raidCostCP")]] call SWLC_fnc_radio;
		_why
	};
	_player setVariable ["BIS_WL_funds", _funds - CFG("raidCostCP"), true];
	// Who goes is up to the player: their borrowed groups follow them in, and a raid sector is open to them.
	[_cmd, _s, "player", []] call SWLC_fnc_raidStart;
	"ok"
};

// ---- Send groups with me / Release my groups ----

SWLC_fnc_menuDo_borrow = {
	params ["_cmd", "_player", "_data"];
	private _side = _cmd get "side";
	private _list = [_cmd, "menuBorrowed"] call SWLC_fnc_menuList;
	private _have = {(_x getVariable ["SWLC_borrowedBy", objNull]) isEqualTo _player} count _list;
	private _room = CFG("menuBorrowGroups") - _have;
	if (_room <= 0) exitWith {[_side, "borrowmax"] call SWLC_fnc_radio; "max"};
	private _spare = [_cmd, _player, getPosATL _player, _room] call SWLC_fnc_menuSpare;
	if ((count _spare) < ((CFG("menuBorrowMinGroups") - _have) max 1)) exitWith {[_side, "borrowno"] call SWLC_fnc_radio; "nospare"};
	{
		private _g = _x;
		[_g, false] call SWLC_fnc_lambsRelease;
		[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
		_g setVariable ["SWLC_borrowedBy", _player];
		_g setVariable ["SWLC_borrowSlot", _have + _forEachIndex];
		_g setVariable ["SWLC_followAt", -1e6];
		[_g, "Borrowed", getPosATL _player, "borrowed"] call SWLC_fnc_setState;
		[_g] call SWLC_fnc_menuDropOrder;
		_list pushBackUnique _g;
		[_cmd, _g, _player, true] call SWLC_fnc_menuFollow;
	} forEach _spare;
	[_side, "borrowok", [count _spare]] call SWLC_fnc_radio;
	"ok"
};

// Fast travels a far group to the safe owned sector nearest its player, then walks it to a spot behind them.
SWLC_fnc_menuFollow = {
	params ["_cmd", "_g", "_by", ["_force", false]];
	private _side = _cmd get "side";
	private _p = getPosATL _by;
	private _leader = leader _g;
	private _threats = _cmd get "threats";

	if ((_leader distance2D _p) > CFG("menuFollowFar") && {(time - (_g getVariable ["SWLC_followFT", -1e6])) >= CFG("menuFollowFTSeconds")}) then {
		private _safe = ([_side] call SWLC_fnc_adOwned) select {!(([_x] call SWLC_fnc_adName) in _threats) && {[_side, _x] call SWLC_fnc_adCanFTTo}};
		if (_safe isNotEqualTo []) then {
			private _hop = ([_safe, _p] call SWLC_fnc_adNearest);
			private _sp = [_hop] call SWLC_fnc_adPos;
			if (((_sp distance2D _p) + CFG("menuFollowFTGain")) < (_leader distance2D _p)) then {
				private _land = [_sp, [_sp, _p] call SWLC_fnc_bearing, 40 + random 30] call SWLC_fnc_offset;
				if (surfaceIsWater _land) then {_land = _sp};
				if ([_g, _hop, _land] call SWLC_fnc_adFastTravel) then {_g setVariable ["SWLC_followFT", time]};
			};
		};
	};

	private _stale = (time - (_g getVariable ["SWLC_followAt", -1e6])) >= CFG("menuFollowRefresh");
	private _slot = _g getVariable ["SWLC_borrowSlot", 0];
	private _spot = [_p, (getDir _by) + 180 + (_slot * 35) - 35, 20 + _slot * 10] call SWLC_fnc_offset;
	// A waiting leader gets moved a little, or Warlords treats it as stuck.
	if (_stale) then {_spot = [_spot, random 360, 5 + random 15] call SWLC_fnc_offset};
	if (surfaceIsWater _spot || {[_cmd, _spot] call SWLC_fnc_menuBlocked}) exitWith {[_cmd, _g, _stale] call SWLC_fnc_menuBorrowLeave};

	private _order = _g getVariable ["SWLC_order", []];
	private _wasOut = _g getVariable ["SWLC_borrowOut", false];
	private _moved = _wasOut || {_order isEqualTo []} || {(((_order # 0) # 0) # 0 distance2D _spot) > CFG("menuFollowDist")};
	if !(_force || {_stale} || {_moved}) exitWith {false};
	if (!_force && {!_wasOut} && {(behaviour leader _g) == "COMBAT"} && {(leader _g distance2D _spot) < CFG("menuFollowCombatDist")}) exitWith {false};
	_g setVariable ["SWLC_borrowOut", nil];
	_g setVariable ["SWLC_followAt", time];
	_g setVariable ["SWLC_goal", _spot];
	[_g, [[_spot, "MOVE", 15]], "AWARE", "FULL", "WEDGE", "YELLOW"] call SWLC_fnc_adSetOrder;
	true
};

// Following is blocked. A group inside a sector Warlords would kill it in, or walking to one, goes to the safe owned
// sector nearest it and stays Borrowed. Any other group keeps what it's doing. menuFollow takes them back once it's safe.
SWLC_fnc_menuBorrowLeave = {
	params ["_cmd", "_g", "_stale"];
	private _side = _cmd get "side";
	private _here = getPosATL leader _g;
	private _order = _g getVariable ["SWLC_order", []];
	private _goalBad = _order isNotEqualTo [] && {[_cmd, ((_order # 0) # 0) # 0, 25] call SWLC_fnc_menuBlocked};
	private _out = _g getVariable ["SWLC_borrowOut", false];
	if (!_out && {!_goalBad} && {!([_cmd, _here, 25] call SWLC_fnc_menuBlocked)}) exitWith {false};
	// Already leaving: only a destination gone bad changes that, or the regular nudge a waiting leader needs.
	if (_out && {!_goalBad} && {!_stale}) exitWith {false};

	private _owned = [_side] call SWLC_fnc_adOwned;
	private _threats = _cmd get "threats";
	private _safe = _owned select {!(([_x] call SWLC_fnc_adName) in _threats)};
	if (_safe isEqualTo []) then {_safe = _owned};
	if (_safe isEqualTo []) exitWith {false};
	private _home = [([_safe, _here] call SWLC_fnc_adNearest)] call SWLC_fnc_adPos;
	private _spot = [_home, random 360, 20 + random 30] call SWLC_fnc_offset;
	if (surfaceIsWater _spot || {[_cmd, _spot, 25] call SWLC_fnc_menuBlocked}) then {_spot = +_home};

	if (!_out) then {["C_MENU", [["side", _side], ["kind", "borrow_leave"], ["group", groupId _g]]] call SWLC_fnc_log};
	_g setVariable ["SWLC_borrowOut", true];
	_g setVariable ["SWLC_followAt", time];
	_g setVariable ["SWLC_goal", _spot];
	[_g, [[_spot, "MOVE", 20]], "AWARE", "FULL", "WEDGE", "YELLOW"] call SWLC_fnc_adSetOrder;
	true
};

SWLC_fnc_menuRelease = {
	params ["_cmd", "_g", "_why"];
	_cmd set ["menuBorrowed", ([_cmd, "menuBorrowed"] call SWLC_fnc_menuList) - [_g]];
	if (isNull _g) exitWith {};
	_g setVariable ["SWLC_borrowedBy", nil];
	_g setVariable ["SWLC_borrowSlot", nil];
	_g setVariable ["SWLC_borrowOut", nil];
	["C_MENU", [["side", _cmd get "side"], ["kind", "released"], ["group", groupId _g], ["why", _why]]] call SWLC_fnc_log;
	if ((_g in (_cmd get "groups")) && {([_g] call SWLC_fnc_groupMen) > 0} && {([_g] call SWLC_fnc_state) == "Borrowed"}) then {
		[_g] call SWLC_fnc_adClearOrder;
		[_g, "Unassigned", [], _why] call SWLC_fnc_setState;
	};
};

SWLC_fnc_menuDo_release = {
	params ["_cmd", "_player", "_data"];
	private _side = _cmd get "side";
	private _mine = ([_cmd, "menuBorrowed"] call SWLC_fnc_menuList) select {(_x getVariable ["SWLC_borrowedBy", objNull]) isEqualTo _player};
	if (_mine isEqualTo []) exitWith {[_side, "releasenone"] call SWLC_fnc_radio; "none"};
	{[_cmd, _x, "released_by_player"] call SWLC_fnc_menuRelease} forEach _mine;
	[_side, "releaseok"] call SWLC_fnc_radio;
	"ok"
};

// Borrowed groups each tick: let go of any whose player has gone, walk the rest after their player.
SWLC_fnc_menuBorrowedTick = {
	params ["_cmd"];
	private _list = [_cmd, "menuBorrowed"] call SWLC_fnc_menuList;
	if (_list isEqualTo []) exitWith {};
	{
		private _g = _x;
		private _by = if (isNull _g) then {objNull} else {_g getVariable ["SWLC_borrowedBy", objNull]};
		if (isNull _g || {!(_g in (_cmd get "groups"))} || {([_g] call SWLC_fnc_groupMen) == 0}) then {
			[_cmd, _g, "group_lost"] call SWLC_fnc_menuRelease;
		} else {
			if ([_by] call SWLC_fnc_menuValidBy) then {
				[_cmd, _g, _by] call SWLC_fnc_menuFollow;
			} else {
				[_cmd, _g, "player_gone"] call SWLC_fnc_menuRelease;
			};
		};
	} forEach (_list select {true});
};

// ---- Hold the wave for us / Go now ----

SWLC_fnc_menuDo_hold = {
	params ["_cmd", "_player", "_data"];
	private _side = _cmd get "side";
	private _op = _cmd get "op";
	if (isNil "_op" || {_op getOrDefault ["holdGo", false]}) exitWith {[_side, "holdno_noop"] call SWLC_fnc_radio; "no_op"};
	if ((_op get "phase") == "ASSAULT") exitWith {[_side, "holdno_assault"] call SWLC_fnc_radio; "assault"};
	if (time < (_cmd getOrDefault ["menuHoldNext", -1])) exitWith {[_side, "holdno_used"] call SWLC_fnc_radio; "used"};
	_op set ["playerHoldUntil", time + CFG("menuHoldSeconds")];
	_op set ["forceGo", false];
	_cmd set ["menuHoldNext", time + CFG("menuHoldSideCooldown")];
	[_side, "holdok", [round (CFG("menuHoldSeconds") / 60)]] call SWLC_fnc_radio;
	"ok"
};

SWLC_fnc_menuDo_go = {
	params ["_cmd", "_player", "_data"];
	private _side = _cmd get "side";
	private _op = _cmd get "op";
	if (isNil "_op" || {_op getOrDefault ["holdGo", false]}) exitWith {[_side, "holdno_noop"] call SWLC_fnc_radio; "no_op"};
	if ((_op get "phase") == "ASSAULT") exitWith {[_side, "gono_going"] call SWLC_fnc_radio; "assault"};
	private _staged = ([_op] call SWLC_fnc_waveLive) select {([_x] call SWLC_fnc_state) in ["Mustering", "Waiting"]};
	if ((count _staged) < CFG("requestGoMinGroups")) exitWith {[_side, "gono"] call SWLC_fnc_radio; "not_enough"};
	_op deleteAt "playerHoldUntil";
	_op set ["forceGo", true];
	[_side, "gook"] call SWLC_fnc_radio;
	"ok"
};

// ---- Report contact ----

SWLC_fnc_menuDo_report = {
	params ["_cmd", "_player", "_data"];
	private _g = group _player;
	private _sightings = [];
	{
		if (_x isEqualType []) then {
			_x params [["_cls", "", [""]], ["_pos", [], [[]], [2]]];
			if (_cls != "" && {_pos isNotEqualTo []} && {({_x isEqualType 0} count _pos) == 2} && {isClass (configFile >> "CfgVehicles" >> _cls)} && {(_player distance2D _pos) <= CFG("playerReportRange")}) then {
				private _cat = [_cls] call SWLC_fnc_intelCategory;
				if (_cat != "") then {_sightings pushBack [_cat, [_pos # 0, _pos # 1, 0], objNull, CFG("playerReportConf"), _g, 4]};
			};
		};
	} forEach (_data select [0, CFG("playerReportMax")]);
	if (_sightings isEqualTo []) exitWith {[_cmd get "side", "reportno"] call SWLC_fnc_radio; "none"};
	[_cmd, _sightings, "player"] call SWLC_fnc_intelPost;
	[_cmd get "side", "report", [], _g] call SWLC_fnc_radio;
	"ok"
};

// ---- Defend this sector ----

// Added to the sector's worth in the defence logic while a player's request lasts.
SWLC_fnc_menuDefendBonus = {
	params ["_cmd", "_s"];
	private _until = (_cmd getOrDefault ["menuDefend", createHashMap]) getOrDefault [[_s] call SWLC_fnc_adName, -1];
	[0, CFG("menuDefendValue")] select (time < _until)
};

SWLC_fnc_menuDo_defend = {
	params ["_cmd", "_player", "_data"];
	private _side = _cmd get "side";
	private _s = [_data] call SWLC_fnc_menuSector;
	if (isNull _s) exitWith {[_side, "menubad"] call SWLC_fnc_radio; "bad_sector"};
	private _name = [_s] call SWLC_fnc_adName;
	if (([_s] call SWLC_fnc_adOwner) != _side) exitWith {[_side, "defendbad", [_name]] call SWLC_fnc_radio; "not_owned"};

	private _boost = _cmd getOrDefault ["menuDefend", createHashMap];
	_cmd set ["menuDefend", _boost];
	_boost set [_name, time + CFG("requestDefendSeconds")];

	private _threats = _cmd get "threats";
	private _free = {([_x] call SWLC_fnc_state) == "Reserve"} count (_cmd get "groups");
	if (_free == 0 && {!(_name in _threats)}) exitWith {[_side, "defendthin", [_name]] call SWLC_fnc_radio; "ok_no_force"};
	private _rec = _threats getOrDefault [_name, createHashMap];
	if (count _rec == 0) then {
		private _bearing = [[_s] call SWLC_fnc_adPos, [[_side] call SWLC_fnc_adBase] call SWLC_fnc_adPos] call SWLC_fnc_bearing;
		_rec = createHashMapFromArray [["sector", _s], ["first", time], ["last", time], ["groups", []], ["slot", 0], ["strength", CFG("defenceMenPerGroup")], ["bearing", _bearing + 180]];
		_rec set ["spots", [_cmd, _s, _bearing + 180] call SWLC_fnc_defSpots];
		_threats set [_name, _rec];
	};
	_rec set ["requestedUntil", time + CFG("requestDefendSeconds")];
	[_cmd, _rec] call SWLC_fnc_defRespond;
	[_side, "defendok", [_name]] call SWLC_fnc_radio;
	"ok"
};

// ---- Request a pickup ----
// One spare group brings a vehicle to the player, leaves it there and goes back to the commander.

SWLC_fnc_menuDo_pickup = {
	params ["_cmd", "_player", "_data"];
	private _side = _cmd get "side";
	private _list = [_cmd, "menuPickups"] call SWLC_fnc_menuList;
	if (!CFG("vehiclesEnabled") || {isNil {_cmd get "catalog"}}) exitWith {[_side, "pickupno"] call SWLC_fnc_radio; "off"};
	if ((count _list) >= CFG("menuPickupMaxActive")) exitWith {[_side, "pickupbusy"] call SWLC_fnc_radio; "busy"};
	private _p = getPosATL _player;
	if (surfaceIsWater _p || {[_cmd, _p] call SWLC_fnc_menuBlocked}) exitWith {[_side, "pickupbad"] call SWLC_fnc_radio; "bad_place"};
	private _spare = ([_cmd, _player, _p, 8] call SWLC_fnc_menuSpare) select {leader _x call SWLC_fnc_adIsWarlordUnit};
	if (_spare isEqualTo []) exitWith {[_side, "pickupno"] call SWLC_fnc_radio; "nospare"};
	_spare = _spare select {(leader _x distance2D _p) <= CFG("menuPickupMaxDistance")};
	if (_spare isEqualTo []) exitWith {[_side, "pickupbad"] call SWLC_fnc_radio; "too_far"};
	private _g = _spare # 0;
	private _men = [_g] call SWLC_fnc_groupMen;

	private _parked = (_cmd get "vehicles") select {
		(_x get "state") == "parked" && {alive (_x get "obj")} && {canMove (_x get "obj")} && {(_x get "seats") >= _men} && {((_x get "obj") distance2D leader _g) <= CFG("vehReuseRadius")}
	};
	private _entry = [];
	if (_parked isEqualTo []) then {_entry = [_cmd, _men, getPosATL leader _g] call SWLC_fnc_vehCheapestTransport};
	if (_parked isEqualTo [] && {_entry isEqualTo [] || {([_cmd] call SWLC_fnc_vehFleetCount) >= CFG("vehMaxFleet")} || {([_side] call SWLC_fnc_cpFree) < (_entry # 1)}}) exitWith {
		[_side, "pickupno"] call SWLC_fnc_radio;
		"funds"
	};

	[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
	[_g, "Pickup", _p, "pickup"] call SWLC_fnc_setState;
	private _job = createHashMapFromArray [["id", -2]];
	private _ok = if (_parked isNotEqualTo []) then {[_cmd, _parked # 0, _g, _job] call SWLC_fnc_vehClaimParked; true} else {[_cmd, _entry, _g, _job] call SWLC_fnc_vehBuy};
	if (!_ok) exitWith {
		[_g, "Unassigned", [], "pickup_failed"] call SWLC_fnc_setState;
		[_side, "pickupno"] call SWLC_fnc_radio;
		"funds"
	};
	[_g] call SWLC_fnc_menuDropOrder;
	_list pushBack (createHashMapFromArray [["player", _player], ["group", _g], ["veh", [_g] call SWLC_fnc_vehRecOf], ["stage", "arriving"], ["since", time], ["clock", time], ["boardAt", -1], ["driveAt", -1e6]]);
	[_side, "pickupok", [groupId _g]] call SWLC_fnc_radio;
	"ok"
};

SWLC_fnc_menuPickupEnd = {
	params ["_cmd", "_rec", "_why"];
	private _g = _rec get "group";
	["C_MENU", [["side", _cmd get "side"], ["kind", "pickup_end"], ["why", _why], ["stage", _rec get "stage"]]] call SWLC_fnc_log;
	if (!isNull _g && {_g in (_cmd get "groups")} && {([_g] call SWLC_fnc_groupMen) > 0}) then {
		if (count ([_g] call SWLC_fnc_vehRecOf) > 0) then {[_cmd, _g, "pickup_end"] call SWLC_fnc_vehDismount};
		if (([_g] call SWLC_fnc_state) == "Pickup") then {
			[_g] call SWLC_fnc_adClearOrder;
			[_g, "Unassigned", [], "pickup_" + _why] call SWLC_fnc_setState;
		};
	};
	if (_why in ["timeout", "vehicle_lost", "group_lost"]) then {[_cmd get "side", "pickupfail"] call SWLC_fnc_radio};
};

SWLC_fnc_menuPickupDrive = {
	params ["_cmd", "_rec", "_g", "_by"];
	private _p = getPosATL _by;
	if (surfaceIsWater _p || {[_cmd, _p] call SWLC_fnc_menuBlocked}) exitWith {};
	_rec set ["driveAt", time];
	_rec set ["drivePos", _p];
	_g setVariable ["SWLC_goal", _p];
	[_g, [[_p, "MOVE", 25]], "AWARE", "FULL", "COLUMN", "YELLOW"] call SWLC_fnc_adSetOrder;
};

// Hands the vehicle over: the group gets out, and the commander forgets the vehicle so nobody drives it away.
SWLC_fnc_menuPickupDeliver = {
	params ["_cmd", "_rec", "_g"];
	private _r = _rec get "veh";
	private _v = _r get "obj";
	private _id = _r get "id";
	[_cmd, _g, "pickup_delivered"] call SWLC_fnc_vehDismount;
	_cmd set ["vehicles", (_cmd get "vehicles") select {(_x get "id") != _id}];
	_v setVehicleLock "UNLOCKED";
	[_g] call SWLC_fnc_adClearOrder;
	[_g, "Unassigned", [], "pickup_done"] call SWLC_fnc_setState;
	["C_MENU", [["side", _cmd get "side"], ["kind", "pickup_end"], ["why", "delivered"], ["stage", _rec get "stage"], ["took", round (time - (_rec get "since"))]]] call SWLC_fnc_log;
	[_cmd get "side", "pickuphere", [], _g] call SWLC_fnc_radio;
};

// Returns false once the pickup is over.
SWLC_fnc_menuPickupStep = {
	params ["_cmd", "_rec"];
	private _g = _rec get "group";
	private _by = _rec get "player";
	private _r = _rec get "veh";
	private _v = _r get "obj";
	private _fail = "";
	if (isNull _g || {!(_g in (_cmd get "groups"))} || {([_g] call SWLC_fnc_groupMen) == 0}) then {_fail = "group_lost"};
	if (_fail == "" && {isNull _v || {!alive _v} || {!canMove _v}}) then {_fail = "vehicle_lost"};
	if (_fail == "" && {!([_by] call SWLC_fnc_menuValidBy)}) then {_fail = "player_gone"};
	if (_fail == "" && {(time - (_rec get "clock")) >= CFG("menuPickupTimeoutSeconds")}) then {_fail = "timeout"};
	if (_fail != "") exitWith {[_cmd, _rec, _fail] call SWLC_fnc_menuPickupEnd; false};

	private _stage = _rec get "stage";
	if (_stage == "arriving" && {(_r get "state") != "arriving"}) then {
		[_cmd, _g] call SWLC_fnc_vehMountGroup;
		_rec set ["boardAt", time];
		_rec set ["stage", "boarding"];
		_stage = "boarding";
	};
	if (_stage == "boarding") then {
		if ((time - (_rec get "boardAt")) >= CFG("menuPickupBoardSeconds")) then {[_g] call SWLC_fnc_vehForceBoard};
		if ([_g] call SWLC_fnc_vehAboard) then {
			[_cmd, _rec, _g, _by] call SWLC_fnc_menuPickupDrive;
			_rec set ["clock", time];
			_rec set ["stage", "driving"];
			_stage = "driving";
		};
	};
	if (_stage != "driving") exitWith {true};
	if ((_v distance2D _by) <= CFG("menuPickupArriveDist")) exitWith {[_cmd, _rec, _g] call SWLC_fnc_menuPickupDeliver; false};
	private _last = _rec getOrDefault ["drivePos", []];
	if ((time - (_rec get "driveAt")) >= 20 && {_last isEqualTo [] || {(_last distance2D _by) >= CFG("menuPickupRefreshMetres")}}) then {
		[_cmd, _rec, _g, _by] call SWLC_fnc_menuPickupDrive;
	};
	true
};

SWLC_fnc_menuPickupTick = {
	params ["_cmd"];
	private _list = [_cmd, "menuPickups"] call SWLC_fnc_menuList;
	if (_list isEqualTo []) exitWith {};
	_cmd set ["menuPickups", _list select {[_cmd, _x] call SWLC_fnc_menuPickupStep}];
};

// ---- What's the plan? ----

SWLC_fnc_menuDo_plan = {
	params ["_cmd", "_player", "_data"];
	private _side = _cmd get "side";
	private _op = _cmd get "op";
	private _raid = [_cmd] call SWLC_fnc_raidOf;
	private _raidText = if (count _raid > 0 && {(_raid get "stage") == "active"}) then {
		format ["Raid on %1, %2 left.", [_raid get "sector"] call SWLC_fnc_adName, [(_raid get "expires") - time] call SWLC_fnc_statusClock]
	} else {""};
	if (isNil "_op" || {isNull (_cmd get "target")}) exitWith {[_side, "planidle", [_raidText]] call SWLC_fnc_radio; "ok_idle"};
	private _timer = call {
		if ((_op get "phase") == "ASSAULT") exitWith {"Attack under way."};
		private _held = (_op getOrDefault ["playerHoldUntil", -1]) - time;
		if (_held > 0) exitWith {format ["Holding for you, %1 left.", [_held] call SWLC_fnc_statusClock]};
		if ((_op get "firstAtRally") >= 0) exitWith {
			format ["Going in within %1.", [(_op get "firstAtRally") + ([_cmd, _op] call SWLC_fnc_rallyLoneWait) - time] call SWLC_fnc_statusClock]
		};
		"Waiting for groups at the rally."
	};
	[_side, "plan", [[_cmd get "target"] call SWLC_fnc_adName, mapGridPosition (_op get "rally"), _timer, _raidText]] call SWLC_fnc_radio;
	"ok"
};

// ---- Each tick ----

// What clients need for the menu: whether it exists, and which sectors a raid can be ordered on.
SWLC_fnc_menuPublish = {
	params ["_cmd"];
	if ((missionNamespace getVariable ["SWLC_menuOn", !CFG("ruleCommanderMenu")]) isNotEqualTo CFG("ruleCommanderMenu")) then {
		missionNamespace setVariable ["SWLC_menuOn", CFG("ruleCommanderMenu"), true];
	};
	private _side = _cmd get "side";
	if !([_side] call SWLC_fnc_adSideHasPlayers) exitWith {};
	if ((time - (_cmd getOrDefault ["menuFrontAt", -1e6])) < 30) exitWith {};
	_cmd set ["menuFrontAt", time];
	private _front = ([_side] call SWLC_fnc_raidFront) apply {[[_x] call SWLC_fnc_adPos, [_x] call SWLC_fnc_adName]};
	private _var = format ["SWLC_front_%1", _side];
	if ((missionNamespace getVariable [_var, []]) isNotEqualTo _front) then {
		missionNamespace setVariable [_var, _front, true];
	};
};

SWLC_fnc_menuTick = {
	params ["_cmd"];
	[_cmd] call SWLC_fnc_menuPublish;
	[_cmd] call SWLC_fnc_menuBorrowedTick;
	[_cmd] call SWLC_fnc_menuPickupTick;
};
