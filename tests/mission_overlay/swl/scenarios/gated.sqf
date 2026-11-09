// Part D gate: raids and probes. Run with:
//   -DurationMinutes 19 -Scenario gated -Overrides "goMinGroups=99;rallyLoneWait=99999;scanBuying=false;ruleCommitTimer=false;raidKeepGroups=0;raidMaxDefenders=99;raidDecideSeconds=15;probeMinMen=1;probeEverySeconds=15;probeRepeatSeconds=1;probeObserveSeconds=20;scoutVehicleSpareCP=999999"
// Then: python tools/analyse_round.py <rpt> --gate partd
//
// Setup hands sectors to each side by writing BIS_WL_sectorSide, which is the only thing Warlords' seize trigger does
// on activation. A sector has to be selected first, so its Warlords handler is running: raids need that.
// T1: a raid with nobody on it expires, goes through grace and undoes everything.
// P1: a probe that finds a garrison pulls back. P2: a probe that finds nothing marks the sector weak and buys a raid.
// T2: the AI buys a raid with its own groups and captures the sector through Warlords' trigger.

waitUntil {sleep 1; !isNil "SWLC_ready" && {!isNil "SWLC_cmd_WEST"} && {!isNil "SWLC_cmd_EAST"}};

SWLG_emit = {
	params ["_fields"];
	diag_log text ((["SWL", "GD", format ["t=%1", round time]] + _fields) joinString "|");
};

SWLG_nameOf = {
	params ["_list"];
	(_list apply {[_x] call SWLC_fnc_adName}) joinString ","
};

// Guerrillas left in a sector handed over without a fight would contest every capture after it.
SWLG_clearGuer = {
	params ["_s"];
	{
		if (vehicle _x != _x) then {deleteVehicle vehicle _x};
		deleteVehicle _x;
	} forEach (allUnits select {side group _x == resistance && {[_s, getPosATL _x, 150] call SWLC_fnc_adInSquare}});
};

SWLG_take = {
	params ["_side", "_s"];
	[_s] call SWLG_clearGuer;
	_s setVariable ["BIS_WL_sectorSide", _side, true];
	[[format ["event=took|side=%1|sector=%2|handler=%3", _side, [_s] call SWLC_fnc_adName, _s getVariable ["BIS_WL_handleServerRunning", false]]]] call SWLG_emit;
};

