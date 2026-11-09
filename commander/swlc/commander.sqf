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
		["tickSpent", 0],
		["tickWorstSlice", 0],
		["lastDecision", ""]
	];
	missionNamespace setVariable [format ["SWLC_cmd_%1", _side], _cmd];
	[_cmd] call SWLC_fnc_intelStart;
	_cmd set ["heartbeat", time];
	_cmd set ["loopHandle", [_cmd] spawn SWLC_fnc_commanderLoop];
	_cmd set ["guardHandle", [_cmd] spawn SWLC_fnc_commanderGuard];
	if (CFG("resilience")) then {
		[] call SWLC_fnc_resInstall;
		_cmd set ["supervisorHandle", [_cmd] spawn SWLC_fnc_supervisor];
	};
};

// _restarted: started again by the supervisor on the same state, so it has no reason to wait.
SWLC_fnc_commanderLoop = {
	params ["_cmd", ["_restarted", false]];
	scriptName format ["SWLC commander %1", _cmd get "side"];
	// The sides work half a tick apart, so their busy frames don't land together.
	if (!_restarted && {(_cmd get "side") == east}) then {sleep (CFG("tickSeconds") / 2)};
	while {true} do {
		private _started = time;
		_cmd set ["tickSpent", 0];
		{
			_cmd set ["heartbeat", time];
			if (_x isEqualType "") then {
				_cmd set ["curStage", _x];
				[_cmd] call (missionNamespace getVariable ("SWLC_fnc_" + _x));
			} else {
				[_cmd, _x] call SWLC_fnc_cmdSlice;
			};
			sleep CFG("tickYieldSeconds");
		} forEach SWLC_cmdSlices;
		_cmd set ["heartbeat", time];
		[_cmd, _cmd get "tickSpent"] call SWLC_fnc_cmdLogCost;
		sleep ((CFG("tickSeconds") - (time - _started)) max 1);
	};
};

// Between ticks: re-assert orders Warlords' AI overwrote, and vote the moment a vote is possible.
SWLC_fnc_commanderGuard = {
	params ["_cmd"];
	scriptName format ["SWLC guard %1", _cmd get "side"];
	while {true} do {
		sleep CFG("guardSeconds");
		[_cmd] call SWLC_fnc_resWatchSupervisor;
		private _side = _cmd get "side";
		private _spent = 0;
		private _voteOk = false;
		isNil {
			private _t0 = diag_tickTime;
			if (isNull ([_side] call SWLC_fnc_adTarget)) then {
				[_cmd] call SWLC_fnc_voteCast;
			};
			_spent = (diag_tickTime - _t0) * 1000;
			_voteOk = true;
		};
		if (!_voteOk) then {[_cmd, "guardVote"] call SWLC_fnc_resStageFault};
		// One group per step, so a round of re-asserted waypoints doesn't all land in one frame.
		{
			private _g = _x;
			private _sliceOk = false;
			isNil {
				private _t0 = diag_tickTime;
				if (!isNull _g) then {[_cmd, _g, "guard", SWLC_fnc_cmdGuardGroup, "guard"] call SWLC_fnc_resGuarded};
				_spent = _spent + (diag_tickTime - _t0) * 1000;
				_sliceOk = true;
			};
			if (!_sliceOk) then {[_cmd, "guard"] call SWLC_fnc_resStageFault};
			sleep 0.01;
		} forEach ((_cmd get "groups") select {true});
		_cmd set ["guardCost", (_cmd getOrDefault ["guardCost", 0]) + _spent];
		_cmd set ["guardCount", (_cmd getOrDefault ["guardCount", 0]) + 1];
	};
};

SWLC_fnc_cmdGuardGroup = {
	params ["_cmd", "_g"];
	if ([_g] call SWLC_fnc_adGuardOrder) then {
		["C_GUARD", [["side", _cmd get "side"], ["group", groupId _g], ["why", _g getVariable ["SWLC_guardWhy", "?"]]]] call SWLC_fnc_log;
	};
	[_cmd, _g] call SWLC_fnc_squadLight;
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
				["guard_ms", (((_cmd getOrDefault ["guardCost", 0]) / ((_cmd getOrDefault ["guardCount", 0]) max 1))) toFixed 2],
			["max_frame_ms", (_cmd get "tickWorstSlice") toFixed 2]]] call SWLC_fnc_log;
		_cmd set ["tickCost", 0];
		_cmd set ["tickCount", 0];
		_cmd set ["tickWorstSlice", 0];
		{_cmd set [_x, 0]} forEach ["pollCost", "pollCount", "guardCost", "guardCount"];
		if (CFG("profileStages")) then {
			private _fields = [["side", _cmd get "side"]];
			{_fields pushBack [_x, ((_y / _n) toFixed 2)]} forEach (_cmd get "stageCost");
			["C_PROF", _fields] call SWLC_fnc_log;
			_cmd set ["stageCost", createHashMap];
		};
	};
};

