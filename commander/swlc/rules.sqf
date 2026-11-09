// Rules variant, part B: capture progress that pauses and decays, no respawning in a sector being seized,
// and a commitment timer so no target can hold a side forever. Warlords' own trigger stays in charge of
// the capture; this file only shortens what is left of its countdown between attempts.
#include "macros.hpp"

// ---- Capture progress ----

SWLC_capRecs = createHashMap;

SWLC_fnc_capNominal = {
	params ["_s"];
	((_s getVariable ["SWLC_timeoutT", 60]) / 1.5) max CFG("captureMinRemaining")
};

// A sector's seize triggers exist once its Warlords handler has started. Returns [] until then.
SWLC_fnc_capTriggers = {
	params ["_s"];
	private _have = _s getVariable ["SWLC_capTrg", []];
	if (_have isNotEqualTo []) exitWith {_have};
	if ((time - (_s getVariable ["SWLC_capLook", -1e6])) < 5) exitWith {[]};
	_s setVariable ["SWLC_capLook", time];
	private _found = (allMissionObjects "EmptyDetector") select {(_x getVariable ["BIS_WL_parentSector", objNull]) isEqualTo _s};
	if ((count _found) >= 2) then {_s setVariable ["SWLC_capTrg", _found]};
	_found
};

// The trigger that hands the sector to _side.
SWLC_fnc_capTrigger = {
	params ["_s", "_side"];
	private _want = format ["%1 SEIZED", ["EAST", "WEST"] select (_side == west)];
	private _trgs = [_s] call SWLC_fnc_capTriggers;
	private _i = _trgs findIf {((triggerActivation _x) # 0) == _want};
	if (_i < 0) exitWith {objNull};
	_trgs # _i
};

SWLC_fnc_capKey = {
	params ["_s", "_side"];
	format ["%1|%2", [_s] call SWLC_fnc_adName, _side]
};

SWLC_fnc_capSetTimeout = {
	params ["_trg", "_seconds"];
	if (!CFG("ruleCapturePause") && {!(_trg getVariable ["SWLC_capForce", false])}) exitWith {};
	_trg setTriggerTimeout [_seconds, _seconds, _seconds, true];
};

// A raid takes longer than a main target. The multiplier stays on the sector for that side.
SWLC_fnc_capNominalFor = {
	params ["_s", "_side"];
	([_s] call SWLC_fnc_capNominal) * (_s getVariable [format ["SWLC_capMult_%1", _side], 1])
};

// Fixes the countdown length while the sector is being watched, which removes Warlords' random roll.
SWLC_fnc_capPrime = {
	params ["_s", "_side"];
	private _trg = [_s, _side] call SWLC_fnc_capTrigger;
	if (isNull _trg) exitWith {};
	private _key = [_s, _side] call SWLC_fnc_capKey;
	if (_key in SWLC_capRecs) exitWith {};
	private _nominal = [_s, _side] call SWLC_fnc_capNominalFor;
	private _flag = format ["SWLC_capPrimed_%1", _side];
	if ((_s getVariable [_flag, -1]) != _nominal && {(triggerTimeoutCurrent _trg) < 0}) then {
		[_trg, _nominal] call SWLC_fnc_capSetTimeout;
		_s setVariable [_flag, _nominal];
	};
};

SWLC_fnc_capFinish = {
	params ["_key", "_rec", "_why"];
	private _s = _rec get "sector";
	private _side = _rec get "side";
	private _nominal = [_s, _side] call SWLC_fnc_capNominalFor;
	[_rec get "trg", _nominal] call SWLC_fnc_capSetTimeout;
	_s setVariable [format ["SWLC_capPrimed_%1", _side], _nominal];
	["C_CAP", [["side", _side], ["sector", [_s] call SWLC_fnc_adName], ["event", _why], ["left", (_rec get "rem") toFixed 1]]] call SWLC_fnc_log;
	SWLC_capRecs deleteAt _key;
};

SWLC_fnc_capUpdate = {
	params ["_key", "_rec"];
	private _s = _rec get "sector";
	private _side = _rec get "side";
	if (([_s] call SWLC_fnc_adOwner) == _side) exitWith {[_key, _rec, "captured"] call SWLC_fnc_capFinish};
	private _trg = _rec get "trg";
	private _cur = triggerTimeoutCurrent _trg;
	private _dt = time - (_rec get "last");
	_rec set ["last", time];
	if (_cur >= 0) then {
		if !(_rec get "counting") then {
			_rec set ["counting", true];
			_rec set ["started", time];
			["C_CAP", [["side", _side], ["sector", [_s] call SWLC_fnc_adName], ["event", "resume"], ["left", _cur toFixed 1]]] call SWLC_fnc_log;
		};
		_rec set ["rem", _cur];
		_rec set ["countedAt", time];
		// Warlords' seize bar reads this as the full length, and its own loop rewrites it on every new countdown.
		if (CFG("ruleCapturePause") && {(time - (_rec get "started")) < 5} && {(_s getVariable ["BIS_WL_timeoutBase", 0]) != (_rec get "nominal")}) then {
			_s setVariable ["BIS_WL_timeoutBase", _rec get "nominal", true];
		};
	} else {
		if (_rec get "counting") then {
			_rec set ["counting", false];
			_rec set ["pausedAt", time];
			["C_CAP", [["side", _side], ["sector", [_s] call SWLC_fnc_adName], ["event", "pause"], ["left", (_rec get "rem") toFixed 1], ["nominal", (_rec get "nominal") toFixed 1]]] call SWLC_fnc_log;
		};
		if ((time - (_rec get "pausedAt")) >= CFG("captureHoldSeconds")) then {
			_rec set ["rem", ((_rec get "rem") + CFG("captureDecayPerSecond") * _dt) min (_rec get "nominal")];
		};
		private _apply = ((_rec get "rem") max CFG("captureMinRemaining")) min (_rec get "nominal");
		if (abs (_apply - (_rec get "applied")) >= 0.5) then {
			[_trg, _apply] call SWLC_fnc_capSetTimeout;
			_rec set ["applied", _apply];
		};
		if ((_rec get "rem") >= (_rec get "nominal")) then {[_key, _rec, "reset"] call SWLC_fnc_capFinish};
	};
};

SWLC_fnc_capWatch = {
	params ["_s", "_side"];
	if (isNull _s) exitWith {};
	if (([_s] call SWLC_fnc_adOwner) == _side) exitWith {};
	[_s, _side] call SWLC_fnc_capPrime;
	private _key = [_s, _side] call SWLC_fnc_capKey;
	if (_key in SWLC_capRecs) exitWith {};
	private _trg = [_s, _side] call SWLC_fnc_capTrigger;
	if (isNull _trg) exitWith {};
	private _cur = triggerTimeoutCurrent _trg;
	if (_cur < 0) exitWith {};
	private _nominal = ([_s, _side] call SWLC_fnc_capNominalFor) max _cur;
	SWLC_capRecs set [_key, createHashMapFromArray [["sector", _s], ["side", _side], ["trg", _trg], ["nominal", _nominal], ["rem", _cur], ["applied", _cur],
		["counting", true], ["started", time], ["last", time], ["countedAt", time], ["pausedAt", time]]];
	["C_CAP", [["side", _side], ["sector", [_s] call SWLC_fnc_adName], ["event", "start"], ["left", _cur toFixed 1], ["nominal", _nominal toFixed 1]]] call SWLC_fnc_log;
};

// Sectors each side can capture right now: its target and, later, its raid.
SWLC_fnc_capWatched = {
	params ["_side"];
	private _list = [[_side] call SWLC_fnc_adTarget];
	private _raid = missionNamespace getVariable [format ["SWLC_raidSector_%1", _side], objNull];
	if (!isNull _raid) then {_list pushBack _raid};
	_list
};

SWLC_fnc_capLoop = {
	scriptName "SWLC capture";
	while {true} do {
		sleep CFG("capturePollSeconds");
		private _pollOk = false;
		isNil {
			{
				private _side = _x;
				{[_x, _side] call SWLC_fnc_capWatch} forEach ([_side] call SWLC_fnc_capWatched);
			} forEach [west, east];
			{[_x, SWLC_capRecs get _x] call SWLC_fnc_capUpdate} forEach (keys SWLC_capRecs);
			_pollOk = true;
		};
		if (!_pollOk && {["resGroupGuard"] call SWLC_fnc_resItem}) then {
			["C_SUP", [["side", "-"], ["action", "stage_error"], ["stale_s", 0], ["last_group", "-"], ["last_stage", "capture"],
				["error", missionNamespace getVariable ["SWLC_lastScriptError", "unknown"]]]] call SWLC_fnc_log;
		};
	};
};

// How far along _side's capture of _s is, 0 to 1. A countdown that restarted still counts.
SWLC_fnc_capProgress = {
	params ["_s", "_side"];
	private _rec = SWLC_capRecs getOrDefault [[_s, _side] call SWLC_fnc_capKey, createHashMap];
	if (count _rec == 0) exitWith {0};
	(1 - ((_rec get "rem") / ((_rec get "nominal") max 1))) max 0
};

// One line for the commander panel, because Warlords' own seize bar is hidden while a capture is paused.
SWLC_fnc_capStatusText = {
	params ["_s", "_side"];
	if (isNull _s) exitWith {""};
	private _rec = SWLC_capRecs getOrDefault [[_s, _side] call SWLC_fnc_capKey, createHashMap];
	if (count _rec == 0) exitWith {""};
	format [["holding %1%%", "seizing %1%%"] select (_rec get "counting"), round (100 * ([_s, _side] call SWLC_fnc_capProgress))]
};

// Seconds since _side's countdown on _s was last running, or a huge number.
SWLC_fnc_capIdleFor = {
	params ["_s", "_side"];
	private _rec = SWLC_capRecs getOrDefault [[_s, _side] call SWLC_fnc_capKey, createHashMap];
	if (count _rec == 0) exitWith {1e6};
	if (_rec get "counting") exitWith {0};
	time - (_rec get "countedAt")
};

// True while the enemy has a capture running or banked on _s, which _side owns.
SWLC_fnc_capBeingSeized = {
	params ["_side", "_s"];
	if ([_side, _s] call SWLC_fnc_adEnemySeizing) exitWith {true};
	private _enemy = [_side] call SWLC_fnc_adEnemySide;
	private _rec = SWLC_capRecs getOrDefault [[_s, _enemy] call SWLC_fnc_capKey, createHashMap];
	(count _rec > 0) && {(_rec get "counting") || {(time - (_rec get "pausedAt")) < CFG("captureHoldSeconds")}}
};

// ---- Respawn ----

// The owned sector nearest _pos that is not being seized. Falls back to the base.
SWLC_fnc_rulesSafeSector = {
	params ["_side", "_pos"];
	private _safe = ([_side] call SWLC_fnc_adOwned) select {!([_side, _x] call SWLC_fnc_capBeingSeized)};
	if (_safe isEqualTo []) exitWith {[_side] call SWLC_fnc_adBase};
	([_safe, _pos] call SWLC_fnc_adNearest)
};

// Warlords puts a respawned AI warlord beside a living subordinate. If that is inside a sector being seized,
// move him out. The check repeats for a few seconds because Warlords' own teleport runs after the respawn event.
SWLC_fnc_rulesRespawnFix = {
	params ["_unit"];
	scriptName "SWLC respawn check";
	private _side = side group _unit;
	if !(_side in [west, east]) exitWith {};
	private _end = time + CFG("respawnCheckSeconds");
	while {time < _end && {alive _unit}} do {
		sleep 1;
		private _pos = getPosATL _unit;
		private _i = ([_side] call SWLC_fnc_adOwned) findIf {[_x, _pos, CFG("respawnSectorMargin")] call SWLC_fnc_adInSquare && {[_side, _x] call SWLC_fnc_capBeingSeized}};
		if (_i >= 0) then {
			private _from = ([_side] call SWLC_fnc_adOwned) # _i;
			private _to = [_side, _pos] call SWLC_fnc_rulesSafeSector;
			private _c = [_to] call SWLC_fnc_adPos;
			private _spot = ([_c, random 360, 20 + random 40] call SWLC_fnc_offset) findEmptyPosition [1, 40, "CAManBase"];
			if (_spot isEqualTo []) then {_spot = +_c};
			_unit setPosATL [_spot # 0, _spot # 1, 0];
			["C_RESPAWN", [["side", _side], ["unit", groupId group _unit], ["moved_from", [_from] call SWLC_fnc_adName], ["moved_to", [_to] call SWLC_fnc_adName]]] call SWLC_fnc_log;
		};
	};
};

// ---- Kills and losses, for the commitment decision ----

SWLC_fnc_rulesInstall = {
	[] call SWLC_fnc_frontInstall;
	addMissionEventHandler ["EntityRespawned", {
		params ["_new"];
		if (!isPlayer _new && {_new isKindOf "CAManBase"} && {CFG("ruleNoRespawnSeized")}) then {[_new] spawn SWLC_fnc_rulesRespawnFix};
	}];
	addMissionEventHandler ["EntityKilled", {
		params ["_dead", "_killer", "_instigator"];
		if !(_dead isKindOf "CAManBase") exitWith {};
		private _deadSide = side group _dead;
		if !(_deadSide in [west, east]) exitWith {};
		private _cmd = missionNamespace getVariable [format ["SWLC_cmd_%1", _deadSide], createHashMap];
		// A warlord the ladder sent to respawn wasn't lost to the enemy, and the commitment decision shouldn't think so.
		if (count _cmd > 0 && {!(_dead getVariable ["SWLC_forcedRespawn", false])}) then {_cmd set ["losses", (_cmd getOrDefault ["losses", 0]) + 1]};
		private _by = if (isNull _instigator) then {_killer} else {_instigator};
		if (isNull _by || {_by == _dead}) exitWith {};
		private _other = missionNamespace getVariable [format ["SWLC_cmd_%1", side group _by], createHashMap];
		if (count _other > 0 && {(side group _by) != _deadSide}) then {_other set ["kills", (_other getOrDefault ["kills", 0]) + 1]};
	}];
	[] spawn SWLC_fnc_capLoop;
};

// ---- Commitment timer ----

SWLC_fnc_commitOn = { CFG("rulesVariant") && {CFG("ruleCommitTimer")} };

SWLC_fnc_commitNew = {
	params ["_cmd"];
	private _timerKey = ["commitSeconds", "commitSecondsHuman"] select ([_cmd get "side"] call SWLC_fnc_adSideHasPlayers);
	_cmd set ["commitUntil", time + CFG(_timerKey)];
	_cmd set ["commitExt", 0];
	_cmd set ["commitLosses", _cmd getOrDefault ["losses", 0]];
	_cmd set ["commitKills", _cmd getOrDefault ["kills", 0]];
};

SWLC_fnc_commitBanned = {
	params ["_cmd", "_s"];
	time < ((_cmd getOrDefault ["banned", createHashMap]) getOrDefault [[_s] call SWLC_fnc_adName, -1])
};

// Sectors the side can move on to instead: available to it, not banned, not the one it's leaving.
SWLC_fnc_commitCandidates = {
	params ["_cmd", "_t"];
	([_cmd get "side"] call SWLC_fnc_adAvailable) select {_x isNotEqualTo _t && {([_x] call SWLC_fnc_adOwner) != (_cmd get "side")} && {!([_cmd, _x] call SWLC_fnc_commitBanned)}}
};

SWLC_fnc_commitBan = {
	params ["_cmd", "_s"];
	private _banned = _cmd getOrDefault ["banned", createHashMap];
	_banned set [[_s] call SWLC_fnc_adName, time + CFG("abandonBanSeconds")];
	_cmd set ["banned", _banned];
	[_cmd] call SWLC_fnc_commitBanPublish;
};

// Clients see only the bans still running, so this also runs when one expires.
SWLC_fnc_commitBanPublish = {
	params ["_cmd"];
	private _banned = _cmd getOrDefault ["banned", createHashMap];
	private _list = (keys _banned) select {time < (_banned get _x)};
	_list sort true;
	if (_list isEqualTo (_cmd getOrDefault ["bannedShown", []])) exitWith {};
	_cmd set ["bannedShown", _list];
	missionNamespace setVariable [format ["SWLC_banned_%1", _cmd get "side"], _list, true];
};

SWLC_fnc_commitLog = {
	params ["_cmd", "_decision", "_t", "_extra"];
	["C_COMMIT", [["side", _cmd get "side"], ["decision", _decision], ["target", [_t] call SWLC_fnc_adName], ["held", round (time - (_cmd get "targetSince"))]] + _extra] call SWLC_fnc_log;
};

// The timer ran out. Close to winning: stay. Otherwise switch, pull back, or for a human side reopen the vote.
SWLC_fnc_commitDecide = {
	params ["_cmd", "_t"];
	private _side = _cmd get "side";
	private _progress = [_t, _side] call SWLC_fnc_capProgress;
	private _idle = [_t, _side] call SWLC_fnc_capIdleFor;
	private _op = _cmd get "op";
	private _fails = if (isNil "_op") then {0} else {_op getOrDefault ["pushFails", 0]};
	private _lost = (_cmd getOrDefault ["losses", 0]) - (_cmd getOrDefault ["commitLosses", 0]);
	private _killed = (_cmd getOrDefault ["kills", 0]) - (_cmd getOrDefault ["commitKills", 0]);
	private _ratio = _lost / (_killed max 1);
	private _men = 0;
	{_men = _men + ([_x] call SWLC_fnc_groupMen)} forEach (_cmd get "groups");
	private _perGroup = _men / ((count (_cmd get "groups")) max 1);
	private _extra = [["progress", _progress toFixed 2], ["idle", round (_idle min 9999)], ["fails", _fails], ["ratio", _ratio toFixed 2], ["men", _men]];

	private _close = _progress >= CFG("commitStayProgress") || {_progress >= CFG("commitStayProgressRecent") && {_idle <= CFG("commitRecentSeconds")}};
	if (_close && {(_cmd get "commitExt") < CFG("commitMaxExtensions")}) exitWith {
		_cmd set ["commitExt", (_cmd get "commitExt") + 1];
		_cmd set ["commitUntil", time + CFG("commitExtendSeconds")];
		[_cmd, "stay", _t, _extra] call SWLC_fnc_commitLog;
		[_side, "commitstay", [[_t] call SWLC_fnc_adName]] call SWLC_fnc_radio;
	};

	if (([_side] call SWLC_fnc_adSideHasPlayers) && {([_cmd, _t] call SWLC_fnc_commitCandidates) isEqualTo []}) exitWith {
		_cmd set ["commitUntil", time + CFG("commitExtendSeconds")];
		[_cmd, "stay_no_alternative", _t, _extra] call SWLC_fnc_commitLog;
	};

	if ([_side] call SWLC_fnc_adSideHasPlayers) exitWith {
		[_cmd, "reopen_vote", _t, _extra] call SWLC_fnc_commitLog;
		[_side, "commitvote", [[_t] call SWLC_fnc_adName, round (CFG("abandonBanSeconds") / 60)]] call SWLC_fnc_radio;
		[_cmd, _t, ""] call SWLC_fnc_commitLeave;
	};

	private _candidates = [_cmd, _t] call SWLC_fnc_commitCandidates;
	private _losing = _ratio >= CFG("commitLossRatio") || {_fails >= CFG("commitFailedPushes")};
	private _rebuild = (_losing && {_perGroup < CFG("commitRebuildMenPerGroup")}) || {_candidates isEqualTo []};
	if (_rebuild && {_candidates isEqualTo []} && {!_losing}) exitWith {
		_cmd set ["commitUntil", time + CFG("commitExtendSeconds")];
		[_cmd, "stay_no_alternative", _t, _extra] call SWLC_fnc_commitLog;
	};
	if (_rebuild) exitWith {
		[_cmd, "rebuild", _t, _extra] call SWLC_fnc_commitLog;
		[_side, "commitrebuild", [[_t] call SWLC_fnc_adName]] call SWLC_fnc_radio;
		[_cmd, _t, "rebuild"] call SWLC_fnc_commitLeave;
	};

	private _weak = _cmd getOrDefault ["probeWeak", createHashMap];
	private _pick = objNull;
	private _bestScore = -1e9;
	private _owned = [_side] call SWLC_fnc_adOwned;
	private _enemyBase = [[_side] call SWLC_fnc_adEnemySide] call SWLC_fnc_adBase;
	{
		private _score = [_cmd, _x, _owned, _enemyBase] call SWLC_fnc_voteScore;
		if (time < (_weak getOrDefault [[_x] call SWLC_fnc_adName, -1])) then {_score = _score + CFG("commitProbeWeakBonus")};
		if (_score > _bestScore) then {_bestScore = _score; _pick = _x};
	} forEach _candidates;
	[_cmd, "switch", _t, _extra + [["to", [_pick] call SWLC_fnc_adName]]] call SWLC_fnc_commitLog;
	[_side, "commitswitch", [[_t] call SWLC_fnc_adName, [_pick] call SWLC_fnc_adName]] call SWLC_fnc_radio;
	_cmd set ["preferredTarget", _pick];
	[_cmd, _t, ""] call SWLC_fnc_commitLeave;
};

// Bans the sector, pulls attackers out of its square, and clears the target once they're out.
// Warlords kills AI left inside a sector that is no longer their target.
SWLC_fnc_commitLeave = {
	params ["_cmd", "_t", "_then"];
	// A side leaving to save its holdouts hasn't given up on that sector.
	if (_then != "hold") then {[_cmd, _t] call SWLC_fnc_commitBan};
	private _op = _cmd get "op";
	if (!isNil "_op") then {
		_op set ["holdGo", true];
		private _live = [_op] call SWLC_fnc_waveLive;
		private _attackers = _live select {([_x] call SWLC_fnc_state) == "Assaulting"};
		if (_attackers isNotEqualTo []) then {[_cmd, _op, _attackers, "abandoned"] call SWLC_fnc_pushOver};
	};
	_cmd set ["switchPending", [time + CFG("switchWithdrawSeconds"), _then, _t]];
};

SWLC_fnc_commitFinish = {
	params ["_cmd", "_pending"];
	_pending params ["_deadline", "_then", "_for"];
	private _side = _cmd get "side";
	private _t = _cmd get "target";
	// Captured or replaced while withdrawing: the decision no longer applies, and a win is no reason to rebuild.
	if (_t isNotEqualTo _for) exitWith {
		_cmd set ["switchPending", []];
		[_cmd, "switch_dropped", _for, []] call SWLC_fnc_commitLog;
	};
	private _inside = false;
	if (!isNull _t) then {
		private _margin = CFG("switchClearMargin");
		// Warlords' kill loop looks at every man, not only leaders.
		_inside = ((_cmd get "groups") findIf {
			((units _x) findIf {alive _x && {[_t, getPosATL _x, _margin] call SWLC_fnc_adInSquare}}) >= 0
		}) >= 0;
	};
	if (_inside && {time < _deadline}) exitWith {};
	_cmd set ["switchPending", []];
	if (_then == "rebuild") then {
		_cmd set ["rebuildUntil", time + CFG("rebuildSeconds")];
		_cmd deleteAt "preferredTarget";
	};
	[_side] call SWLC_fnc_adForceRevote;
};

SWLC_fnc_commitTick = {
	params ["_cmd"];
	if !([] call SWLC_fnc_commitOn) exitWith {};
	[_cmd] call SWLC_fnc_commitBanPublish;
	private _pending = _cmd getOrDefault ["switchPending", []];
	if (_pending isNotEqualTo []) exitWith {[_cmd, _pending] call SWLC_fnc_commitFinish};
	private _t = _cmd get "target";
	if (isNull _t) exitWith {};
	if (time < (_cmd getOrDefault ["commitUntil", 1e12])) exitWith {};
	[_cmd, _t] call SWLC_fnc_commitDecide;
};

// ---- Rebuilding ----

// The commitment rule's rebuild on its own: it runs its full length, and nobody votes during it.
SWLC_fnc_commitRebuilding = {
	params ["_cmd"];
	time < (_cmd getOrDefault ["rebuildUntil", -1])
};

// Either way of being in a rebuild. The stance holds it for as long as the balance is bad; see stance.sqf.
SWLC_fnc_rebuilding = {
	params ["_cmd"];
	([_cmd] call SWLC_fnc_commitRebuilding) || {[_cmd] call SWLC_fnc_stanceRebuilding}
};

// Top the reserve up while the side rebuilds, using the normal infantry shop and its own drop point.
SWLC_fnc_rebuildTick = {
	params ["_cmd"];
	if !(([_cmd] call SWLC_fnc_rebuilding) || {([_cmd] call SWLC_fnc_stanceOf) == "hold"}) exitWith {};
	// A wave still finishing in hold has the crate and the musters. The fake op below would take them over.
	if (isNil {_cmd get "catalog"} || {!isNil {_cmd get "op"}}) exitWith {};
	private _post = [_cmd] call SWLC_fnc_defCentralSector;
	if (isNull _post) exitWith {};
	private _op = createHashMapFromArray [["id", -2], ["tpos", [_post] call SWLC_fnc_adPos]];
	private _rec = [_cmd, _op, _post] call SWLC_fnc_musterRec;
	_cmd set ["crate", _rec get "crate"];
	_cmd set ["dropHelper", _rec get "helper"];
	private _staged = (_cmd get "groups") select {([_x] call SWLC_fnc_state) == "Reserve" && {(leader _x distance2D ([_post] call SWLC_fnc_adPos)) <= CFG("defenceRadius")}};
	[_cmd, _op, _staged] call SWLC_fnc_shopInfantry;
	[_cmd, _op, _staged] call SWLC_fnc_stanceKit;
};
