// Rules variant, parts A and C: a side that loses a sector with its groups still inside keeps the fight there.
// The groups inside become holdouts: they stay in the state "Defending" with SWLC_holdout set, and the side keeps the
// sector as its target so reinforcements go to them ahead of any other job. Part C switches the side's goal to defending
// the next sector when fighting starts there, and back once that sector is clear.
//
// _cmd get "frontGoal" is [], ["hold", X], ["counter", X] or ["defend", Y].
//
// Warlords kills AI in a sector that is neither on the side's conquered list nor its target. The list is only ever added
// to, so a sector the side captured is safe already. Anything else is added here while the holdouts need it.
#include "macros.hpp"

{SWLC_radioLines set _x} forEach [
	["holdvote", ["Our people are still holding %1. Vote %1 so we can reinforce them.", "%1 has fallen with our men inside. Put your vote on %1 and we'll go get them.", "Holdouts in %1. They need %1 voted as our target to get help."]],
	["holdformed", ["We've lost %1 but we're still in there. Holding on.", "%1 has fallen with our people inside. They're staying.", "Enemy has %1. Our groups inside are holding."]],
	["holdgoal_hold", ["Holding %1. All free units get to them.", "Priority is %1. Reinforce the holdouts.", "Holding %1, reinforcements go there first."]],
	["holdgoal_counter", ["Counterattacking %1.", "Holdouts are gone. Counterattack %1.", "We're taking %1 back."]],
	["holdgoal_defend", ["Defending %1. Expel them.", "Enemy at %1, everyone not fighting defends it.", "Defending %1, push them out."]],
	["holdsupply", ["Resupply on the way to %1.", "Ammo drop coming in at %1.", "Crate inbound for the holdouts at %1."]]
];
{CFG("radioCooldowns") set _x} forEach [["holdformed", 20], ["holdgoal_hold", 20], ["holdgoal_counter", 20], ["holdgoal_defend", 20], ["holdsupply", 30], ["holdvote", 30]];

SWLC_holdSkipStates = ["Raiding", "Probing", "Borrowed", "Pickup", "Hunting"];

SWLC_fnc_holdOn = { CFG("rulesVariant") && {CFG("ruleHoldouts")} };

SWLC_fnc_holdLog = {
	params ["_cmd", "_event", ["_extra", []]];
	private _name = (_cmd getOrDefault ["holdRec", createHashMap]) getOrDefault ["name", "-"];
	["C_HOLD", [["side", _cmd get "side"], ["event", _event], ["sector", _name]] + _extra] call SWLC_fnc_log;
};

// Parts B and D provide these. Until they exist the group check falls back on combat mode and no sector counts as fighting.
SWLC_fnc_holdFighting = {
	params ["_g"];
	if (isNil "SWLC_fnc_groupFighting") exitWith {(behaviour leader _g) == "COMBAT"};
	[_g] call SWLC_fnc_groupFighting
};

SWLC_fnc_holdFront = {
	params ["_s"];
	if (isNil "SWLC_fnc_frontFighting") exitWith {false};
	[_s] call SWLC_fnc_frontFighting
};

SWLC_fnc_holdUndoAdd = {
	params ["_cmd", "_s"];
	private _list = _cmd getOrDefault ["holdUndo", []];
	_list pushBack [_s, time + CFG("holdoutUnprotectGrace")];
	_cmd set ["holdUndo", _list];
};

// A protected sector comes off the list a little after the holdouts are done, so the men leaving aren't killed on the way out.
SWLC_fnc_holdUndoTick = {
	params ["_cmd"];
	private _list = _cmd getOrDefault ["holdUndo", []];
	if (_list isEqualTo []) exitWith {};
	private _side = _cmd get "side";
	private _current = (_cmd getOrDefault ["holdRec", createHashMap]) getOrDefault ["sector", objNull];
	private _keep = [];
	{
		_x params ["_s", "_at"];
		if (time < _at || {_s isEqualTo _current}) then {
			_keep pushBack _x;
		} else {
			if (([_s] call SWLC_fnc_adOwner) != _side && {(_cmd get "target") isNotEqualTo _s}) then {[_side, _s] call SWLC_fnc_adUnprotectSector};
		};
	} forEach _list;
	_cmd set ["holdUndo", _keep];
};

