// One commander per side, on the server, on a slow tick.
#include "macros.hpp"

SWLC_fnc_startCommander = {
	params ["_side"];
	private _cmd = createHashMapFromArray [
		["side", _side],
		["groups", []],
		["flying", []],
		["waveCounter", 0],
		["target", objNull],
		["targetSince", 0],
		["stagingSector", objNull],
		["stagingPos", []],
		["stagingSpots", []],
		["stagingSlot", 0],
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
		isNil {
			private _side = _cmd get "side";
			if (isNull ([_side] call SWLC_fnc_adTarget)) then {
				[_cmd] call SWLC_fnc_voteCast;
			};
			{
				if ([_x] call SWLC_fnc_adGuardOrder) then {
					["C_GUARD", [["side", _side], ["group", groupId _x]]] call SWLC_fnc_log;
				};
			} forEach (_cmd get "groups");
		};
	};
};

SWLC_fnc_cmdLogCost = {
	params ["_cmd", "_cost"];
	_cmd set ["tickCost", (_cmd get "tickCost") + _cost];
	private _n = (_cmd get "tickCount") + 1;
	_cmd set ["tickCount", _n];
	if (_n >= 6) then {
		["C_TICK", [["side", _cmd get "side"], ["avg_ms", ((_cmd get "tickCost") / _n) toFixed 2], ["groups", count (_cmd get "groups")],
			["flying", count (_cmd get "flying")], ["fps", round diag_fps]]] call SWLC_fnc_log;
		_cmd set ["tickCost", 0];
		_cmd set ["tickCount", 0];
	};
};

SWLC_fnc_cmdTick = {
	params ["_cmd"];
	[_cmd] call SWLC_fnc_refreshGroups;
	[_cmd] call SWLC_fnc_cmdTarget;
	[_cmd] call SWLC_fnc_intelSummarise;
	[_cmd] call SWLC_fnc_logInit;
	[_cmd] call SWLC_fnc_vehTick;
	[_cmd] call SWLC_fnc_watchdogTick;
	[_cmd] call SWLC_fnc_waveTick;
	[_cmd] call SWLC_fnc_defenceTick;
	[_cmd] call SWLC_fnc_smartTick;
	[_cmd] call SWLC_fnc_cmdAssign;
	[_cmd] call SWLC_fnc_planPublish;
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
		if (isNull _t) then {
			_cmd deleteAt "gather";
		} else {
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

// New target: new staging, new gather wave.
SWLC_fnc_cmdNewPlan = {
	params ["_cmd"];
	private _target = _cmd get "target";
	_cmd set ["stagingChoice", [_cmd, _target] call SWLC_fnc_chooseStaging];
	[_cmd] call SWLC_fnc_setStaging;
	private _w = [_cmd] call SWLC_fnc_waveNew;
	_cmd set ["gather", _w];
	[_cmd get "side", "staging", [[_cmd] call SWLC_fnc_stagingName, [_target] call SWLC_fnc_adName]] call SWLC_fnc_radio;

	// Groups that were gathering for the old target move to the new plan.
	{
		if (([_x] call SWLC_fnc_state) in ["Staging", "Travelling", "Regrouping"]) then {
			[_cmd, _x] call SWLC_fnc_vehRelease;
			[_cmd, _x, "Travelling"] call SWLC_fnc_sendToStaging;
		};
	} forEach (_cmd get "groups");
};

// Unassigned groups join the gathering wave.
SWLC_fnc_cmdAssign = {
	params ["_cmd"];
	if (isNil {_cmd get "gather"}) exitWith {};
	{
		if (([_x] call SWLC_fnc_state) == "Unassigned") then {
			[_cmd, _x, "Travelling"] call SWLC_fnc_sendToStaging;
		};
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
