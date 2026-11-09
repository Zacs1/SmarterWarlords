// Resilience: the full sweep, the stuck ladder, the idle cap, commander protection and group locality.
//
// Every behaviour is behind the master switch "resilience" and its own switch in settings.sqf. None of this is part
// of rulesVariant. Runs wherever isServer is true.
//
// How the last rung handles a warlord slot. The 16 slot warlords are playable units: deleting one removes the slot
// from Warlords (BIS_WL_allWarlords, funds, the slot for a joining player). So the men and the slot are treated apart:
//   - Bought men are deleted. Their price comes back through adCredit, and the normal shop tops the group up at its
//     next muster, so the men are "fresh" without creating any for free.
//   - The men go first because Warlords' AI core teleports a respawned warlord next to any subordinate still alive.
//   - The slot warlord is killed with setDamage 1: the same thing Bohemia's own AI core does to a stuck warlord
//     ("was forced to respawn"). The mission respawns it at base after 20 seconds with a fresh body and a fresh AI
//     core, funds intact through Bohemia's backup. A null killer means no enemy income or kill credit.
//   - Spawn protection (allowDamage false) would make that a no-op, so allowDamage true comes first.
//   - Nothing can then keep it alive, but the sweep checks anyway: still alive after ladderRespawnVerifySeconds and
//     it is moved to the base and given new orders.
#include "macros.hpp"

// States the code gives a moving order to. Left out on purpose, from what they actually do:
// Mustering and Waiting stand at their spot until the go signal, Mounting waits for seats, Unassigned has its own check,
// Borrowed and Pickup belong to a player.
SWLC_resNeedOrder = ["Travelling", "Advancing", "Regrouping", "Assaulting", "Recon", "Raiding", "Probing", "Hunting", "Defending", "Picket", "Reserve"];
// States where a finished order away from the goal means the group has stopped short.
SWLC_resNeedArrival = ["Travelling", "Advancing", "Regrouping", "Assaulting"];
SWLC_ladderRungs = ["reissue", "reroute", "dismount", "fasttravel", "respawn"];

SWLC_fnc_resItem = {
	params ["_key"];
	CFG("resilience") && {SWLC_settings get _key}
};

SWLC_fnc_resLog = {
	params ["_cmd", "_g", "_fault", "_fix"];
	["C_RES", [["action", "sweep"], ["group", groupId _g], ["side", _cmd get "side"], ["fault", _fault], ["fix", _fix]]] call SWLC_fnc_log;
};

// Never a player's group, and never one borrowed through the menu.
SWLC_fnc_resMayTouch = {
	params ["_g"];
	if (isNull _g) exitWith {false};
	if (([_g] call SWLC_fnc_groupMen) == 0) exitWith {false};
	if (([_g] call SWLC_fnc_state) in ["Borrowed", "Pickup"]) exitWith {false};
	if ((_g getVariable ["SWLC_borrowedBy", objNull]) isNotEqualTo objNull) exitWith {false};
	!([_g] call SWLC_fnc_adGroupHasPlayer)
};

// ---- Protection ----

// Records what a script error said, for the supervisor's log line. Bohemia's engine has this event; if an
// older one doesn't, the line just says "unknown".
SWLC_fnc_resInstall = {
	if (!isNil "SWLC_resInstalled") exitWith {};
	SWLC_resInstalled = true;
	addMissionEventHandler ["ScriptError", {
		params [["_text", ""]];
		// Kept to one log field: no separators or line breaks.
		SWLC_lastScriptError = ((_text splitString (toString [10, 13, 124])) joinString " ") select [0, 200];
	}];
};

// The test hook. Runs code with a script error, once, for a group the test marked.
SWLC_fnc_resSabotage = {
	params ["_cmd", "_g", "_stage"];
	if !(CFG("testHooks")) exitWith {};
	if !(_g getVariable ["SWLC_sabotageError", false]) exitWith {};
	_g setVariable ["SWLC_sabotageError", nil];
	["C_RES", [["action", "sabotage"], ["group", groupId _g], ["side", _cmd get "side"], ["stage", _stage]]] call SWLC_fnc_log;
	private _boom = [] select 5;
	_boom
};

// Runs one group's work so its failure stays its own, as far as the engine allows. SQF has no catch, and how far an
// error unwinds isn't something to rely on, so this works either way:
//   - the sentinel names the group and stage before the work and is cleared after it;
//   - if the error ends only the isNil, control comes back here with the reached flag still false: the group is
//     quarantined and the tick carries on;
//   - if the error kills the whole script, the sentinel is left standing and the supervisor reads it.
// _slot keeps the guard script's sentinel apart from the main loop's.
SWLC_fnc_resGuarded = {
	params ["_cmd", "_g", "_stage", "_code", ["_slot", "cur"]];
	if !(["resGroupGuard"] call SWLC_fnc_resItem) exitWith {
		[_cmd, _g] call _code;
		true
	};
	if (_g in (_cmd getOrDefault ["quarantine", []])) exitWith {true};
	private _resReached = false;
	isNil {
		_cmd set [_slot + "Group", _g];
		_cmd set [_slot + "Stage", _stage];
		[_cmd, _g, _stage] call SWLC_fnc_resSabotage;
		[_cmd, _g] call _code;
		_resReached = true;
		_cmd set [_slot + "Group", grpNull];
		_cmd set [_slot + "Stage", ""];
	};
	if (!_resReached) then {
		_cmd set [_slot + "Group", grpNull];
		_cmd set [_slot + "Stage", ""];
		[_cmd, _g, _stage] call SWLC_fnc_resGroupFault;
	};
	_resReached
};

