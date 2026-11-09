// Part F gate. Calls every server-side menu handler with no player connected, using an AI warlord as the requester.
// Run with: -Scenario gatef -Overrides "scanBuying=false". The menu's own test settings are set below.
// Proves no script errors and sensible refusals. What a real player sees needs a person: see the hand-off.

waitUntil {sleep 1; !isNil "SWLC_ready" && {!isNil "SWLC_cmd_WEST"}};

SWLG_emit = {
	params ["_fields"];
	diag_log text ((["SWL", "GF", format ["t=%1", round time]] + _fields) joinString "|");
};

private _cmd = missionNamespace getVariable "SWLC_cmd_WEST";
SWLC_settings set ["menuTestAllowAI", true];
SWLC_settings set ["menuKeepGroups", 0];
SWLC_settings set ["menuCooldowns", createHashMap];
SWLC_settings set ["menuCooldownSeconds", 0];

// A step runs in one go, as a real remote call would.
SWLG_step = {
	params ["_step", "_kind", ["_data", []], ["_who", SWLG_unit]];
	private _got = "";
	isNil {_got = [_cmd, _who, _kind, _data] call SWLC_fnc_menuHandle};
	[[format ["event=step"], format ["step=%1", _step], format ["kind=%1", _kind], format ["got=%1", _got]]] call SWLG_emit;
	_got
};

