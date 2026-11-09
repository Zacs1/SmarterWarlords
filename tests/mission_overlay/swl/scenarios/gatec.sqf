// Part C checks: income follows the curve, and capabilities switch off when a chain is cut and come
// back when it is restored. Ownership is written directly so a short round can prove both. Run with:
//   -Scenario gatec -Overrides "rulesVariant=true"
// Then: python tools/gates_c.py <rpt> --gate gatec

waitUntil {sleep 1; !isNil "SWLC_ready"};

SWLG_emit = {
	params ["_type", "_fields"];
	diag_log text ((["SWL", _type, format ["t=%1", round time]] + _fields) joinString "|");
};

waitUntil {sleep 1; !isNil "SWLC_econReady" && {!isNil "SWLC_caps_WEST"}};

SWLG_settle = 14;   // one commander tick and a little more
SWLG_nonBase = SWLC_sectors select {!([_x] call SWLC_fnc_adIsBase)};

SWLG_give = {
	params ["_s", "_side"];
	_s setVariable ["BIS_WL_sectorSide", _side, true];
};

SWLG_special = {
	params ["_s"];
	private _l = _s getVariable ["BIS_WL_sectorSpecial", []];
	if (_l isEqualTo []) then {"none"} else {_l joinString "+"}
};

SWLG_caps = {
	private _l = missionNamespace getVariable ["SWLC_caps_WEST", []];
	if (_l isEqualTo []) then {"none"} else {_l joinString "+"}
};

// Reachable from the WEST base over the links, treating _skip as not owned.
SWLG_reach = {
	params ["_skip"];
	private _base = [west] call SWLC_fnc_adBase;
	private _seen = [_base];
	private _queue = [_base];
	while {_queue isNotEqualTo []} do {
		private _s = _queue deleteAt 0;
		{
			if (!(_x in _seen) && {_x != _skip} && {_x in SWLG_nonBase}) then {
				_seen pushBack _x;
				_queue pushBack _x;
			};
		} forEach ([_s] call SWLC_fnc_adLinks);
	};
	_seen
};

// Income: hand WEST sectors one at a time, richest first, and log what each pays.
private _ordered = [SWLG_nonBase, [], {_x getVariable "SWLC_econValue"}, "DESCEND"] call BIS_fnc_sortBy;
["GC", [format ["event=start|sectors=%1|base_value=%2", count _ordered, [[west] call SWLC_fnc_adBase] call SWLC_fnc_adValue]]] call SWLG_emit;

{[_x, east] call SWLG_give} forEach SWLG_nonBase;
sleep SWLG_settle;

{
	[_x, west] call SWLG_give;
	sleep SWLG_settle;
	private _owned = _ordered select [0, _forEachIndex + 1];
	private _base = [west] call SWLC_fnc_adBase;
	private _values = _owned apply {[_x] call SWLC_fnc_adValue};
	private _originals = _owned apply {_x getVariable "SWLC_econValue"};
	private _sum = [_base] call SWLC_fnc_adValue;
	{_sum = _sum + _x} forEach _values;
	["GC", [format ["event=curve|n=%1|base=%2|values=%3|originals=%4|income=%5", _forEachIndex + 1, [_base] call SWLC_fnc_adValue, _values joinString ",", _originals joinString ",", _sum]]] call SWLG_emit;
} forEach _ordered;

// A sector whose loss leaves something else cut off, preferring one that strands a capability.
private _candidates = [];
{
	private _cut = _x;
	private _strand = SWLG_nonBase - [_cut] - ([_cut] call SWLG_reach);
	if (_strand isNotEqualTo []) then {
		private _letters = [];
		{_letters append (_x getVariable ["SWLC_econLetters", []])} forEach _strand;
		_candidates pushBack [count _letters, _cut, _strand];
	};
} forEach SWLG_nonBase;

if (_candidates isEqualTo []) exitWith {
	["GC", ["event=skip|reason=no_cut_vertex"]] call SWLG_emit;
	["GC", ["event=done"]] call SWLG_emit;
};

_candidates sort false;
(_candidates # 0) params ["_lettersCount", "_cut", "_strand"];
private _cutName = [_cut] call SWLC_fnc_adName;
private _strandNames = (_strand apply {[_x] call SWLC_fnc_adName}) joinString ",";
private _lost = [];
{_lost append (_x getVariable ["SWLC_econLetters", []])} forEach _strand;
_lost = _lost arrayIntersect _lost;

// Letters that only the stranded sectors give, so the check isn't fooled by a duplicate elsewhere.
private _kept = [];
{_kept append (_x getVariable ["SWLC_econLetters", []])} forEach (([_cut] call SWLG_reach) - [_cut]);
private _unique = _lost - _kept;

private _report = {
	params ["_stage"];
	private _resupply = [west, [_strand # 0] call SWLC_fnc_adPos] call SWLC_fnc_econResupplyAllowed;
	private _armour = [west, "M"] call SWLC_fnc_econHasCapability;
	["GC", [format ["event=chain|stage=%1|cut=%2|stranded=%3|unique=%4|caps=%5|special=%6|military=%7|resupply_there=%8|cap_owned=%9",
		_stage, _cutName, _strandNames, _unique joinString "+", [] call SWLG_caps, [_strand # 0] call SWLG_special, _armour, _resupply,
		({([_x] call SWLC_fnc_adOwner) == west} count _strand)]]] call SWLG_emit;
};

["before"] call _report;
[_cut, east] call SWLG_give;
sleep SWLG_settle;
["cut"] call _report;
[_cut, west] call SWLG_give;
sleep SWLG_settle;
["restored"] call _report;

// The discounts the commander's buying relies on.
private _base = [[west] call SWLC_fnc_adBase] call SWLC_fnc_adPos;
["GC", [format ["event=query|price_base=%1|squadcap=%2|scan=%3",
	[west, "B_Soldier_F", _base] call SWLC_fnc_econPriceMult, [west] call SWLC_fnc_econSquadCap, [west] call SWLC_fnc_econScanCost]]] call SWLG_emit;
["GC", ["event=done"]] call SWLG_emit;