// A stage died and control came back. Log it, and blame the group if one was being worked on.
SWLC_fnc_resStageFault = {
	params ["_cmd", "_stage"];
	if !(["resGroupGuard"] call SWLC_fnc_resItem) exitWith {};
	private _g = _cmd getOrDefault ["curGroup", grpNull];
	["C_SUP", [["side", _cmd get "side"], ["action", "stage_error"], ["stale_s", 0],
		["last_group", if (isNull _g) then {"-"} else {groupId _g}], ["last_stage", _stage],
		["error", missionNamespace getVariable ["SWLC_lastScriptError", "unknown"]]]] call SWLC_fnc_log;
	_cmd set ["curGroup", grpNull];
	_cmd set ["curStage", ""];
	if (!isNull _g) then {[_cmd, _g, _stage] call SWLC_fnc_resGroupFault};
};

// Several groups failing in one stage within moments: the stage is what's broken, and replacing the groups would
// throw away a side's men for a bug. Returns true when the stage takes the blame; the groups keep working.
SWLC_fnc_resStageBlame = {
	params ["_cmd", "_g", "_stage"];
	private _all = _cmd getOrDefault ["stageFaults", createHashMap];
	_cmd set ["stageFaults", _all];
	private _window = CFG("stageFaultWindowSeconds");
	private _recent = (_all getOrDefault [_stage, []]) select {(time - (_x # 0)) <= _window};
	_recent pushBack [time, _g];
	_all set [_stage, _recent];
	private _groups = _recent apply {_x # 1};
	_groups = (_groups arrayIntersect _groups) select {!isNull _x};
	if ((count _groups) < CFG("stageFaultGroups")) exitWith {false};
	// The ones that failed first were already set aside. They go back, with nothing held against them.
	_cmd set ["quarantine", (_cmd getOrDefault ["quarantine", []]) - _groups];
	{
		_x setVariable ["SWLC_quarantineUntil", nil];
		_x setVariable ["SWLC_errCount", 0];
		[_x] call SWLC_fnc_ladderReset;
	} forEach _groups;
	private _logKey = _stage + "#logged";
	if ((time - (_all getOrDefault [_logKey, -1e6])) >= _window) then {
		_all set [_logKey, time];
		["C_SUP", [["side", _cmd get "side"], ["action", "stage_fault"], ["stale_s", 0], ["last_group", groupId _g], ["last_stage", _stage], ["groups", count _groups],
			["error", missionNamespace getVariable ["SWLC_lastScriptError", "unknown"]]]] call SWLC_fnc_log;
	};
	true
};

// A group's handling failed: log it, put it aside for a while and send it to the ladder. A group that keeps
// failing goes straight to the last rung, which replaces whatever about it is broken.
SWLC_fnc_resGroupFault = {
	params ["_cmd", "_g", "_stage"];
	if (isNull _g) exitWith {};
	["C_GROUPERR", [["side", _cmd get "side"], ["group", groupId _g], ["stage", _stage]]] call SWLC_fnc_log;
	if ([_cmd, _g, _stage] call SWLC_fnc_resStageBlame) exitWith {};

	private _q = _cmd getOrDefault ["quarantine", []];
	_q pushBackUnique _g;
	_cmd set ["quarantine", _q];
	_g setVariable ["SWLC_quarantineUntil", time + CFG("quarantineSeconds")];
	// It can't do its part while set aside, so the wave shouldn't wait for it. The sweep gives it a job when it's back.
	[_cmd, _g] call SWLC_fnc_waveRemoveGroup;

	private _last = _g getVariable ["SWLC_errLast", -1e6];
	private _count = [1, (_g getVariable ["SWLC_errCount", 0]) + 1] select ((time - _last) <= CFG("quarantineRepeatWindow"));
	_g setVariable ["SWLC_errCount", _count];
	_g setVariable ["SWLC_errLast", time];

	if !(["resLadder"] call SWLC_fnc_resItem) exitWith {};
	if (_count >= CFG("quarantineRepeatLimit")) exitWith {
		[_cmd, _g, "script_error_repeat", "respawn"] call SWLC_fnc_ladderStep;
	};
	[_cmd, _g, "script_error"] call SWLC_fnc_ladderStep;
};

// One per side. The loop can't report its own death, so this watches a heartbeat it updates every slice.
SWLC_fnc_supervisor = {
	params ["_cmd"];
	private _side = _cmd get "side";
	scriptName format ["SWLC supervisor %1", _side];
	while {true} do {
		sleep CFG("supervisorPollSeconds");
		if (["resSupervisor"] call SWLC_fnc_resItem) then {
			private _reached = false;
			isNil {
				[_cmd] call SWLC_fnc_supervisorCheck;
				_reached = true;
			};
			if (!_reached) then {
				["C_SUP", [["side", _side], ["action", "self_error"], ["stale_s", 0], ["last_group", "-"], ["last_stage", "supervisor"],
					["error", missionNamespace getVariable ["SWLC_lastScriptError", "unknown"]]]] call SWLC_fnc_log;
			};
		};
	};
};

SWLC_fnc_supervisorCheck = {
	params ["_cmd"];
	private _side = _cmd get "side";
	private _error = missionNamespace getVariable ["SWLC_lastScriptError", "unknown"];

	// The guard script has no heartbeat of its own, but a dead one can be seen.
	private _guard = _cmd getOrDefault ["guardHandle", scriptNull];
	if (scriptDone _guard) then {
		private _gg = _cmd getOrDefault ["guardGroup", grpNull];
		private _gs = _cmd getOrDefault ["guardStage", ""];
		["C_SUP", [["side", _side], ["action", "restart_guard"], ["stale_s", 0],
			["last_group", if (isNull _gg) then {"-"} else {groupId _gg}], ["last_stage", _gs], ["error", _error]]] call SWLC_fnc_log;
		_cmd set ["guardGroup", grpNull];
		_cmd set ["guardStage", ""];
		_cmd set ["guardHandle", [_cmd] spawn SWLC_fnc_commanderGuard];
		if (!isNull _gg) then {[_cmd, _gg, _gs] call SWLC_fnc_resGroupFault};
	};

	private _stale = time - (_cmd getOrDefault ["heartbeat", time]);
	if (_stale < CFG("supervisorStaleSeconds")) exitWith {};

	private _g = _cmd getOrDefault ["curGroup", grpNull];
	private _stage = _cmd getOrDefault ["curStage", ""];
	["C_SUP", [["side", _side], ["action", "restart"], ["stale_s", round _stale],
		["last_group", if (isNull _g) then {"-"} else {groupId _g}], ["last_stage", _stage], ["error", _error]]] call SWLC_fnc_log;
	terminate (_cmd getOrDefault ["loopHandle", scriptNull]);
	_cmd set ["curGroup", grpNull];
	_cmd set ["curStage", ""];
	_cmd set ["heartbeat", time];
	if (!isNull _g) then {[_cmd, _g, _stage] call SWLC_fnc_resGroupFault};
	_cmd set ["loopHandle", [_cmd, true] spawn SWLC_fnc_commanderLoop];
};

// The guard looks after the supervisor, so neither can quietly be the only one gone.
SWLC_fnc_resWatchSupervisor = {
	params ["_cmd"];
	if !(["resSupervisor"] call SWLC_fnc_resItem) exitWith {};
	if !(scriptDone (_cmd getOrDefault ["supervisorHandle", scriptNull])) exitWith {};
	["C_SUP", [["side", _cmd get "side"], ["action", "restart_supervisor"], ["stale_s", 0], ["last_group", "-"], ["last_stage", "supervisor"],
		["error", missionNamespace getVariable ["SWLC_lastScriptError", "unknown"]]]] call SWLC_fnc_log;
	_cmd set ["supervisorHandle", [_cmd] spawn SWLC_fnc_supervisor];
};

// ---- Putting a group back to work ----

// Holds a group with no operation to join at the nearest owned sector that isn't being seized. It stays Unassigned, so
// it joins the next operation like any other. Moving it also keeps Warlords from treating a waiting leader as stuck.
SWLC_fnc_resHoldOrder = {
	params ["_cmd", "_g", ["_walk", false]];
	private _side = _cmd get "side";
	private _p = getPosATL leader _g;
	private _owned = ([_side] call SWLC_fnc_adOwned) select {
		private _s = _x;
		!(CFG("rulesVariant") && {CFG("ruleNoRespawnSeized")} && {[_side, _s] call SWLC_fnc_capBeingSeized})
	};
	if (_owned isEqualTo []) then {_owned = [_side] call SWLC_fnc_adOwned};
	if (_owned isEqualTo []) exitWith {false};
	if (_walk) then {
		private _near = _owned select {[_p, [_x] call SWLC_fnc_adPos] call SWLC_fnc_ladderWalkable};
		if (_near isNotEqualTo []) then {_owned = _near};
	};
	private _c = [[_owned, _p] call SWLC_fnc_adNearest] call SWLC_fnc_adPos;
	private _spot = [_c, _g] call SWLC_fnc_shuffleSpot;
	if (!isNil "SWLC_fnc_routeSafePos") then {
		private _safe = [_spot, CFG("ladderLandRadius")] call SWLC_fnc_routeSafePos;
		if (!isNil "_safe" && {_safe isNotEqualTo []}) then {_spot = _safe};
	};
	_g setVariable ["SWLC_goal", _spot];
	_g setVariable ["SWLC_holdAt", time];
	[_g, [[_spot, "MOVE", 15]], "AWARE", "NORMAL", "WEDGE", "YELLOW"] call SWLC_fnc_adSetOrder;
	true
};

// Takes the group off whatever it was doing and gives it a new task now.
SWLC_fnc_groupReassign = {
	params ["_cmd", "_g", ["_reason", "reassign"]];
	if !([_g] call SWLC_fnc_resMayTouch) exitWith {false};
	[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
	[_g] call SWLC_fnc_adClearOrder;
	_g setVariable ["SWLC_picketSector", nil];
	_g setVariable ["SWLC_scoutUntil", nil];
	_g setVariable ["SWLC_joinUntil", -1];
	[_g, "Unassigned", [], _reason] call SWLC_fnc_setState;
	if (!isNil {_cmd get "op"} && {!([_cmd] call SWLC_fnc_rebuilding)}) exitWith {
		[_cmd, _g] call SWLC_fnc_musterAssign;
		true
	};
	[_cmd, _g] call SWLC_fnc_resHoldOrder;
	true
};

// ---- The ladder ----

// Whether a group could walk between two places. Always yes with the water check switched off.
SWLC_fnc_ladderWalkable = {
	params ["_from", "_to"];
	if !(["noWaterMoves"] call SWLC_fnc_resItem) exitWith {true};
	[_from, _to] call SWLC_fnc_routeLandReachable
};

// For a group the ladder won't replace: a job it can reach. The operation if there's land to its rally, otherwise a
// hold at the nearest owned sector it can walk to, and it's left out of the operation for a while so it isn't sent
// straight back to the order it couldn't carry out.
SWLC_fnc_ladderReachableJob = {
	params ["_cmd", "_g", "_reason"];
	if !([_g] call SWLC_fnc_resMayTouch) exitWith {false};
	private _op = _cmd get "op";
	private _joins = !isNil "_op" && {!([_cmd] call SWLC_fnc_rebuilding)} && {[getPosATL leader _g, _op get "rally"] call SWLC_fnc_ladderWalkable};
	[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
	[_g] call SWLC_fnc_adClearOrder;
	_g setVariable ["SWLC_picketSector", nil];
	_g setVariable ["SWLC_scoutUntil", nil];
	_g setVariable ["SWLC_joinUntil", -1];
	[_g, "Unassigned", [], _reason] call SWLC_fnc_setState;
	["C_LADDER", [["group", groupId _g], ["side", _cmd get "side"], ["rung", "job"], ["reason", _reason], ["joins", _joins]]] call SWLC_fnc_log;
	if (_joins) exitWith {
		[_cmd, _g] call SWLC_fnc_musterAssign;
		true
	};
	_g setVariable ["SWLC_noAssignUntil", time + CFG("ladderJobHoldSeconds")];
	[_cmd, _g, true] call SWLC_fnc_resHoldOrder;
	true
};

// How far the group still has to go: along its route when the route code is loaded, else in a straight line.
SWLC_fnc_watchdogDist = {
	params ["_g", "_goal"];
	if (_goal isEqualTo []) exitWith {0};
	private _dist = (leader _g) distance2D _goal;
	if (!isNil "SWLC_fnc_routeRemaining") then {
		private _left = [_g] call SWLC_fnc_routeRemaining;
		if (!isNil "_left" && {_left isEqualType 0} && {_left >= 0}) then {_dist = _left};
	};
	_dist
};

SWLC_fnc_ladderReset = {
	params ["_g"];
	_g setVariable ["SWLC_ladderRung", 0];
	_g setVariable ["SWLC_ladderStart", nil];
	_g setVariable ["SWLC_ladderAt", nil];
	_g setVariable ["SWLC_ladderDist", nil];
	_g setVariable ["SWLC_ladderJob", nil];
};

// A rung gets a chance to work before the next one. Called by the watchdog while the ladder is climbing.
SWLC_fnc_ladderTick = {
	params ["_cmd", "_g", "_state", "_goal", "_dist"];
	(_g getVariable ["SWLC_ladderJob", []]) params [["_jobState", ""], ["_jobGoal", []]];
	// A new job or a different goal is a new problem, not this one getting worse.
	if (_jobState != _state || {_jobGoal isEqualTo []} || {(_jobGoal distance2D _goal) > CFG("ladderSameGoalMetres")}) exitWith {
		[_g] call SWLC_fnc_ladderReset;
	};
	if (((_g getVariable ["SWLC_ladderDist", _dist]) - _dist) >= CFG("ladderProgressMetres")) exitWith {
		[_g] call SWLC_fnc_ladderReset;
		_g setVariable ["SWLC_stuck", 0];
		_g setVariable ["SWLC_progress", []];
	};
	if ((time - (_g getVariable ["SWLC_ladderAt", 0])) < CFG("ladderRungSeconds")) exitWith {};
	[_cmd, _g, "no_progress"] call SWLC_fnc_ladderStep;
};

// Advances one rung: the next one that can do something. A rung that can't apply (not mounted, no other route,
// fast travel refused) falls through to the next at once, so a dead rung costs no time.
// _force names a rung to go to directly. Returns the rung used, or "" if there was nothing to do.
SWLC_fnc_ladderStep = {
	params ["_cmd", "_g", ["_reason", "stuck"], ["_force", ""]];
	if !([_g] call SWLC_fnc_resMayTouch) exitWith {""};
	private _next = if (_force == "") then {_g getVariable ["SWLC_ladderRung", 0]} else {(SWLC_ladderRungs find _force) max 0};
	private _state = [_g] call SWLC_fnc_state;
	private _goal = _g getVariable ["SWLC_goal", []];
	if ((_g getVariable ["SWLC_ladderRung", 0]) == 0) then {_g setVariable ["SWLC_ladderStart", time]};
	private _done = "";
	private _wait = false;
	while {_done == "" && {!_wait} && {_next < count SWLC_ladderRungs}} do {
		private _rung = SWLC_ladderRungs # _next;
		if (_rung == "respawn" && {_force == ""} && {_g getVariable ["SWLC_orderBlocked", false]}) then {
			// The order has no land route, and a fresh body at base wouldn't have one either. Fast travel has had its go.
			_next = _next + 1;
			["C_LADDERSKIP", [["group", groupId _g], ["side", _cmd get "side"], ["rung", _rung], ["why", "order_blocked"]]] call SWLC_fnc_log;
			[_cmd, _g, "ladder_blocked"] call SWLC_fnc_ladderReachableJob;
			_done = "job";
		} else {
			// The earlier rungs can all fall through in one step. Replacing a group needs longer than that to be justified.
			if (_rung == "respawn" && {_force == ""} && {(time - (_g getVariable ["SWLC_ladderStart", time])) < CFG("ladderMinClimbSeconds")}) then {
				_wait = true;
			} else {
				_next = _next + 1;
				private _why = [_cmd, _g, _rung, _reason, _state, _goal] call SWLC_fnc_ladderApply;
				if (_why == "") then {
					_done = _rung;
				} else {
					["C_LADDERSKIP", [["group", groupId _g], ["side", _cmd get "side"], ["rung", _rung], ["why", _why]]] call SWLC_fnc_log;
				};
			};
		};
	};
	// Every rung refused, which only happens with the last rung switched off: start again from the first.
	if (_done == "" && {!_wait}) exitWith {
		[_g] call SWLC_fnc_ladderReset;
		""
	};
	if (_done in ["respawn", "job"]) exitWith {
		[_g] call SWLC_fnc_ladderReset;
		_done
	};
	_g setVariable ["SWLC_ladderRung", _next];
	_g setVariable ["SWLC_ladderAt", time];
	_g setVariable ["SWLC_ladderDist", [_g, _goal] call SWLC_fnc_watchdogDist];
	_g setVariable ["SWLC_ladderJob", [_state, _goal]];
	_done
};

// Tries one rung. Returns "" if it did something, otherwise why it couldn't. Every rung that acts logs itself.
SWLC_fnc_ladderApply = {
	params ["_cmd", "_g", "_rung", "_reason", "_state", "_goal"];
	private _log = {
		["C_LADDER", [["group", groupId _g], ["side", _cmd get "side"], ["rung", _rung], ["reason", _reason]]] call SWLC_fnc_log;
	};
	private _why = "";
	switch (_rung) do {
		case "reissue": {
			if ((_g getVariable ["SWLC_order", []]) isEqualTo []) then {
				_why = "no_order";
			} else {
				[_g, _g getVariable ["SWLC_wpProgress", 0]] call SWLC_fnc_adApplyOrder;
				{_x doFollow leader _g} forEach ([_g] call SWLC_fnc_alive);
				call _log;
			};
		};
		case "reroute": {
			if (isNil "SWLC_fnc_routeAlternate") then {
				_why = "no_route_code";
			} else {
				private _other = [_g, _reason] call SWLC_fnc_routeAlternate;
				if (!isNil "_other" && {_other isEqualTo true}) then {
					[_g, _g getVariable ["SWLC_wpProgress", 0]] call SWLC_fnc_adApplyOrder;
					call _log;
				} else {
					_why = "no_alternate";
				};
			};
		};
		case "dismount": {
			private _seated = ([_g] call SWLC_fnc_alive) select {vehicle _x != _x};
			if (_seated isEqualTo []) then {
				_why = "not_mounted";
			} else {
				if (count ([_g] call SWLC_fnc_vehRecOf) > 0) then {
					[_cmd, _g] call SWLC_fnc_vehRelease;
				} else {
					private _units = [_g] call SWLC_fnc_alive;
					{unassignVehicle _x} forEach _units;
					_units orderGetIn false;
					{doGetOut _x} forEach _seated;
				};
				call _log;
			};
		};
		case "fasttravel": {
			if ([_cmd, _g, _state, _goal, true] call SWLC_fnc_watchdogEscalate) then {call _log} else {_why = "ft_refused"};
		};
		case "respawn": {
			_why = [_cmd, _g, _reason] call SWLC_fnc_ladderRespawn;
		};
	};
	_why
};

// The last rung. See the top of this file for why a slot warlord is handled the way it is.
// Returns "" when done, otherwise why it couldn't.
SWLC_fnc_ladderRespawn = {
	params ["_cmd", "_g", "_reason"];
	if !(CFG("ladderRespawn")) exitWith {"switched_off"};
	private _side = _cmd get "side";
	private _units = [_g] call SWLC_fnc_alive;
	if (_units isEqualTo []) exitWith {"no_men"};
	if ([_g] call SWLC_fnc_adGroupHasPlayer) exitWith {"player"};

	// A cap on the last rung, so no fault can spend a side's men faster than this.
	private _times = (_cmd getOrDefault ["respawnTimes", []]) select {(time - _x) < CFG("ladderRespawnWindowSeconds")};
	if ((count _times) >= CFG("ladderRespawnMax")) exitWith {
		_cmd set ["respawnTimes", _times];
		[_cmd, _g, "ladder_capped"] call SWLC_fnc_ladderReachableJob;
		"capped"
	};
	_times pushBack time;
	_cmd set ["respawnTimes", _times];

	private _slots = _units select {[_x] call SWLC_fnc_adIsWarlord};
	private _bought = _units - _slots;

	// What the bought men cost when they were bought, or the list price for men from elsewhere.
	// A class the shop doesn't sell refunds nothing.
	private _list = _cmd getOrDefault ["infantry", []];
	private _refund = 0;
	{
		private _price = _x getVariable "SWLC_paid";
		if (isNil "_price") then {
			private _class = typeOf _x;
			private _i = _list findIf {(_x # 0) == _class};
			_price = if (_i >= 0) then {(_list # _i) # 1} else {0};
		};
		_refund = _refund + _price;
	} forEach _bought;
	_refund = round (_refund * CFG("ladderRefundFactor"));

	[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
	[_g] call SWLC_fnc_adClearOrder;
	_g setVariable ["SWLC_picketSector", nil];
	_g setVariable ["SWLC_scoutUntil", nil];

	// Men first: the respawning warlord is sent to a living subordinate otherwise.
	{
		if (vehicle _x == _x) then {deleteVehicle _x} else {(vehicle _x) deleteVehicleCrew _x};
	} forEach _bought;

	// Paid before the kill and not to the warlords about to die: a dead warlord's funds come back from a backup that
	// is only taken every two seconds, so a credit just before the kill could be lost with it.
	private _paid = [_side, _refund, _slots] call SWLC_fnc_adCredit;
	if (_paid < _refund) then {_paid = _paid + ([_side, _refund - _paid] call SWLC_fnc_adCredit)};

	private _pending = _cmd getOrDefault ["respawning", []];
	{
		_x setVariable ["SWLC_forcedRespawn", true];
		_x allowDamage true;
		if (vehicle _x != _x) then {moveOut _x};
		_x setDamage 1;
		_pending pushBack [_x, _g, time];
	} forEach _slots;
	_cmd set ["respawning", _pending];

	["C_LADDER", [["group", groupId _g], ["side", _side], ["rung", "respawn"], ["reason", _reason], ["refund", _paid]]] call SWLC_fnc_log;
	""
};

// The guarantee behind the last rung. A warlord still alive after the kill is moved to base and put back to work.
SWLC_fnc_ladderVerify = {
	params ["_cmd"];
	private _pending = _cmd getOrDefault ["respawning", []];
	if (_pending isEqualTo []) exitWith {};
	private _wait = CFG("ladderRespawnVerifySeconds");
	private _keep = [];
	{
		_x params ["_u", "_g", "_at"];
		if (alive _u) then {
			if ((time - _at) < _wait) then {
				_keep pushBack _x;
			} else {
				private _base = [[_cmd get "side"] call SWLC_fnc_adBase] call SWLC_fnc_adPos;
				if (vehicle _u != _u) then {moveOut _u};
				_u setPosATL [(_base # 0) + 5 + random 20, (_base # 1) + 5 + random 20, 0];
				["C_RES", [["action", "respawn_fallback"], ["group", groupId _g], ["side", _cmd get "side"]]] call SWLC_fnc_log;
				[_cmd, _g, "respawn_fallback"] call SWLC_fnc_groupReassign;
			};
		};
	} forEach _pending;
	_cmd set ["respawning", _keep];
};

// ---- The sweep ----

// Whether the goal still makes sense. "" if it does.
SWLC_fnc_resGoalFault = {
	params ["_cmd", "_g", "_state"];
	private _side = _cmd get "side";
	private _op = _cmd get "op";
	private _fault = "";
	// A join-push is an Assaulting group outside any wave, on purpose, and ends itself when its time is up.
	if (_state in ["Travelling", "Mustering", "Mounting", "Advancing", "Waiting", "Regrouping", "Assaulting"] && {(_g getVariable ["SWLC_joinUntil", -1]) < 0}) then {
		if (isNil "_op") then {
			_fault = "bad_goal";
		} else {
			if (([_op get "target"] call SWLC_fnc_adOwner) == _side || {(_g getVariable ["SWLC_waveId", -1]) != (_op get "id")}) then {
				_fault = "bad_goal";
			} else {
				if (_state in ["Travelling", "Mustering", "Mounting"]) then {
					private _rec = (_cmd get "musters") getOrDefault [_g getVariable ["SWLC_musterName", ""], createHashMap];
					if (count _rec == 0 || {([_rec get "sector"] call SWLC_fnc_adOwner) != _side}) then {_fault = "bad_goal"};
				};
			};
		};
	};
	if (_state == "Picket") then {
		private _s = _g getVariable ["SWLC_picketSector", objNull];
		if (isNull _s || {([_s] call SWLC_fnc_adOwner) != _side}) then {_fault = "bad_goal"};
	};
	if (_state == "Raiding" && {count ([_cmd] call SWLC_fnc_raidOf) == 0}) then {_fault = "bad_goal"};
	if (_state == "Probing" && {count (_cmd getOrDefault ["probe", createHashMap]) == 0}) then {_fault = "bad_goal"};
	if (_state == "Hunting" && {time >= (_g getVariable ["SWLC_huntUntil", 0]) + CFG("resHuntOverdueSeconds")}) then {_fault = "bad_goal"};
	if (_state == "Recon" && {isNil {_g getVariable "SWLC_scoutUntil"}}) then {_fault = "bad_goal"};
	_fault
};

// What is wrong with a group, or "".
SWLC_fnc_resFaultOf = {
	params ["_cmd", "_g", "_state", "_age"];
	private _leader = leader _g;
	if (_state == "-") exitWith {"no_task"};

	if (_state == "Unassigned") exitWith {
		if ([_cmd] call SWLC_fnc_rebuilding) exitWith {""};
		if (_age < CFG("idleGraceSeconds")) exitWith {""};
		if (!isNil {_cmd get "op"} && {time >= (_g getVariable ["SWLC_noAssignUntil", -1])}) exitWith {"no_task"};
		if ((_g getVariable ["SWLC_order", []]) isEqualTo []) exitWith {"no_task"};
		// No operation yet and a hold order already: keep it shifting, nothing to report.
		if ((time - (_g getVariable ["SWLC_holdAt", -1e6])) >= CFG("reservePatrolSeconds") && {[_g] call SWLC_fnc_adOrderDone}) then {
			[_cmd, _g] call SWLC_fnc_resHoldOrder;
		};
		""
	};

	if (_age < CFG("resSweepGraceSeconds")) exitWith {""};

	private _fault = "";
	if (_state in SWLC_resNeedOrder
		&& {(behaviour _leader) != "COMBAT"}
		&& {(_g getVariable ["SWLC_leg", ""]) != "LATE"}
		&& {!([_g] call SWLC_fnc_lambsBusy)}) then {
		private _waitingForRide = _state == "Recon" && {!(_g getVariable ["SWLC_scoutMoving", false])} && {!isNull (_g getVariable ["SWLC_scoutVeh", objNull])};
		if (!_waitingForRide) then {
			private _goal = _g getVariable ["SWLC_goal", []];
			if ((_g getVariable ["SWLC_order", []]) isEqualTo []) then {
				_fault = "no_waypoint";
			} else {
				if (_goal isEqualTo []) then {
					_fault = "no_goal";
				} else {
					if (_state in SWLC_resNeedArrival && {[_g] call SWLC_fnc_adOrderDone} && {(_leader distance2D _goal) > CFG("resNotAtGoalMetres")}) then {
						private _op = _cmd get "op";
						private _inTarget = _state == "Assaulting" && {!isNil "_op"} && {[_op get "target", getPosATL _leader] call SWLC_fnc_adInSquare};
						if (!_inTarget) then {_fault = "no_waypoint"};
					};
				};
			};
		};
	};
	if (_fault == "") then {_fault = [_cmd, _g, _state] call SWLC_fnc_resGoalFault};
	_fault
};

// Applies the fix for a fault that has now been seen on two sweeps in a row, and returns what was done.
SWLC_fnc_resFix = {
	params ["_cmd", "_g", "_fault"];
	// A waypoint problem with a task that's still good only needs the order written again.
	if (_fault == "no_waypoint" && {(_g getVariable ["SWLC_order", []]) isNotEqualTo []}) exitWith {
		[_g, 0] call SWLC_fnc_adApplyOrder;
		{_x doFollow leader _g} forEach ([_g] call SWLC_fnc_alive);
		"reissue"
	};
	[_cmd, _g, "sweep_" + _fault] call SWLC_fnc_groupReassign;
	["assign", "hold"] select (isNil {_cmd get "op"} || {[_cmd] call SWLC_fnc_rebuilding})
};

// Re-issues a group's orders when it moves to another machine.
SWLC_fnc_resLocality = {
	params ["_cmd", "_g"];
	if !(["resLocality"] call SWLC_fnc_resItem) exitWith {};
	private _owner = groupOwner _g;
	private _was = _g getVariable ["SWLC_ownerWas", -1];
	_g setVariable ["SWLC_ownerWas", _owner];
	if (_was < 0 || {_was == _owner}) exitWith {};
	["C_LOCALITY", [["group", groupId _g], ["from", _was], ["to", _owner]]] call SWLC_fnc_log;
	if ((_g getVariable ["SWLC_order", []]) isNotEqualTo []) then {
		[_g, _g getVariable ["SWLC_wpProgress", 0]] call SWLC_fnc_adApplyOrder;
		{_x doFollow leader _g} forEach ([_g] call SWLC_fnc_alive);
	};
};

SWLC_fnc_resCheckGroup = {
	params ["_cmd", "_g"];
	if !([_g] call SWLC_fnc_resMayTouch) exitWith {};
	if (isNull leader _g) exitWith {};
	[_cmd, _g] call SWLC_fnc_resLocality;
	if !(["resSweep"] call SWLC_fnc_resItem) exitWith {};

	private _state = [_g] call SWLC_fnc_state;
	private _age = time - (_g getVariable ["SWLC_stateSince", -1e6]);
	private _fault = [_cmd, _g, _state, _age] call SWLC_fnc_resFaultOf;
	if (_fault == "") exitWith {_g setVariable ["SWLC_resFault", ""]};

	// One sighting could be a frame between two stages. A real fault is still there on the next sweep.
	if ((_g getVariable ["SWLC_resFault", ""]) != _fault) exitWith {_g setVariable ["SWLC_resFault", _fault]};
	_g setVariable ["SWLC_resFault", ""];

	[_cmd, _g, _fault, [_cmd, _g, _fault] call SWLC_fnc_resFix] call SWLC_fnc_resLog;

	// The same group needing a fix again and again has something the sweep can't mend.
	private _fixes = ((_g getVariable ["SWLC_resFixes", []]) select {(time - _x) < CFG("resFixWindowSeconds")}) + [time];
	_g setVariable ["SWLC_resFixes", _fixes];
	if ((count _fixes) >= CFG("resFixesToLadder") && {["resLadder"] call SWLC_fnc_resItem}) then {
		_g setVariable ["SWLC_resFixes", []];
		[_cmd, _g, "sweep_" + _fault] call SWLC_fnc_ladderStep;
	};
};

// True if the group is sitting about when it should be working. A group waiting inside its limits is not idle.
SWLC_fnc_resIsIdle = {
	params ["_cmd", "_g", "_loneWait"];
	private _state = [_g] call SWLC_fnc_state;
	private _age = time - (_g getVariable ["SWLC_stateSince", time]);
	if (_state == "Unassigned") exitWith {_age >= CFG("idleGraceSeconds")};
	if (_state == "Mustering") exitWith {_age >= CFG("musterMaxSeconds") + CFG("idleMusterMargin")};
	if (_state == "Waiting") exitWith {
		// Held at the rally on purpose: a player's hold, or the wait for groups peeled off to defend.
		private _op = _cmd get "op";
		private _held = !isNil "_op" && {(_op getOrDefault ["holdGo", false])
			|| {time < (_op getOrDefault ["playerHoldUntil", -1])}
			|| {(time - (_op getOrDefault ["peelHoldSince", -1e6])) < CFG("peelHoldMaxSeconds")}};
		!_held && {_age >= _loneWait + CFG("idleWaitingMargin")}
	};
	// LAMBS clears the order while it has the group: that's a group with a job.
	(_state in SWLC_resNeedOrder) && {_age >= CFG("resSweepGraceSeconds")} && {(_g getVariable ["SWLC_order", []]) isEqualTo []} && {!([_g] call SWLC_fnc_lambsBusy)}
};

// Too much of the side standing about means the plan has stopped working, whatever the reason. Drop it and start over.
SWLC_fnc_resIdleCap = {
	params ["_cmd", "_idle", "_total"];
	if !(["resIdleCap"] call SWLC_fnc_resItem) exitWith {};
	if (_total < CFG("idleCapMinGroups")) exitWith {};
	private _share = _idle / _total;
	if (_share <= CFG("idleCapShare")) exitWith {};
	if (time < (_cmd getOrDefault ["idleCapNext", 0])) exitWith {};
	if ([_cmd] call SWLC_fnc_rebuilding) exitWith {};
	private _hasOp = !isNil {_cmd get "op"};
	private _target = _cmd get "target";
	// No plan and no target just means a vote is under way, and a new plan needs a target.
	if (!_hasOp && {isNull _target}) exitWith {};
	_cmd set ["idleCapNext", time + CFG("idleCapCooldownSeconds")];
	["C_IDLECAP", [["side", _cmd get "side"], ["idle", _idle], ["total", _total], ["share", _share toFixed 2], ["action", "replan"]]] call SWLC_fnc_log;
	if (_hasOp) then {[_cmd, "idle_cap"] call SWLC_fnc_waveResolve};
	if (!isNull _target && {([_target] call SWLC_fnc_adOwner) != (_cmd get "side")}) then {[_cmd] call SWLC_fnc_cmdNewPlan};
};

// Quarantine in and out, the last rung's guarantee, and groups the commander has lost track of.
SWLC_fnc_resSweepStart = {
	params ["_cmd"];
	[_cmd] call SWLC_fnc_ladderVerify;

	private _q = _cmd getOrDefault ["quarantine", []];
	if (_q isNotEqualTo []) then {
		_q = _q select {!isNull _x && {([_x] call SWLC_fnc_groupMen) > 0} && {time < (_x getVariable ["SWLC_quarantineUntil", 0])}};
		_cmd set ["quarantine", _q];
		_cmd set ["groups", (_cmd get "groups") - _q];
	};

	if !(["resSweep"] call SWLC_fnc_resItem) exitWith {};
	if (time < (_cmd getOrDefault ["resLostNext", 0])) exitWith {};
	_cmd set ["resLostNext", time + CFG("resLostScanSeconds")];
	private _side = _cmd get "side";
	private _list = _cmd get "groups";
	// A group still marked with a job but on nobody's list. Groups the commander let go are marked "-".
	{
		private _g = _x;
		_list pushBack _g;
		_g setVariable ["SWLC_waveId", -1];
		[_cmd, _g, "lost", "readopted"] call SWLC_fnc_resLog;
		[_cmd, _g, "lost"] call SWLC_fnc_groupReassign;
	} forEach (allGroups select {
		side _x == _side
		&& {!(_x in _list)}
		&& {!(_x in _q)}
		&& {!((_x getVariable ["SWLC_state", "-"]) in ["-", "Borrowed", "Pickup"])}
		&& {[_x] call SWLC_fnc_resMayTouch}
	});
};

// Every tick: one group per frame, so the sweep costs almost nothing in any one of them.
SWLC_fnc_resSweepSlice = {
	params ["_cmd"];
	if !(CFG("resilience")) exitWith {};
	private _startOk = false;
	isNil {
		[_cmd] call SWLC_fnc_resSweepStart;
		_startOk = true;
	};
	if (!_startOk) then {[_cmd, "resSweepStart"] call SWLC_fnc_resStageFault};

	private _idle = 0;
	private _total = 0;
	private _op = _cmd get "op";
	private _loneWait = if (isNil "_op") then {CFG("rallyLoneWait")} else {[_cmd, _op] call SWLC_fnc_rallyLoneWait};
	{
		private _g = _x;
		private _spent = 0;
		private _sliceOk = false;
		isNil {
			private _t0 = diag_tickTime;
			if (!isNull _g && {_g in (_cmd get "groups")}) then {
				[_cmd, _g, "sweep", SWLC_fnc_resCheckGroup] call SWLC_fnc_resGuarded;
				if ([_g] call SWLC_fnc_resMayTouch) then {
					_total = _total + 1;
					if ([_cmd, _g, _loneWait] call SWLC_fnc_resIsIdle) then {_idle = _idle + 1};
				};
			};
			_spent = (diag_tickTime - _t0) * 1000;
			_sliceOk = true;
		};
		if (!_sliceOk) then {[_cmd, "resSweep"] call SWLC_fnc_resStageFault};
		[_cmd, "resSweep", _spent] call SWLC_fnc_cmdStageCost;
		[_cmd, _spent] call SWLC_fnc_cmdSliceDone;
		sleep CFG("tickYieldSeconds");
	} forEach ((_cmd get "groups") select {true});

	private _capOk = false;
	isNil {
		[_cmd, _idle, _total] call SWLC_fnc_resIdleCap;
		_capOk = true;
	};
	if (!_capOk) then {[_cmd, "resIdleCap"] call SWLC_fnc_resStageFault};
};
