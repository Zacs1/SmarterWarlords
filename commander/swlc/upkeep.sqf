// Upkeep: small repairs that keep the commander's groups in working order between orders.
// Stragglers, remnants, dead leaders, fleeing, and men left behind by vehicles.
//
// Runs as its own slice. The two cheap things happen for every group in one frame; the rest takes a
// share of the groups each tick, one group per frame. Groups a player leads or has borrowed are never touched.
#include "macros.hpp"

SWLC_fnc_upkeepSlices = {
	params ["_cmd"];
	if !(CFG("resilience")) exitWith {};
	private _work = [];
	private _spent = 0;
	private _sliceOk = false;
	isNil {
		private _t0 = diag_tickTime;
		private _mine = (_cmd get "groups") select {[_x] call SWLC_fnc_upkeepMine};
		private _noFlee = CFG("upkeepNoFlee");
		private _lead = CFG("upkeepLeader");
		{
			// Every pass, not once: the setting doesn't reach men who join or respawn later.
			[_cmd, _x, "upkeepLeader", {
				if (_noFlee) then {_x allowFleeing 0};
				if (_lead) then {[_cmd, _x] call SWLC_fnc_upkeepLeader};
			}] call SWLC_fnc_resGuarded;
		} forEach _mine;
		private _n = CFG("upkeepSlices") max 1;
		private _i = (_cmd getOrDefault ["upkeepIdx", 0]) mod _n;
		_cmd set ["upkeepIdx", (_i + 1) mod _n];
		{if ((_forEachIndex mod _n) == _i) then {_work pushBack _x}} forEach _mine;
		_spent = (diag_tickTime - _t0) * 1000;
		_sliceOk = true;
	};
	if (!_sliceOk) then {[_cmd, "upkeep"] call SWLC_fnc_resStageFault};
	[_cmd, "upkeep", _spent] call SWLC_fnc_cmdStageCost;
	[_cmd, _spent] call SWLC_fnc_cmdSliceDone;
	if (_work isEqualTo []) exitWith {};
	sleep CFG("tickYieldSeconds");
	{
		private _g = _x;
		private _cost = 0;
		private _sliceOk = false;
		isNil {
			private _t0 = diag_tickTime;
			if ([_g] call SWLC_fnc_upkeepMine) then {
				[_cmd, _g, "upkeep", {
					if !([_cmd, _g] call SWLC_fnc_upkeepRemnant) then {
						[_cmd, _g] call SWLC_fnc_upkeepLeftovers;
						[_cmd, _g] call SWLC_fnc_upkeepStragglers;
					};
				}] call SWLC_fnc_resGuarded;
			};
			_cost = (diag_tickTime - _t0) * 1000;
			_sliceOk = true;
		};
		if (!_sliceOk) then {[_cmd, "upkeep"] call SWLC_fnc_resStageFault};
		[_cmd, "upkeep", _cost] call SWLC_fnc_cmdStageCost;
		[_cmd, _cost] call SWLC_fnc_cmdSliceDone;
		sleep CFG("tickYieldSeconds");
	} forEach _work;
};

// The commander's to look after: alive, no player in it, not lent out.
SWLC_fnc_upkeepMine = {
	params ["_g"];
	([_g] call SWLC_fnc_squadOwner) == "own" && {!(([_g] call SWLC_fnc_state) in ["Borrowed", "Pickup"])}
};

// A group doing something that deliberately spreads its men out or depends on its waypoints.
SWLC_fnc_upkeepBusy = {
	params ["_g"];
	(_g getVariable ["SWLC_squadTask", ""]) != "" || {(_g getVariable ["SWLC_lambsTask", ""]) != ""}
};

// A man sent somewhere on his own on purpose.
SWLC_fnc_upkeepOnJob = {
	params ["_g", "_u"];
	_u isEqualTo (_g getVariable ["SWLC_rearmUnit", objNull]) || {(_u getVariable ["SWLC_kitTask", ""]) != ""}
};

// Writes the group's standing order again, from where it had got to.
SWLC_fnc_upkeepReissue = {
	params ["_g"];
	if ([_g] call SWLC_fnc_upkeepBusy) exitWith {};
	[_g, _g getVariable ["SWLC_wpProgress", 0]] call SWLC_fnc_adApplyOrder;
};

