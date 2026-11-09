// Parts A and C gate: holding a lost sector, and switching between holding it and defending the next one. Run with:
//   -DurationMinutes 18 -Scenario fronta -Overrides "ruleCommitTimer=false;scanBuying=false;holdClearSeconds=60"
// Then: python tools/analyse_round.py <rpt> --gate fronta
//
// WEST is the losing side. Setup hands WEST the first two sectors on the route towards EAST: Y (nearest WEST) and X, gives the rest
// to EAST, puts three WEST groups inside X and flips X to EAST with them there.
// The EAST garrison at X can't be hurt and doesn't shoot, so the holdouts have someone to fight but only die when this script says so.
// WEST's capture of X is slowed right down, and anything that still flips X back is undone, so the fight can't end early by a recapture.
// Stages after X falls: strip the holdouts' ammo, break one group, force fighting at Y and then stop it, wipe the holdouts.
// Fighting at Y is forced by replacing SWLC_fnc_frontFighting, so this tests the goal switching and not part B's detection.

waitUntil {sleep 1; !isNil "SWLC_ready" && {!isNil "SWLC_cmd_WEST"} && {!isNil "SWLC_cmd_EAST"}};

SWLG_emit = {
	params ["_fields"];
	diag_log text ((["SWL", "GFA", format ["t=%1", round time]] + _fields) joinString "|");
};

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
	[[format ["event=took|side=%1|sector=%2", _side, [_s] call SWLC_fnc_adName]]] call SWLG_emit;
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

