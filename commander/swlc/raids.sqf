// Rules variant, part D: raid orders and probes.
// A raid uses Warlords' own capture. Putting the sector on the raiding side's conquered list opens the native
// seize trigger and lifts Warlords' kill zones; the trigger is then slowed down for the raid. Only sectors
// that Warlords' handler is already running on can be raided, because a preset sector doesn't react to capture.
#include "macros.hpp"

SWLC_fnc_raidOn = { CFG("rulesVariant") && {CFG("ruleRaids")} };

SWLC_fnc_raidOf = { (_this # 0) getOrDefault ["raid", createHashMap] };

SWLC_fnc_raidLog = {
	params ["_cmd", "_event", "_s", ["_extra", []]];
	["C_RAID", [["side", _cmd get "side"], ["event", _event], ["sector", [_s] call SWLC_fnc_adName]] + _extra] call SWLC_fnc_log;
};

// Enemy sectors next to one the side owns: the only places a raid can be ordered.
SWLC_fnc_raidFront = {
	params ["_side"];
	private _owned = [_side] call SWLC_fnc_adOwned;
	private _target = [_side] call SWLC_fnc_adTarget;
	([[_side] call SWLC_fnc_adEnemySide] call SWLC_fnc_adOwned) select {
		private _s = _x;
		!([_s] call SWLC_fnc_adIsBase)
		&& {_s isNotEqualTo _target}
		&& {!(([_s, _side] call SWLC_fnc_capKey) in SWLC_capRecs)}
		&& {_s getVariable ["BIS_WL_handleServerRunning", false]}
		&& {(([_s] call SWLC_fnc_adLinks) findIf {_x in _owned}) >= 0}
	}
};

// Why a raid on _s can't be ordered, or "" when it can. _funds is what the buyer has to spend.
SWLC_fnc_raidRefusal = {
	params ["_cmd", "_s", "_funds"];
	if !([] call SWLC_fnc_raidOn) exitWith {"off"};
	if (count ([_cmd] call SWLC_fnc_raidOf) > 0) exitWith {"active"};
	if (time < (_cmd getOrDefault ["raidCooldownUntil", -1])) exitWith {"cooldown"};
	if !(_s in ([_cmd get "side"] call SWLC_fnc_raidFront)) exitWith {"not_front"};
	if (_funds < CFG("raidCostCP")) exitWith {"funds"};
	""
};

// Groups the attack can do without, nearest the given position first.
SWLC_fnc_raidSpare = {
	params ["_cmd", "_near"];
	private _groups = _cmd get "groups";
	private _attack = {([_x] call SWLC_fnc_state) in ["Unassigned", "Mustering", "Travelling", "Advancing", "Waiting", "Assaulting", "Regrouping"]} count _groups;
	private _can = _attack - CFG("raidKeepGroups");
	if (_can <= 0) exitWith {[]};
	private _free = _groups select {([_x] call SWLC_fnc_state) in ["Unassigned", "Mustering", "Travelling"] && {vehicle leader _x == leader _x}};
	_free = [_free, [], {leader _x distance2D _near}, "ASCEND"] call BIS_fnc_sortBy;
	_free select [0, _can]
};

// Gives a group its raid order and fast travels it to the safe owned sector nearest the raid.
SWLC_fnc_raidSend = {
	params ["_cmd", "_rec", "_g"];
	private _s = _rec get "sector";
	private _c = [_s] call SWLC_fnc_adPos;
	private _spot = [_c, random 360, random (([_s] call SWLC_fnc_adSize) / 4)] call SWLC_fnc_offset;
	if (surfaceIsWater _spot) then {_spot = +_c};
	[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
	[_g, "Raiding", _spot, "raid"] call SWLC_fnc_setState;
	_g setVariable ["SWLC_patrolAt", time];
	[_g, [[_spot, "MOVE", 20]], "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
	(_rec get "groups") pushBackUnique _g;
	if ((leader _g distance2D _spot) <= CFG("stagingFarThreshold")) exitWith {};
	private _side = _cmd get "side";
	private _from = ([_side] call SWLC_fnc_adOwned) select {[_side, _x] call SWLC_fnc_adCanFTTo};
	if (_from isEqualTo []) exitWith {};
	private _hop = ([_from, [], {([_x] call SWLC_fnc_adPos) distance2D _c}, "ASCEND"] call BIS_fnc_sortBy) # 0;
	private _sp = [_hop] call SWLC_fnc_adPos;
	private _land = [_sp, [_sp, _c] call SWLC_fnc_bearing, 40 + random 30] call SWLC_fnc_offset;
	if (surfaceIsWater _land) then {_land = _sp};
	[_g, _hop, _land] call SWLC_fnc_adFastTravel;
};

// Starts a paid raid. Payment and the refusal check are the caller's.
SWLC_fnc_raidStart = {
	params ["_cmd", "_s", "_by", "_groups"];
	private _side = _cmd get "side";
	private _listVar = format ["BIS_WL_conqueredSectors_%1", _side];
	private _list = missionNamespace getVariable [_listVar, []];
	private _added = !(_s in _list);
	if (_added) then {
		_list pushBack _s;
		missionNamespace setVariable [_listVar, _list];
		publicVariable _listVar;
	};
	_s setVariable [format ["SWLC_capMult_%1", _side], CFG("raidSeizeMult")];
	private _trg = [_s, _side] call SWLC_fnc_capTrigger;
	if (!isNull _trg) then {_trg setVariable ["SWLC_capForce", true]};
	missionNamespace setVariable [format ["SWLC_raidSector_%1", _side], _s];
	private _expires = time + (CFG("raidExpirySeconds") max (([_s, _side] call SWLC_fnc_capNominalFor) + CFG("raidExpiryTravelSeconds")));
	missionNamespace setVariable [format ["SWLC_raid_%1", _side], [[_s] call SWLC_fnc_adName, [_s] call SWLC_fnc_adPos, _expires], true];
	private _rec = createHashMapFromArray [["sector", _s], ["started", time], ["expires", _expires], ["by", _by], ["added", _added], ["groups", []], ["stage", "active"], ["trg", _trg]];
	_cmd set ["raid", _rec];
	[_cmd, "start", _s, [["by", _by], ["cost", CFG("raidCostCP")], ["groups", count _groups], ["added", _added], ["nominal", ([_s, _side] call SWLC_fnc_capNominalFor) toFixed 1]]] call SWLC_fnc_raidLog;
	[_side, "raidorder", [[_s] call SWLC_fnc_adName]] call SWLC_fnc_radio;
	{[_cmd, _rec, _x] call SWLC_fnc_raidSend} forEach _groups;
	_rec
};

// Undoes the raid's changes and starts the cooldown.
SWLC_fnc_raidClear = {
	params ["_cmd", "_rec", "_result"];
	private _s = _rec get "sector";
	private _side = _cmd get "side";
	_s setVariable [format ["SWLC_capMult_%1", _side], nil];
	_s setVariable [format ["SWLC_capPrimed_%1", _side], nil];
	private _trg = _rec get "trg";
	if (!isNull _trg) then {
		// capForce is still set here, so this works with the capture-pause rule off.
		[_trg, [_s, _side] call SWLC_fnc_capNominalFor] call SWLC_fnc_capSetTimeout;
		_trg setVariable ["SWLC_capForce", nil];
	};
	missionNamespace setVariable [format ["SWLC_raidSector_%1", _side], objNull];
	missionNamespace setVariable [format ["SWLC_raid_%1", _side], [], true];
	{
		if (([_x] call SWLC_fnc_groupMen) > 0 && {([_x] call SWLC_fnc_state) == "Raiding"}) then {
			[_x] call SWLC_fnc_adClearOrder;
			[_x, "Unassigned", [], "raid_over"] call SWLC_fnc_setState;
		};
	} forEach (_rec get "groups");
	_cmd deleteAt "raid";
	_cmd set ["raidCooldownUntil", time + CFG("raidCooldownSeconds")];
	[_cmd, "end", _s, [["result", _result], ["held", round (time - (_rec get "started"))]]] call SWLC_fnc_raidLog;
};

// The raid ran out of time or men. Raiders get a short grace period to leave before Warlords' kill zone returns,
// and the trigger is stretched so the capture can't finish during it.
// Walks a group to the nearest owned sector. The commander's next job for it replaces this.
SWLC_fnc_raidGoHome = {
	params ["_cmd", "_g"];
	private _owned = [_cmd get "side"] call SWLC_fnc_adOwned;
	if (_owned isEqualTo []) exitWith {};
	private _p = getPosATL leader _g;
	private _home = [([_owned, [], {([_x] call SWLC_fnc_adPos) distance2D _p}, "ASCEND"] call BIS_fnc_sortBy) # 0] call SWLC_fnc_adPos;
	private _spot = [_home, random 360, 20 + random 30] call SWLC_fnc_offset;
	if (surfaceIsWater _spot) then {_spot = +_home};
	[_g, [[_spot, "MOVE", 20]], "AWARE", "FULL", "WEDGE", "YELLOW"] call SWLC_fnc_adSetOrder;
};

// The side's vote landed on the raid's own sector. The main capture takes over at its normal speed.
SWLC_fnc_raidMerge = {
	params ["_cmd", "_rec"];
	private _s = _rec get "sector";
	private _key = [_s, _cmd get "side"] call SWLC_fnc_capKey;
	private _cap = SWLC_capRecs getOrDefault [_key, createHashMap];
	if (count _cap > 0) then {[_key, _cap, "became_target"] call SWLC_fnc_capFinish};
	{
		if (([_x] call SWLC_fnc_groupMen) > 0 && {([_x] call SWLC_fnc_state) == "Raiding"}) then {
			[_x] call SWLC_fnc_adClearOrder;
			[_x, "Unassigned", [], "raid_merged"] call SWLC_fnc_setState;
		};
	} forEach (_rec get "groups");
	_rec set ["why", "became_target"];
	[_cmd, "stop", _s, [["why", "became_target"]]] call SWLC_fnc_raidLog;
	[_cmd, _rec] call SWLC_fnc_raidGraceOver;
};

SWLC_fnc_raidStop = {
	params ["_cmd", "_rec", "_why"];
	private _s = _rec get "sector";
	private _side = _cmd get "side";
	private _key = [_s, _side] call SWLC_fnc_capKey;
	private _cap = SWLC_capRecs getOrDefault [_key, createHashMap];
	if (count _cap > 0) then {[_key, _cap, _why] call SWLC_fnc_capFinish};
	private _trg = _rec get "trg";
	if (!isNull _trg) then {[_trg, CFG("raidDisabledSeconds")] call SWLC_fnc_capSetTimeout};
	missionNamespace setVariable [format ["SWLC_raidSector_%1", _side], objNull];
	_rec set ["stage", "grace"];
	_rec set ["graceUntil", time + CFG("raidGraceSeconds")];
	_rec set ["why", _why];
	{
		if (([_x] call SWLC_fnc_groupMen) > 0 && {([_x] call SWLC_fnc_state) == "Raiding"}) then {
			[_x] call SWLC_fnc_adClearOrder;
			[_x, "Unassigned", [], "raid_stopped"] call SWLC_fnc_setState;
			[_cmd, _x] call SWLC_fnc_raidGoHome;
		};
	} forEach (_rec get "groups");
	[_cmd, "stop", _s, [["why", _why]]] call SWLC_fnc_raidLog;
	[_side, "raidstop", [[_s] call SWLC_fnc_adName]] call SWLC_fnc_radio;
};

SWLC_fnc_raidGraceOver = {
	params ["_cmd", "_rec"];
	private _s = _rec get "sector";
	private _side = _cmd get "side";
	if (_rec get "added") then {
		private _listVar = format ["BIS_WL_conqueredSectors_%1", _side];
		private _list = (missionNamespace getVariable [_listVar, []]) - [_s];
		missionNamespace setVariable [_listVar, _list];
		publicVariable _listVar;
	};
	private _trg = _rec get "trg";
	if (!isNull _trg) then {[_trg, [_s] call SWLC_fnc_capNominal] call SWLC_fnc_capSetTimeout};
	[_cmd, _rec, _rec get "why"] call SWLC_fnc_raidClear;
};

SWLC_fnc_raidCaptured = {
	params ["_cmd", "_rec"];
	private _s = _rec get "sector";
	// Warlords does this itself for a captured target, but not for any other sector.
	_s setVariable ["BIS_WL_responseArr", []];
	call BIS_fnc_WLUpdateAO;
	[_cmd get "side", "raidwon", [[_s] call SWLC_fnc_adName]] call SWLC_fnc_radio;
	[_cmd, _rec, "captured"] call SWLC_fnc_raidClear;
};

// Keeps raiders moving inside the square, so Warlords doesn't treat a waiting leader as stuck.
SWLC_fnc_raidShuffle = {
	params ["_g", "_s"];
	if ((time - (_g getVariable ["SWLC_patrolAt", -1e6])) < CFG("reservePatrolSeconds")) exitWith {};
	if !([_g] call SWLC_fnc_adOrderDone) exitWith {};
	_g setVariable ["SWLC_patrolAt", time];
	private _c = [_s] call SWLC_fnc_adPos;
	private _spot = [_c, random 360, random (([_s] call SWLC_fnc_adSize) / 4)] call SWLC_fnc_offset;
	if (surfaceIsWater _spot) then {_spot = +_c};
	_g setVariable ["SWLC_goal", _spot];
	[_g, [[_spot, "MOVE", 20]], "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
};

SWLC_fnc_raidDecide = {
	params ["_cmd"];
	if (time < (_cmd getOrDefault ["raidNextCheck", 0])) exitWith {};
	_cmd set ["raidNextCheck", time + CFG("raidDecideSeconds")];
	private _side = _cmd get "side";
	if (([_side] call SWLC_fnc_adSideHasPlayers) && {!CFG("raidAIOnPlayerSide")}) exitWith {};
	if ([_cmd] call SWLC_fnc_rebuilding) exitWith {};
	if (time < (_cmd getOrDefault ["raidCooldownUntil", -1])) exitWith {};
	if (([_side] call SWLC_fnc_cpFree) < CFG("raidCostCP")) exitWith {};

	private _op = _cmd get "op";
	private _stuck = !isNil "_op" && {((_op getOrDefault ["pushFails", 0]) >= 1) || {(time - (_op get "created")) >= CFG("raidStuckAfterSeconds")}};
	private _limit = [CFG("raidMaxDefenders"), CFG("raidMaxDefendersStuck")] select _stuck;
	private _best = objNull;
	private _bestScore = -1e9;
	{
		private _t = [_cmd, _x] call SWLC_fnc_threatOf;
		private _strength = (_t get "infantry") + 3 * (_t get "light") + 6 * (_t get "armour");
		if (_strength <= _limit) then {
			private _score = ([_cmd, _x] call SWLC_fnc_raidValue) - _strength * CFG("raidDefenderWeight") - ([CFG("raidUnscoutedPenalty"), 0] select (_t get "scouted"));
			if (_score > _bestScore) then {_bestScore = _score; _best = _x};
		};
	} forEach ([_side] call SWLC_fnc_raidFront);
	if (isNull _best) exitWith {};

	private _spare = [_cmd, [_best] call SWLC_fnc_adPos] call SWLC_fnc_raidSpare;
	if ((count _spare) < CFG("raidAIMinGroups")) exitWith {};
	if (([_cmd, _best, [_side] call SWLC_fnc_cpFree] call SWLC_fnc_raidRefusal) != "") exitWith {};
	if !([_side, CFG("raidCostCP")] call SWLC_fnc_adDebit) exitWith {};
	[_cmd, _best, "ai", _spare select [0, CFG("raidAIGroups")]] call SWLC_fnc_raidStart;
};

// How much a raid on this sector is worth. Part G adds what the sector unlocks.
SWLC_fnc_raidValue = {
	params ["_cmd", "_s"];
	([_s] call SWLC_fnc_adValue) + ([_cmd get "side", _s] call SWLC_fnc_stratWorth)
};

SWLC_fnc_raidTick = {
	params ["_cmd"];
	if !([] call SWLC_fnc_raidOn) exitWith {};
	private _rec = [_cmd] call SWLC_fnc_raidOf;
	if (count _rec == 0) exitWith {[_cmd] call SWLC_fnc_raidDecide};
	private _s = _rec get "sector";
	private _side = _cmd get "side";
	if (([_s] call SWLC_fnc_adOwner) == _side) exitWith {[_cmd, _rec] call SWLC_fnc_raidCaptured};
	if (_s isEqualTo ([_side] call SWLC_fnc_adTarget)) exitWith {[_cmd, _rec] call SWLC_fnc_raidMerge};
	if ((_rec get "stage") == "grace") exitWith {
		if (time < (_rec get "graceUntil")) exitWith {};
		// Warlords' kill loops come back with the sector's closing, so anyone still inside gets a little longer.
		private _inside = (_rec get "groups") findIf {
			((units _x) findIf {alive _x && {[_s, getPosATL _x] call SWLC_fnc_adInSquare}}) >= 0
		};
		if (_inside >= 0 && {time < ((_rec get "graceUntil") + CFG("raidGraceExtraSeconds"))}) exitWith {};
		[_cmd, _rec] call SWLC_fnc_raidGraceOver;
	};
	private _live = (_rec get "groups") select {([_x] call SWLC_fnc_groupMen) > 0 && {([_x] call SWLC_fnc_state) == "Raiding"}};
	_rec set ["groups", _live];
	if (_live isEqualTo [] && {(_rec get "by") in ["ai", "probe"]}) exitWith {[_cmd, _rec, "wiped"] call SWLC_fnc_raidStop};
	if (time >= (_rec get "expires")) exitWith {[_cmd, _rec, "expired"] call SWLC_fnc_raidStop};
	{[_x, _s] call SWLC_fnc_raidShuffle} forEach _live;
};

// ---- Probes ----

SWLC_fnc_probeOn = { CFG("rulesVariant") && {CFG("ruleProbes")} };

SWLC_fnc_probeLog = {
	params ["_cmd", "_event", "_rec", ["_extra", []]];
	["C_PROBE", [["side", _cmd get "side"], ["event", _event], ["sector", [_rec get "sector"] call SWLC_fnc_adName], ["group", groupId (_rec get "group")]] + _extra] call SWLC_fnc_log;
};

SWLC_fnc_probeStrength = {
	params ["_cmd", "_s"];
	private _t = [_cmd, _s] call SWLC_fnc_threatOf;
	(_t get "infantry") + 3 * (_t get "light") + 6 * (_t get "armour")
};

// The weakest-looking enemy front-line sector, least scouted first, not probed recently.
SWLC_fnc_probeChoose = {
	params ["_cmd"];
	private _side = _cmd get "side";
	private _seen = _cmd getOrDefault ["probedAt", createHashMap];
	private _open = ([_side] call SWLC_fnc_raidFront) select {(time - (_seen getOrDefault [[_x] call SWLC_fnc_adName, -1e6])) >= CFG("probeRepeatSeconds")};
	if (_open isEqualTo []) exitWith {objNull};
	([_open, [], {
		private _t = [_cmd, _x] call SWLC_fnc_threatOf;
		([_cmd, _x] call SWLC_fnc_probeStrength) - ([1000, 0] select (_t get "scouted"))
	}, "ASCEND"] call BIS_fnc_sortBy) # 0
};

SWLC_fnc_probeBack = {
	params ["_cmd", "_rec", "_why"];
	private _g = _rec get "group";
	[_cmd, "back", _rec, [["why", _why], ["men", [_g] call SWLC_fnc_groupMen], ["known", [_cmd, _rec get "sector"] call SWLC_fnc_probeStrength]]] call SWLC_fnc_probeLog;
	[_cmd get "side", "probeback", [[_rec get "sector"] call SWLC_fnc_adName], _g] call SWLC_fnc_radio;
	[_g] call SWLC_fnc_adClearOrder;
	[_g, "Unassigned", [], "probe_back"] call SWLC_fnc_setState;
	[_cmd, _g] call SWLC_fnc_raidGoHome;
	_cmd deleteAt "probe";
};

// The probe has had a look: mark a weak sector, buy a raid if the side can, otherwise come home.
SWLC_fnc_probeJudge = {
	params ["_cmd", "_rec"];
	private _s = _rec get "sector";
	private _g = _rec get "group";
	private _side = _cmd get "side";
	private _threat = [_cmd, _s] call SWLC_fnc_threatOf;
	private _strength = [_cmd, _s] call SWLC_fnc_probeStrength;
	if !((_threat get "scouted") && {_strength <= CFG("probeLightlyHeldMen")}) exitWith {[_cmd, _rec, "resistance"] call SWLC_fnc_probeBack};

	private _weak = _cmd getOrDefault ["probeWeak", createHashMap];
	_weak set [[_s] call SWLC_fnc_adName, time + CFG("probeWeakSeconds")];
	_cmd set ["probeWeak", _weak];
	[_cmd, "weak", _rec, [["known", _strength]]] call SWLC_fnc_probeLog;
	[_side, "probeweak", [[_s] call SWLC_fnc_adName], _g] call SWLC_fnc_radio;

	private _canBuy = !([_side] call SWLC_fnc_adSideHasPlayers) || {CFG("raidAIOnPlayerSide")};
	if (_canBuy && {([_cmd, _s, [_side] call SWLC_fnc_cpFree] call SWLC_fnc_raidRefusal) == ""} && {[_side, CFG("raidCostCP")] call SWLC_fnc_adDebit}) exitWith {
		_cmd deleteAt "probe";
		[_cmd, "raid", _rec] call SWLC_fnc_probeLog;
		[_cmd, _s, "probe", [_g]] call SWLC_fnc_raidStart;
	};
	[_cmd, _rec, "weak_no_raid"] call SWLC_fnc_probeBack;
};

SWLC_fnc_probeRun = {
	params ["_cmd", "_rec"];
	private _g = _rec get "group";
	private _men = [_g] call SWLC_fnc_groupMen;
	if (_men == 0 || {!(_g in (_cmd get "groups"))}) exitWith {
		[_cmd, "lost", _rec] call SWLC_fnc_probeLog;
		_cmd deleteAt "probe";
	};
	private _s = _rec get "sector";
	if ((_rec get "phase") == "travel") exitWith {
		if (_men < (_rec get "men") * CFG("probeBreakFraction")) exitWith {[_cmd, _rec, "hit_on_the_way"] call SWLC_fnc_probeBack};
		if (([_g] call SWLC_fnc_state) == "Recon") exitWith {};
		if ((leader _g distance2D (_rec get "spot")) > CFG("probeArriveDist")) exitWith {[_cmd, _rec, "never_arrived"] call SWLC_fnc_probeBack};
		[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
		[_g, "Probing", _rec get "spot", "probe_observe"] call SWLC_fnc_setState;
		[_g, [[getPosATL leader _g, "MOVE", 15]], "AWARE", "NORMAL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
		_rec set ["phase", "observe"];
		_rec set ["until", time + CFG("probeObserveSeconds")];
		[_cmd, "observe", _rec, [["men", _men]]] call SWLC_fnc_probeLog;
	};
	if (([_g] call SWLC_fnc_state) != "Probing") exitWith {
		[_cmd, "pulled", _rec] call SWLC_fnc_probeLog;
		_cmd deleteAt "probe";
	};
	private _known = [_cmd, _s] call SWLC_fnc_probeStrength;
	if (_men < (_rec get "men") * CFG("probeBreakFraction") || {_known > _men * CFG("probeOutmatchRatio")}) exitWith {[_cmd, _rec, "outmatched"] call SWLC_fnc_probeBack};
	if (time >= (_rec get "until")) then {[_cmd, _rec] call SWLC_fnc_probeJudge};
};

SWLC_fnc_probeTick = {
	params ["_cmd"];
	if !([] call SWLC_fnc_probeOn) exitWith {};
	private _rec = _cmd getOrDefault ["probe", createHashMap];
	if (count _rec > 0) exitWith {[_cmd, _rec] call SWLC_fnc_probeRun};
	if (time < (_cmd getOrDefault ["probeNext", 0])) exitWith {};
	private _op = _cmd get "op";
	private _bad = !isNil "_op" && {(_op getOrDefault ["pushFails", 0]) >= 1};
	_cmd set ["probeNext", time + ([CFG("probeEverySeconds"), CFG("probeEveryBadSeconds")] select _bad)];
	if ([_cmd] call SWLC_fnc_rebuilding) exitWith {};
	if (([_cmd get "groups"] call SWLC_fnc_groupsMen) < CFG("probeMinMen")) exitWith {};
	private _s = [_cmd] call SWLC_fnc_probeChoose;
	if (isNull _s) exitWith {};
	private _c = [_s] call SWLC_fnc_adPos;
	private _spare = [_cmd, _c] call SWLC_fnc_raidSpare;
	if (_spare isEqualTo []) exitWith {};
	private _g = ([_spare, [], {[_x] call SWLC_fnc_groupMen}, "ASCEND"] call BIS_fnc_sortBy) # 0;
	private _side = _cmd get "side";
	private _owned = [_side] call SWLC_fnc_adOwned;
	private _home = ([_owned, [], {([_x] call SWLC_fnc_adPos) distance2D _c}, "ASCEND"] call BIS_fnc_sortBy) # 0;
	private _spot = [_side, _c, [_c, [_home] call SWLC_fnc_adPos] call SWLC_fnc_bearing, CFG("probeObserveDist") max (([_s] call SWLC_fnc_adSize) * 0.71 + 80)] call SWLC_fnc_validHoldPoint;
	[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
	private _rode = [_cmd, _g, _spot] call SWLC_fnc_scoutDispatch;
	private _seen = _cmd getOrDefault ["probedAt", createHashMap];
	_seen set [[_s] call SWLC_fnc_adName, time];
	_cmd set ["probedAt", _seen];
	private _new = createHashMapFromArray [["group", _g], ["sector", _s], ["spot", _spot], ["phase", "travel"], ["men", [_g] call SWLC_fnc_groupMen], ["sent", time]];
	_cmd set ["probe", _new];
	[_cmd, "sent", _new, [["vehicle", _rode], ["bad", _bad]]] call SWLC_fnc_probeLog;
	[_side, "probe", [[_s] call SWLC_fnc_adName], _g] call SWLC_fnc_radio;
};