// Nearest group that can take _adding more men within _within metres of _pos, or grpNull.
// On foot, on no special job, and a warlord group counts: only its own warlord can never leave one.
SWLC_fnc_upkeepReceiver = {
	params ["_cmd", "_g", "_pos", "_within", "_adding"];
	private _cap = ([_cmd get "side"] call SWLC_fnc_econSquadCap) + CFG("upkeepRoomExtra");
	private _best = grpNull;
	private _bestD = _within;
	{
		private _l = leader _x;
		private _d = _l distance2D _pos;
		if (_d < _bestD
			&& {alive _l}
			&& {isNull objectParent _l}
			&& {[_x] call SWLC_fnc_upkeepMine}
			&& {!([_x] call SWLC_fnc_upkeepBusy)}
			&& {count ([_x] call SWLC_fnc_vehRecOf) == 0}
			&& {(_x getVariable ["SWLC_leg", ""]) in ["", "FOOT"]}
			&& {!(([_x] call SWLC_fnc_state) in ["Recon", "Raiding", "Probing", "Picket"])}
			&& {(([_x] call SWLC_fnc_groupMen) + _adding) <= _cap}) then {
			_best = _x;
			_bestD = _d;
		};
	} forEach ((_cmd get "groups") - [_g]);
	_best
};

