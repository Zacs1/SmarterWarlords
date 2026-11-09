// Smarter squads: how a commander-owned group moves and fights once it has its order.
// Posture, bounding overwatch, suppress and flank, rearming, and the LAMBS hand-off.
//
// Two entry points:
//   [_cmd] call SWLC_fnc_squadTick       one commander stage, works through a slice of the groups
//   [_cmd, _g] call SWLC_fnc_squadLight  from the guard pass, cheap, only does work for groups with a task
//
// Only commander-owned groups and groups flagged SWLC_borrowedBy while that player leads them.
// Never a group with a player in it. Borrowed groups get posture and rearming only, since the
// player sets their pace.
#include "macros.hpp"

SWLC_lambs = false;
SWLC_squadMagCache = createHashMap;

SWLC_fnc_squadLog = {
	params ["_side", "_behaviour", "_event", ["_fields", []]];
	["C_SQUAD", [["side", _side], ["behaviour", _behaviour], ["event", _event]] + _fields] call SWLC_fnc_log;
};

// "own", "borrowed" or "" when the group isn't ours to touch.
SWLC_fnc_squadOwner = {
	params ["_g"];
	if (isNull _g || {!local _g}) exitWith {""};
	if ((units _g findIf {alive _x}) < 0) exitWith {""};
	if ([_g] call SWLC_fnc_adGroupHasPlayer) exitWith {""};
	private _by = _g getVariable ["SWLC_borrowedBy", objNull];
	if (_by isEqualTo objNull) exitWith {"own"};
	if (_by isEqualType objNull && {alive _by} && {isPlayer _by}) exitWith {"borrowed"};
	""
};

SWLC_fnc_squadOnFoot = {
	params ["_g"];
	private _l = leader _g;
	alive _l && {vehicle _l == _l}
};

// Recent sightings the commander has on its board, as positions. Built once per tick.
SWLC_fnc_squadContacts = {
	params ["_cmd"];
	private _minConf = CFG("intelThreatMinConf");
	private _maxAge = CFG("defenceSightAge");
	private _out = [];
	{
		if ((_x get "conf") >= _minConf && {(time - (_x get "seen")) <= _maxAge}) then {_out pushBack (_x get "pos")};
	} forEach (_cmd get "board");
	_out
};

SWLC_fnc_squadNearest = {
	params ["_pos", "_list"];
	private _best = 1e6;
	{_best = _best min (_pos distance2D _x)} forEach _list;
	_best
};

// The sector the group's operation is after, or objNull.
SWLC_fnc_squadTarget = {
	params ["_cmd"];
	private _op = _cmd get "op";
	if (isNil "_op") exitWith {objNull};
	_op getOrDefault ["target", objNull]
};

SWLC_fnc_squadTick = {
	params ["_cmd"];
	private _contacts = [_cmd] call SWLC_fnc_squadContacts;
	_cmd set ["squadContacts", _contacts];

	private _groups = _cmd get "groups";
	private _n = count _groups;
	if (_n > 0) then {
		private _slice = ceil (_n / (CFG("squadSlices") max 1));
		private _i = (_cmd getOrDefault ["squadIdx", 0]) mod _n;
		for "_k" from 1 to _slice do {
			[_cmd, _groups # _i, "squad", {
				params ["_cmd", "_g"];
				[_cmd, _g, _contacts] call SWLC_fnc_squadGroup;
				[_cmd, _g] call SWLC_fnc_squadCalm;
			}] call SWLC_fnc_resGuarded;
			_i = (_i + 1) mod _n;
		};
		_cmd set ["squadIdx", _i];
	};

	// Borrowed groups may have left the commander's list, so the guard pass doesn't see them.
	private _side = _cmd get "side";
	{
		if (!(_x in _groups)) then {
			[_cmd, _x, _contacts] call SWLC_fnc_squadGroup;
			[_cmd, _x] call SWLC_fnc_squadLight;
		};
	} forEach (allGroups select {side _x == _side && {!((_x getVariable ["SWLC_borrowedBy", objNull]) isEqualTo objNull)}});
};

// The engine drops a group into COMBAT when it knows of an enemy however far away, and a group in COMBAT bounds forward at
// well under half its pace. A group on the march with nobody it knows of near it goes back to its ordered behaviour.
// Inside this range Engaged and the squad rules take over, so nothing here touches a real fight.
SWLC_fnc_squadCalm = {
	params ["_cmd", "_g"];
	if !(CFG("moveCalm")) exitWith {};
	private _l = leader _g;
	if (!alive _l || {(behaviour _l) != "COMBAT"} || {!isNull objectParent _l}) exitWith {};
	if !(([_g] call SWLC_fnc_state) in CFG("moveCalmStates")) exitWith {};
	if (!([_g] call SWLC_fnc_resMayTouch) || {[_g] call SWLC_fnc_lambsBusy} || {[_g] call SWLC_fnc_groupFighting}) exitWith {};
	if ((_l targets [true, CFG("moveCalmRange"), [], CFG("moveCalmMaxAge")]) isNotEqualTo []) exitWith {};
	private _want = (_g getVariable ["SWLC_order", []]) param [1, "AWARE"];
	if (_want == "COMBAT") then {_want = "AWARE"};
	_g setBehaviour _want;
	if (time >= (_g getVariable ["SWLC_calmLogAt", -1e6])) then {
		_g setVariable ["SWLC_calmLogAt", time + 60];
		["C_SQUAD", [["side", side _g], ["behaviour", "calm"], ["event", "calm"], ["group", groupId _g], ["to", _want], ["state", [_g] call SWLC_fnc_state]]] call SWLC_fnc_log;
	};
};

SWLC_fnc_squadGroup = {
	params ["_cmd", "_g", "_contacts"];
	private _owner = [_g] call SWLC_fnc_squadOwner;
	if (_owner == "") exitWith {
		if (!isNull _g) then {[_cmd, _g] call SWLC_fnc_squadDrop};
	};
	private _state = [_g] call SWLC_fnc_state;
	private _foot = [_g] call SWLC_fnc_squadOnFoot;

	if (_owner == "own") then {[_cmd, _g, _state, _foot] call SWLC_fnc_lambsTick};
	// A running task owns the group's order, including its speed and formation.
	if ((_g getVariable ["SWLC_squadTask", ""]) == "" && {(_g getVariable ["SWLC_lambsTask", ""]) == ""}) then {
		[_cmd, _g, _state, _foot, _contacts] call SWLC_fnc_squadPosture;
	};
	if (_owner == "own" && {_foot}) then {
		[_cmd, _g, _state, _contacts] call SWLC_fnc_squadTactics;
	};
	if (_foot) then {[_cmd, _g] call SWLC_fnc_squadRearmCheck};
};

// Bounding and flanking are mutually exclusive. A pinned squad drops its bound and flanks.
SWLC_fnc_squadTactics = {
	params ["_cmd", "_g", "_state", "_contacts"];
	[_g, _state] call SWLC_fnc_squadPinTrack;
	private _task = _g getVariable ["SWLC_squadTask", ""];
	if (_task == "flank") exitWith {};
	if ([_g, _state] call SWLC_fnc_squadPinned) exitWith {
		if (_task == "bound") then {[_cmd, _g, "pinned"] call SWLC_fnc_squadBoundEnd};
		[_cmd, _g, _state] call SWLC_fnc_squadFlankStart;
	};
	if (_task == "") then {[_cmd, _g, _state, _contacts] call SWLC_fnc_squadBoundStart};
};