SWLG_moveGroup = {
	params ["_g", "_p"];
	{_x setPosATL [(_p # 0) + (random 16) - 8, (_p # 1) + (random 16) - 8, 0]} forEach units _g;
};

SWLG_placeEast = {
	params ["_s", "_n"];
	private _g = createGroup [east, true];
	private _c = [_s] call SWLC_fnc_adPos;
	for "_i" from 1 to _n do {
		private _u = _g createUnit ["O_T_Soldier_F", _c, [], 25, "NONE"];
		_u allowDamage false;
		_u disableAI "PATH";
		removeAllWeapons _u; // combat mode alone didn't stop them shooting the holdouts in the first run
	};
	_g setCombatMode "BLUE";
	_g
};

SWLG_holdouts = {
	params ["_cmd"];
	((_cmd getOrDefault ["holdRec", createHashMap]) getOrDefault ["groups", []]) select {!isNull _x}
};

SWLG_waitTo = {
	params ["_t"];
	waitUntil {sleep 1; time >= _t};
};

// Every commander group the holdouts' fights could pull on, with enough to tell whether each stayed.
SWLG_tracker = {
	params ["_cmd", "_xS"];
	private _c = [_xS] call SWLC_fnc_adPos;
	while {isNil "SWLG_over"} do {
		private _target = _cmd get "target";
		private _goal = _cmd getOrDefault ["frontGoal", []];
		private _holdouts = [_cmd] call SWLG_holdouts;
		[[format ["event=tick|target=%1|goal=%2|at=%3|holdouts=%4|owner_x=%5",
			if (isNull _target) then {"none"} else {[_target] call SWLC_fnc_adName},
			if (_goal isEqualTo []) then {"none"} else {_goal # 0},
			if (_goal isEqualTo []) then {"-"} else {[_goal # 1] call SWLC_fnc_adName},
			count _holdouts,
			[_xS] call SWLC_fnc_adOwner]]] call SWLG_emit;
		{
			[[format ["event=track|group=%1|state=%2|men=%3|dist_x=%4|broken=%5",
				groupId _x, [_x] call SWLC_fnc_state, [_x] call SWLC_fnc_groupMen, round (leader _x distance2D _c), _x getVariable ["SWLC_holdoutBroken", false]]]] call SWLG_emit;
		} forEach _holdouts;
		sleep 10;
	};
};

sleep 15;
private _cmd = SWLC_cmd_WEST;
private _route = [] call SWLG_path;
[[format ["event=route|sectors=%1", (_route apply {[_x] call SWLC_fnc_adName}) joinString ","]]] call SWLG_emit;
if (count _route < 2) exitWith {
	[["event=fail_short_route"]] call SWLG_emit;
	[["event=done"]] call SWLG_emit;
};

private _yS = _route # 0;
private _xS = _route # 1;
{[east, _x] call SWLG_take} forEach (_route select [2, 99]);
[west, _yS] call SWLG_take;
[west, _xS] call SWLG_take;
_xS setVariable ["SWLC_capMult_WEST", 100];

// The commander needs a few passes with X in its owned list, and some groups to send.
// Fund first and wait for full groups, because a group that has just spawned is one man and dies at once.
[west, 4000] call SWLG_fund;
private _end = time + 240;
private _pool = [];
waitUntil {
	sleep 2;
	_pool = (_cmd get "groups") select {
		[_x] call SWLC_fnc_resMayTouch
		&& {!(([_x] call SWLC_fnc_state) in ["Picket", "Reserve", "Raiding", "Probing", "Hunting"])}
		&& {vehicle leader _x == leader _x}
		&& {([_x] call SWLC_fnc_groupMen) >= 4}
	};
	(count _pool) >= 5 || {time > _end}
};
sleep 10;

SWLC_fnc_frontFighting = {
	params ["_s"];
	!isNil "SWLG_fightAt" && {_s isEqualTo SWLG_fightAt}
};

private _inside = _pool select [0, 3];
private _c = [_xS] call SWLC_fnc_adPos;
{[_x, [_c, random 360, 20 + random 40] call SWLC_fnc_offset] call SWLG_moveGroup} forEach _inside;
[_xS, 12] call SWLG_placeEast;
_xS setVariable ["BIS_WL_sectorSide", east, true];
[[format ["event=x_fell|x=%1|y=%2|groups=%3|pool=%4", [_xS] call SWLC_fnc_adName, [_yS] call SWLC_fnc_adName, count _inside, count _pool]]] call SWLG_emit;
private _t0 = time;

[_cmd, _xS] spawn SWLG_tracker;
// A recapture would end the holdout early. West can't capture quickly with the slowed trigger, this catches the rest.
[_xS] spawn {
	params ["_xS"];
	while {isNil "SWLG_over"} do {
		if (([_xS] call SWLC_fnc_adOwner) == west) then {
			_xS setVariable ["BIS_WL_sectorSide", east, true];
			[["event=reflip"]] call SWLG_emit;
		};
		sleep 1;
	};
};

// Stage 1: the holdouts run low, so a resupply should be bought.
[_t0 + 150] call SWLG_waitTo;
{
	{
		private _u = _x;
		// Takes every spare magazine and leaves what is loaded.
		{_u removeMagazines _x} forEach ((magazines _u) arrayIntersect (magazines _u));
	} forEach (units _x select {alive _x});
} forEach ([_cmd] call SWLG_holdouts);
[[format ["event=low|groups=%1", count ([_cmd] call SWLG_holdouts)]]] call SWLG_emit;

// Stage 2: break the biggest holdout group.
[_t0 + 300] call SWLG_waitTo;
private _live = [_cmd] call SWLG_holdouts;
if (_live isNotEqualTo []) then {
	private _g = ([_live, [], {[_x] call SWLC_fnc_groupMen}, "DESCEND"] call BIS_fnc_sortBy) # 0;
	private _men = (units _g) select {alive _x};
	private _keep = 1 max floor ((_g getVariable ["SWLC_holdoutMen0", count _men]) * 0.3);
	{_x setDamage 1} forEach (_men select [_keep, 99]);
	[[format ["event=break|group=%1|killed=%2|left=%3", groupId _g, ((count _men) - _keep) max 0, _keep]]] call SWLG_emit;
};

// Stage 3: part C. Fighting starts at Y, then stops.
[_t0 + 390] call SWLG_waitTo;
SWLG_fightAt = _yS;
[[format ["event=fight_y_on|y=%1", [_yS] call SWLC_fnc_adName]]] call SWLG_emit;
[_t0 + 480] call SWLG_waitTo;
SWLG_fightAt = objNull;
[["event=fight_y_off"]] call SWLG_emit;

// Stage 4: the holdouts die, and the reinforcements carry on as a counterattack.
[_t0 + 620] call SWLG_waitTo;
{
	{_x setDamage 1} forEach (units _x select {alive _x});
} forEach ([_cmd] call SWLG_holdouts);
[["event=wiped"]] call SWLG_emit;

[_t0 + 840] call SWLG_waitTo;
SWLG_over = true;
_xS setVariable ["SWLC_capMult_WEST", nil];
[["event=done"]] call SWLG_emit;