// One tick, in order. Each entry runs in its own frame: a list of stages together, or a function that works
// through musters or groups one at a time. A tick spread over several frames costs the same but never stalls one.
SWLC_cmdSlices = [
	["refreshGroups", "cmdTarget", "econTick", "commitTick", "rebuildTick", "intelSummarise", "logInit"],
	["vehTick", "watchdogTick", "waveHead"],
	"cmdMusterSlices",
	["waveTail"],
	["picketTick", "defenceTick"],
	["fortifyTick"],
	["smartTick", "squadTick", "holdoutTick"],
	["contactAttachAll", "engagedTick"],
	"upkeepSlices",
	["raidTick", "probeTick", "menuTick"],
	"cmdAssignSlices",
	"resSweepSlice",
	["planPublish", "statusPublish"]
];

SWLC_fnc_cmdStageCost = {
	params ["_cmd", "_name", "_ms"];
	if !(CFG("profileStages")) exitWith {};
	private _costs = _cmd getOrDefault ["stageCost", createHashMap];
	_costs set [_name, (_costs getOrDefault [_name, 0]) + _ms];
	_cmd set ["stageCost", _costs];
};

SWLC_fnc_cmdSliceDone = {
	params ["_cmd", "_ms"];
	_cmd set ["tickSpent", (_cmd get "tickSpent") + _ms];
	_cmd set ["tickWorstSlice", (_cmd get "tickWorstSlice") max _ms];
};

// A list of stages, all in one frame. Timed inside the isNil: a scheduled script can be suspended between two lines.
// A group can be wiped out in the frames since refreshGroups, and the stages all assume every group has someone alive.
SWLC_fnc_cmdSlice = {
	params ["_cmd", "_names"];
	private _spent = 0;
	isNil {
		private _t0 = diag_tickTime;
		[_cmd, (_cmd get "groups") select {(units _x findIf {alive _x}) < 0}] call SWLC_fnc_dropGroups;
		{
			private _name = _x;
			private _s0 = diag_tickTime;
			private _stageReached = false;
			_cmd set ["curStage", _name];
			// Its own isNil, so where the engine lets an error stop here, the stages after it still run.
			isNil {
				[_cmd] call (missionNamespace getVariable ("SWLC_fnc_" + _name));
				_stageReached = true;
			};
			if (!_stageReached) then {[_cmd, _name] call SWLC_fnc_resStageFault};
			[_cmd, _name, (diag_tickTime - _s0) * 1000] call SWLC_fnc_cmdStageCost;
		} forEach _names;
		_spent = (diag_tickTime - _t0) * 1000;
	};
	[_cmd, _spent] call SWLC_fnc_cmdSliceDone;
};

// Each sector's muster in its own frame. Buying is the most expensive thing the commander does.
SWLC_fnc_cmdMusterSlices = {
	params ["_cmd"];
	private _op = _cmd get "op";
	if (isNil "_op") exitWith {};
	private _id = _op get "id";
	{
		private _name = _x;
		private _busy = false;
		private _spent = 0;
		private _sliceOk = false;
		isNil {
			private _t0 = diag_tickTime;
			private _now = _cmd get "op";
			private _rec = (_cmd get "musters") getOrDefault [_name, createHashMap];
			if (!isNil "_now" && {(_now get "id") == _id} && {count _rec > 0}) then {
				_busy = (_rec get "groups") isNotEqualTo [] || {(_rec get "batch") isNotEqualTo []};
				[_cmd, _now, _rec] call SWLC_fnc_musterTick;
			};
			_spent = (diag_tickTime - _t0) * 1000;
			_sliceOk = true;
		};
		if (!_sliceOk) then {[_cmd, "waveMusters"] call SWLC_fnc_resStageFault};
		[_cmd, "waveMusters", _spent] call SWLC_fnc_cmdStageCost;
		[_cmd, _spent] call SWLC_fnc_cmdSliceDone;
		if (_busy) then {sleep CFG("tickYieldSeconds")};
	} forEach (keys (_cmd get "musters"));
};

