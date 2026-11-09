// Rules variant, front line part B: defenders keep fast travel to a sector until real fighting reaches it.
// One state per owned sector, on a server loop. It drives Warlords' own per-sector switch, so players' fast travel
// menu and the commander (adCanFTTo reads the same variable) can't disagree. Spec in docs/design/rules-variant.md.
#include "macros.hpp"

SWLC_frontRecs = createHashMap;    // sector name -> state
SWLC_frontDeaths = [];             // [time, pos, side] of men killed by someone, newest last

SWLC_fnc_frontOn = {
	CFG("rulesVariant") && {CFG("ruleDefenderFT")}
};

// Is active fighting on at this sector, for the side that owns it?
SWLC_fnc_frontFighting = {
	params ["_s"];
	if (isNull _s || {!([] call SWLC_fnc_frontOn)}) exitWith {false};
	(SWLC_frontRecs getOrDefault [[_s] call SWLC_fnc_adName, createHashMap]) getOrDefault ["on", false]
};

// May _side fast travel to _s? One answer for everyone: fighting closes Warlords' per-sector switch, which adCanFTTo reads.
SWLC_fnc_frontFTOpen = {
	params ["_side", "_s"];
	[_side, _s] call SWLC_fnc_adCanFTTo
};

// Should the commander stay away from _s when choosing where to fast travel? _threats is the commander's board.
SWLC_fnc_frontHot = {
	params ["_threats", "_s"];
	if ([] call SWLC_fnc_frontOn) exitWith {[_s] call SWLC_fnc_frontFighting};
	// A warning with nothing seen yet isn't hot: that's when defenders should still be landing there.
	private _rec = _threats getOrDefault [[_s] call SWLC_fnc_adName, createHashMap];
	count _rec > 0 && {!(_rec getOrDefault ["alertOnly", false])}
};

SWLC_fnc_frontSetState = {
	params ["_s", "_rec", "_on", "_attackers", "_why", ["_tell", true]];
	_rec set ["on", _on];
	_rec set ["changedAt", time];
	[_s, !_on] call SWLC_fnc_adSetFTOpen;
	private _side = _rec get "side";
	private _name = [_s] call SWLC_fnc_adName;
	["C_FRONT", [["side", _side], ["sector", _name], ["state", ["open", "closed"] select _on], ["attackers", _attackers], ["why", _why]]] call SWLC_fnc_log;
	if (_tell) then {[_side, ["ftopen", "ftclose"] select _on, [_name]] call SWLC_fnc_radio};
};

// The owner changed, or the sector went neutral: what was true for the old owner is over.
SWLC_fnc_frontDrop = {
	params ["_s", "_rec"];
	if (_rec get "on") then {[_s, _rec, false, 0, "owner_changed", false] call SWLC_fnc_frontSetState};
	SWLC_frontRecs deleteAt ([_s] call SWLC_fnc_adName);
};

// Advances the sector's 30 s windows and returns how many finished ones had real fighting in them.
// Windows start at the first exchange, so one burst always sits inside one window. The window still running isn't counted.
SWLC_fnc_frontWindows = {
	params ["_rec", "_hit", "_now"];
	private _w = CFG("frontWindowSeconds");
	private _n = CFG("frontWindowsTotal");
	private _anchor = _rec get "anchor";
	private _bits = _rec get "bits";
	if (_anchor >= 0) then {
		private _idx = floor ((_now - _anchor) / _w);
		for "_i" from 1 to ((_idx - (_rec get "idx")) min (_n + 1)) do {_bits pushBack false};
		_bits = _bits select [((count _bits) - (_n + 1)) max 0, _n + 1];
		if (_idx != (_rec get "idx")) then {_rec set ["hits", 0]};
		_rec set ["idx", _idx];
		if (!_hit && {({_x} count _bits) == 0} && {(_rec getOrDefault ["hits", 0]) == 0}) then {
			_anchor = -1;
			_bits = [];
			_rec set ["anchor", -1];
		};
	};
	if (_hit) then {
		if (_anchor < 0) then {
			_rec set ["anchor", _now];
			_rec set ["idx", 0];
			_rec set ["hits", 0];
			_bits = [false];
		};
		private _hits = (_rec getOrDefault ["hits", 0]) + 1;
		_rec set ["hits", _hits];
		if (_hits >= CFG("frontWindowMinHits")) then {_bits set [(count _bits) - 1, true]};
		_rec set ["lastHit", _now];
	};
	_rec set ["bits", _bits];
	if ((count _bits) < 2) exitWith {0};
	{_x} count (_bits select [0, (count _bits) - 1])
};