waitUntil {sleep 2; (!isNil {_cmd get "op"} && {(count (_cmd getOrDefault ["groups", []])) >= 4}) || {time > 240}};
SWLG_unit = leader ((_cmd get "groups") # 0);
private _base = [west] call SWLC_fnc_adBase;
private _enemyBase = [east] call SWLC_fnc_adBase;
[[format ["event=start"], format ["groups=%1", count (_cmd get "groups")], format ["unit=%1", SWLG_unit]]] call SWLG_emit;

// Nothing that isn't a real player gets past the front door, on any side.
private _before = count allGroups;
["go", objNull, []] call SWLC_fnc_playerMsg;
["go", SWLG_unit, []] call SWLC_fnc_playerMsg;
["", objNull] call SWLC_fnc_playerMsg;
[[format ["event=front_door"], format ["groups_same=%1", _before == count allGroups]]] call SWLG_emit;

["unknown_kind", "nonsense"] call SWLG_step;
["null_player", "plan", [], objNull] call SWLG_step;

["plan_first", "plan"] call SWLG_step;
SWLC_settings set ["menuCooldownSeconds", 60];
["plan_set", "plan"] call SWLG_step;
["plan_cooled", "plan"] call SWLG_step;
SWLC_settings set ["menuCooldownSeconds", 0];

["raid_null", "raid", [objNull]] call SWLG_step;
["raid_junk", "raid", ["text"]] call SWLG_step;
["raid_own", "raid", [_base]] call SWLG_step;
private _funds = SWLG_unit getVariable ["BIS_WL_funds", 0];
private _front = [west] call SWLC_fnc_raidFront;
// The AI may have a raid running or cooling down. Only money should stand in the way of the paid path.
private _blocked = if (_front isEqualTo []) then {"no_front_sector_yet"} else {[_cmd, _front # 0, 1e6] call SWLC_fnc_raidRefusal};
if (_blocked == "") then {
	SWLG_unit setVariable ["BIS_WL_funds", 0, true];
	["raid_poor", "raid", [_front # 0]] call SWLG_step;
	SWLG_unit setVariable ["BIS_WL_funds", (SWLC_settings get "raidCostCP") + 100, true];
	["raid_paid", "raid", [_front # 0]] call SWLG_step;
	[[format ["event=raid_paid"], format ["left=%1", SWLG_unit getVariable ["BIS_WL_funds", 0]], format ["has_rec=%1", count ([_cmd] call SWLC_fnc_raidOf) > 0]]] call SWLG_emit;
	["raid_second", "raid", [_front # 0]] call SWLG_step;
	isNil {
		private _rec = [_cmd] call SWLC_fnc_raidOf;
		if (count _rec > 0) then {[_cmd, _rec, "test"] call SWLC_fnc_raidStop};
	};
} else {
	[["event=raid_skipped", format ["why=%1", _blocked]]] call SWLG_emit;
};
SWLG_unit setVariable ["BIS_WL_funds", _funds, true];

// Borrowing: groups are taken, marked and walked after the requester until released.
["release_none", "release"] call SWLG_step;
["borrow", "borrow"] call SWLG_step;
private _list = _cmd getOrDefault ["menuBorrowed", []];
[[format ["event=borrow_state"], format ["count=%1", count _list],
	format ["marked=%1", {(_x getVariable ["SWLC_borrowedBy", objNull]) isEqualTo SWLG_unit} count _list],
	format ["state_ok=%1", {([_x] call SWLC_fnc_state) == "Borrowed"} count _list]]] call SWLG_emit;
sleep 45;
[[format ["event=borrow_follow"], format ["count=%1", count _list], format ["ordered=%1", {
	private _order = _x getVariable ["SWLC_order", []];
	_order isNotEqualTo [] && {(((_order # 0) # 0) # 0 distance2D SWLG_unit) < 200}
} count _list]]] call SWLG_emit;
private _taken = _list select {true};
["release", "release"] call SWLG_step;
[[format ["event=release_state"], format ["left=%1", count (_cmd getOrDefault ["menuBorrowed", []])],
	format ["unmarked=%1", {isNil {_x getVariable "SWLC_borrowedBy"}} count _taken],
	format ["not_borrowed=%1", {([_x] call SWLC_fnc_state) != "Borrowed"} count _taken]]] call SWLG_emit;

// Pickup: at least the request and its stages. The drive itself is watched for a few minutes.
["pickup", "pickup"] call SWLG_step;
["pickup_second", "pickup"] call SWLG_step;
for "_i" from 1 to 18 do {
	sleep 10;
	private _rows = _cmd getOrDefault ["menuPickups", []];
	[[format ["event=pickup_stage"], format ["active=%1", count _rows], format ["stage=%1", if (_rows isEqualTo []) then {"-"} else {(_rows # 0) get "stage"}]]] call SWLG_emit;
	if (_rows isEqualTo []) exitWith {};
};

// The requester dies: everything they borrowed comes back on the next tick.
sleep 30;
["borrow_for_death", "borrow"] call SWLG_step;
private _held = (_cmd getOrDefault ["menuBorrowed", []]) select {true};
[[format ["event=before_death"], format ["count=%1", count _held]]] call SWLG_emit;
SWLG_unit setDamage 1;
sleep 25;
[[format ["event=after_death"], format ["had=%1", count _held],
	format ["left=%1", count (_cmd getOrDefault ["menuBorrowed", []])],
	format ["unmarked=%1", {isNil {_x getVariable "SWLC_borrowedBy"}} count _held]]] call SWLG_emit;

["report_empty", "report", []] call SWLG_step;
["report_junk", "report", [["NotAClass_X", [1, 1]], 5, ["O_T_Soldier_F", ["a", "b"]]]] call SWLG_step;
SWLG_unit = leader ((_cmd get "groups") # 0);
private _p = getPosATL _enemyBase;
["report_good", "report", [["O_T_Soldier_F", [(_p # 0) + 50, _p # 1]]]] call SWLG_step;

["defend_null", "defend", []] call SWLG_step;
["defend_enemy", "defend", [_enemyBase]] call SWLG_step;
["defend_own", "defend", [_base]] call SWLG_step;
[[format ["event=defend_bonus"], format ["bonus=%1", [_cmd, _base] call SWLC_fnc_menuDefendBonus]]] call SWLG_emit;


// Hold and go come last: going sends the staged groups in, and borrowing needs them still waiting.
SWLG_unit = leader ((_cmd get "groups") # 0);
["hold", "hold"] call SWLG_step;
private _op = _cmd get "op";
if (!isNil "_op") then {
	[[format ["event=hold_state"], format ["left=%1", round ((_op getOrDefault ["playerHoldUntil", -1]) - time)]]] call SWLG_emit;
};
["hold_again", "hold"] call SWLG_step;
["go", "go"] call SWLG_step;

SWLC_settings set ["ruleCommanderMenu", false];
["menu_off", "plan"] call SWLG_step;
SWLC_settings set ["ruleCommanderMenu", true];

[["event=done"]] call SWLG_emit;