// Each unassigned group joins the operation in its own frame: a whole side getting orders at once includes fast travel.
SWLC_fnc_cmdAssignSlices = {
	params ["_cmd"];
	if (isNil {_cmd get "op"}) exitWith {};
	{
		private _g = _x;
		private _spent = 0;
		private _sliceOk = false;
		isNil {
			private _t0 = diag_tickTime;
			if (!isNil {_cmd get "op"} && {(units _g findIf {alive _x}) >= 0} && {([_g] call SWLC_fnc_state) == "Unassigned"} && {time >= (_g getVariable ["SWLC_noAssignUntil", -1])}) then {[_cmd, _g, "assign", SWLC_fnc_musterAssign] call SWLC_fnc_resGuarded};
			_spent = (diag_tickTime - _t0) * 1000;
			_sliceOk = true;
		};
		if (!_sliceOk) then {[_cmd, "cmdAssign"] call SWLC_fnc_resStageFault};
		[_cmd, "cmdAssign", _spent] call SWLC_fnc_cmdStageCost;
		[_cmd, _spent] call SWLC_fnc_cmdSliceDone;
		sleep CFG("tickYieldSeconds");
	} forEach ((_cmd get "groups") select {([_x] call SWLC_fnc_state) == "Unassigned" && {time >= (_x getVariable ["SWLC_noAssignUntil", -1])}});
};

// Tracks the side's target and reacts when it changes.
// A side's vote has been seen to never resolve, leaving it with no target for the whole round. Warlords' vote
// machine moves on when the side's sector count changes, so a stuck vote gets that nudge, and the state is logged.
SWLC_fnc_cmdVoteStuck = {
	params ["_cmd", "_t"];
	if (!isNull _t) exitWith {_cmd deleteAt "noTargetSince"};
	private _side = _cmd get "side";
	if (([_cmd] call SWLC_fnc_rebuilding) || {[_side] call SWLC_fnc_adSideHasPlayers}) exitWith {_cmd deleteAt "noTargetSince"};
	private _since = _cmd getOrDefault ["noTargetSince", -1];
	if (_since < 0) exitWith {_cmd set ["noTargetSince", time]};
	private _wait = CFG("voteStuckSeconds");
	if (_wait <= 0 || {(time - _since) < _wait} || {time < (_cmd getOrDefault ["voteStuckNext", 0])}) exitWith {};
	_cmd set ["voteStuckNext", time + CFG("voteStuckRepeatSeconds")];
	private _var = format ["BIS_WL_lastSectorCnt_%1", _side];
	private _cnt = missionNamespace getVariable [_var, 0];
	["C_VOTESTUCK", [["side", _side], ["after", round (time - _since)],
		["votes", {!isNull (_x getVariable ["BIS_WL_selectedSector", objNull])} count ([_side] call SWLC_fnc_adAIWarlords)],
		["options", count ([_side] call SWLC_fnc_adAvailable)],
		["count", _cnt],
		["selTime", missionNamespace getVariable [format ["BIS_WL_selectionTime_%1", _side], -999]],
		["reset", missionNamespace getVariable ["BIS_WL_resetVoting", "nil"]],
		["aiReset", missionNamespace getVariable ["BIS_WL_AIVotingReset", "nil"]]]] call SWLC_fnc_log;
	missionNamespace setVariable [_var, _cnt + 1];
};