SWLC_fnc_holdInside = {
	params ["_cmd", "_s"];
	private _m = CFG("holdoutMargin");
	(_cmd get "groups") select {
		[_x] call SWLC_fnc_resMayTouch
		&& {!(([_x] call SWLC_fnc_state) in SWLC_holdSkipStates)}
		&& {[_s, getPosATL leader _x, _m] call SWLC_fnc_adInSquare}
	}
};

// Cover around a point, best first: buildings with room inside, then the terrain's best spots.
SWLC_fnc_holdCover = {
	params ["_s", ["_centre", []], ["_radius", -1]];
	private _c = if (_centre isEqualTo []) then {[_s] call SWLC_fnc_adPos} else {_centre};
	private _r = if (_radius < 0) then {CFG("holdoutCoverRadius")} else {_radius};
	private _out = (nearestObjects [_c, ["House", "Building"], _r]) select {count (_x buildingPos -1) >= 2};
	_out = _out apply {private _p = getPosATL _x; [_p # 0, _p # 1, 0]};
	if (_out isEqualTo []) then {
		_out = ([_c, _r] call SWLC_fnc_stagingPlaces) apply {[(_x # 0) # 0, (_x # 0) # 1, 0]};
	};
	_out = _out select {!surfaceIsWater _x};
	if (_out isEqualTo []) then {_out = [[_c # 0, _c # 1, 0]]};
	_out select [0, 12]
};

// Sector lost since last time, or the target went to the enemy: if our groups are inside, they stay.
SWLC_fnc_holdDetect = {
	params ["_cmd"];
	private _side = _cmd get "side";
	private _enemy = [_side] call SWLC_fnc_adEnemySide;
	private _owned = [_side] call SWLC_fnc_adOwned;
	private _target = _cmd get "target";
	private _targetOwner = if (isNull _target) then {sideUnknown} else {[_target] call SWLC_fnc_adOwner};
	private _lost = (_cmd getOrDefault ["holdPrevOwned", []]) select {!(_x in _owned) && {([_x] call SWLC_fnc_adOwner) == _enemy}};
	if (!isNull _target && {_target isEqualTo (_cmd getOrDefault ["holdPrevTarget", objNull])} && {_targetOwner == _enemy}
		&& {(_cmd getOrDefault ["holdPrevTargetOwner", _enemy]) != _enemy} && {!(_target in _lost)}) then {
		_lost pushBack _target;
	};
	_cmd set ["holdPrevOwned", _owned];
	_cmd set ["holdPrevTarget", _target];
	_cmd set ["holdPrevTargetOwner", _targetOwner];
	if (count (_cmd getOrDefault ["holdRec", createHashMap]) > 0) exitWith {};
	private _at = _lost findIf {!([_x] call SWLC_fnc_adIsBase) && {([_cmd, _x] call SWLC_fnc_holdInside) isNotEqualTo []}};
	if (_at >= 0) then {[_cmd, _lost # _at] call SWLC_fnc_holdStart};
};

SWLC_fnc_holdSetGoal = {
	params ["_cmd", "_goal"];
	private _old = _cmd getOrDefault ["frontGoal", []];
	if (_old isEqualTo _goal) exitWith {};
	_cmd set ["frontGoal", _goal];
	private _kindOf = {if (_this isEqualTo []) then {"none"} else {_this # 0}};
	private _name = if (_goal isEqualTo []) then {"-"} else {[_goal # 1] call SWLC_fnc_adName};
	[_cmd, "goal_change", [["from", _old call _kindOf], ["to", _goal call _kindOf], ["at", _name]]] call SWLC_fnc_holdLog;
	if (_goal isNotEqualTo []) then {[_cmd get "side", "holdgoal_" + (_goal # 0), [_name]] call SWLC_fnc_radio};
};

SWLC_fnc_holdStart = {
	params ["_cmd", "_s"];
	private _side = _cmd get "side";
	private _groups = [_cmd, _s] call SWLC_fnc_holdInside;
	private _seq = (_cmd getOrDefault ["holdSeq", 0]) + 1;
	_cmd set ["holdSeq", _seq];
	private _added = [_side, _s] call SWLC_fnc_adProtectSector;
	private _rec = createHashMapFromArray [
		["id", _seq], ["sector", _s], ["name", [_s] call SWLC_fnc_adName], ["groups", []], ["formed", time], ["added", _added],
		["targetBy", time + CFG("holdoutVoteGrace")], ["slot", 0], ["spots", [_s] call SWLC_fnc_holdCover],
		["resupplyNext", time + CFG("holdoutResupplyFirstDelay")], ["crates", []], ["defendY", objNull], ["clearSince", -1], ["wiped", false]
	];
	_cmd set ["holdRec", _rec];
	{[_cmd, _x, "holdMake", {[_cmd, _rec, _x] call SWLC_fnc_holdMake}] call SWLC_fnc_resGuarded} forEach _groups;
	private _target = _cmd get "target";
	private _was = if (isNull _target) then {"none"} else {[_target] call SWLC_fnc_adName};
	_cmd set ["preferredTarget", _s];
	if (_target isNotEqualTo _s) then {
		// A human side's vote is theirs: ask for X, don't cancel what they picked.
		if ([_side] call SWLC_fnc_adSideHasPlayers) exitWith {[_side, "holdvote", [_rec get "name"]] call SWLC_fnc_radio};
		// Anyone attacking the old target gets out first, or Warlords' kill loop finds them there.
		if (!isNull _target && {[] call SWLC_fnc_commitOn}) exitWith {[_cmd, _target, "hold"] call SWLC_fnc_commitLeave};
		[_side] call SWLC_fnc_adForceRevote;
	};
	[_cmd, "formed", [["groups", count (_rec get "groups")], ["men", [_rec get "groups"] call SWLC_fnc_groupsMen], ["target_was", _was], ["protected", _added]]] call SWLC_fnc_holdLog;
	[_side, "holdformed", [_rec get "name"]] call SWLC_fnc_radio;
	[_cmd, ["hold", _s]] call SWLC_fnc_holdSetGoal;
};

// True while the side is holding X or counterattacking it: everything free goes there first.
SWLC_fnc_holdPriority = {
	params ["_cmd"];
	((_cmd getOrDefault ["frontGoal", []]) param [0, ""]) in ["hold", "counter"]
};

SWLC_fnc_holdMake = {
	params ["_cmd", "_rec", "_g"];
	[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
	if ((_g getVariable ["SWLC_lambsTask", ""]) != "") then {[_g, false] call SWLC_fnc_lambsRelease};
	_g setVariable ["SWLC_picketSector", nil];
	_g setVariable ["SWLC_digUntil", -1];
	// A defence record stands its groups down when the sector's threat ends, which would release a holdout.
	{
		private _list = _y getOrDefault ["groups", []];
		private _i = _list find _g;
		if (_i >= 0) then {_list deleteAt _i};
	} forEach (_cmd getOrDefault ["threats", createHashMap]);
	_g setVariable ["SWLC_holdout", true];
	_g setVariable ["SWLC_holdoutMen0", [_g] call SWLC_fnc_groupMen];
	_g setVariable ["SWLC_holdoutBroken", false];
	private _spots = _rec get "spots";
	private _i = _rec get "slot";
	_rec set ["slot", _i + 1];
	private _spot = _spots # (_i mod count _spots);
	[_g, "Defending", _spot, "holdout"] call SWLC_fnc_setState;
	_g setVariable ["SWLC_patrolAt", time];
	[_g, [[_spot, "MOVE", 15], [_spot, "HOLD", 0]], "AWARE", "FULL", "WEDGE", "YELLOW"] call SWLC_fnc_adSetOrder;
	(_rec get "groups") pushBackUnique _g;
	[_cmd, "holdout", [["group", groupId _g], ["men", [_g] call SWLC_fnc_groupMen]]] call SWLC_fnc_holdLog;
};

// The nearest cover on the X side of the way to the nearest owned sector, never further than the limit from X.
SWLC_fnc_holdFallback = {
	params ["_cmd", "_rec"];
	private _s = _rec get "sector";
	private _c = [_s] call SWLC_fnc_adPos;
	private _owned = [_cmd get "side"] call SWLC_fnc_adOwned;
	private _b = if (_owned isEqualTo []) then {random 360} else {[_c, [([_owned, _c] call SWLC_fnc_adNearest)] call SWLC_fnc_adPos] call SWLC_fnc_bearing};
	private _max = CFG("holdoutFallbackMax");
	private _d = ((([_s] call SWLC_fnc_adSize) / 2) + CFG("holdoutFallbackBeyond")) min _max;
	private _p = [_c, _b, _d] call SWLC_fnc_offset;
	private _spots = ([_s, _p, CFG("holdoutCoverSearch")] call SWLC_fnc_holdCover) select {(_x distance2D _c) <= _max};
	if (_spots isNotEqualTo []) exitWith {_spots # 0};
	if (surfaceIsWater _p) exitWith {[_c # 0, _c # 1, 0]};
	[_p # 0, _p # 1, 0]
};

SWLC_fnc_holdBreak = {
	params ["_cmd", "_rec", "_g"];
	private _spot = [_cmd, _rec] call SWLC_fnc_holdFallback;
	if ((_g getVariable ["SWLC_lambsTask", ""]) != "") then {[_g, false] call SWLC_fnc_lambsRelease};
	_g setVariable ["SWLC_holdoutBroken", true];
	[_g, "Defending", _spot, "holdout_fallback"] call SWLC_fnc_setState;
	_g setVariable ["SWLC_patrolAt", time];
	[_g, [[_spot, "MOVE", 15], [_spot, "HOLD", 0]], "AWARE", "FULL", "WEDGE", "YELLOW"] call SWLC_fnc_adSetOrder;
	[_cmd, "broke", [["group", groupId _g], ["men", [_g] call SWLC_fnc_groupMen], ["dist_x", round (_spot distance2D ([_rec get "sector"] call SWLC_fnc_adPos))], ["limit", CFG("holdoutFallbackMax")]]] call SWLC_fnc_holdLog;
};

// LAMBS and combat block the normal rearming trip, so a holdout close to a delivered crate takes from it where he stands.
SWLC_fnc_holdRestock = {
	params ["_cmd", "_rec", "_g"];
	if !(CFG("holdoutRestock")) exitWith {};
	if ((_rec get "crates") isEqualTo []) exitWith {};
	if (time < (_g getVariable ["SWLC_holdRestockNext", 0])) exitWith {};
	_g setVariable ["SWLC_holdRestockNext", time + CFG("holdoutRestockSeconds")];
	if ((_g getVariable ["SWLC_lambsTask", ""]) == "" && {(behaviour leader _g) != "COMBAT"}) exitWith {};
	private _men = ([_g] call SWLC_fnc_alive) select {isNull objectParent _x};
	private _r = CFG("rearmRadius");
	private _crates = (_rec get "crates") select {alive _x};
	// One man per turn, but a man no crate can help mustn't hold up the rest.
	for "_i" from 1 to 6 do {
		private _need = [_men] call SWLC_fnc_squadRearmNeed;
		if (_need isEqualTo []) exitWith {};
		_need params ["_u", "_kind", "_mags", "_take"];
		private _at = _crates findIf {(_x distance2D _u) <= _r && {([magazineCargo _x, _mags] call SWLC_fnc_squadRearmFirst) != ""}};
		if (_at >= 0) exitWith {
			private _crate = _crates # _at;
			private _class = [magazineCargo _crate, _mags] call SWLC_fnc_squadRearmFirst;
			private _got = [_u, _crate, "crate", _class, _take] call SWLC_fnc_squadRearmTake;
			if (_got > 0) then {[_cmd, "restock", [["group", groupId _g], ["kind", _kind], ["n", _got]]] call SWLC_fnc_holdLog};
		};
		_men = _men - [_u];
	};
};

// One holdout's turn: fall back if broken, otherwise dig in and restock.
SWLC_fnc_holdGroupTick = {
	params ["_cmd", "_rec", "_g"];
	private _men0 = _g getVariable ["SWLC_holdoutMen0", 0];
	private _broken = _g getVariable ["SWLC_holdoutBroken", false];
	if (!_broken && {_men0 > 0} && {(([_g] call SWLC_fnc_groupMen) / _men0) <= CFG("holdoutBreakFraction")}) exitWith {
		[_cmd, _rec, _g] call SWLC_fnc_holdBreak;
	};
	[_cmd, _rec, _g] call SWLC_fnc_holdRestock;
	if (_broken || {!SWLC_lambs} || {!CFG("squadLambs")} || {!CFG("holdoutGarrison")}) exitWith {};
	if ((_g getVariable ["SWLC_lambsTask", ""]) != "" || {time < (_g getVariable ["SWLC_lambsNext", 0])}) exitWith {};
	if ((time - (_g getVariable ["SWLC_stateSince", time])) < CFG("holdoutSettleSeconds")) exitWith {};
	if (!isNull objectParent leader _g) exitWith {};
	private _goal = _g getVariable ["SWLC_goal", []];
	if (_goal isEqualTo [] || {(leader _g distance2D _goal) > CFG("lambsHoldReach")}) exitWith {};
	[_cmd, _g, _rec get "sector"] call SWLC_fnc_lambsHold;
};

SWLC_fnc_holdResupply = {
	params ["_cmd", "_rec", "_live"];
	if !(CFG("holdoutResupply")) exitWith {};
	if (_live isEqualTo [] || {time < (_rec get "resupplyNext")}) exitWith {};
	private _side = _cmd get "side";
	private _cost = CFG("holdoutResupplyCost");
	if (([_side] call SWLC_fnc_cpFree) < _cost) exitWith {};
	private _low = _live select {([([_x] call SWLC_fnc_alive) select {isNull objectParent _x}] call SWLC_fnc_squadRearmNeed) isNotEqualTo []};
	if (_low isEqualTo []) exitWith {};
	// A crate with ammo in it already beside them: another one won't help whoever it can't feed.
	if (((_rec get "crates") findIf {alive _x && {(_x distance2D leader (_low # 0)) <= CFG("rearmRadius")} && {(magazineCargo _x) isNotEqualTo []}}) >= 0) exitWith {};
	if !([_side, _cost] call SWLC_fnc_adDebit) exitWith {};
	_rec set ["resupplyNext", time + CFG("holdoutResupplyCooldown")];
	[_cmd, "resupply_sent", [["group", groupId (_low # 0)], ["cost", _cost], ["low_groups", count _low]]] call SWLC_fnc_holdLog;
	[_side, "holdsupply", [_rec get "name"]] call SWLC_fnc_radio;
	[_cmd, _rec, _low # 0] spawn SWLC_fnc_holdDeliver;
};

SWLC_fnc_holdDeliver = {
	params ["_cmd", "_rec", "_g"];
	sleep CFG("holdoutResupplyDelay");
	isNil {
		private _current = (_cmd getOrDefault ["holdRec", createHashMap]) getOrDefault ["id", -1];
		private _live = (_rec get "groups") select {([_x] call SWLC_fnc_groupMen) > 0};
		if (_current != (_rec get "id") || {_live isEqualTo []}) exitWith {
			["C_HOLD", [["side", _cmd get "side"], ["event", "resupply_cancelled"], ["sector", _rec get "name"]]] call SWLC_fnc_log;
		};
		private _to = if (_g in _live) then {_g} else {_live # 0};
		private _p = getPosATL leader _to;
		private _class = ["O_CargoNet_01_ammo_F", "B_CargoNet_01_ammo_F"] select ((_cmd get "side") == west);
		private _pos = _p findEmptyPosition [3, 25, _class];
		if (_pos isEqualTo []) then {_pos = _p};
		private _crate = createVehicle [_class, _pos, [], 0, "NONE"];
		(_rec get "crates") pushBack _crate;
		// Stock what these men actually fire, since a side's crate needn't match its faction's rifles.
		private _seen = [];
		{
			{
				private _man = _x;
				{
					_x params ["_weapon", "_n"];
					if (_weapon != "") then {
						private _list = [_weapon] call SWLC_fnc_squadMags;
						if (_list isNotEqualTo [] && {!((_list # 0) in _seen)}) then {
							_seen pushBack (_list # 0);
							_crate addMagazineCargoGlobal [_list # 0, _n];
						};
					};
				} forEach [[primaryWeapon _man, 12], [secondaryWeapon _man, 3]];
			} forEach ([_x] call SWLC_fnc_alive);
		} forEach _live;
		[_cmd, "resupply_delivered", [["group", groupId _to], ["x", round (_pos # 0)], ["y", round (_pos # 1)], ["dist", round (_pos distance2D _p)]]] call SWLC_fnc_holdLog;
	};
};

// While the goal is X, every free group goes there without waiting to form a wave. forceGo opens both the muster and the
// rally, and once the first group is in, the wave's existing reinforce mode sends the rest as they arrive.
SWLC_fnc_holdReinforce = {
	params ["_cmd", "_rec", "_live", "_kind"];
	private _s = _rec get "sector";
	if (_kind == "defend" || {(_cmd get "target") isNotEqualTo _s}) exitWith {};
	private _op = _cmd get "op";
	if (!isNil "_op" && {(_op get "target") isEqualTo _s}) then {_op set ["forceGo", true]};
	private _id = _rec get "id";
	private _margin = CFG("holdoutArriveMargin");
	{
		private _g = _x;
		if !(_g getVariable ["SWLC_holdout", false]) then {
			if ((_g getVariable ["SWLC_holdLeft", -1]) != _id) then {
				if (([_g] call SWLC_fnc_state) in ["Mustering", "Travelling", "Advancing", "Waiting", "Assaulting"]) then {
					_g setVariable ["SWLC_holdLeft", _id];
					[_cmd, "reinforce_left", [["group", groupId _g], ["state", [_g] call SWLC_fnc_state], ["after", round (time - (_rec get "formed"))],
						["dist", round (leader _g distance2D ([_s] call SWLC_fnc_adPos))]]] call SWLC_fnc_holdLog;
				};
			} else {
				if ((_g getVariable ["SWLC_holdArrived", -1]) != _id && {[_s, getPosATL leader _g, _margin] call SWLC_fnc_adInSquare}) then {
					_g setVariable ["SWLC_holdArrived", _id];
					[_cmd, "reinforce_arrived", [["group", groupId _g], ["after", round (time - (_rec get "formed"))], ["holdouts", count _live]]] call SWLC_fnc_holdLog;
				};
			};
		};
	} forEach ((_cmd get "groups") select {[_x] call SWLC_fnc_resMayTouch});
};

// Part C. Groups defending Y go back to the commander's normal assignment, which is X again.
SWLC_fnc_holdDefendRelease = {
	params ["_cmd", "_rec"];
	private _id = _rec get "id";
	{
		[_cmd, _x, "holdDefendRelease", {
			if ((_x getVariable ["SWLC_holdDefendOf", -1]) == _id) then {
				_x setVariable ["SWLC_holdDefendOf", nil];
				if (([_x] call SWLC_fnc_state) == "Defending" && {[_x] call SWLC_fnc_resMayTouch}) then {
					if ((_x getVariable ["SWLC_lambsTask", ""]) != "") then {[_x, false] call SWLC_fnc_lambsRelease};
					[_x] call SWLC_fnc_adClearOrder;
					[_x, "Unassigned", [], "defend_over"] call SWLC_fnc_setState;
				};
			};
		}] call SWLC_fnc_resGuarded;
	} forEach (_cmd get "groups");
};

SWLC_fnc_holdDefendGroup = {
	params ["_cmd", "_rec", "_g", "_y", "_atY"];
	private _side = _cmd get "side";
	private _threat = [_cmd, _y] call SWLC_fnc_defThreatAt;
	private _b = _threat param [3, random 360];
	if !(_b isEqualType 0) then {_b = random 360};
	private _spot = selectRandom ([_cmd, _y, _b] call SWLC_fnc_defSpots);
	[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
	if ((_g getVariable ["SWLC_lambsTask", ""]) != "") then {[_g, false] call SWLC_fnc_lambsRelease};
	[_g, "Defending", _spot, "defend_y"] call SWLC_fnc_setState;
	_g setVariable ["SWLC_patrolAt", time];
	_g setVariable ["SWLC_holdDefendOf", _rec get "id"];
	[_g, [[_spot, "MOVE", 20]], "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
	[_cmd, "group_defend", [["group", groupId _g], ["at", [_y] call SWLC_fnc_adName], ["was_near", _atY]]] call SWLC_fnc_holdLog;
	if (_atY || {!isNull objectParent leader _g}) exitWith {};
	private _from = (([_side] call SWLC_fnc_adOwned) - [_y]) select {[_side, _x] call SWLC_fnc_adCanFTTo};
	if (_from isEqualTo []) exitWith {};
	private _yPos = [_y] call SWLC_fnc_adPos;
	private _hop = [_from, _yPos] call SWLC_fnc_adNearest;
	private _hp = [_hop] call SWLC_fnc_adPos;
	private _land = [_hp, [_hp, _yPos] call SWLC_fnc_bearing, 40 + random 30] call SWLC_fnc_offset;
	if (surfaceIsWater _land) then {_land = _hp};
	if ([_g, _hop, _land] call SWLC_fnc_adFastTravel) then {
		[_g] call SWLC_fnc_routeAfterHop;
		[_cmd, "group_ft", [["group", groupId _g], ["via", [_hop] call SWLC_fnc_adName]]] call SWLC_fnc_holdLog;
	};
};

// Groups at or near Y turn to defend it, and new arrivals fast travel in from the other nearest sectors.
// A group fighting near X, and every holdout, carries on where it is.
SWLC_fnc_holdDefendTick = {
	params ["_cmd", "_rec", "_y"];
	private _id = _rec get "id";
	private _xPos = [_rec get "sector"] call SWLC_fnc_adPos;
	private _yPos = [_y] call SWLC_fnc_adPos;
	private _near = (([_y] call SWLC_fnc_adSize) / 2) + CFG("holdDefendNearMetres");
	private _nearX = CFG("holdNearXMetres");
	{
		[_cmd, _x, "holdDefend", {
			private _g = _x;
			private _state = [_g] call SWLC_fnc_state;
			private _p = getPosATL leader _g;
			if ((_p distance2D _xPos) > _nearX || {!([_g] call SWLC_fnc_holdFighting)}) then {
				private _atY = (_p distance2D _yPos) <= _near && {_state in ["Unassigned", "Mustering", "Travelling", "Advancing", "Waiting", "Regrouping", "Assaulting"]};
				if (_atY || {_state in ["Unassigned", "Mustering", "Travelling"]}) then {[_cmd, _rec, _g, _y, _atY] call SWLC_fnc_holdDefendGroup};
			};
		}] call SWLC_fnc_resGuarded;
	} forEach ((_cmd get "groups") select {
		[_x] call SWLC_fnc_resMayTouch
		&& {!(_x getVariable ["SWLC_holdout", false])}
		&& {(_x getVariable ["SWLC_holdDefendOf", -1]) != _id}
		&& {!(([_x] call SWLC_fnc_state) in SWLC_holdSkipStates)}
	});
};

// Decides the side's goal. Returns its kind.
SWLC_fnc_holdGoalTick = {
	params ["_cmd", "_rec", "_live"];
	private _s = _rec get "sector";
	private _side = _cmd get "side";
	private _y = _rec get "defendY";
	if (CFG("holdoutSwitching")) then {
		if (isNull _y) then {
			private _fights = ([_side] call SWLC_fnc_adOwned) select {[_x] call SWLC_fnc_holdFront};
			if (_fights isNotEqualTo []) then {
				_y = [_fights, [_s] call SWLC_fnc_adPos] call SWLC_fnc_adNearest;
				_rec set ["defendY", _y];
				_rec set ["clearSince", -1];
				[_cmd, "defend_start", [["y", [_y] call SWLC_fnc_adName]]] call SWLC_fnc_holdLog;
			};
		} else {
			if (([_y] call SWLC_fnc_adOwner) != _side) then {
				// Y fell too. The men inside walk out towards X, so they get the same protection on the way.
				if ([_side, _y] call SWLC_fnc_adProtectSector) then {[_cmd, _y] call SWLC_fnc_holdUndoAdd};
				[_cmd, "defend_end", [["y", [_y] call SWLC_fnc_adName], ["why", "lost"]]] call SWLC_fnc_holdLog;
				[_cmd, _rec] call SWLC_fnc_holdDefendRelease;
				_rec set ["defendY", objNull];
				_y = objNull;
			} else {
				private _threat = [_cmd, _y] call SWLC_fnc_defThreatAt;
				if (([_y] call SWLC_fnc_holdFront) || {((_threat # 0) + (_threat # 1) + (_threat # 2)) > 0}) then {
					_rec set ["clearSince", -1];
				} else {
					if ((_rec get "clearSince") < 0) then {_rec set ["clearSince", time]};
					if ((time - (_rec get "clearSince")) >= CFG("holdClearSeconds")) then {
						[_cmd, "defend_end", [["y", [_y] call SWLC_fnc_adName], ["why", "clear"]]] call SWLC_fnc_holdLog;
						[_cmd, _rec] call SWLC_fnc_holdDefendRelease;
						_rec set ["defendY", objNull];
						_y = objNull;
					};
				};
			};
		};
	};
	private _goal = if (!isNull _y) then {["defend", _y]} else {[["counter", "hold"] select (_live isNotEqualTo []), _s]};
	[_cmd, _goal] call SWLC_fnc_holdSetGoal;
	_goal # 0
};

SWLC_fnc_holdEnd = {
	params ["_cmd", "_rec", "_why"];
	[_cmd, _rec] call SWLC_fnc_holdDefendRelease;
	{
		[_cmd, _x, "holdEnd", {
			_x setVariable ["SWLC_holdout", nil];
			_x setVariable ["SWLC_holdoutBroken", nil];
			if (([_x] call SWLC_fnc_state) in ["Defending", "Engaged"] && {[_x] call SWLC_fnc_resMayTouch}) then {
				if ((_x getVariable ["SWLC_lambsTask", ""]) != "") then {[_x, false] call SWLC_fnc_lambsRelease};
				[_x] call SWLC_fnc_adClearOrder;
				[_x, "Unassigned", [], "holdout_over"] call SWLC_fnc_setState;
			};
		}] call SWLC_fnc_resGuarded;
	} forEach ((_rec get "groups") select {!isNull _x});
	private _s = _rec get "sector";
	if (_rec get "added") then {[_cmd, _s] call SWLC_fnc_holdUndoAdd};
	if ((_cmd getOrDefault ["preferredTarget", objNull]) isEqualTo _s) then {_cmd deleteAt "preferredTarget"};
	[_cmd, "end", [["why", _why], ["lasted", round (time - (_rec get "formed"))]]] call SWLC_fnc_holdLog;
	[_cmd, []] call SWLC_fnc_holdSetGoal;
	_cmd deleteAt "holdRec";
};

SWLC_fnc_holdStatusText = {
	params ["_cmd"];
	private _goal = _cmd getOrDefault ["frontGoal", []];
	if (_goal isEqualTo []) exitWith {""};
	private _name = [_goal # 1] call SWLC_fnc_adName;
	switch (_goal # 0) do {
		case "hold": {format ["Holding %1   ", _name]};
		case "counter": {format ["Counterattacking %1   ", _name]};
		case "defend": {format ["Defending %1   ", _name]};
		default {""};
	}
};

SWLC_fnc_holdoutTick = {
	params ["_cmd"];
	if (isNil {_cmd get "frontGoal"}) then {_cmd set ["frontGoal", []]};
	if !([] call SWLC_fnc_holdOn) exitWith {};
	if ((time - (_cmd getOrDefault ["holdAt", -1e6])) < CFG("holdoutCheckSeconds")) exitWith {};
	_cmd set ["holdAt", time];
	[_cmd] call SWLC_fnc_holdUndoTick;
	[_cmd] call SWLC_fnc_holdDetect;
	private _rec = _cmd getOrDefault ["holdRec", createHashMap];
	if (count _rec == 0) exitWith {};
	private _s = _rec get "sector";
	if (([_s] call SWLC_fnc_adOwner) == (_cmd get "side")) exitWith {[_cmd, _rec, "recaptured"] call SWLC_fnc_holdEnd};
	// The commitment timer has given up on X.
	private _pending = _cmd getOrDefault ["switchPending", []];
	if (_pending isNotEqualTo [] && {(_pending # 2) isEqualTo _s}) exitWith {[_cmd, _rec, "commit"] call SWLC_fnc_holdEnd};
	if ((_cmd get "target") isEqualTo _s) then {_rec set ["targetBy", time + CFG("holdoutVoteGrace")]};
	if (time > (_rec get "targetBy")) exitWith {[_cmd, _rec, "target_moved"] call SWLC_fnc_holdEnd};

	private _all = _rec get "groups";
	// Part D's "Engaged" is still a holdout in its fight. Any other state means something took the group over.
	private _live = _all select {[_x] call SWLC_fnc_resMayTouch && {([_x] call SWLC_fnc_state) in ["Defending", "Engaged"]} && {_x getVariable ["SWLC_holdout", false]}};
	{if (!isNull _x) then {_x setVariable ["SWLC_holdout", nil]}} forEach (_all - _live);
	_rec set ["groups", _live];
	if (_live isEqualTo [] && {!(_rec get "wiped")}) then {
		_rec set ["wiped", true];
		[_cmd, "wiped", [["after", round (time - (_rec get "formed"))]]] call SWLC_fnc_holdLog;
	};
	private _kind = [_cmd, _rec, _live] call SWLC_fnc_holdGoalTick;
	{[_cmd, _x, "holdGroup", {[_cmd, _rec, _x] call SWLC_fnc_holdGroupTick}] call SWLC_fnc_resGuarded} forEach _live;
	[_cmd, _rec, _live] call SWLC_fnc_holdResupply;
	[_cmd, _rec, _live, _kind] call SWLC_fnc_holdReinforce;
	if (_kind == "defend") then {[_cmd, _rec, (_cmd get "frontGoal") # 1] call SWLC_fnc_holdDefendTick};
};