// One sector, one poll. _men is every living man of the two Warlords sides.
SWLC_fnc_frontUpdate = {
	params ["_s", "_men", "_now"];
	private _owner = [_s] call SWLC_fnc_adOwner;
	private _key = [_s] call SWLC_fnc_adName;
	private _rec = SWLC_frontRecs getOrDefault [_key, createHashMap];
	if ((count _rec > 0) && {(_rec get "side") != _owner}) then {
		[_s, _rec] call SWLC_fnc_frontDrop;
		_rec = createHashMap;
	};
	if !(_owner in [west, east]) exitWith {};
	if (count _rec == 0) then {
		_rec = createHashMapFromArray [["side", _owner], ["on", false], ["anchor", -1], ["idx", 0], ["bits", []], ["lastHit", -1e6], ["lastSeize", -1e6], ["changedAt", _now]];
		SWLC_frontRecs set [_key, _rec];
	};

	private _enemy = [_owner] call SWLC_fnc_adEnemySide;
	private _margin = CFG("frontAreaMargin");
	private _inArea = _men select {[_s, getPosATL _x, _margin] call SWLC_fnc_adInSquare};
	private _attackers = _inArea select {side group _x == _enemy};
	private _defenders = _inArea select {side group _x == _owner};
	private _deaths = SWLC_frontDeaths select {[_s, _x # 1, _margin] call SWLC_fnc_adInSquare};

	// Both sides: gunfire from each, or someone died. One side shooting at nothing doesn't count.
	private _recent = _now - CFG("frontExchangeSeconds");
	private _firedRecently = {(_x getVariable ["SWLC_firedAt", -1e6]) >= _recent};
	private _exchange = ((_attackers findIf _firedRecently) >= 0 && {(_defenders findIf _firedRecently) >= 0})
		|| {(_deaths findIf {(_x # 0) >= _recent && {(_x # 2) in [_owner, _enemy]}}) >= 0};

	// Numbers: attackers who fired, came under fire or died here lately. A lone infiltrator never reaches this.
	private _since = _now - CFG("frontInvolvedSeconds");
	private _involved = ({((_x getVariable ["SWLC_firedAt", -1e6]) max (_x getVariable ["SWLC_underFireAt", -1e6])) >= _since} count _attackers)
		+ ({(_x # 0) >= _since && {(_x # 2) == _enemy}} count _deaths);

	private _hit = _exchange && {_involved >= CFG("frontMinAttackers")};
	private _sustained = ([_rec, _hit, _now] call SWLC_fnc_frontWindows) >= CFG("frontWindowsNeeded");

	// The enemy's countdown is running on it. A seize needs real numbers too: one man sneaking in is exactly who defenders must be able to reach.
	private _seizing = ([_owner, _s] call SWLC_fnc_capBeingSeized) && {({[_s, getPosATL _x, 0] call SWLC_fnc_adInSquare} count _attackers) >= CFG("frontSeizeMinMen")};
	if (_seizing) then {_rec set ["lastSeize", _now]};

	if (_rec get "on") then {
		if ((_now - ((_rec get "lastHit") max (_rec get "lastSeize"))) >= CFG("frontQuietSeconds")) then {
			[_s, _rec, false, _involved, "quiet"] call SWLC_fnc_frontSetState;
			_rec set ["anchor", -1];
			_rec set ["bits", []];
		};
	} else {
		if (_seizing || _sustained) then {
			[_s, _rec, true, _involved, ["exchange", "seizing"] select _seizing] call SWLC_fnc_frontSetState;
		};
	};
};

SWLC_fnc_frontTick = {
	private _now = time;
	private _keep = _now - (CFG("frontInvolvedSeconds") max CFG("frontExchangeSeconds"));
	SWLC_frontDeaths = SWLC_frontDeaths select {(_x # 0) >= _keep};
	private _men = allUnits select {(side group _x) in [west, east]};
	{[_x, _men, _now] call SWLC_fnc_frontUpdate} forEach SWLC_sectors;
};

SWLC_fnc_frontLoop = {
	scriptName "SWLC front";
	while {true} do {
		sleep CFG("frontPollSeconds");
		private _pollOk = false;
		isNil {
			[] call SWLC_fnc_frontTick;
			_pollOk = true;
		};
		if (!_pollOk && {["resGroupGuard"] call SWLC_fnc_resItem}) then {
			["C_SUP", [["side", "-"], ["action", "stage_error"], ["stale_s", 0], ["last_group", "-"], ["last_stage", "front"],
				["error", missionNamespace getVariable ["SWLC_lastScriptError", "unknown"]]]] call SWLC_fnc_log;
		};
	};
};

// Called once, with the rest of the rules variant. Nothing here runs when the rule is off.
SWLC_fnc_frontInstall = {
	if !([] call SWLC_fnc_frontOn) exitWith {};
	CFG("radioCooldowns") set ["ftclose", CFG("frontRadioCooldown")];
	CFG("radioCooldowns") set ["ftopen", CFG("frontRadioCooldown")];
	addMissionEventHandler ["EntityKilled", {
		params ["_dead", "_killer", "_instigator"];
		if !(_dead isKindOf "CAManBase") exitWith {};
		// Killed by someone: Warlords' restricted-area kills and accidents aren't a fight.
		private _who = if (isNull _instigator) then {_killer} else {_instigator};
		if (isNull _who || {_who == _dead}) exitWith {};
		SWLC_frontDeaths pushBack [time, getPosATL _dead, [typeOf _dead] call SWLC_fnc_econCfgSide];
	}];
	[] spawn SWLC_fnc_frontLoop;
};

// The commander panel's line: each threatened sector and whether we can still fast travel to it.
SWLC_fnc_frontStatusText = {
	params ["_cmd"];
	if !([] call SWLC_fnc_frontOn) exitWith {""};
	private _side = _cmd get "side";
	private _threats = _cmd get "threats";
	private _enemyTarget = [[_side] call SWLC_fnc_adEnemySide] call SWLC_fnc_adTarget;
	private _list = ([_side] call SWLC_fnc_adOwned) select {
		_x isEqualTo _enemyTarget || {([_x] call SWLC_fnc_adName) in _threats} || {[_x] call SWLC_fnc_frontFighting}
	};
	if (_list isEqualTo []) exitWith {""};
	"Fast travel: " + ((_list apply {format ["%1 %2", [_x] call SWLC_fnc_adName, ["closed", "open"] select ([_side, _x] call SWLC_fnc_frontFTOpen)]}) joinString ", ")
};
