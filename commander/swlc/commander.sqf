// One commander per side, on the server, on a slow tick.
#include "macros.hpp"

SWLC_fnc_startCommander = {
	params ["_side"];
	private _cmd = createHashMapFromArray [
		["side", _side],
		["groups", []],
		["musters", createHashMap],
		["waveCounter", 0],
		["target", objNull],
		["targetSince", 0],
		["sectorFailures", createHashMap],
		["threats", createHashMap],
		["vehicles", []],
		["vehCounter", 0],
		["crate", objNull],
		["dropHelper", objNull],
		["tickCost", 0],
		["tickCount", 0],
		["lastDecision", ""]
	];
	missionNamespace setVariable [format ["SWLC_cmd_%1", _side], _cmd];
	[_cmd] call SWLC_fnc_intelStart;
	[_cmd] spawn SWLC_fnc_commanderLoop;
	[_cmd] spawn SWLC_fnc_commanderGuard;
};

SWLC_fnc_commanderLoop = {
	params ["_cmd"];
	scriptName format ["SWLC commander %1", _cmd get "side"];
	while {true} do {
		private _t0 = diag_tickTime;
		isNil {[_cmd] call SWLC_fnc_cmdTick};
		private _cost = (diag_tickTime - _t0) * 1000;
		[_cmd, _cost] call SWLC_fnc_cmdLogCost;
		sleep CFG("tickSeconds");
	};
};

// Between ticks: re-assert orders Warlords' AI overwrote, and vote the moment a vote is possible.
SWLC_fnc_commanderGuard = {
	params ["_cmd"];
	scriptName format ["SWLC guard %1", _cmd get "side"];
	while {true} do {
		sleep CFG("guardSeconds");
		private _side = _cmd get "side";
		private _spent = 0;
		private _t0 = diag_tickTime;
		isNil {
			if (isNull ([_side] call SWLC_fnc_adTarget)) then {
				[_cmd] call SWLC_fnc_voteCast;
			};
		};
		_spent = (diag_tickTime - _t0) * 1000;
		// One group per step, so a round of re-asserted waypoints doesn't all land in one frame.
		{
			private _g = _x;
			_t0 = diag_tickTime;
			isNil {
				if (!isNull _g && {[_g] call SWLC_fnc_adGuardOrder}) then {
					["C_GUARD", [["side", _side], ["group", groupId _g]]] call SWLC_fnc_log;
				};
			};
			_spent = _spent + (diag_tickTime - _t0) * 1000;
			sleep 0.01;
		} forEach ((_cmd get "groups") select {true});
		_cmd set ["guardCost", (_cmd getOrDefault ["guardCost", 0]) + _spent];
		_cmd set ["guardCount", (_cmd getOrDefault ["guardCount", 0]) + 1];
	};
};

SWLC_fnc_cmdLogCost = {
	params ["_cmd", "_cost"];
	_cmd set ["tickCost", (_cmd get "tickCost") + _cost];
	private _n = (_cmd get "tickCount") + 1;
	_cmd set ["tickCount", _n];
	if (_n >= 6) then {
		["C_TICK", [["side", _cmd get "side"], ["avg_ms", ((_cmd get "tickCost") / _n) toFixed 2], ["groups", count (_cmd get "groups")],
			["op", [0, 1] select (!isNil {_cmd get "op"})], ["fps", round diag_fps],
			["poll_ms", (((_cmd getOrDefault ["pollCost", 0]) / ((_cmd getOrDefault ["pollCount", 0]) max 1))) toFixed 2],
			["guard_ms", (((_cmd getOrDefault ["guardCost", 0]) / ((_cmd getOrDefault ["guardCount", 0]) max 1))) toFixed 2]]] call SWLC_fnc_log;
		_cmd set ["tickCost", 0];
		_cmd set ["tickCount", 0];
		{_cmd set [_x, 0]} forEach ["pollCost", "pollCount", "guardCost", "guardCount"];
		if (CFG("profileStages")) then {
			private _fields = [["side", _cmd get "side"]];
			{_fields pushBack [_x, ((_y / _n) toFixed 2)]} forEach (_cmd get "stageCost");
			["C_PROF", _fields] call SWLC_fnc_log;
			_cmd set ["stageCost", createHashMap];
		};
	};
};

SWLC_cmdStages = ["refreshGroups", "cmdTarget", "intelSummarise", "logInit", "vehTick", "watchdogTick", "waveTick", "defenceTick", "smartTick", "cmdAssign", "planPublish", "statusPublish"];

SWLC_fnc_cmdTick = {
	params ["_cmd"];
	private _profile = CFG("profileStages");
	private _costs = _cmd getOrDefault ["stageCost", createHashMap];
	{
		private _name = _x;
		private _t0 = diag_tickTime;
		[_cmd] call (missionNamespace getVariable ("SWLC_fnc_" + _name));
		if (_profile) then {_costs set [_name, (_costs getOrDefault [_name, 0]) + (diag_tickTime - _t0) * 1000]};
	} forEach SWLC_cmdStages;
	if (_profile) then {_cmd set ["stageCost", _costs]};
};