SWLC_fnc_cmdTarget = {
	params ["_cmd"];
	private _side = _cmd get "side";
	private _t = [_side] call SWLC_fnc_adTarget;
	[_cmd, _t] call SWLC_fnc_cmdVoteStuck;

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
			[_cmd] call SWLC_fnc_commitNew;
			_cmd deleteAt "preferredTarget";
			if !([_cmd] call SWLC_fnc_rebuilding) then {[_cmd] call SWLC_fnc_cmdNewPlan};
		};
	};

	// A target that arrived during a rebuild gets its plan once the rebuild is over.
	if (!isNull _t && {isNil {_cmd get "op"}} && {([_t] call SWLC_fnc_adOwner) != _side} && {!([_cmd] call SWLC_fnc_rebuilding)}) then {[_cmd] call SWLC_fnc_cmdNewPlan};

	// Deadlock breaker: no capture for too long, force a new vote on an all-AI side.
	if (!isNull _t
		&& {!([] call SWLC_fnc_commitOn)}
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

// Votes: only on an all-AI side (or if the setting allows it), only for available sectors.
SWLC_fnc_voteCast = {
	params ["_cmd"];
	private _side = _cmd get "side";
	if (([_side] call SWLC_fnc_adSideHasPlayers) && {!CFG("voteOnPlayerSide")}) exitWith {
		// Warlords' AI may vote on a human side. A banned sector doesn't get to come back that way.
		private _ais = [_side] call SWLC_fnc_adAIWarlords;
		if (_ais findIf {
			private _s = _x getVariable ["BIS_WL_selectedSector", objNull];
			!isNull _s && {[_cmd, _s] call SWLC_fnc_commitBanned}
		} < 0) exitWith {};
		private _choice = [_cmd] call SWLC_fnc_voteChoose;
		if (isNull _choice) exitWith {};
		{
			private _s = _x getVariable ["BIS_WL_selectedSector", objNull];
			if (!isNull _s && {[_cmd, _s] call SWLC_fnc_commitBanned}) then {_x setVariable ["BIS_WL_selectedSector", _choice, true]};
		} forEach _ais;
	};
	// While rebuilding, nobody votes. If a respawning warlord has voted anyway, Warlords' timer is running and an
	// empty vote would hand the side its first sector in the list, so the vote gets a real answer. The rebuild still holds the groups back.
	if ([_cmd] call SWLC_fnc_rebuilding) exitWith {
		if (([_side] call SWLC_fnc_adAIWarlords) findIf {!isNull (_x getVariable ["BIS_WL_selectedSector", objNull])} < 0) exitWith {};
		private _choice = [_cmd] call SWLC_fnc_voteChoose;
		if (!isNull _choice) then {[_side, _choice, true] call SWLC_fnc_adCastVotes};
	};
	private _choice = [_cmd] call SWLC_fnc_voteChoose;
	if (!isNull _choice) then {
		// Warlords' own AI votes at random, so a choice made for a reason has to replace it.
		[_side, _choice, [] call SWLC_fnc_commitOn] call SWLC_fnc_adCastVotes;
	};
};

SWLC_fnc_voteChoose = {
	params ["_cmd"];
	private _side = _cmd get "side";
	private _avail = [_side] call SWLC_fnc_adAvailable;
	if (_avail isEqualTo []) exitWith {objNull};
	private _raiding = missionNamespace getVariable [format ["SWLC_raidSector_%1", _side], objNull];
	private _open = _avail select {!([_cmd, _x] call SWLC_fnc_commitBanned) && {_x isNotEqualTo _raiding}};
	if (_open isNotEqualTo []) then {_avail = _open};
	private _preferred = _cmd getOrDefault ["preferredTarget", objNull];
	if (!isNull _preferred && {_preferred in _avail}) exitWith {_preferred};
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
		[_cmd, _best, _avail] call SWLC_fnc_stratLogChoice;
	};
	_best
};

SWLC_fnc_voteScore = {
	params ["_cmd", "_s", "_owned", "_enemyBase"];
	private _p = [_s] call SWLC_fnc_adPos;
	private _d = 1e9;
	{_d = _d min (([_x] call SWLC_fnc_adPos) distance2D _p)} forEach _owned;
	private _unlocks = {([_x] call SWLC_fnc_adOwner) != (_cmd get "side")} count ([_s] call SWLC_fnc_adLinks);
	private _score = ([_s] call SWLC_fnc_adWorth) * CFG("voteValueWeight")
		+ _unlocks * CFG("voteUnlockWeight")
		- (_d / 100) * CFG("voteDistancePer100m");
	if (_s == _enemyBase) then {_score = _score + CFG("voteEnemyBaseBonus")};
	private _momentum = _cmd getOrDefault ["momentum", []];
	if (_momentum isNotEqualTo [] && {(_momentum # 0) isEqualTo _s} && {time < (_momentum # 1)}) then {_score = _score + 100000};
	private _threat = [_cmd, _s] call SWLC_fnc_threatOf;
	private _defence = (_threat get "infantry") * CFG("voteDefenderWeight") + (_threat get "armour") * CFG("voteArmourWeight");
	if !(_threat get "scouted") then {_defence = _defence * CFG("voteUnscoutedFactor")};
	_score = _score - _defence + ([_cmd get "side", _s] call SWLC_fnc_stratWorth) - ([_cmd, _s, _enemyBase] call SWLC_fnc_stratBasePenalty);
	private _failed = (_cmd get "sectorFailures") getOrDefault [[_s] call SWLC_fnc_adName, -1];
	if (_failed >= 0 && {(time - _failed) < CFG("voteRecentFailSeconds")}) then {
		_score = _score - CFG("voteRecentFailPenalty");
	};
	_score
};