// Neutral sectors on the shortest route between the two sides' territory, nearest WEST first.
SWLG_path = {
	private _seen = +([west] call SWLC_fnc_adOwned);
	private _parent = _seen apply {-1};
	private _hit = -1;
	private _i = 0;
	while {_hit < 0 && {_i < count _seen}} do {
		private _from = _i;
		{
			private _n = _x;
			if (_hit < 0 && {!(_n in _seen)}) then {
				private _owner = [_n] call SWLC_fnc_adOwner;
				if (_owner == east) then {_hit = _from};
				if (_owner != east && {_owner != west}) then {
					_seen pushBack _n;
					_parent pushBack _from;
				};
			};
		} forEach ([_seen # _from] call SWLC_fnc_adLinks);
		_i = _i + 1;
	};
	private _route = [];
	while {_hit >= 0} do {
		if (([_seen # _hit] call SWLC_fnc_adOwner) != west) then {_route pushBack (_seen # _hit)};
		_hit = _parent # _hit;
	};
	reverse _route;
	_route
};

SWLG_fund = {
	params ["_side", "_amount"];
	{_x setVariable ["BIS_WL_funds", _amount, true]} forEach ([_side] call SWLC_fnc_adAIWarlords);
};

// Groups that have reached the rally aren't spare, so a few are sent back to the commander.
SWLG_free = {
	params ["_cmd", "_n"];
	private _pool = (_cmd get "groups") select {([_x] call SWLC_fnc_state) == "Waiting" && {vehicle leader _x == leader _x}};
	{
		[_cmd, _x] call SWLC_fnc_waveRemoveGroup;
		[_x] call SWLC_fnc_adClearOrder;
		[_x, "Unassigned", [], "test_free"] call SWLC_fnc_setState;
	} forEach (_pool select [0, _n]);
};

SWLG_placeEast = {
	params ["_s", "_n"];
	private _g = createGroup [east, true];
	private _c = [_s] call SWLC_fnc_adPos;
	for "_i" from 1 to _n do {
		private _u = _g createUnit ["O_T_Soldier_F", _c, [], 25, "NONE"];
		_u allowDamage false;
		_u disableAI "PATH";
	};
	_g setCombatMode "BLUE";
	_g
};

SWLG_conquered = {
	params ["_s"];
	_s in (missionNamespace getVariable ["BIS_WL_conqueredSectors_WEST", []])
};

SWLG_stringOr = {
	params ["_v"];
	if (isNil "_v") exitWith {"nil"};
	str _v
};

// Stands a group next to the point, ready for a commander tick to find it there.
SWLG_moveGroup = {
	params ["_g", "_p"];
	{_x setPosATL [(_p # 0) + (random 16) - 8, (_p # 1) + (random 16) - 8, 0]} forEach units _g;
};

// Just outside the square on dry land, close enough that the commander counts the sector as looked at.
SWLG_edgeSpot = {
	params ["_s"];
	private _c = [_s] call SWLC_fnc_adPos;
	private _d = (([_s] call SWLC_fnc_adSize) / 2) + 40;
	private _spot = [(_c # 0) + _d, _c # 1, 0];
	{
		private _p = [(_c # 0) + (_x # 0) * _d, (_c # 1) + (_x # 1) * _d, 0];
		if !(surfaceIsWater _p) exitWith {_spot = _p};
	} forEach [[1, 0], [-1, 0], [0, 1], [0, -1]];
	_spot
};

SWLG_scrub = {
	params ["_cmd", "_s"];
	_cmd set ["board", (_cmd get "board") select {!((_x get "sector") isEqualTo _s)}];
};

SWLG_probeOnly = {
	params ["_cmd", "_s"];
	private _seen = createHashMap;
	{_seen set [[_x] call SWLC_fnc_adName, time + 1e5]} forEach (([west] call SWLC_fnc_raidFront) - [_s]);
	_cmd set ["probedAt", _seen];
	_cmd deleteAt "probe";
	if (([_cmd, [_s] call SWLC_fnc_adPos] call SWLC_fnc_raidSpare) isEqualTo []) then {[_cmd, 2] call SWLG_free};
	_cmd set ["probeNext", 0];
};

private _cmd = missionNamespace getVariable "SWLC_cmd_WEST";
private _cmdE = missionNamespace getVariable "SWLC_cmd_EAST";
{_x set ["raidNextCheck", 1e9]; _x set ["probeNext", 1e9]} forEach [_cmd, _cmdE];

// ---- Setup: a WEST sector next to an EAST one that isn't a base ----
private _deadline = time + 300;
while {(([west] call SWLC_fnc_raidFront) isEqualTo []) && {time < _deadline}} do {
	private _route = [] call SWLG_path;
	// The last neutral sector goes to EAST: a base can't be raided, so WEST needs an ordinary EAST sector next to it.
	private _lastOne = if (count _route == 1) then {_route # 0} else {objNull};
	if (_route isNotEqualTo []) then {
		if (isNull _lastOne) then {_cmd set ["preferredTarget", _route # 0]};
		_cmdE set ["preferredTarget", _route # ((count _route) - 1)];
	};
	{
		private _side = _x;
		private _t = [_side] call SWLC_fnc_adTarget;
		if (!isNull _t && {!([_t] call SWLC_fnc_adIsBase)} && {!(([_t] call SWLC_fnc_adOwner) in [west, east])} && {_side == east || {!(_t isEqualTo _lastOne)}}) then {
			[_side, _t] call SWLG_take;
		};
	} forEach [west, east];
	// A side's own target can't be raided. If that is the only enemy sector in reach, WEST votes elsewhere.
	private _wt = [west] call SWLC_fnc_adTarget;
	if (!isNull _wt && {([_wt] call SWLC_fnc_adOwner) == east}) then {
		private _other = ([west] call SWLC_fnc_adAvailable) select {_x isNotEqualTo _wt && {([_x] call SWLC_fnc_adOwner) != west} && {!([_x] call SWLC_fnc_adIsBase)}};
		if (_other isNotEqualTo []) then {
			_cmd set ["preferredTarget", _other # 0];
			[west] call SWLC_fnc_adForceRevote;
			[[format ["event=revote|from=%1|to=%2", [_wt] call SWLC_fnc_adName, [_other # 0] call SWLC_fnc_adName]]] call SWLG_emit;
		};
	};
	sleep 8;
};
private _front = [west] call SWLC_fnc_raidFront;
if (_front isEqualTo []) exitWith {[["event=fail_no_front"]] call SWLG_emit};

private _raidS = _front # 0;
private _raidName = [_raidS] call SWLC_fnc_adName;
// The next vote must not take the raid sector itself as WEST's target.
private _other = (([west] call SWLC_fnc_adAvailable) - _front) select {!(([_x] call SWLC_fnc_adOwner) in [west, east])};
if (_other isNotEqualTo []) then {_cmd set ["preferredTarget", _other # 0]} else {_cmd deleteAt "preferredTarget"};
[[format ["event=front|sector=%1|front=%2|links=%3|owned=%4|other=%5", _raidName, [_front] call SWLG_nameOf, [[_raidS] call SWLC_fnc_adLinks] call SWLG_nameOf,
	[[west] call SWLC_fnc_adOwned] call SWLG_nameOf, [_other] call SWLG_nameOf]]] call SWLG_emit;
sleep 25;
private _targetNow = [west] call SWLC_fnc_adTarget;
[[format ["event=target_after_setup|target=%1|front=%2", if (isNull _targetNow) then {"-"} else {[_targetNow] call SWLC_fnc_adName}, [[west] call SWLC_fnc_raidFront] call SWLG_nameOf]]] call SWLG_emit;
private _trg = [_raidS, west] call SWLC_fnc_capTrigger;
private _baseNominal = [_raidS] call SWLC_fnc_capNominal;

// ---- Refusals that need no raid running ----
[[format ["event=refusal|case=not_front|got=%1", [_cmd, [east] call SWLC_fnc_adBase, 99999] call SWLC_fnc_raidRefusal]]] call SWLG_emit;
[[format ["event=refusal|case=funds|got=%1", [_cmd, _raidS, 0] call SWLC_fnc_raidRefusal]]] call SWLG_emit;

// ---- T1: an order that expires ----
SWLC_settings set ["raidExpirySeconds", 45];
SWLC_settings set ["raidGraceSeconds", 20];
SWLC_settings set ["raidCooldownSeconds", 30];
private _listBefore = [_raidS] call SWLG_conquered;
private _timeoutBefore = triggerTimeout _trg;
private _rec1 = [_cmd, _raidS, "test", []] call SWLC_fnc_raidStart;
[[format ["event=t1_start|sector=%1|in_list_before=%2|in_list=%3|mult=%4|nominal=%5|base_nominal=%6|timeout_before=%7|marker=%8", _raidName, _listBefore, [_raidS] call SWLG_conquered,
	_raidS getVariable ["SWLC_capMult_WEST", -1], ([_raidS, west] call SWLC_fnc_capNominalFor) toFixed 1, _baseNominal toFixed 1, _timeoutBefore, missionNamespace getVariable ["SWLC_raid_WEST", []]]]] call SWLG_emit;
[[format ["event=refusal|case=active|got=%1", [_cmd, _raidS, 99999] call SWLC_fnc_raidRefusal]]] call SWLG_emit;

private _end = time + 90;
waitUntil {sleep 1; ((_rec1 getOrDefault ["stage", ""]) == "grace") || {count ([_cmd] call SWLC_fnc_raidOf) == 0} || {time > _end}};
[[format ["event=t1_grace|stage=%1|in_list=%2|timeout=%3|watched=%4", _rec1 getOrDefault ["stage", ""], [_raidS] call SWLG_conquered, triggerTimeout _trg, !isNull (missionNamespace getVariable ["SWLC_raidSector_WEST", objNull])]]] call SWLG_emit;
_end = time + 60;
waitUntil {sleep 1; count ([_cmd] call SWLC_fnc_raidOf) == 0 || {time > _end}};
[[format ["event=t1_after|cleared=%1|in_list=%2|mult=%3|force=%4|timeout=%5|base_nominal=%6|marker=%7|cooldown_left=%8|owner=%9", count ([_cmd] call SWLC_fnc_raidOf) == 0, [_raidS] call SWLG_conquered,
	[_raidS getVariable "SWLC_capMult_WEST"] call SWLG_stringOr, [_trg getVariable "SWLC_capForce"] call SWLG_stringOr, triggerTimeout _trg, _baseNominal toFixed 1, missionNamespace getVariable ["SWLC_raid_WEST", []],
	round ((_cmd getOrDefault ["raidCooldownUntil", -1]) - time), [_raidS] call SWLC_fnc_adOwner]]] call SWLG_emit;
[[format ["event=refusal|case=cooldown|got=%1", [_cmd, _raidS, 99999] call SWLC_fnc_raidRefusal]]] call SWLG_emit;

// ---- P1: a garrison turns a probe back ----
private _garrison = [_raidS, 20] call SWLG_placeEast;
_cmd set ["raidCooldownUntil", -1];
[_cmd, _raidS] call SWLG_probeOnly;
_end = time + 60;
waitUntil {sleep 1; (count (_cmd getOrDefault ["probe", createHashMap]) > 0) || {time > _end}};
private _p1 = _cmd getOrDefault ["probe", createHashMap];
if (count _p1 == 0) exitWith {[["event=fail_no_probe_1"]] call SWLG_emit};
private _pg = _p1 get "group";
_cmd set ["probeNext", 1e9];
[[format ["event=p1_sent|sector=%1|group=%2|men=%3|spot=%4", [_p1 get "sector"] call SWLC_fnc_adName, groupId _pg, [_pg] call SWLC_fnc_groupMen, _p1 get "spot"]]] call SWLG_emit;
[_pg, _p1 get "spot"] call SWLG_moveGroup;
_pg setVariable ["SWLC_scoutUntil", time];
_end = time + 90;
while {(count (_cmd getOrDefault ["probe", createHashMap]) > 0) && {time < _end}} do {
	{(leader _pg) reveal [_x, 4]} forEach units _garrison;
	sleep 2;
};
[[format ["event=p1_over|still_probing=%1|state=%2|known=%3", count (_cmd getOrDefault ["probe", createHashMap]) > 0, [_pg] call SWLC_fnc_state, [_cmd, _raidS] call SWLC_fnc_probeStrength]]] call SWLG_emit;
{deleteVehicle _x} forEach units _garrison;
deleteGroup _garrison;
[_cmd, _raidS] call SWLG_scrub;
sleep 12;

// ---- P2: nobody home, so the probe buys a raid ----
[west, 3000] call SWLG_fund;
_cmd set ["raidCooldownUntil", -1];
[_cmd, _raidS] call SWLG_probeOnly;
_end = time + 60;
waitUntil {sleep 1; (count (_cmd getOrDefault ["probe", createHashMap]) > 0) || {time > _end}};
private _p2 = _cmd getOrDefault ["probe", createHashMap];
if (count _p2 == 0) exitWith {[["event=fail_no_probe_2"]] call SWLG_emit};
private _pg2 = _p2 get "group";
_cmd set ["probeNext", 1e9];
[[format ["event=p2_sent|sector=%1|group=%2|men=%3", [_p2 get "sector"] call SWLC_fnc_adName, groupId _pg2, [_pg2] call SWLC_fnc_groupMen]]] call SWLG_emit;
[_pg2, [_raidS] call SWLG_edgeSpot] call SWLG_moveGroup;
_pg2 setVariable ["SWLC_scoutUntil", time];
[_cmd, _raidS] call SWLG_scrub;
_end = time + 80;
waitUntil {sleep 1; (count (_cmd getOrDefault ["probe", createHashMap]) == 0) || {time > _end}};
private _rp = [_cmd] call SWLC_fnc_raidOf;
[[format ["event=p2_over|still_probing=%1|raid_by=%2|known=%3|scouted=%4", count (_cmd getOrDefault ["probe", createHashMap]) > 0, _rp getOrDefault ["by", "-"],
	[_cmd, _raidS] call SWLC_fnc_probeStrength, ([_cmd, _raidS] call SWLC_fnc_threatOf) get "scouted"]]] call SWLG_emit;
if (count _rp > 0) then {[_cmd, _rp, "test_cleanup"] call SWLC_fnc_raidStop};
_cmd deleteAt "probe";
_end = time + 50;
waitUntil {sleep 1; count ([_cmd] call SWLC_fnc_raidOf) == 0 || {time > _end}};

// ---- T2: the AI buys a raid and captures ----
SWLC_settings set ["raidExpirySeconds", 480];
SWLC_settings set ["raidCooldownSeconds", 600];
[west, 3000] call SWLG_fund;
_cmd set ["raidCooldownUntil", -1];
{[_x] call SWLG_clearGuer} forEach ([west] call SWLC_fnc_raidFront);
[_cmd, 3] call SWLG_free;
_cmd set ["raidNextCheck", 0];
private _cpBefore = [west] call SWLC_fnc_adSideCP;
private _startAt = time;
_end = time + 90;
waitUntil {
	sleep 0.5;
	if (count ([_cmd] call SWLC_fnc_raidOf) == 0) then {_cpBefore = [west] call SWLC_fnc_adSideCP};
	count ([_cmd] call SWLC_fnc_raidOf) > 0 || {time > _end}
};
private _rec2 = [_cmd] call SWLC_fnc_raidOf;
if (count _rec2 == 0) exitWith {[[format ["event=fail_no_ai_raid|front=%1|cp=%2", [[west] call SWLC_fnc_raidFront] call SWLG_nameOf, [west] call SWLC_fnc_cpFree]]] call SWLG_emit};
_cmd set ["raidNextCheck", 1e9];
private _S2 = _rec2 get "sector";
private _s2Name = [_S2] call SWLC_fnc_adName;
private _trg2 = [_S2, west] call SWLC_fnc_capTrigger;
private _nominal2 = [_S2] call SWLC_fnc_capNominal;
[[format ["event=ai_buy|sector=%1|by=%2|groups=%3|cp_before=%4|cp_after=%5|cost=%6|in_front=%7|marker=%8|mult=%9|seconds=%10", _s2Name, _rec2 get "by", count (_rec2 get "groups"),
	round _cpBefore, round ([west] call SWLC_fnc_adSideCP), SWLC_settings get "raidCostCP", _S2 in _front, missionNamespace getVariable ["SWLC_raid_WEST", []], _S2 getVariable ["SWLC_capMult_WEST", -1], round (time - _startAt)]]] call SWLG_emit;

// The raiders must get there: this tests the raid, not a firefight with whoever is passing.
SWLG_guardRaid = true;
[_rec2, _S2] spawn {
	params ["_rec", "_s"];
	while {SWLG_guardRaid} do {
		{{_x allowDamage false} forEach units _x} forEach (_rec get "groups");
		// EAST groups that happen to be mustering in the square would hold the numbers there.
		{
			private _p = getPosATL _x;
			_x setPosATL [(_p # 0) + 700, (_p # 1) + 700, 0];
		} forEach (allUnits select {side group _x == east && {!isPlayer _x} && {[_s, getPosATL _x, 40] call SWLC_fnc_adInSquare}});
		sleep 3;
	};
};

private _value = [_S2] call SWLC_fnc_adValue;
private _warlords = [west] call SWLC_fnc_adAIWarlords;
private _funds = _warlords apply {_x getVariable ["BIS_WL_funds", 0]};
private _timeoutSeen = false;
_end = time + 520;
while {([_S2] call SWLC_fnc_adOwner) != west && {time < _end} && {count ([_cmd] call SWLC_fnc_raidOf) > 0}} do {
	_funds = _warlords apply {_x getVariable ["BIS_WL_funds", 0]};
	if (!_timeoutSeen && {(triggerTimeoutCurrent _trg2) >= 0}) then {
		_timeoutSeen = true;
		[[format ["event=t2_counting|sector=%1|left=%2|timeout=%3|base_nominal=%4", _s2Name, (triggerTimeoutCurrent _trg2) toFixed 1, triggerTimeout _trg2, _nominal2 toFixed 1]]] call SWLG_emit;
	};
	sleep 0.25;
};
private _flipped = ([_S2] call SWLC_fnc_adOwner) == west;
sleep 5;
private _jump = 0;
{_jump = _jump max ((_x getVariable ["BIS_WL_funds", 0]) - (_funds # _forEachIndex))} forEach _warlords;
[[format ["event=payout|sector=%1|flipped=%2|value=%3|mult=%4|max_jump=%5", _s2Name, _flipped, _value, missionNamespace getVariable ["BIS_WL_CPIncomeMult", 1], round _jump]]] call SWLG_emit;
_end = time + 30;
waitUntil {sleep 1; count ([_cmd] call SWLC_fnc_raidOf) == 0 || {time > _end}};
[[format ["event=t2_after|sector=%1|owner=%2|cleared=%3|in_list=%4|marker=%5|cooldown_left=%6", _s2Name, [_S2] call SWLC_fnc_adOwner, count ([_cmd] call SWLC_fnc_raidOf) == 0,
	[_S2] call SWLG_conquered, missionNamespace getVariable ["SWLC_raid_WEST", []], round ((_cmd getOrDefault ["raidCooldownUntil", -1]) - time)]]] call SWLG_emit;
SWLG_guardRaid = false;

// ---- The cooldown holds: money and a target are there, but no second raid ----
[west, 3000] call SWLG_fund;
_cmd set ["raidNextCheck", 0];
[_cmd, 2] call SWLG_free;
sleep 40;
[[format ["event=done|raid_active=%1|front=%2", count ([_cmd] call SWLC_fnc_raidOf) > 0, [[west] call SWLC_fnc_raidFront] call SWLG_nameOf]]] call SWLG_emit;
