// Rules variant, part G: the commander values sectors by what they unlock and by the supply chain.
// Everything read here is public: who owns what, and what each sector type gives.
#include "macros.hpp"

SWLC_fnc_stratOn = { CFG("rulesVariant") && {CFG("ruleStrategy")} };
SWLC_fnc_stratFortressOn = { CFG("rulesVariant") && {CFG("ruleFortressAware")} };

// The sectors a side reaches from its base through its own sectors, leaving out _skip.
SWLC_fnc_stratReach = {
	params ["_side", ["_skip", objNull]];
	private _base = [_side] call SWLC_fnc_adBase;
	if (isNull _base || {_skip isEqualTo _base}) exitWith {[]};
	private _owned = [_side] call SWLC_fnc_adOwned;
	private _seen = [_base];
	private _queue = [_base];
	while {_queue isNotEqualTo []} do {
		private _at = _queue deleteAt 0;
		{
			if (!(_x in _seen) && {_x isNotEqualTo _skip} && {_x in _owned}) then {
				_seen pushBack _x;
				_queue pushBack _x;
			};
		} forEach ([_at] call SWLC_fnc_adLinks);
	};
	_seen
};

// The sectors that have a road home now and would lose it if _s fell. One already cut off doesn't count.
SWLC_fnc_stratCutBy = {
	params ["_side", "_s"];
	if (([_s] call SWLC_fnc_adOwner) != _side || {[_s] call SWLC_fnc_adIsBase}) exitWith {[]};
	([_side] call SWLC_fnc_stratReach) - ([_side, _s] call SWLC_fnc_stratReach) - [_s]
};

// What a sector unlocks: its type on this map, plus Warlords' own services (airfield, naval) on any map.
SWLC_fnc_stratSectorLetters = {
	params ["_s"];
	private _letters = +(_s getVariable ["SWLC_econLetters", []]);
	{_letters pushBackUnique _x} forEach ((_s getVariable ["SWLC_econNative", []]) select {_x in CFG("stratLetterWeights")});
	_letters
};

SWLC_fnc_stratLettersOf = {
	params ["_sectors"];
	private _all = [];
	{{_all pushBackUnique _x} forEach ([_x] call SWLC_fnc_stratSectorLetters)} forEach _sectors;
	_all
};

// Extra value of a sector to _side beyond its Warlords value.
// Unlocks count in full unless the side would still have them. An enemy sector also counts for what taking it denies.
SWLC_fnc_stratWorth = {
	params ["_side", "_s"];
	if !([] call SWLC_fnc_stratOn) exitWith {0};
	private _weights = CFG("stratLetterWeights");
	private _letters = [_s] call SWLC_fnc_stratSectorLetters;
	private _owner = [_s] call SWLC_fnc_adOwner;
	private _have = if (_owner == _side) then {
		[[_side, _s] call SWLC_fnc_stratReach] call SWLC_fnc_stratLettersOf
	} else {
		[_side] call SWLC_fnc_econCaps
	};
	private _worth = 0;
	{
		private _w = _weights getOrDefault [_x, 0];
		_worth = _worth + ([_w, _w * CFG("stratHaveFactor")] select (_x in _have));
	} forEach _letters;
	if !(_owner in [west, east]) exitWith {_worth};

	private _reach = [_owner] call SWLC_fnc_stratReach;
	private _after = [_owner, _s] call SWLC_fnc_stratReach;
	_worth = _worth + (count (_reach - _after - [_s])) * CFG("stratCutWeight");
	private _lost = ([_reach] call SWLC_fnc_stratLettersOf) - ([_after] call SWLC_fnc_stratLettersOf);
	if (_owner == _side) then {_lost = _lost - _letters};
	{_worth = _worth + (_weights getOrDefault [_x, 0]) * CFG("stratCutLetterFactor")} forEach _lost;
	_worth
};

// Logged when the commander's pick changes, so a soak can compare it against what else was on offer.
SWLC_fnc_stratLogChoice = {
	params ["_cmd", "_best", "_avail"];
	if !([] call SWLC_fnc_stratOn) exitWith {};
	private _side = _cmd get "side";
	private _worths = _avail apply {[_side, _x] call SWLC_fnc_stratWorth};
	private _mean = 0;
	{_mean = _mean + _x} forEach _worths;
	_mean = _mean / ((count _worths) max 1);
	private _owner = [_best] call SWLC_fnc_adOwner;
	private _cut = if (_owner in [west, east]) then {count ([_owner, _best] call SWLC_fnc_stratCutBy)} else {0};
	private _top = selectMax _worths;
	private _n = (count _worths) max 1;
	private _shareAbove = ({_x > _mean} count _worths) / _n;
	private _shareTop = ({_x >= (_top - 0.05)} count _worths) / _n;
	["C_STRAT", [["side", _side], ["event", "choice"], ["sector", [_best] call SWLC_fnc_adName], ["worth", ([_side, _best] call SWLC_fnc_stratWorth) toFixed 1],
		["mean", _mean toFixed 1], ["max", (selectMax _worths) toFixed 1], ["options", count _avail], ["cut", _cut], ["letters", ([_best] call SWLC_fnc_stratSectorLetters) joinString "+"], ["share_above", _shareAbove toFixed 2], ["share_top", _shareTop toFixed 2]]] call SWLC_fnc_log;
};

// How many groups have to be ready at the rally. The enemy's fortress base takes more.
SWLC_fnc_stratGoCount = {
	params ["_cmd", "_op"];
	private _go = CFG("goMinGroups");
	if ([] call SWLC_fnc_stratFortressOn && {[_op get "target"] call SWLC_fnc_adIsBase}) then {_go = _go + CFG("stratBaseGoExtra")};
	_go
};

// Bringing the right kit to the final fight, whatever the board says about the base.
SWLC_fnc_stratPlan = {
	params ["_w", "_plan"];
	if !([] call SWLC_fnc_stratFortressOn) exitWith {};
	if !([_w get "target"] call SWLC_fnc_adIsBase) exitWith {};
	_plan set ["atWanted", (_plan get "atWanted") max CFG("stratBaseAtWanted")];
	_plan set ["combatVehicle", true];
	_plan set ["smoke", true];
};

// Attacking the base too thin wastes the side's men on its guns.
SWLC_fnc_stratBasePenalty = {
	params ["_cmd", "_s", "_enemyBase"];
	if !([] call SWLC_fnc_stratFortressOn) exitWith {0};
	if (_s isNotEqualTo _enemyBase) exitWith {0};
	if (([_cmd get "groups"] call SWLC_fnc_groupsMen) >= CFG("stratBaseMinMen")) exitWith {0};
	CFG("stratBaseEarlyPenalty")
};
