// Per-side stance: attack, hold or rebuild. Worked out from the side's own numbers against what its intel board knows
// about the enemy, plus how its recent waves went. Never reads true enemy numbers.
//
// Attack is the normal game. Hold stops new waves and keeps everyone on defence. Rebuild is SWLC_fnc_rebuilding: the
// whole side in the reserve at the central sector, buying men, until the balance recovers.
// The commitment rule's rebuild (rebuildUntil in rules.sqf) puts the side in the rebuild stance and keeps it there.
// Not under the rules variant.
#include "macros.hpp"

{SWLC_radioLines set _x} forEach [
	["stance_attack", ["Balance has swung back our way. We're going on the attack.", "We've got the strength now. Back on the offensive.", "All units, we're attacking again."]],
	["stance_hold", ["They're stronger than we thought. Hold what we have, no big attacks.", "We're going on the defensive. Hold the line.", "Enemy has the edge for now. Dig in and hold."]],
	["stance_rebuild", ["We're too weak to stay out there. Pull back and rebuild.", "Falling back to rebuild. Everyone to the central sector.", "We need men before we can fight. Pull back, we're rebuilding."]]
];
{CFG("radioCooldowns") set _x} forEach [["stance_attack", 20], ["stance_hold", 20], ["stance_rebuild", 20]];

SWLC_fnc_stanceOf = {
	params ["_cmd"];
	_cmd getOrDefault ["stance", "attack"]
};

// Reinforcing holdouts is a defensive job: while the side's goal is "hold", the stance doesn't get in its way.
SWLC_fnc_stanceHoldoutGoal = {
	params ["_cmd"];
	((_cmd getOrDefault ["frontGoal", []]) param [0, ""]) == "hold"
};