// Dead leader. The engine keeps the group's waypoints and variables but can leave a dead man in charge for a
// while, so the group's next leader is chosen here and the order written again. A respawned warlord comes
// back as a subordinate; he gets the group back when he's close, because only a warlord leader can buy.
SWLC_fnc_upkeepLeader = {
	params ["_cmd", "_g"];
	private _men = [_g] call SWLC_fnc_alive;
	if (_men isEqualTo []) exitWith {};
	private _l = leader _g;
	private _new = objNull;
	if (alive _l) then {
		if !([_l] call SWLC_fnc_adIsWarlord) then {
			private _i = _men findIf {([_x] call SWLC_fnc_adIsWarlord) && {(_x distance2D _l) <= CFG("leaderWarlordMetres")}};
			if (_i >= 0) then {_new = _men # _i};
		};
	} else {
		private _i = _men findIf {[_x] call SWLC_fnc_adIsWarlord};
		if (_i >= 0) then {
			_new = _men # _i;
		} else {
			_new = _men # 0;
			{if ((rankId _x) > (rankId _new)) then {_new = _x}} forEach _men;
		};
	};
	if (isNull _new) exitWith {};
	_g selectLeader _new;
	if !([_g] call SWLC_fnc_upkeepBusy) then {
		{
			if (_x isNotEqualTo _new && {isNull objectParent _x} && {!([_g, _x] call SWLC_fnc_upkeepOnJob)}) then {_x doFollow _new};
		} forEach _men;
		[_g] call SWLC_fnc_upkeepReissue;
	};
	["C_LEADER", [["group", groupId _g], ["new", name _new]]] call SWLC_fnc_log;
};

// Stragglers: men who've lost their leader get sent back, or join a group that's closer.
SWLC_fnc_upkeepStragglers = {
	params ["_cmd", "_g"];
	if !(CFG("upkeepStragglers")) exitWith {};
	// A group with a vehicle is the vehicle code's to manage, and its men can be far apart while boarding.
	if ((count ([_g] call SWLC_fnc_vehRecOf)) > 0 || {(_g getVariable ["SWLC_leg", ""]) in ["DRIVE", "FOLLOW", "LATE"]}) exitWith {};
	if (([_g] call SWLC_fnc_upkeepBusy) || {[_g] call SWLC_fnc_lambsBusy} || {[_g] call SWLC_fnc_groupFighting}) exitWith {};
	private _l = leader _g;
	if (!alive _l || {!isNull objectParent _l}) exitWith {};
	{
		private _u = _x;
		if (alive _u && {_u isNotEqualTo _l} && {!isPlayer _u} && {isNull objectParent _u} && {isNull assignedVehicle _u} && {!([_g, _u] call SWLC_fnc_upkeepOnJob)}) then {
			[_cmd, _g, _u, _l] call SWLC_fnc_upkeepStraggler;
		};
	} forEach (units _g);
};

SWLC_fnc_upkeepStraggler = {
	params ["_cmd", "_g", "_u", "_l"];
	private _d = _u distance2D _l;
	if (_d <= CFG("stragglerMetres")) exitWith {
		if ((_u getVariable ["SWLC_stragAt", -1]) >= 0) then {_u setVariable ["SWLC_stragAt", -1]};
	};
	// Seen far away twice, so a man who has just landed or fast travelled isn't moved for it.
	private _at = _u getVariable ["SWLC_stragAt", -1];
	if (_at < 0) exitWith {_u setVariable ["SWLC_stragAt", time]};
	if ((time - _at) < CFG("stragglerGraceSeconds") || {time < (_u getVariable ["SWLC_stragNext", 0])}) exitWith {};
	_u setVariable ["SWLC_stragNext", time + CFG("stragglerRecheckSeconds")];
	private _into = grpNull;
	if (CFG("stragglerJoin") && {!([_u] call SWLC_fnc_adIsWarlord)}) then {
		_into = [_cmd, _g, getPosATL _u, _d min CFG("stragglerJoinMetres"), 1] call SWLC_fnc_upkeepReceiver;
	};
	if (isNull _into) then {
		_u doFollow _l;
		["C_STRAGGLER", [["side", side _g], ["group", groupId _g], ["unit", name _u], ["dist", round _d], ["action", "recall"], ["into", "-"]]] call SWLC_fnc_log;
	} else {
		[_u] joinSilent _into;
		_u doFollow (leader _into);
		_u setVariable ["SWLC_stragAt", -1];
		["C_STRAGGLER", [["side", side _g], ["group", groupId _g], ["unit", name _u], ["dist", round _d], ["action", "join"], ["into", groupId _into]]] call SWLC_fnc_log;
	};
};

// Remnants: a group down to a man or two with its warlord dead joins the nearest group. A group with a living
// warlord is never merged away, since he has to stay in his own group. The wait gives a dead warlord time to
// respawn beside his men. The emptied group drops off the list as a wiped-out one does, and comes back with him.
// Returns true when the group was merged.
SWLC_fnc_upkeepRemnant = {
	params ["_cmd", "_g"];
	if !(CFG("upkeepRemnants")) exitWith {false};
	private _men = [_g] call SWLC_fnc_alive;
	if ((count _men) > CFG("remnantMaxMen") || {_men isEqualTo []} || {(_men findIf {[_x] call SWLC_fnc_adIsWarlord}) >= 0}) exitWith {
		_g setVariable ["SWLC_remnantAt", -1];
		false
	};
	private _since = _g getVariable ["SWLC_remnantAt", -1];
	if (_since < 0) exitWith {
		_g setVariable ["SWLC_remnantAt", time];
		false
	};
	if ((time - _since) < CFG("remnantGraceSeconds")) exitWith {false};
	if (((_g getVariable ["SWLC_squadTask", ""]) != "")
		|| {!isNull (_g getVariable ["SWLC_rearmUnit", objNull])}
		|| {[_g] call SWLC_fnc_kitPending}) exitWith {false};
	// Men in a vehicle the commander doesn't know about stay put until the leftovers rule has them on foot.
	if (count ([_g] call SWLC_fnc_vehRecOf) == 0 && {(_men findIf {!isNull objectParent _x}) >= 0}) exitWith {false};
	private _into = [_cmd, _g, getPosATL (_men # 0), CFG("remnantMergeMetres"), count _men] call SWLC_fnc_upkeepReceiver;
	if (isNull _into) exitWith {false};

	[_g, false] call SWLC_fnc_lambsRelease;
	// Before the men move: it needs the head count of the group that's leaving.
	[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
	_men joinSilent _into;
	private _new = leader _into;
	{_x doFollow _new} forEach _men;
	private _op = _cmd get "op";
	if (!isNil "_op" && {_into in (_op get "groups")} && {([_into] call SWLC_fnc_state) == "Assaulting"}) then {
		_op set ["launchStrength", (_op get "launchStrength") + count _men];
	};
	["C_REMNANT", [["group", groupId _g], ["men", count _men], ["into", groupId _into]]] call SWLC_fnc_log;
	true
};

// Vehicle leftovers: men a vehicle has left behind, and men left sitting in one.
SWLC_fnc_upkeepLeftovers = {
	params ["_cmd", "_g"];
	if !(CFG("upkeepLeftovers")) exitWith {};
	// A scout's car and a garrison's static guns are in use on purpose.
	if (([_g] call SWLC_fnc_state) == "Recon" || {[_g] call SWLC_fnc_upkeepBusy}) exitWith {};
	private _leg = _g getVariable ["SWLC_leg", ""];
	private _rec = [_g] call SWLC_fnc_vehRecOf;
	if (count _rec > 0) exitWith {[_cmd, _g, _rec, _leg] call SWLC_fnc_upkeepLegCrew};
	[_g] call SWLC_fnc_upkeepLegClear;
	// The vehicle has just gone and the wave's own leg handling is about to deal with it.
	if (_leg in ["DRIVE", "FOLLOW", "LATE"]) exitWith {};
	[_cmd, _g] call SWLC_fnc_upkeepLooseCrew;
};

SWLC_fnc_upkeepLegClear = {
	params ["_g"];
	if ((_g getVariable ["SWLC_loAt", -1]) >= 0) then {
		_g setVariable ["SWLC_loAt", -1];
		_g setVariable ["SWLC_loTries", 0];
	};
};

// A group driving somewhere whose vehicle has no-one in it or no driver. First told to get back in,
// then the vehicle is given up and the group walks. Combat can have them out on purpose, so it waits for that.
SWLC_fnc_upkeepLegCrew = {
	params ["_cmd", "_g", "_rec", "_leg"];
	private _v = _rec get "obj";
	if !(_leg in ["DRIVE", "FOLLOW"]) exitWith {[_g] call SWLC_fnc_upkeepLegClear};
	if (isNull _v || {!alive _v}) exitWith {[_g] call SWLC_fnc_upkeepLegClear};
	private _men = [_g] call SWLC_fnc_alive;
	private _aboard = _men select {vehicle _x == _v};
	private _driver = driver _v;
	if (_aboard isNotEqualTo [] && {alive _driver} && {_driver in _men}) exitWith {[_g] call SWLC_fnc_upkeepLegClear};
	private _at = _g getVariable ["SWLC_loAt", -1];
	if (_at < 0) exitWith {_g setVariable ["SWLC_loAt", time]};
	if ((time - _at) < CFG("leftoverSeconds") || {(behaviour leader _g) == "COMBAT"}) exitWith {};

	private _tries = _g getVariable ["SWLC_loTries", 0];
	_g setVariable ["SWLC_loAt", time];
	_g setVariable ["SWLC_loTries", _tries + 1];
	private _kind = ["crew", "gunner"] select (_aboard isNotEqualTo [] && {(_aboard findIf {(gunner _v) isNotEqualTo _x}) < 0});
	if (_tries == 0 && {canMove _v} && {(fuel _v) > 0}) exitWith {
		[_cmd, _g] call SWLC_fnc_vehMountGroup;
		_rec set ["state", "moving"];
		(_men select {vehicle _x != _v}) orderGetIn true;
		["C_LEFTOVER", [["group", groupId _g], ["kind", _kind], ["action", "remount"]]] call SWLC_fnc_log;
	};
	private _op = _cmd get "op";
	if (!isNil "_op" && {_g in ([_op] call SWLC_fnc_waveLive)}) then {
		// The wave's own leg handling gives the group its foot order.
		_g setVariable ["SWLC_legAbandon", true];
	} else {
		[_cmd, _g] call SWLC_fnc_vehRelease;
		[_g] call SWLC_fnc_upkeepReissue;
	};
	["C_LEFTOVER", [["group", groupId _g], ["kind", _kind], ["action", "abandon"]]] call SWLC_fnc_log;
};

// Worth pulling a man out of: on the ground, no player aboard, and either no driver or his own group's driver.
// A man riding with someone else's driver is being carried.
SWLC_fnc_upkeepLooseRide = {
	params ["_g", "_v"];
	if ((_v isKindOf "ParachuteBase") || {((getPosATL _v) # 2) >= 3}) exitWith {false};
	if ((crew _v) findIf {isPlayer _x} >= 0) exitWith {false};
	private _d = driver _v;
	!alive _d || {(group _d) isEqualTo _g}
};

// Men sitting in a vehicle the commander has no plan for: asked to get out, then put out.
SWLC_fnc_upkeepLooseCrew = {
	params ["_cmd", "_g"];
	private _combat = (behaviour leader _g) == "COMBAT";
	private _wait = CFG("leftoverSeconds");
	private _reissue = false;
	{
		private _u = _x;
		private _v = objectParent _u;
		if (alive _u && {!isNull _v} && {[_g, _v] call SWLC_fnc_upkeepLooseRide}) then {
			// A crew with a working gun in a fight is doing its job, whoever put it there. Men sitting in a truck under fire are not.
			if !(_combat && {canFire _v} && {alive gunner _v}) then {
				private _at = _u getVariable ["SWLC_loAt", -1];
				if (_at < 0) then {
					_u setVariable ["SWLC_loAt", time];
				} else {
					if ((time - _at) >= _wait) then {
						private _tries = _u getVariable ["SWLC_loTries", 0];
						private _kind = ["crew", "gunner"] select ((gunner _v) isEqualTo _u);
						_g leaveVehicle _v;
						unassignVehicle _u;
						[_u] orderGetIn false;
						if (_tries == 0) then {doGetOut _u} else {moveOut _u};
						_u setVariable ["SWLC_loAt", time];
						_u setVariable ["SWLC_loTries", _tries + 1];
						if (_u isEqualTo leader _g) then {_reissue = true};
						["C_LEFTOVER", [["group", groupId _g], ["kind", _kind], ["action", ["getout", "moveout"] select (_tries > 0)]]] call SWLC_fnc_log;
					};
				};
			};
		} else {
			// Out now. Someone who had to be pulled out needs telling what to do next.
			if ((_u getVariable ["SWLC_loAt", -1]) >= 0) then {
				if (alive _u && {(_u getVariable ["SWLC_loTries", 0]) > 0} && {alive leader _g} && {_u isNotEqualTo leader _g}) then {_u doFollow (leader _g)};
				_u setVariable ["SWLC_loAt", -1];
				_u setVariable ["SWLC_loTries", 0];
			};
		};
	} forEach (units _g);
	if (_reissue) then {[_g] call SWLC_fnc_upkeepReissue};
};