// From the guard pass. Most groups leave on the first three lookups.
SWLC_fnc_squadLight = {
	params ["_cmd", "_g"];
	if (isNull _g) exitWith {};
	private _task = _g getVariable ["SWLC_squadTask", ""];
	private _trip = !isNull (_g getVariable ["SWLC_rearmUnit", objNull]);
	private _lambs = (_g getVariable ["SWLC_lambsTask", ""]) != "";
	if (_task == "" && {!_trip} && {!_lambs}) exitWith {};
	if (([_g] call SWLC_fnc_squadOwner) == "") exitWith {[_cmd, _g] call SWLC_fnc_squadDrop};
	if (_task == "bound") then {[_cmd, _g] call SWLC_fnc_squadBoundLight};
	if (_task == "flank") then {[_cmd, _g] call SWLC_fnc_squadFlankLight};
	if (_trip) then {[_cmd, _g] call SWLC_fnc_squadRearmLight};
	if (_lambs) then {[_cmd, _g] call SWLC_fnc_lambsLight};
};

// The group stopped being ours (a player joined, or the borrower left). Lets go without giving orders.
SWLC_fnc_squadDrop = {
	params ["_cmd", "_g"];
	private _task = _g getVariable ["SWLC_squadTask", ""];
	if (_task == "bound") then {[_cmd, _g, "not_ours"] call SWLC_fnc_squadBoundEnd};
	if (_task == "flank") then {[_cmd, _g, "not_ours"] call SWLC_fnc_squadFlankEnd};
	if (!isNull (_g getVariable ["SWLC_rearmUnit", objNull])) then {[_cmd, _g, "not_ours"] call SWLC_fnc_squadRearmStop};
	if ((_g getVariable ["SWLC_lambsTask", ""]) != "") then {[_g, false] call SWLC_fnc_lambsRelease};
};

// ------------------------------------------------------------------ posture

SWLC_fnc_squadStance = {
	params ["_g", "_stance"];
	{_x setUnitPosWeak _stance} forEach ((units _g) select {alive _x});
};

SWLC_fnc_squadPostureClear = {
	params ["_cmd", "_g", "_cur"];
	if (_cur == "") exitWith {};
	if (_cur == "CAREFUL") then {[_g, "AUTO"] call SWLC_fnc_squadStance};
	_g setVariable ["SWLC_postureMode", ""];
	_g setVariable ["SWLC_posturePack", []];
	[_cmd get "side", "posture", "mode", [["group", groupId _g], ["mode", "NONE"], ["from", _cur], ["state", [_g] call SWLC_fnc_state]]] call SWLC_fnc_squadLog;
};

// Which of ROAD, OPEN and CAREFUL fits. Distances widen on the way out of CAREFUL.
SWLC_fnc_squadPostureWant = {
	params ["_pos", "_cur", "_dTarget", "_dContact"];
	private _extra = [0, CFG("squadCarefulExitExtra")] select (_cur == "CAREFUL");
	if (_dTarget <= CFG("squadCarefulTarget") + _extra || {_dContact <= CFG("squadCarefulContact") + _extra}) exitWith {"CAREFUL"};
	if (_dTarget > CFG("squadRoadTarget") && {_dContact > CFG("squadRoadContact")} && {count (_pos nearRoads CFG("squadRoadRadius")) > 0}) exitWith {"ROAD"};
	"OPEN"
};

SWLC_fnc_squadPosturePack = {
	params ["_mode", "_dContact"];
	switch (_mode) do {
		case "ROAD": {[CFG("squadRoadBehaviour"), "FULL", "COLUMN"]};
		case "CAREFUL": {
			private _form = ["WEDGE", "LINE"] select (_dContact <= CFG("squadCarefulContact"));
			["AWARE", CFG("squadCarefulSpeed"), _form]
		};
		default {["AWARE", "FULL", CFG("squadOpenFormation")]};
	}
};