// The holdouts' sector is the current target, so a wave there is the reinforcement.
SWLC_fnc_stanceHoldoutJob = {
	params ["_cmd"];
	([_cmd] call SWLC_fnc_stanceHoldoutGoal) && {((_cmd get "frontGoal") # 1) isEqualTo (_cmd get "target")}
};

// The rebuild stance's half of SWLC_fnc_rebuilding. Holdouts still get reinforced during it.
SWLC_fnc_stanceRebuilding = {
	params ["_cmd"];
	(([_cmd] call SWLC_fnc_stanceOf) == "rebuild") && {!([_cmd] call SWLC_fnc_stanceHoldoutGoal)}
};

// True when no new wave may start. The one gate on cmdNewPlan.
SWLC_fnc_stanceNoWave = {
	params ["_cmd"];
	if ([_cmd] call SWLC_fnc_commitRebuilding) exitWith {true};
	if (([_cmd] call SWLC_fnc_stanceOf) == "attack") exitWith {false};
	!([_cmd] call SWLC_fnc_stanceHoldoutJob)
};

// holdPriority as the reserve and pickets should see it. A counterattack ("counter") is a wave, and a defensive stance
// doesn't launch one, so only "hold" empties the reserve there.
SWLC_fnc_stanceHoldPriority = {
	params ["_cmd"];
	if !([_cmd] call SWLC_fnc_holdPriority) exitWith {false};
	(([_cmd] call SWLC_fnc_stanceOf) == "attack") || {[_cmd] call SWLC_fnc_stanceHoldoutGoal}
};

// [men, armour, AT launchers, CP] of the side's own forces. These are its own, so they are true numbers.
SWLC_fnc_stanceOwn = {
	params ["_cmd"];
	private _side = _cmd get "side";
	private _men = 0;
	private _at = 0;
	{
		if (side group _x == _side) then {
			_men = _men + 1;
			if (([secondaryWeapon _x] call SWLC_fnc_adLauncherKind) == "AT") then {_at = _at + 1};
		};
	} forEach allUnits;
	private _armour = {(_x get "role") == "combat" && {alive (_x get "obj")}} count (_cmd getOrDefault ["vehicles", []]);
	[_men, _armour, _at, [_side] call SWLC_fnc_adSideCP]
};

// [infantry, light, armour, AT] the board knows about. Same filter as the threat summary. Air counts as light vehicles.
SWLC_fnc_stanceKnown = {
	params ["_cmd"];
	private _now = time;
	private _minConf = CFG("intelThreatMinConf");
	private _delay = CFG("reactionDelay");
	private _inf = 0; private _light = 0; private _armour = 0; private _at = 0;
	{
		if ((_x get "conf") >= _minConf && {(_now - (_x get "born")) >= _delay}) then {
			private _n = _x get "count";
			switch (_x get "cat") do {
				case "infantry": {_inf = _inf + _n};
				case "light"; case "heli"; case "jet": {_light = _light + _n};
				case "tank"; case "apc": {_armour = _armour + _n};
				case "unknownAT": {_at = _at + _n};
			};
		};
	} forEach (_cmd get "board");
	[_inf, _light, _armour, _at]
};

// 1 for no recent results; lower after failed pushes, higher after captures. Outcomes come from pushOver and waveResolve.
SWLC_fnc_stanceOutcome = {
	params ["_cmd", "_result"];
	if !(CFG("stanceEnabled")) exitWith {};
	private _score = 0;
	if (_result == "seized") then {_score = 1};
	if (_result in ["wiped", "attrition", "no_progress"]) then {_score = -1};
	if (_score == 0) exitWith {};
	private _list = _cmd getOrDefault ["stanceOutcomes", []];
	_list pushBack [time, _score];
	_cmd set ["stanceOutcomes", _list];
};

SWLC_fnc_stanceOutcomeFactor = {
	params ["_cmd"];
	private _since = time - CFG("stanceOutcomeWindow");
	private _list = (_cmd getOrDefault ["stanceOutcomes", []]) select {(_x # 0) >= _since};
	_cmd set ["stanceOutcomes", _list];
	private _sum = 0;
	{_sum = _sum + (_x # 1)} forEach _list;
	((1 + _sum * CFG("stanceOutcomeStep")) max CFG("stanceOutcomeMin")) min CFG("stanceOutcomeMax")
};

// Everything the decision uses, in one map so a switch can log what drove it.
SWLC_fnc_stanceNumbers = {
	params ["_cmd"];
	([_cmd] call SWLC_fnc_stanceOwn) params ["_men", "_armour", "_at", "_cp"];
	([_cmd] call SWLC_fnc_stanceKnown) params ["_kInf", "_kLight", "_kArmour", "_kAT"];
	private _atEach = CFG("planAtPerArmour") max 1;
	private _armourW = CFG("stanceArmourWeight");
	private _cpMen = (_cp / (CFG("stanceCPPerMan") max 1)) min CFG("stanceCPMaxMen");
	private _own = _men + _cpMen + _armourW * ((_armour - _kAT / _atEach) max 0);
	private _knownNow = _kInf + CFG("stanceLightWeight") * _kLight + _armourW * ((_kArmour - _at / _atEach) max 0);

	// What it has seen fades slowly, so a side sitting at home doesn't "recover" because its picture went stale.
	private _dt = time - (_cmd getOrDefault ["stancePeakAt", time]);
	private _peak = (_cmd getOrDefault ["stancePeak", 0]) * (0.5 ^ (_dt / (CFG("stanceMemoryHalfLife") max 1)));
	_peak = _peak max _knownNow;
	_cmd set ["stancePeak", _peak];
	_cmd set ["stancePeakAt", time];

	private _outcome = [_cmd] call SWLC_fnc_stanceOutcomeFactor;
	private _ratio = _own / ((_peak * CFG("stanceIntelFactor")) max 1) * _outcome;
	createHashMapFromArray [["men", _men], ["armour", _armour], ["at", _at], ["cp", _cp], ["own", _own], ["known_now", _knownNow], ["known", _peak], ["k_inf", _kInf], ["k_light", _kLight], ["k_armour", _kArmour], ["k_at", _kAT], ["outcome", _outcome], ["ratio", _ratio]]
};

SWLC_fnc_stanceFields = {
	params ["_n"];
	[["ratio", (_n get "ratio") toFixed 2], ["own", round (_n get "own")], ["known", round (_n get "known")], ["known_now", round (_n get "known_now")],
		["men", _n get "men"], ["armour", _n get "armour"], ["at", _n get "at"], ["cp", round (_n get "cp")],
		["k_inf", _n get "k_inf"], ["k_light", _n get "k_light"], ["k_armour", _n get "k_armour"], ["k_at", _n get "k_at"], ["outcome", (_n get "outcome") toFixed 2]]
};

// The stance the numbers ask for. Separate thresholds in and out of each stance.
// Too little intel to judge means carrying on attacking, not assuming the worst.
SWLC_fnc_stanceWanted = {
	params ["_stance", "_ratio", "_known"];
	if (_known < CFG("stanceMinKnown")) exitWith {"attack"};
	if (_stance == "attack") exitWith {["attack", "hold"] select (_ratio < CFG("stanceHoldBelow"))};
	if (_ratio >= CFG("stanceAttackAbove")) exitWith {"attack"};
	if (_stance == "hold") exitWith {["hold", "rebuild"] select (_ratio < CFG("stanceRebuildBelow"))};
	["rebuild", "hold"] select (_ratio >= CFG("stanceHoldAbove"))
};

SWLC_fnc_stanceSwitch = {
	params ["_cmd", "_to", "_reason", "_n"];
	private _from = [_cmd] call SWLC_fnc_stanceOf;
	if (_from == _to) exitWith {};
	_cmd set ["stance", _to];
	_cmd set ["stanceSince", time];
	_cmd deleteAt "stanceHeldLogged";
	["C_STANCE", [["side", _cmd get "side"], ["event", "switch"], ["from", _from], ["to", _to], ["reason", _reason]] + ([_n] call SWLC_fnc_stanceFields)] call SWLC_fnc_log;
	[_cmd get "side", "stance_" + _to] call SWLC_fnc_radio;
};

SWLC_fnc_stanceEvaluate = {
	params ["_cmd"];
	private _n = [_cmd] call SWLC_fnc_stanceNumbers;
	private _side = _cmd get "side";
	private _stance = [_cmd] call SWLC_fnc_stanceOf;
	if (time >= (_cmd getOrDefault ["stanceLogNext", 0])) then {
		_cmd set ["stanceLogNext", time + CFG("stanceLogSeconds")];
		["C_STANCE", [["side", _side], ["event", "state"], ["stance", _stance]] + ([_n] call SWLC_fnc_stanceFields)] call SWLC_fnc_log;
	};
	// A commit-timer rebuild runs its full length.
	if ([_cmd] call SWLC_fnc_commitRebuilding) exitWith {};
	private _wanted = [_stance, _n get "ratio", _n get "known"] call SWLC_fnc_stanceWanted;
	// Nobody on this side has fought for a long time: the enemy isn't pressing, and two sides both waiting is a dead round.
	if (((_cmd get "groups") findIf {[_x] call SWLC_fnc_groupFighting}) >= 0) then {_cmd set ["stanceFoughtAt", time]};
	if (_wanted != "attack" && {_stance == "hold"} && {(time - ((_cmd getOrDefault ["stanceFoughtAt", -1e6]) max (_cmd getOrDefault ["stanceSince", -1e6]))) >= CFG("stanceQuietSeconds")}) then {_wanted = "attack"};
	if (_wanted == _stance) exitWith {_cmd deleteAt "stanceHeldLogged"};
	private _left = ((_cmd getOrDefault ["stanceSince", -1e6]) + CFG("stanceMinSeconds")) - time;
	if (_left > 0) exitWith {
		if !(_cmd getOrDefault ["stanceHeldLogged", false]) then {
			_cmd set ["stanceHeldLogged", true];
			["C_STANCE", [["side", _side], ["event", "held"], ["stance", _stance], ["wanted", _wanted], ["left", round _left]] + ([_n] call SWLC_fnc_stanceFields)] call SWLC_fnc_log;
		};
	};
	[_cmd, _wanted, "balance", _n] call SWLC_fnc_stanceSwitch;
};

// An op from before the stance changed. Nothing new goes in, whoever is not in the fight goes back to the commander,
// and once nobody is in contact the op ends. An assault at the objective finishes, and a fight on the road ends itself.
SWLC_fnc_stanceStandDown = {
	params ["_cmd"];
	private _op = _cmd get "op";
	if (isNil "_op") exitWith {};
	_op set ["holdGo", true];
	_op set ["forceGo", false];
	_op set ["stanceHeld", true];
	private _nearR = CFG("waveNearRadius");
	private _tpos = _op get "tpos";
	private _contact = false;
	{
		private _g = _x;
		private _state = [_g] call SWLC_fnc_state;
		private _fighting = [_g] call SWLC_fnc_groupFighting;
		if (_state == "Assaulting" && {_fighting || {(leader _g distance2D _tpos) <= _nearR}}) then {_contact = true};
		if (_state == "Engaged" && {_fighting}) then {_contact = true};
		if (_state in ["Travelling", "Mustering", "Mounting", "Advancing", "Waiting", "Regrouping"]) then {
			if (_fighting) then {_contact = true} else {
				[_cmd, _g, "stanceRelease", {
					[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
					[_g] call SWLC_fnc_adClearOrder;
					[_g, "Unassigned", [], "stance_release"] call SWLC_fnc_setState;
				}] call SWLC_fnc_resGuarded;
			};
		};
	} forEach ([_op] call SWLC_fnc_waveLive);
	if (!_contact) exitWith {[_cmd, "stance_hold"] call SWLC_fnc_waveResolve};
	// The op is still there for its fighters, so the normal assignment mustn't pull anyone back into it.
	private _until = time + 2 * CFG("tickSeconds");
	{
		if (([_x] call SWLC_fnc_state) == "Unassigned") then {_x setVariable ["SWLC_noAssignUntil", (_x getVariable ["SWLC_noAssignUntil", -1]) max _until]};
	} forEach (_cmd get "groups");
};

SWLC_fnc_stanceTick = {
	params ["_cmd"];
	if !(CFG("stanceEnabled")) exitWith {};
	if (time >= (_cmd getOrDefault ["stanceNext", 0])) then {
		_cmd set ["stanceNext", time + CFG("stanceTickSeconds")];
		[_cmd] call SWLC_fnc_stanceEvaluate;
	};
	if (([_cmd] call SWLC_fnc_commitRebuilding) && {([_cmd] call SWLC_fnc_stanceOf) != "rebuild"}) then {
		[_cmd, "rebuild", "commit", [_cmd] call SWLC_fnc_stanceNumbers] call SWLC_fnc_stanceSwitch;
	};
	if ([_cmd] call SWLC_fnc_stanceNoWave) then {
		// The side isn't going for its target, so neither the commitment timer nor the deadlock revote should judge
		// it for not getting there. Back in attack the timer starts in full.
		[_cmd] call SWLC_fnc_commitNew;
		_cmd set ["targetSince", time];
		[_cmd] call SWLC_fnc_stanceStandDown;
	} else {
		private _op = _cmd get "op";
		if (!isNil "_op" && {_op getOrDefault ["stanceHeld", false]}) then {
			_op deleteAt "stanceHeld";
			_op set ["holdGo", false];
		};
	};
};

// Called with the reserve at the post: AT launchers go to the groups there. Vehicles aren't bought because no muster
// shop runs without a wave, and statics are bought elsewhere.
SWLC_fnc_stanceKit = {
	params ["_cmd", "_op", "_groups"];
	if (([_cmd] call SWLC_fnc_stanceOf) == "attack") exitWith {};
	private _armour = ([_cmd] call SWLC_fnc_stanceKnown) # 2;
	_op set ["plan", createHashMapFromArray [["atWanted", (count _groups) * CFG("stanceAtPerGroup") + _armour * CFG("planAtPerArmour")], ["aa", false], ["smoke", false], ["ammo", false]]];
	[_cmd, _op, _groups] call SWLC_fnc_kitTick;
};

// Panel header text, in front of the holdout goal.
SWLC_fnc_stanceStatusText = {
	params ["_cmd"];
	if !(CFG("stanceEnabled")) exitWith {""};
	format ["Stance: %1   ", toUpper ([_cmd] call SWLC_fnc_stanceOf)]
};