// Tracks the side's target and reacts when it changes.
SWLC_fnc_cmdTarget = {
	params ["_cmd"];
	private _side = _cmd get "side";
	private _t = [_side] call SWLC_fnc_adTarget;

	if (_t isNotEqualTo (_cmd get "target")) then {
		private _old = _cmd get "target";
		_cmd set ["target", _t];
		_cmd set ["targetSince", time];
		["C_TARGET", [["side", _side], ["target", if (isNull _t) then {"-"} else {[_t] call SWLC_fnc_adName}], ["prev", if (isNull _old) then {"-"} else {[_old] call SWLC_fnc_adName}]]] call SWLC_fnc_log;
		if (!isNil {_cmd get "op"} && {!isNull _old}) then {
			[_cmd, ["target_changed", "seized"] select (([_old] call SWLC_fnc_adOwner) == _side)] call SWLC_fnc_waveResolve;
		};
		if (!isNull _t) then {
			[_side] call SWLC_fnc_adClearVotes;
			[_side, _t] call SWLC_fnc_adBlockVanillaScan;
			[_cmd] call SWLC_fnc_cmdNewPlan;
		};
	};

	// Deadlock breaker: no capture for too long, force a new vote on an all-AI side.
	if (!isNull _t
		&& {(time - (_cmd get "targetSince")) >= CFG("deadlockSeconds")}
		&& {!([_side] call SWLC_fnc_adSideHasPlayers)}) then {
		["C_DECISION", [["side", _side], ["decision", "deadlock_revote"], ["target", [_t] call SWLC_fnc_adName]]] call SWLC_fnc_log;
		(_cmd get "sectorFailures") set [[_t] call SWLC_fnc_adName, time];
		[_side] call SWLC_fnc_adForceRevote;
		_cmd set ["targetSince", time];
	};
};

// New target: one rally point for this operation. Groups muster wherever they are.
SWLC_fnc_cmdNewPlan = {
	params ["_cmd"];
	private _op = [_cmd] call SWLC_fnc_waveNew;
	_cmd set ["op", _op];
	[_cmd get "side", "staging", [[_op get "target"] call SWLC_fnc_adName, mapGridPosition (_op get "rally")]] call SWLC_fnc_radio;
};

// Unassigned groups join the operation.
SWLC_fnc_cmdAssign = {
	params ["_cmd"];
	if (isNil {_cmd get "op"}) exitWith {};
	{
		if (([_x] call SWLC_fnc_state) == "Unassigned") then {[_cmd, _x] call SWLC_fnc_musterAssign};
	} forEach (_cmd get "groups");
};

// Votes: only on an all-AI side (or if the setting allows it), only for available sectors.
SWLC_fnc_voteCast = {
	params ["_cmd"];
	private _side = _cmd get "side";
	if (([_side] call SWLC_fnc_adSideHasPlayers) && {!CFG("voteOnPlayerSide")}) exitWith {};
	private _choice = [_cmd] call SWLC_fnc_voteChoose;
	if (!isNull _choice) then {
		[_side, _choice] call SWLC_fnc_adCastVotes;
	};
};

SWLC_fnc_voteChoose = {
	params ["_cmd"];
	private _side = _cmd get "side";
	private _avail = [_side] call SWLC_fnc_adAvailable;
	if (_avail isEqualTo []) exitWith {objNull};
	private _owned = [_side] call SWLC_fnc_adOwned;
	private _enemyBase = [[_side] call SWLC_fnc_adEnemySide] call SWLC_fnc_adBase;
	private _best = objNull;
	private _bestScore = -1e9;
	{
		private _score = [_cmd, _x, _owned, _enemyBase] call SWLC_fnc_voteScore;
		if (_score > _bestScore) then {_bestScore = _score; _best = _x};
	} forEach _avail;
	if (isNull _best) exitWith {objNull};
	if ((_cmd getOrDefault ["lastVote", objNull]) isNotEqualTo _best) then {
		_cmd set ["lastVote", _best];
		["C_VOTE", [["side", _side], ["sector", [_best] call SWLC_fnc_adName], ["score", _bestScore toFixed 1]]] call SWLC_fnc_log;
	};
	_best
};

SWLC_fnc_voteScore = {
	params ["_cmd", "_s", "_owned", "_enemyBase"];
	private _p = [_s] call SWLC_fnc_adPos;
	private _d = 1e9;
	{_d = _d min (([_x] call SWLC_fnc_adPos) distance2D _p)} forEach _owned;
	private _unlocks = {([_x] call SWLC_fnc_adOwner) != (_cmd get "side")} count ([_s] call SWLC_fnc_adLinks);
	private _score = ([_s] call SWLC_fnc_adValue) * CFG("voteValueWeight")
		+ _unlocks * CFG("voteUnlockWeight")
		- (_d / 100) * CFG("voteDistancePer100m");
	if (_s == _enemyBase) then {_score = _score + CFG("voteEnemyBaseBonus")};
	private _momentum = _cmd getOrDefault ["momentum", []];
	if (_momentum isNotEqualTo [] && {(_momentum # 0) isEqualTo _s} && {time < (_momentum # 1)}) then {_score = _score + 100000};
	private _threat = [_cmd, _s] call SWLC_fnc_threatOf;
	private _defence = (_threat get "infantry") * CFG("voteDefenderWeight") + (_threat get "armour") * CFG("voteArmourWeight");
	if !(_threat get "scouted") then {_defence = _defence * CFG("voteUnscoutedFactor")};
	_score = _score - _defence;
	private _failed = (_cmd get "sectorFailures") getOrDefault [[_s] call SWLC_fnc_adName, -1];
	if (_failed >= 0 && {(time - _failed) < CFG("voteRecentFailSeconds")}) then {
		_score = _score - CFG("voteRecentFailPenalty");
	};
	_score
};