SWLC_fnc_squadPosture = {
	params ["_cmd", "_g", "_state", "_foot", "_contacts"];
	private _cur = _g getVariable ["SWLC_postureMode", ""];
	if (!CFG("squadPosture") || {!_foot} || {!(_state in CFG("squadPostureStates"))}) exitWith {
		[_cmd, _g, _cur] call SWLC_fnc_squadPostureClear;
	};
	private _order = _g getVariable ["SWLC_order", []];
	if (_order isEqualTo []) exitWith {};

	private _l = leader _g;
	private _pos = getPosATL _l;
	private _dContact = [_pos, _contacts] call SWLC_fnc_squadNearest;
	private _target = [_cmd] call SWLC_fnc_squadTarget;
	private _dTarget = 1e6;
	if (!isNull _target) then {
		_dTarget = _pos distance2D ([_target] call SWLC_fnc_adPos);
	} else {
		private _goal = _g getVariable ["SWLC_goal", []];
		if (_goal isNotEqualTo []) then {_dTarget = _pos distance2D _goal};
	};

	private _want = [_pos, _cur, _dTarget, _dContact] call SWLC_fnc_squadPostureWant;
	private _held = (time - (_g getVariable ["SWLC_postureAt", -1000])) < CFG("squadPostureHoldSeconds");
	if (_held && {_cur != ""} && {_want != "CAREFUL"}) then {_want = _cur};

	private _changed = _want != _cur;
	private _pack = _g getVariable ["SWLC_posturePack", []];
	if (_changed || {_pack isEqualTo []}) then {
		_pack = [_want, _dContact] call SWLC_fnc_squadPosturePack;
		_g setVariable ["SWLC_posturePack", _pack];
	};
	if (_changed) then {
		_g setVariable ["SWLC_postureMode", _want];
		_g setVariable ["SWLC_postureAt", time];
		if (_want == "CAREFUL") then {[_g, "MIDDLE"] call SWLC_fnc_squadStance};
		if (_cur == "CAREFUL") then {[_g, "AUTO"] call SWLC_fnc_squadStance};
		[_cmd get "side", "posture", "mode", [["group", groupId _g], ["mode", _want], ["from", _cur], ["state", _state],
			["speed", _pack # 1], ["formation", _pack # 2], ["d_target", round _dTarget], ["d_contact", [round _dContact, -1] select (_dContact >= 1e6)]]] call SWLC_fnc_squadLog;
	};

	// The order remembers the posture, so the guard restores it along with the waypoints.
	private _fresh = (_order select [1, 3]) isNotEqualTo _pack;
	if (_fresh) then {
		_g setVariable ["SWLC_order", [_order # 0, _pack # 0, _pack # 1, _pack # 2, _order # 4]];
	};
	if ([_g] call SWLC_fnc_lambsBusy) exitWith {};
	if ((_changed || _fresh) && {(behaviour _l) != "COMBAT"}) then {_g setBehaviour (_pack # 0)};
	if ((speedMode _g) != (_pack # 1)) then {_g setSpeedMode (_pack # 1)};
	if ((formation _g) != (_pack # 2)) then {_g setFormation (_pack # 2)};
};

// ------------------------------------------------------------------ bounding overwatch

SWLC_fnc_squadTeam = {
	params ["_g", "_var"];
	(_g getVariable [_var, []]) select {alive _x && {group _x == _g}}
};

// A point _len ahead, pulled to the near side of whatever cover is around it.
SWLC_fnc_squadBoundPos = {
	params ["_from", "_toward"];
	private _min = CFG("bpMinMetres");
	private _len = _min + random ((CFG("bpMaxMetres") - _min) max 0);
	private _b = [_from, _toward] call SWLC_fnc_bearing;
	private _p = [_from, _b, _len] call SWLC_fnc_offset;
	private _cover = false;
	{
		private _c = getPosATL _x;
		if (!surfaceIsWater _c) exitWith {
			_p = [_c, _b + 180, 3] call SWLC_fnc_offset;
			_cover = true;
		};
	} forEach (nearestTerrainObjects [_p, ["BUILDING", "HOUSE", "WALL", "ROCK", "ROCKS", "TREE", "BUSH", "FENCE"], CFG("bpCoverRadius"), true]);
	if (surfaceIsWater _p) then {
		_p = +_from;
		_len = 0;
	};
	[_p, _len, _cover]
};

SWLC_fnc_squadBoundStart = {
	params ["_cmd", "_g", "_state", "_contacts"];
	if (!CFG("squadBounding") || {_state != "Assaulting"} || {(_g getVariable ["SWLC_leg", ""]) != "FOOT"}) exitWith {};
	if ((_g getVariable ["SWLC_lambsTask", ""]) != "" || {time < (_g getVariable ["SWLC_bpNext", 0])}) exitWith {};
	private _target = [_cmd] call SWLC_fnc_squadTarget;
	if (isNull _target) exitWith {};
	private _men = [_g] call SWLC_fnc_alive;
	if (count _men < CFG("bpMinMen")) exitWith {};

	private _l = leader _g;
	private _pos = getPosATL _l;
	private _tpos = [_target] call SWLC_fnc_adPos;
	private _d = _pos distance2D _tpos;
	private _op = _cmd get "op";
	private _rally = _op getOrDefault ["rally", []];
	private _from = if (_rally isEqualTo []) then {CFG("bpStartMetres")} else {(_rally distance2D _tpos) + CFG("bpStartExtra")};
	if (_d > _from || {_d <= (([_target] call SWLC_fnc_adSize) / 2) * CFG("bpInsideFraction")}) exitWith {};
	if (([_pos, _contacts] call SWLC_fnc_squadNearest) <= CFG("bpCqbDist")) exitWith {};
	if ([_g] call SWLC_fnc_lambsBusy) exitWith {};

	private _rest = _men - [_l];
	private _split = (ceil ((count _men) / 2)) - 1;
	private _a = [_l] + (_rest select [0, _split]);
	private _b = _men - _a;
	_g setVariable ["SWLC_bpA", _a];
	_g setVariable ["SWLC_bpB", _b];
	_g setVariable ["SWLC_bpN", 0];
	_g setVariable ["SWLC_bpTarget", _target];
	_g setVariable ["SWLC_bpHardEnd", time + CFG("bpMaxSeconds")];
	_g setVariable ["SWLC_squadTask", "bound"];
	[_cmd get "side", "bound", "start", [["group", groupId _g], ["a", count _a], ["b", count _b], ["d_target", round _d]]] call SWLC_fnc_squadLog;
	[_cmd, _g, "A", _pos] call SWLC_fnc_squadBoundMove;
};

// One team moves, the other stops and watches the target.
SWLC_fnc_squadBoundMove = {
	params ["_cmd", "_g", "_team", "_from"];
	private _target = _g getVariable "SWLC_bpTarget";
	private _tpos = [_target] call SWLC_fnc_adPos;
	if (count (nearestTerrainObjects [_from, ["BUILDING", "HOUSE"], CFG("bpCqbRadius"), false]) >= CFG("bpCqbBuildings")) exitWith {
		[_cmd, _g, "cqb"] call SWLC_fnc_squadBoundEnd;
	};
	private _a = [_g, "SWLC_bpA"] call SWLC_fnc_squadTeam;
	private _b = [_g, "SWLC_bpB"] call SWLC_fnc_squadTeam;
	([_from, _tpos] call SWLC_fnc_squadBoundPos) params ["_dest", "_len", "_cover"];
	private _holding = [_a, _b] select (_team == "A");
	{
		doStop _x;
		_x doWatch _tpos;
		_x setUnitPosWeak "MIDDLE";
	} forEach _holding;
	if (_team == "A") then {
		[_g, [[_dest, "HOLD", 10]], "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
		private _l = leader _g;
		{
			_x setUnitPosWeak "AUTO";
			_x doFollow _l;
		} forEach _a;
	} else {
		private _across = ([_from, _dest] call SWLC_fnc_bearing) + 90;
		private _mid = ((count _b) - 1) / 2;
		{
			_x setUnitPosWeak "AUTO";
			_x doMove ([_dest, _across, (_forEachIndex - _mid) * 5] call SWLC_fnc_offset);
		} forEach _b;
	};
	private _n = (_g getVariable ["SWLC_bpN", 0]) + 1;
	_g setVariable ["SWLC_bpN", _n];
	_g setVariable ["SWLC_bpTeam", _team];
	_g setVariable ["SWLC_bpDest", _dest];
	_g setVariable ["SWLC_bpPhaseEnd", time + CFG("bpPhaseSeconds")];
	[_cmd get "side", "bound", "bound", [["group", groupId _g], ["team", _team], ["n", _n], ["len", round _len], ["cover", _cover]]] call SWLC_fnc_squadLog;
};

SWLC_fnc_squadBoundLight = {
	params ["_cmd", "_g"];
	if (([_g] call SWLC_fnc_state) != "Assaulting") exitWith {[_cmd, _g, "state"] call SWLC_fnc_squadBoundEnd};
	if (time > (_g getVariable ["SWLC_bpHardEnd", 0])) exitWith {[_cmd, _g, "timeout"] call SWLC_fnc_squadBoundEnd};
	if ([_g] call SWLC_fnc_lambsBusy) exitWith {[_cmd, _g, "lambs"] call SWLC_fnc_squadBoundEnd};
	private _a = [_g, "SWLC_bpA"] call SWLC_fnc_squadTeam;
	private _b = [_g, "SWLC_bpB"] call SWLC_fnc_squadTeam;
	if (_a isEqualTo [] || {_b isEqualTo []}) exitWith {[_cmd, _g, "too_small"] call SWLC_fnc_squadBoundEnd};

	private _l = leader _g;
	if (!(_l in _a)) then {
		_a pushBack _l;
		_b = _b - [_l];
		_g setVariable ["SWLC_bpA", _a];
		_g setVariable ["SWLC_bpB", _b];
	};
	if (_b isEqualTo []) exitWith {[_cmd, _g, "too_small"] call SWLC_fnc_squadBoundEnd};

	private _target = _g getVariable "SWLC_bpTarget";
	if (isNull _target) exitWith {[_cmd, _g, "state"] call SWLC_fnc_squadBoundEnd};
	private _pos = getPosATL _l;
	if ((_pos distance2D ([_target] call SWLC_fnc_adPos)) <= (([_target] call SWLC_fnc_adSize) / 2) * CFG("bpInsideFraction")) exitWith {
		[_cmd, _g, "inside"] call SWLC_fnc_squadBoundEnd;
	};
	if (([_pos, _cmd getOrDefault ["squadContacts", []]] call SWLC_fnc_squadNearest) <= CFG("bpCqbDist")) exitWith {
		[_cmd, _g, "contact"] call SWLC_fnc_squadBoundEnd;
	};

	private _team = _g getVariable ["SWLC_bpTeam", "A"];
	private _dest = _g getVariable ["SWLC_bpDest", _pos];
	private _reach = CFG("bpReachMetres");
	private _arrived = if (_team == "A") then {
		(_l distance2D _dest) <= _reach
	} else {
		(_b findIf {(_x distance2D _dest) > _reach}) < 0
	};
	if (_arrived || {time > (_g getVariable ["SWLC_bpPhaseEnd", 0])}) then {
		private _from = if (_team == "A") then {getPosATL _l} else {getPosATL (_b # 0)};
		[_cmd, _g, ["A", "B"] select (_team == "A"), _from] call SWLC_fnc_squadBoundMove;
	};
};

SWLC_fnc_squadBoundEnd = {
	params ["_cmd", "_g", "_why"];
	private _men = [_g] call SWLC_fnc_alive;
	private _l = leader _g;
	{
		_x doWatch objNull;
		_x setUnitPosWeak "AUTO";
		_x doFollow _l;
	} forEach _men;
	_g setVariable ["SWLC_squadTask", ""];
	_g setVariable ["SWLC_bpNext", time + CFG("bpCooldownSeconds")];
	private _n = _g getVariable ["SWLC_bpN", 0];
	if (_why != "not_ours" && {([_g] call SWLC_fnc_state) == "Assaulting"}) then {
		private _target = _g getVariable ["SWLC_bpTarget", objNull];
		if (!isNull _target) then {
			[_g, [_target] call SWLC_fnc_sweepOrder, "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
		};
	};
	[_cmd get "side", "bound", "end", [["group", groupId _g], ["why", _why], ["bounds", _n]]] call SWLC_fnc_squadLog;
};

// ------------------------------------------------------------------ pinned, suppress and flank

// Closest the leader has come to the group's goal, and when. Per tick, no per-unit work.
SWLC_fnc_squadPinTrack = {
	params ["_g", "_state"];
	if !(_state in ["Advancing", "Assaulting"]) exitWith {_g setVariable ["SWLC_pinGoal", []]};
	private _goal = _g getVariable ["SWLC_goal", []];
	if (_goal isEqualTo []) exitWith {};
	private _d = (leader _g) distance2D _goal;
	if ((_g getVariable ["SWLC_pinGoal", []]) isNotEqualTo _goal) exitWith {
		_g setVariable ["SWLC_pinGoal", _goal];
		_g setVariable ["SWLC_pinBest", _d];
		_g setVariable ["SWLC_pinBestAt", time];
	};
	if (_d <= (_g getVariable ["SWLC_pinBest", 1e6]) - CFG("pinnedMoveMetres")) then {
		_g setVariable ["SWLC_pinBest", _d];
		_g setVariable ["SWLC_pinBestAt", time];
	};
};

// Suppression is only read per unit once everything cheaper has already said yes.
SWLC_fnc_squadPinned = {
	params ["_g", "_state"];
	if (!CFG("squadFlank") || {SWLC_lambs}) exitWith {false};
	if !(_state in ["Advancing", "Assaulting"]) exitWith {false};
	if (time < (_g getVariable ["SWLC_flankNext", 0])) exitWith {false};
	if ((behaviour leader _g) != "COMBAT") exitWith {false};
	if ((time - (_g getVariable ["SWLC_pinBestAt", time])) < CFG("pinnedSeconds")) exitWith {false};
	private _men = [_g] call SWLC_fnc_alive;
	if (count _men < CFG("flankMinMen")) exitWith {false};
	private _sum = 0;
	{_sum = _sum + getSuppression _x} forEach _men;
	(_sum / count _men) >= CFG("pinnedSuppression")
};

// Side with no water and more to hide behind.
SWLC_fnc_squadFlankSide = {
	params ["_lpos", "_epos", "_b", "_grpSide"];
	private _r = CFG("flankOffset");
	private _best = [];
	private _bestScore = -1;
	{
		private _dir = _b + _x;
		private _step = [_lpos, _dir, _r] call SWLC_fnc_offset;
		private _wide = [_epos, _dir, _r] call SWLC_fnc_offset;
		if (!surfaceIsWater _step && {!surfaceIsWater _wide} && {!([_grpSide, _step] call SWLC_fnc_adRestricted)} && {!([_grpSide, _wide] call SWLC_fnc_adRestricted)}) then {
			private _score = count (nearestTerrainObjects [_step, ["BUILDING", "HOUSE", "WALL", "ROCK", "ROCKS", "TREE", "BUSH", "FENCE"], 40, false]);
			if (_score > _bestScore) then {
				_bestScore = _score;
				_best = [_step, _wide];
			};
		};
	} forEach [90, -90];
	_best
};

SWLC_fnc_squadFlankStart = {
	params ["_cmd", "_g", "_state"];
	private _l = leader _g;
	private _e = _l findNearestEnemy _l;
	if (isNull _e) exitWith {};
	private _epos = _l getHideFrom _e;
	if (_epos isEqualTo [0, 0, 0]) exitWith {};
	private _lpos = getPosATL _l;
	private _side = [_lpos, _epos, [_lpos, _epos] call SWLC_fnc_bearing, side _g] call SWLC_fnc_squadFlankSide;
	if (_side isEqualTo [] || {[side _g, _epos] call SWLC_fnc_adRestricted}) exitWith {_g setVariable ["SWLC_flankNext", time + CFG("flankCooldownSeconds")]};
	_side params ["_step", "_wide"];

	private _men = [_g] call SWLC_fnc_alive;
	private _rest = _men - [_l];
	private _split = (ceil ((count _men) / 2)) - 1;
	private _a = [_l] + (_rest select [0, _split]);
	private _b = _men - _a;
	private _wps = [[_step, "MOVE", 15], [_wide, "MOVE", 15], [_epos, "SAD", 30]];
	_g setVariable ["SWLC_flankSaved", [_state, +(_g getVariable ["SWLC_order", []])]];
	_g setVariable ["SWLC_flankA", _a];
	_g setVariable ["SWLC_flankB", _b];
	_g setVariable ["SWLC_flankEnemy", _e];
	_g setVariable ["SWLC_flankWps", _wps];
	_g setVariable ["SWLC_flankStartMen", count _men];
	_g setVariable ["SWLC_flankEnd", time + CFG("flankMaxSeconds")];
	_g setVariable ["SWLC_flankSupAt", 0];
	_g setVariable ["SWLC_squadTask", "flank"];
	[_g, _wps, "AWARE", "FULL", "FILE", "YELLOW"] call SWLC_fnc_adSetOrder;
	{_x setUnitPosWeak "AUTO"; _x doFollow _l} forEach _a;
	{doStop _x} forEach _b;
	[_g, _b, _e] call SWLC_fnc_squadSuppress;
	[_cmd get "side", "flank", "start", [["group", groupId _g], ["a", count _a], ["b", count _b], ["enemy", typeOf _e], ["d_enemy", round (_lpos distance2D _epos)], ["state", _state]]] call SWLC_fnc_squadLog;
	[_cmd get "side", "flank", [], _g] call SWLC_fnc_radio;
};

// Team B fires where the squad thinks the enemy is, not at where the enemy really is.
SWLC_fnc_squadSuppress = {
	params ["_g", "_team", "_enemy"];
	_g setVariable ["SWLC_flankSupAt", time];
	private _fired = 0;
	{
		private _p = _x getHideFrom _enemy;
		if (_p isEqualTo [0, 0, 0]) then {_p = (leader _g) getHideFrom _enemy};
		if (_p isNotEqualTo [0, 0, 0]) then {
			private _asl = AGLToASL _p;
			_x doSuppressiveFire [_asl # 0, _asl # 1, (_asl # 2) + 1];
			_x suppressFor CFG("flankSuppressSeconds");
			_fired = _fired + 1;
		};
	} forEach _team;
	[side _g, "flank", "suppress", [["group", groupId _g], ["men", _fired]]] call SWLC_fnc_squadLog;
};

SWLC_fnc_squadFlankLight = {
	params ["_cmd", "_g"];
	private _saved = _g getVariable ["SWLC_flankSaved", ["", []]];
	if (([_g] call SWLC_fnc_state) != (_saved # 0)) exitWith {[_cmd, _g, "state"] call SWLC_fnc_squadFlankEnd};
	if (time > (_g getVariable ["SWLC_flankEnd", 0])) exitWith {[_cmd, _g, "timeout"] call SWLC_fnc_squadFlankEnd};
	private _men = [_g] call SWLC_fnc_groupMen;
	if (_men <= (_g getVariable ["SWLC_flankStartMen", 1]) * (1 - CFG("flankGiveUpLoss"))) exitWith {[_cmd, _g, "losses"] call SWLC_fnc_squadFlankEnd};
	private _a = [_g, "SWLC_flankA"] call SWLC_fnc_squadTeam;
	private _b = [_g, "SWLC_flankB"] call SWLC_fnc_squadTeam;
	if (_a isEqualTo []) exitWith {[_cmd, _g, "team_dead"] call SWLC_fnc_squadFlankEnd};
	private _e = _g getVariable ["SWLC_flankEnemy", objNull];
	if (!alive _e) exitWith {[_cmd, _g, "enemy_dead"] call SWLC_fnc_squadFlankEnd};
	private _order = _g getVariable ["SWLC_order", []];
	if ((_order param [0, []]) isNotEqualTo (_g getVariable ["SWLC_flankWps", []])) exitWith {[_cmd, _g, "replaced"] call SWLC_fnc_squadFlankEnd};
	if ([_g] call SWLC_fnc_adOrderDone) exitWith {[_cmd, _g, "assaulted"] call SWLC_fnc_squadFlankEnd};
	if (_b isNotEqualTo [] && {(time - (_g getVariable ["SWLC_flankSupAt", 0])) >= CFG("flankSuppressSeconds")}) then {
		[_g, _b, _e] call SWLC_fnc_squadSuppress;
	};
};

SWLC_fnc_squadFlankEnd = {
	params ["_cmd", "_g", "_why"];
	private _l = leader _g;
	{
		_x setUnitPosWeak "AUTO";
		_x doFollow _l;
	} forEach ([_g] call SWLC_fnc_alive);
	private _saved = _g getVariable ["SWLC_flankSaved", ["", []]];
	_saved params ["_state", "_order"];
	_g setVariable ["SWLC_squadTask", ""];
	_g setVariable ["SWLC_flankNext", time + CFG("flankCooldownSeconds")];
	_g setVariable ["SWLC_pinBestAt", time];
	_g setVariable ["SWLC_flankSaved", nil];
	if (_why != "not_ours" && {_why != "replaced"} && {([_g] call SWLC_fnc_state) == _state}) then {
		private _target = [_cmd] call SWLC_fnc_squadTarget;
		if (_state == "Assaulting" && {!isNull _target}) then {
			[_g, [_target] call SWLC_fnc_sweepOrder, "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
		} else {
			if (_order isNotEqualTo []) then {
				_order params ["_wps", "_beh", "_speed", "_form", "_combat"];
				[_g, _wps, _beh, _speed, _form, _combat] call SWLC_fnc_adSetOrder;
			};
		};
	};
	[_cmd get "side", "flank", "end", [["group", groupId _g], ["why", _why]]] call SWLC_fnc_squadLog;
};

// ------------------------------------------------------------------ rearming

// Lower-case magazine classes a weapon takes, looked up once per weapon. Rifles skip the
// underbarrel grenades, which share the weapon's compatible list.
SWLC_fnc_squadMags = {
	params ["_weapon", ["_rifle", false]];
	private _key = format ["%1|%2", toLower _weapon, _rifle];
	private _hit = SWLC_squadMagCache get _key;
	if (!isNil "_hit") exitWith {_hit};
	private _list = compatibleMagazines _weapon;
	if (_rifle) then {_list = _list select {getNumber (configFile >> "CfgMagazines" >> _x >> "count") >= CFG("rearmRifleMinRounds")}};
	_list = _list apply {toLower _x};
	SWLC_squadMagCache set [_key, _list];
	_list
};

// [unit, kind, magazine classes, how many to take], launchers before rifles, or [].
SWLC_fnc_squadRearmNeed = {
	params ["_men"];
	private _found = [];
	{
		private _u = _x;
		private _w = secondaryWeapon _u;
		if (_found isEqualTo [] && {_w != ""} && {([_w] call SWLC_fnc_adLauncherKind) != ""} && {(secondaryWeaponMagazine _u) isEqualTo []}) then {
			private _mags = [_w] call SWLC_fnc_squadMags;
			if ((magazines _u) findIf {(toLower _x) in _mags} < 0) then {
				_found = [_u, [_w] call SWLC_fnc_adLauncherKind, _mags, CFG("rearmTakeRockets")];
			};
		};
	} forEach _men;
	if (_found isNotEqualTo []) exitWith {_found};
	private _limit = CFG("rearmPrimaryMags");
	{
		private _u = _x;
		private _w = primaryWeapon _u;
		if (_found isEqualTo [] && {_w != ""}) then {
			private _mags = [_w, true] call SWLC_fnc_squadMags;
			if (({(toLower _x) in _mags} count (magazines _u)) <= _limit) then {
				_found = [_u, "RIFLE", _mags, CFG("rearmTakeRifle")];
			};
		};
	} forEach _men;
	_found
};

SWLC_fnc_squadRearmFirst = {
	params ["_have", "_mags"];
	private _i = _have findIf {(toLower _x) in _mags};
	if (_i < 0) exitWith {""};
	_have # _i
};

// Nearest safe source holding the magazines: [object, "crate"|"vehicle"|"body", class], or [].
SWLC_fnc_squadRearmSource = {
	params ["_cmd", "_u", "_mags"];
	private _side = _cmd get "side";
	private _sideNum = [east, west, independent, civilian] find _side;
	private _p = getPosATL _u;
	private _r = CFG("rearmRadius");
	private _found = [];
	private _hook = !isNil "SWLC_fnc_econResupplyAllowed";

	{
		if (alive _x) then {
			private _class = [magazineCargo _x, _mags] call SWLC_fnc_squadRearmFirst;
			if (_class != "" && {!_hook || {[_side, getPosATL _x] call SWLC_fnc_econResupplyAllowed}}) then {
				_found pushBack [_x, "crate", _class];
			};
		};
	} forEach (nearestObjects [_p, ["ReammoBox_F", "ReammoBox"], _r]);

	{
		if (alive _x) then {
			private _crew = (crew _x) select {alive _x};
			private _friendly = if (_crew isEqualTo []) then {
				(_x getVariable ["SWLC_side", sideUnknown]) == _side || {getNumber (configOf _x >> "side") == _sideNum}
			} else {
				(side group (_crew # 0)) == _side
			};
			if (_friendly) then {
				private _class = [magazineCargo _x, _mags] call SWLC_fnc_squadRearmFirst;
				if (_class != "") then {_found pushBack [_x, "vehicle", _class]};
			};
		};
	} forEach (nearestObjects [_p, ["Car", "Tank", "Ship", "Air"], _r]);

	{
		if (!alive _x && {getNumber (configOf _x >> "side") == _sideNum}) then {
			private _class = [magazines _x, _mags] call SWLC_fnc_squadRearmFirst;
			if (_class != "") then {_found pushBack [_x, "body", _class]};
		};
	} forEach (nearestObjects [_p, ["CAManBase"], _r]);

	private _safe = _found select {!([_side, getPosATL (_x # 0)] call SWLC_fnc_adEnemyNear)};
	if (_safe isEqualTo []) exitWith {[]};
	private _best = [];
	private _bestD = 1e6;
	{
		private _d = _p distance2D (_x # 0);
		if (_d < _bestD) then {
			_bestD = _d;
			_best = _x;
		};
	} forEach _safe;
	_best
};

SWLC_fnc_squadRearmCheck = {
	params ["_cmd", "_g"];
	if (!CFG("squadRearm")) exitWith {};
	if (time < (_g getVariable ["SWLC_rearmNext", 0])) exitWith {};
	_g setVariable ["SWLC_rearmNext", time + CFG("rearmCheckSeconds")];
	if (!isNull (_g getVariable ["SWLC_rearmUnit", objNull])) exitWith {};
	if ((_g getVariable ["SWLC_squadTask", ""]) != "") exitWith {};
	private _l = leader _g;
	if ((behaviour _l) == "COMBAT") exitWith {};
	if ([_g] call SWLC_fnc_lambsBusy) exitWith {};
	private _men = ([_g] call SWLC_fnc_alive) select {vehicle _x == _x};
	// One man with nothing nearby doesn't stop the next one from restocking.
	private _need = [];
	private _source = [];
	private _missed = "";
	for "_try" from 1 to CFG("rearmTriesPerCheck") do {
		_need = [_men] call SWLC_fnc_squadRearmNeed;
		if (_need isEqualTo []) exitWith {};
		_source = [_cmd, _need # 0, _need # 2] call SWLC_fnc_squadRearmSource;
		if (_source isNotEqualTo []) exitWith {};
		_missed = _need # 1;
		_men = _men - [_need # 0];
	};
	if (_source isEqualTo []) exitWith {
		if (_missed != "") then {
			_g setVariable ["SWLC_rearmNext", time + CFG("rearmBackoffSeconds")];
			[_cmd get "side", "rearm", "no_source", [["group", groupId _g], ["kind", _missed]]] call SWLC_fnc_squadLog;
		};
	};
	_need params ["_u", "_kind", "_mags", "_take"];
	_source params ["_obj", "_srcKind", "_class"];
	_g setVariable ["SWLC_rearmUnit", _u];
	_g setVariable ["SWLC_rearmSrc", [_obj, _srcKind, _class, _kind, _take]];
	_g setVariable ["SWLC_rearmEnd", time + CFG("rearmTripSeconds")];
	_g setVariable ["SWLC_rearmMoveAt", time];
	_u doMove (getPosATL _obj);
	[_cmd get "side", "rearm", "start", [["group", groupId _g], ["unit", typeOf _u], ["kind", _kind], ["source", _srcKind], ["class", _class], ["dist", round (_u distance2D _obj)]]] call SWLC_fnc_squadLog;
};

// Takes up to _n of _class out of the source and into the soldier's kit. Returns how many.
SWLC_fnc_squadRearmTake = {
	params ["_u", "_obj", "_srcKind", "_class", "_n"];
	private _got = 0;
	if (_srcKind == "body") exitWith {
		for "_i" from 1 to _n do {
			if ((magazines _obj) findIf {_x == _class} < 0 || {!(_u canAdd _class)}) exitWith {};
			_obj removeMagazine _class;
			_u addMagazine _class;
			_got = _got + 1;
		};
		_got
	};
	// Cargo has no command to remove one magazine, so it is read, cleared and written back.
	private _cargo = magazineCargo _obj;
	for "_i" from 1 to _n do {
		private _at = _cargo find _class;
		if (_at < 0 || {!(_u canAdd _class)}) exitWith {};
		_cargo deleteAt _at;
		_u addMagazine _class;
		_got = _got + 1;
	};
	if (_got > 0) then {
		clearMagazineCargoGlobal _obj;
		private _counts = createHashMap;
		{_counts set [_x, (_counts getOrDefault [_x, 0]) + 1]} forEach _cargo;
		{_obj addMagazineCargoGlobal [_x, _y]} forEach _counts;
	};
	_got
};

SWLC_fnc_squadRearmStop = {
	params ["_cmd", "_g", "_why", ["_fields", []]];
	private _u = _g getVariable ["SWLC_rearmUnit", objNull];
	if (!isNull _u) then {
		if (SWLC_lambs) then {_u setVariable ["lambs_danger_forceMove", nil]};
		if (alive _u) then {_u doFollow (leader _g)};
	};
	_g setVariable ["SWLC_rearmUnit", objNull];
	_g setVariable ["SWLC_rearmSrc", []];
	if (_why != "taken") then {_g setVariable ["SWLC_rearmNext", time + CFG("rearmBackoffSeconds")]};
	private _event = ["fail", "done"] select (_why == "taken");
	[_cmd get "side", "rearm", _event, [["group", groupId _g], ["why", _why]] + _fields] call SWLC_fnc_squadLog;
};

SWLC_fnc_squadRearmLight = {
	params ["_cmd", "_g"];
	private _u = _g getVariable ["SWLC_rearmUnit", objNull];
	if (!alive _u || {group _u != _g}) exitWith {[_cmd, _g, "unit_lost"] call SWLC_fnc_squadRearmStop};
	(_g getVariable ["SWLC_rearmSrc", []]) params [["_obj", objNull], ["_srcKind", ""], ["_class", ""], ["_kind", ""], ["_take", 1]];
	if (isNull _obj) exitWith {[_cmd, _g, "source_gone"] call SWLC_fnc_squadRearmStop};
	if (time > (_g getVariable ["SWLC_rearmEnd", 0])) exitWith {[_cmd, _g, "timeout", [["dist", round (_u distance2D _obj)], ["cmd", currentCommand _u], ["ready", unitReady _u], ["speed", round speed _u]]] call SWLC_fnc_squadRearmStop};
	if (SWLC_lambs) then {_u setVariable ["lambs_danger_forceMove", true]};
	// Measured to the edge of a vehicle. A soldier can't stand at the middle of a truck.
	if ((_u distance2D _obj) > (CFG("rearmReach") + ((boundingBoxReal _obj) # 2) * 0.6)) exitWith {
		if ((time - (_g getVariable ["SWLC_rearmMoveAt", 0])) >= 9) then {
			_g setVariable ["SWLC_rearmMoveAt", time];
			_u doMove (getPosATL _obj);
		};
	};
	private _got = [_u, _obj, _srcKind, _class, _take] call SWLC_fnc_squadRearmTake;
	if (_got > 0) then {_u playActionNow "PutDown"};
	if (_got == 0) exitWith {[_cmd, _g, "empty"] call SWLC_fnc_squadRearmStop};
	[_cmd, _g, "taken", [["unit", typeOf _u], ["kind", _kind], ["source", _srcKind], ["class", _class], ["n", _got]]] call SWLC_fnc_squadRearmStop;
};

// ------------------------------------------------------------------ LAMBS

// Once at init. SWLC_lambs means LAMBS' danger handling is running, whether or not we hand it tasks.
SWLC_fnc_lambsDetect = {
	private _cfg = configFile >> "CfgPatches";
	SWLC_lambs = isClass (_cfg >> "lambs_danger") && {isClass (_cfg >> "lambs_wp")}
		&& {!isNil "lambs_wp_fnc_taskGarrison"} && {!isNil "lambs_wp_fnc_taskReset"} && {!isNil "lambs_main_fnc_findBuildings"};
	["C_SQUAD", [["side", "ALL"], ["behaviour", "lambs"], ["event", "detected"], ["lambs", SWLC_lambs],
		["cba", isClass (_cfg >> "cba_main")], ["tasks", SWLC_lambs && {CFG("squadLambs")}]]] call SWLC_fnc_log;
	if (SWLC_lambs) then {
		SWLC_settings set ["intelMinKnows", CFG("lambsIntelMinKnows")];
	};
};

// True while LAMBS has this group in hand, or did within the last few seconds.
SWLC_fnc_lambsBusy = {
	params ["_g"];
	if (!SWLC_lambs) exitWith {false};
	if ((_g getVariable ["SWLC_lambsTask", ""]) != "") exitWith {true};
	private _mine = _g getVariable ["SWLC_rearmUnit", objNull];
	private _now = ((_g getVariable ["lambs_danger_isExecutingTactic", false]) isEqualTo true)
		|| {(_g getVariable ["lambs_main_groupMemory", []]) isNotEqualTo []}
		|| {(behaviour leader _g) == "COMBAT"}
		|| {(units _g findIf {_x != _mine && {!isNil {_x getVariable "lambs_main_currentTask"} || {!isNil {_x getVariable "lambs_danger_forceMove"}}}}) >= 0};
	if (_now) exitWith {
		_g setVariable ["SWLC_lambsBusyAt", time];
		true
	};
	(time - (_g getVariable ["SWLC_lambsBusyAt", -1000])) < CFG("lambsBusyHoldSeconds")
};

// Which sector a defending group is sitting in, or objNull.
SWLC_fnc_lambsHoldSector = {
	params ["_side", "_pos"];
	private _at = ([_side] call SWLC_fnc_adOwned) findIf {[_x, _pos, 0] call SWLC_fnc_adInSquare};
	if (_at < 0) exitWith {objNull};
	([_side] call SWLC_fnc_adOwned) # _at
};

// Per slice: starts a task if the group's situation calls for one, otherwise checks a running one still fits.
SWLC_fnc_lambsTick = {
	params ["_cmd", "_g", "_state", "_foot"];
	private _task = _g getVariable ["SWLC_lambsTask", ""];
	if (_task != "") exitWith {
		if (_task == "defend" && {scriptDone (_g getVariable ["SWLC_lambsHandle", scriptNull])}) exitWith {
			[_cmd get "side", "lambs", "stop", [["group", groupId _g], ["task", _task], ["why", "ended"]]] call SWLC_fnc_squadLog;
			[_g, true] call SWLC_fnc_lambsRelease;
		};
		private _fits = [_state == "Assaulting", _state == "Defending"] select (_task != "cqb");
		private _intact = (_g getVariable ["SWLC_order", []]) isEqualTo (_g getVariable ["SWLC_lambsOrder", []]);
		if (!_fits || {_task != "defend" && {!_intact}}) then {
			[_cmd get "side", "lambs", "stop", [["group", groupId _g], ["task", _task], ["why", ["replaced", "state"] select (!_fits)]]] call SWLC_fnc_squadLog;
			[_g, true] call SWLC_fnc_lambsRelease;
		};
	};
	if (!SWLC_lambs || {!CFG("squadLambs")} || {!_foot}) exitWith {};
	if ((_g getVariable ["SWLC_squadTask", ""]) != "" || {time < (_g getVariable ["SWLC_lambsNext", 0])}) exitWith {};
	private _pos = getPosATL leader _g;
	if (_state == "Assaulting") exitWith {
		private _target = [_cmd] call SWLC_fnc_squadTarget;
		if (!isNull _target && {[_target, _pos, 0] call SWLC_fnc_adInSquare}) then {
			[_cmd, _g, _target] call SWLC_fnc_lambsClear;
		};
	};
	if (_state != "Defending" || {(time - (_g getVariable ["SWLC_stateSince", time])) < CFG("lambsHoldDelay")}) exitWith {};
	// Only once it has reached its spot and LAMBS isn't already fighting with it.
	private _goal = _g getVariable ["SWLC_goal", []];
	if (_goal isEqualTo [] || {(_pos distance2D _goal) > CFG("lambsHoldReach")} || {[_g] call SWLC_fnc_lambsBusy}) exitWith {};
	private _s = [_cmd get "side", _pos] call SWLC_fnc_lambsHoldSector;
	if (!isNull _s) then {[_cmd, _g, _s] call SWLC_fnc_lambsHold};
};

// Clear the buildings of a sector the group is taking. Returns true when the task started.
SWLC_fnc_lambsClear = {
	params ["_cmd", "_g", "_s"];
	if (!SWLC_lambs || {!CFG("squadLambs")} || {!local _g} || {(_g getVariable ["SWLC_lambsTask", ""]) != ""}) exitWith {false};
	private _cap = CFG("lambsMaxCqb");
	if (({(_x getVariable ["SWLC_lambsTask", ""]) == "cqb"} count (_cmd get "groups")) >= _cap) exitWith {false};
	private _c = [_s] call SWLC_fnc_adPos;
	private _r = (([_s] call SWLC_fnc_adSize) / 2) min CFG("lambsClearRadius");
	private _buildings = [_c, _r] call lambs_main_fnc_findBuildings;
	if (count _buildings < CFG("lambsMinBuildings")) exitWith {
		_g setVariable ["SWLC_lambsNext", time + CFG("lambsRetrySeconds")];
		false
	};
	// A sector can change hands several times in a round, so start with a clean slate.
	private _flag = format ["lambs_main_CQB_cleared_%1", str (side _g)];
	{_x setVariable [_flag, nil]} forEach _buildings;

	// HOLD where they stand, so Warlords' SAD waypoints stay out and the wave doesn't call it finished.
	[_g, [[getPosATL leader _g, "HOLD", 30]], "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
	_g setVariable ["SWLC_lambsOrder", +(_g getVariable ["SWLC_order", []])];
	_g setVariable ["SWLC_lambsTask", "cqb"];
	_g setVariable ["SWLC_lambsBuildings", _buildings];
	_g setVariable ["SWLC_lambsFlag", _flag];
	_g setVariable ["SWLC_lambsEnd", time + CFG("lambsCqbSeconds")];
	_g setVariable ["SWLC_lambsSector", _s];
	_g setVariable ["SWLC_lambsCheckAt", time];
	_g setVariable ["SWLC_lambsHandle", [_g, _c, _r, CFG("lambsCqbCycle")] spawn lambs_wp_fnc_taskCQB];
	[_cmd get "side", "lambs", "clear", [["group", groupId _g], ["sector", [_s] call SWLC_fnc_adName], ["buildings", count _buildings], ["radius", round _r]]] call SWLC_fnc_squadLog;
	true
};

// Hold a sector: garrison when the buildings have room for everyone, otherwise defend.
SWLC_fnc_lambsHold = {
	params ["_cmd", "_g", "_s"];
	if (!SWLC_lambs || {!CFG("squadLambs")} || {!local _g} || {(_g getVariable ["SWLC_lambsTask", ""]) != ""}) exitWith {false};
	private _c = [_s] call SWLC_fnc_adPos;
	// An alert's main position garrisons the cover it was sent to, on the approach side, not the middle of the sector.
	private _cover = _g getVariable ["SWLC_alertCover", []];
	if (_cover isNotEqualTo [] && {(_cover # 0) isEqualTo _s}) then {_c = _cover # 1};
	private _r = CFG("lambsHoldRadius");
	private _spots = [_c, _r, true, false] call lambs_main_fnc_findBuildings;
	private _men = [_g] call SWLC_fnc_groupMen;
	private _order = +(_g getVariable ["SWLC_order", []]);
	_g setVariable ["SWLC_lambsPrior", _order];
	[_g] call SWLC_fnc_adClearOrder;
	for "_i" from (count waypoints _g - 1) to 0 step -1 do {deleteWaypoint [_g, _i]};
	private _task = "defend";
	if (count _spots >= _men) then {
		_task = "garrison";
		[_g, _c, _r, [], false, false, -1, false] call lambs_wp_fnc_taskGarrison;
		private _idx = (count waypoints _g) - 1;
		_g setCurrentWaypoint [_g, _idx];
		// The order describes the HOLD taskGarrison wrote, so the guard keeps it instead of replacing it.
		private _kept = [[[waypointPosition [_g, _idx], "HOLD", 0]], "AWARE", "NORMAL", "WEDGE", "YELLOW"];
		_g setVariable ["SWLC_order", _kept];
		_g setVariable ["SWLC_wpBase", _idx];
		_g setVariable ["SWLC_wpProgress", 0];
		_g setVariable ["SWLC_lambsOrder", +_kept];
	} else {
		_g setVariable ["SWLC_lambsOrder", []];
		_g setVariable ["SWLC_lambsHandle", [_g, _c, _r, [], false, 0, false, false] spawn lambs_wp_fnc_taskDefend];
	};
	_g setVariable ["SWLC_lambsTask", _task];
	_g setVariable ["SWLC_lambsLeaderAt", time];
	_g setVariable ["SWLC_lambsSector", _s];
	[_cmd get "side", "lambs", "hold", [["group", groupId _g], ["sector", [_s] call SWLC_fnc_adName], ["task", _task], ["spots", count _spots], ["men", _men]]] call SWLC_fnc_squadLog;
	true
};

// Guard pass while LAMBS is working the group. Only looks at the buildings every few seconds.
SWLC_fnc_lambsLight = {
	params ["_cmd", "_g"];
	if ((_g getVariable ["SWLC_lambsTask", ""]) in ["garrison", "defend"]) exitWith {
		if ((time - (_g getVariable ["SWLC_lambsLeaderAt", time])) < CFG("lambsLeaderMoveSeconds")) exitWith {};
		_g setVariable ["SWLC_lambsLeaderAt", time];
		private _l = leader _g;
		if (alive _l && {isNull objectParent _l} && {!isPlayer _l}) then {
			_l enableAI "PATH";
			_l doMove ([getPosATL _l, _g] call SWLC_fnc_shuffleSpot);
		};
	};
	if ((_g getVariable ["SWLC_lambsTask", ""]) != "cqb") exitWith {};
	if ((time - (_g getVariable ["SWLC_lambsCheckAt", 0])) < CFG("lambsCheckSeconds")) exitWith {};
	_g setVariable ["SWLC_lambsCheckAt", time];
	private _flag = _g getVariable ["SWLC_lambsFlag", ""];
	private _left = {count (_x getVariable [_flag, [0, 0]]) > 0} count (_g getVariable ["SWLC_lambsBuildings", []]);
	private _timeout = time > (_g getVariable ["SWLC_lambsEnd", 0]);
	if (_left > 0 && {!_timeout}) exitWith {};
	[_cmd get "side", "lambs", "clear_done", [["group", groupId _g], ["left", _left], ["why", ["cleared", "timeout"] select _timeout]]] call SWLC_fnc_squadLog;
	[_g, true] call SWLC_fnc_lambsRelease;
};

// Gives the group back to the commander. _resume re-applies its order, and again a few seconds later,
// because LAMBS can still have a tactic finishing when the soft reset lands.
SWLC_fnc_lambsRelease = {
	params ["_g", ["_resume", true]];
	private _task = _g getVariable ["SWLC_lambsTask", ""];
	if (_task == "") exitWith {};
	private _handle = _g getVariable ["SWLC_lambsHandle", scriptNull];
	if (!isNull _handle && {_task != "defend"}) then {terminate _handle};
	[_g, true, true] call lambs_wp_fnc_taskReset;
	// taskDefend's loop, and the frame handler it owns, end only when the group's waypoint count changes.
	if (_task == "defend" && {!isNull _handle}) then {
		[_g, _handle] spawn {
			params ["_g", "_h"];
			private _end = time + 30;
			while {!scriptDone _h && {time < _end} && {!isNull _g}} do {
				private _wp = _g addWaypoint [getPosATL leader _g, 0];
				_wp setWaypointName "swlc_lambs_end";
				sleep 4;
				if (waypointName _wp == "swlc_lambs_end") then {deleteWaypoint _wp};
				sleep 2;
			};
		};
	};
	{
		_x enableAI "AUTOCOMBAT";
		_x enableAI "WEAPONAIM";
		_x enableAI "FIREWEAPON";
		_x enableAI "PATH";
		// taskGarrison mans statics and any free turret nearby, including a parked vehicle or a player's.
		private _v = objectParent _x;
		if (!isNull _v && {(_v isKindOf "StaticWeapon") || {gunner _v == _x && {isNull (driver _v) || {group (driver _v) != _g}}}}) then {
			unassignVehicle _x;
			moveOut _x;
		};
	} forEach ((units _g) select {alive _x});
	_g enableAttack true;
	_g setVariable ["lambs_danger_disableGroupAI", nil];
	_g setVariable ["lambs_main_groupMemory", nil];
	// A defender's own order comes back, unless the commander has given it a new one meanwhile.
	private _prior = _g getVariable ["SWLC_lambsPrior", []];
	if (_prior isNotEqualTo [] && {(_g getVariable ["SWLC_order", []]) isEqualTo (_g getVariable ["SWLC_lambsOrder", []])}) then {
		_g setVariable ["SWLC_order", _prior];
	};
	_g setVariable ["SWLC_lambsPrior", []];
	_g setVariable ["SWLC_lambsTask", ""];
	_g setVariable ["SWLC_lambsHandle", scriptNull];
	_g setVariable ["SWLC_lambsBuildings", []];
	_g setVariable ["SWLC_lambsOrder", []];
	_g setVariable ["SWLC_lambsBusyAt", time];
	_g setVariable ["SWLC_lambsNext", time + CFG("lambsRetrySeconds")];
	[side _g, "lambs", "release", [["group", groupId _g], ["task", _task], ["resume", _resume]]] call SWLC_fnc_squadLog;
	if (_resume) then {
		[_g] call SWLC_fnc_lambsResume;
		[_g] spawn {
			params ["_g"];
			sleep 5;
			isNil {
				if (!isNull _g && {(_g getVariable ["SWLC_lambsTask", ""]) == ""} && {!([_g] call SWLC_fnc_adGroupHasPlayer)}) then {
					[_g] call SWLC_fnc_lambsResume;
				};
			};
		};
	};
};

// A group still assaulting goes back to sweeping the sector. Anything else restarts what it was doing.
SWLC_fnc_lambsResume = {
	params ["_g"];
	private _cmd = missionNamespace getVariable [format ["SWLC_cmd_%1", side _g], createHashMap];
	private _target = objNull;
	if (count _cmd > 0) then {_target = [_cmd] call SWLC_fnc_squadTarget};
	if (([_g] call SWLC_fnc_state) == "Assaulting" && {!isNull _target}) exitWith {
		[_g, [_target] call SWLC_fnc_sweepOrder, "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
	};
	[_g, 0] call SWLC_fnc_adApplyOrder;
};
