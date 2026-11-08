// Phase 6 behaviours. Each has an on/off switch and its tunables in settings.sqf.
#include "macros.hpp"

SWLC_fnc_smartLog = {
	params ["_cmd", "_behaviour", "_event", ["_fields", []]];
	["C_SMART", [["side", _cmd get "side"], ["behaviour", _behaviour], ["event", _event]] + _fields] call SWLC_fnc_log;
};

// A personality factor, or the default when no personality is set.
SWLC_fnc_persona = {
	params ["_cmd", "_key", ["_default", 1]];
	(_cmd getOrDefault ["persona", createHashMap]) getOrDefault [_key, _default]
};

SWLC_fnc_smartTick = {
	params ["_cmd"];
	if (CFG("smartPersonality") && {isNil {_cmd get "persona"}}) then {[_cmd] call SWLC_fnc_smartInit};
	[_cmd] call SWLC_fnc_smartBreakTick;
	[_cmd] call SWLC_fnc_smartRadioTick;
	[_cmd] call SWLC_fnc_smartReinforceTick;
	[_cmd] call SWLC_fnc_smartScoutTick;
	[_cmd] call SWLC_fnc_smartHuntTick;
	[_cmd] call SWLC_fnc_smartDigInTick;
	[_cmd] call SWLC_fnc_smartJoinTick;
	// SMART_CALLS
};

SWLC_fnc_smartOnSeized = {
	params ["_cmd", "_w", "_live"];
	[_cmd, _w, _live] call SWLC_fnc_smartCheer;
	[_cmd, _w, _live] call SWLC_fnc_smartMomentum;
	[_cmd, _w, _live] call SWLC_fnc_smartDigIn;
	// SMART_SEIZED
};

// 1. Break and consolidate: a group down to about a third pulls back to the rally and merges.
SWLC_fnc_smartBreakTick = {
	params ["_cmd"];
	if !(CFG("smartBreak")) exitWith {};
	private _op = _cmd get "op";
	if (!isNil "_op") then {
		{
			private _g = _x;
			private _launch = _g getVariable ["SWLC_launchMen", 0];
			private _men = [_g] call SWLC_fnc_groupMen;
			if (_launch >= CFG("breakMinLaunchMen") && {(_g getVariable ["SWLC_leg", ""]) == "FOOT"} && {([_g] call SWLC_fnc_state) in ["Advancing", "Assaulting"]} && {_men <= ((floor (_launch * CFG("breakFraction"))) max 1)}) then {
				if (([_g] call SWLC_fnc_state) == "Assaulting") then {_op set ["launchStrength", ((_op get "launchStrength") - _men) max 0]};
				_g setVariable ["SWLC_broke", true];
				_g setVariable ["SWLC_launchMen", _men];
				[_g, "Regrouping", _op get "rally", "broke"] call SWLC_fnc_setState;
				[_g, [[_op get "rally", "MOVE", 30]], "AWARE", "FULL", "WEDGE", "YELLOW"] call SWLC_fnc_adSetOrder;
				[_cmd, "break", "retreat", [["group", groupId _g], ["men", _men], ["launched", _launch], ["wave", _op get "id"]]] call SWLC_fnc_smartLog;
				[_cmd get "side", "breaking", [], _g] call SWLC_fnc_radio;
			};
		} forEach ([_op] call SWLC_fnc_waveLive);
	};

	// Merge at the rally. Warlords stay in their own groups, so only their bought men change group.
	private _groups = _cmd get "groups";
	{
		private _g = _x;
		private _partners = _groups select {
			_x isNotEqualTo _g && {([_x] call SWLC_fnc_state) == "Waiting"}
			&& {([_x] call SWLC_fnc_groupMen) <= CFG("mergeMaxMen")} && {(leader _x distance2D leader _g) <= CFG("mergeRadius")}
		};
		if (_partners isNotEqualTo []) then {
			private _other = _partners # 0;
			private _big = [_other, _g] select (([_g] call SWLC_fnc_groupMen) >= ([_other] call SWLC_fnc_groupMen));
			private _small = [_g, _other] select (_big isEqualTo _g);
			private _movers = (units _small) select {alive _x && {!isPlayer _x} && {!([_x] call SWLC_fnc_adIsWarlord)}};
			if (_movers isNotEqualTo []) then {_movers joinSilent _big};
			_g setVariable ["SWLC_broke", false];
			[_cmd, "break", "merge", [["group", groupId _g], ["with", groupId _other], ["moved", count _movers]]] call SWLC_fnc_smartLog;
		};
	} forEach (_groups select {(_x getVariable ["SWLC_broke", false]) && {([_x] call SWLC_fnc_state) == "Waiting"}});
};

// 2. Livelier radio: heavy-losses calls. Breaking and cheer calls are sent where those events happen.
SWLC_fnc_smartRadioTick = {
	params ["_cmd"];
	if !(CFG("smartRadio")) exitWith {};
	private _op = _cmd get "op";
	if (isNil "_op") exitWith {};
	{
		private _g = _x;
		private _launch = _g getVariable ["SWLC_launchMen", 0];
		if (([_g] call SWLC_fnc_state) in ["Advancing", "Assaulting"] && {_launch >= 2} && {!(_g getVariable ["SWLC_heavyCalled", false])} && {([_g] call SWLC_fnc_groupMen) <= _launch * (1 - CFG("radioHeavyFraction"))}) then {
			_g setVariable ["SWLC_heavyCalled", true];
			[_cmd get "side", "heavy", [], _g] call SWLC_fnc_radio;
		};
	} forEach ([_op] call SWLC_fnc_waveLive);
};

SWLC_fnc_smartCheer = {
	params ["_cmd", "_w", "_live"];
	if !(CFG("smartRadio")) exitWith {};
	if (_live isNotEqualTo []) then {[_cmd get "side", "cheer", [], selectRandom _live] call SWLC_fnc_radio};
};

// 3. Reinforce success: groups stalled outside the sector move up to a group that has broken in.
SWLC_fnc_smartReinforceTick = {
	params ["_cmd"];
	if !(CFG("smartReinforce")) exitWith {};
	private _op = _cmd get "op";
	if (isNil "_op" || {(_op get "phase") != "ASSAULT"}) exitWith {};
	private _target = _op get "target";
	private _tpos = _op get "tpos";
	private _foot = ([_op] call SWLC_fnc_waveLive) select {(_x getVariable ["SWLC_leg", ""]) == "FOOT" && {([_x] call SWLC_fnc_state) == "Assaulting"}};

	// Track each group's closest approach to the target.
	{
		private _d = (leader _x) distance2D _tpos;
		if (_d < ((_x getVariable ["SWLC_bestD", 1e9]) - CFG("reinforceMinMetres"))) then {
			_x setVariable ["SWLC_bestD", _d];
			_x setVariable ["SWLC_bestAt", time];
		};
	} forEach _foot;

	private _i = _foot findIf {[_target, getPosATL leader _x] call SWLC_fnc_adInSquare};
	if (_i < 0) exitWith {};
	private _inside = _foot # _i;
	{
		private _g = _x;
		if (!([_target, getPosATL leader _g] call SWLC_fnc_adInSquare)
			&& {(time - (_g getVariable ["SWLC_bestAt", time])) >= CFG("reinforceStallSeconds")}
			&& {!(_g getVariable ["SWLC_reinforced", false])}) then {
			_g setVariable ["SWLC_reinforced", true];
			private _order = [[getPosATL leader _inside, "MOVE", 30]] + ([_target] call SWLC_fnc_sweepOrder);
			[_g, "Assaulting", _tpos, "reinforce"] call SWLC_fnc_setState;
			[_g, _order, "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
			[_cmd, "reinforce", "redirect", [["group", groupId _g], ["wave", _op get "id"], ["to_group", groupId _inside]]] call SWLC_fnc_smartLog;
		};
	} forEach _foot;
};

// The centre of what the side knows about near a sector, or the sector centre.
SWLC_fnc_smartEnemyCentre = {
	params ["_cmd", "_target"];
	private _c = [_target] call SWLC_fnc_adPos;
	private _r = ([_target] call SWLC_fnc_adSize) / 2 + 150;
	private _sx = 0;
	private _sy = 0;
	private _n = 0;
	{
		private _p = _x get "pos";
		if ((_p distance2D _c) <= _r) then {
			_sx = _sx + (_p # 0);
			_sy = _sy + (_p # 1);
			_n = _n + 1;
		};
	} forEach (_cmd get "board");
	if (_n == 0) exitWith {+_c};
	[_sx / _n, _sy / _n, 0]
};

// 4. Smoke before the push: laid forward of the lead group, on the line to the enemy.
SWLC_fnc_smartSmoke = {
	params ["_cmd", "_w", "_live"];
	if !(CFG("smartSmoke")) exitWith {};
	private _enemy = [_cmd, _w get "target"] call SWLC_fnc_smartEnemyCentre;
	private _thrown = 0;
	{
		private _u = leader _x;
		private _mag = (magazines _u) select {_x isKindOf ["SmokeShell", configFile >> "CfgMagazines"]};
		if (alive _u && {(_x getVariable ["SWLC_leg", ""]) == "FOOT"} && {_mag isNotEqualTo []}) then {
			private _here = getPosATL _u;
			private _p = [_here, [_here, _enemy] call SWLC_fnc_bearing, CFG("smokeThrowDist")] call SWLC_fnc_offset;
			_u removeMagazine (_mag # 0);
			createVehicle ["SmokeShell", _p, [], 0, "CAN_COLLIDE"];
			_thrown = _thrown + 1;
			[_cmd, "smoke", "thrown", [["group", groupId _x], ["x", round (_p # 0)], ["y", round (_p # 1)], ["known_enemy", _enemy isNotEqualTo ([_w get "target"] call SWLC_fnc_adPos)]]] call SWLC_fnc_smartLog;
		};
	} forEach (_live select [0, CFG("smokeGroupsPerPush")]);
	if (_thrown > 0) then {[_cmd get "side", "smoke", [], _live # 0] call SWLC_fnc_radio};
};

// 5. Prep fire: a short barrage from AI-crewed artillery the side already has, then a wait so it lifts.
// Returns true while the wave should hold for it.
SWLC_fnc_smartPrepFire = {
	params ["_cmd", "_w"];
	if !(CFG("smartPrepFire")) exitWith {false};
	if (_w getOrDefault ["prepDone", false]) exitWith {time < (_w getOrDefault ["prepUntil", -1])};
	_w set ["prepDone", true];
	private _side = _cmd get "side";
	private _target = _w get "target";
	private _pos = [_cmd, _target] call SWLC_fnc_smartEnemyCentre;
	private _pieces = vehicles select {
		alive _x && {getNumber (configOf _x >> "artilleryScanner") > 0} && {!isNull gunner _x} && {alive gunner _x} && {!isPlayer gunner _x} && {!isPlayer leader group gunner _x} &&{side group gunner _x == _side} && {local gunner _x}
	};
	if (_pieces isEqualTo []) exitWith {
		[_cmd, "prepfire", "no_piece", [["wave", _w get "id"]]] call SWLC_fnc_smartLog;
		false
	};
	if ((allUnits findIf {side group _x == _side && {(_x distance2D _pos) < CFG("prepMinFriendlyDist")}}) >= 0) exitWith {
		[_cmd, "prepfire", "friendlies_close", [["wave", _w get "id"]]] call SWLC_fnc_smartLog;
		false
	};
	private _fired = 0;
	{
		private _piece = _x;
		private _mags = getArtilleryAmmo [_piece];
		private _he = _mags select {!("SMOKE" in toUpper _x) && {!("FLARE" in toUpper _x)}};
		private _mag = if (_he isNotEqualTo []) then {_he # 0} else {if (_mags isEqualTo []) then {""} else {_mags # 0}};
		if (_mag != "" && {_pos inRangeOfArtillery [[_piece], _mag]}) then {
			_piece commandArtilleryFire [_pos, _mag, CFG("prepRounds")];
			_fired = _fired + 1;
		};
	} forEach _pieces;
	[_cmd, "prepfire", ["out_of_range", "fired"] select (_fired > 0), [["wave", _w get "id"], ["pieces", _fired], ["rounds", CFG("prepRounds")], ["x", round (_pos # 0)], ["y", round (_pos # 1)]]] call SWLC_fnc_smartLog;
	if (_fired == 0) exitWith {false};
	[_side, "prepfire", [[_target] call SWLC_fnc_adName]] call SWLC_fnc_radio;
	_w set ["prepUntil", time + CFG("prepFireLeadSeconds")];
	true
};

// 6. Exploit momentum: after a fast, cheap capture, go straight for a weak neighbouring sector.
SWLC_fnc_smartMomentum = {
	params ["_cmd", "_w", "_live"];
	if !(CFG("smartMomentum")) exitWith {};
	private _f = [_cmd, "momentum"] call SWLC_fnc_persona;
	private _side = _cmd get "side";
	if (([_side] call SWLC_fnc_adSideHasPlayers) && {!CFG("voteOnPlayerSide")}) exitWith {
		[_cmd, "momentum", "players_vote", []] call SWLC_fnc_smartLog;
	};
	private _took = time - (_w get "launched");
	private _men = [_live] call SWLC_fnc_groupsMen;
	if (_took > CFG("momentumFastSeconds") * _f || {_men < (CFG("momentumMinStrength") / _f) * (_w get "launchStrength")}) exitWith {
		[_cmd, "momentum", "not_earned", [["took", round _took], ["men", _men], ["launched", _w get "launchStrength"]]] call SWLC_fnc_smartLog;
	};
	private _best = objNull;
	private _bestMen = 1e9;
	private _avail = [_side] call SWLC_fnc_adAvailable;
	{
		if (([_x] call SWLC_fnc_adOwner) != _side && {!([_x] call SWLC_fnc_adIsBase)} && {_x in _avail}) then {
			private _t = [_cmd, _x] call SWLC_fnc_threatOf;
			private _known = (_t get "infantry") + 3 * (_t get "light");
			// A neighbour nobody has seen can stand in only when no scouted weak one exists.
			private _rank = _known + ([1000, 0] select (_t get "scouted"));
			if ((_t get "armour") == 0 && {_known <= CFG("momentumWeakMen")} && {_rank < _bestMen}) then {
				_best = _x;
				_bestMen = _rank;
			};
		};
	} forEach ([_w get "target"] call SWLC_fnc_adLinks);
	if (isNull _best) exitWith {
		[_cmd, "momentum", "no_weak_neighbour", [["took", round _took]]] call SWLC_fnc_smartLog;
	};
	_cmd set ["momentum", [_best, time + CFG("momentumHoldSeconds")]];
	[_cmd, "momentum", "push", [["from", [_w get "target"] call SWLC_fnc_adName], ["to", [_best] call SWLC_fnc_adName], ["took", round _took], ["men", _men], ["known_defenders", _bestMen mod 1000], ["scouted", _bestMen < 1000]]] call SWLC_fnc_smartLog;
	[_side, "momentum", [[_best] call SWLC_fnc_adName]] call SWLC_fnc_radio;
};

// 7. Scout first: a small group goes ahead while the others muster. Never holds up the go.
SWLC_fnc_smartScoutTick = {
	params ["_cmd"];
	if !(CFG("smartScout")) exitWith {};
	private _side = _cmd get "side";
	private _w = _cmd get "op";
	if (!isNil "_w" && {!(_w getOrDefault ["scoutSent", false])}) then {
		private _target = _w get "target";
		private _groups = [_w] call SWLC_fnc_waveLive;
		if !(([_cmd, _target] call SWLC_fnc_threatOf) get "scouted") then {
			// The attack must still reach the go count without the scout.
			if ((count _groups) >= (CFG("scoutMinGroups") max (CFG("goMinGroups") + 1))) then {
				private _sorted = [_groups select {([_x] call SWLC_fnc_state) in ["Mustering", "Travelling"]}, [], {[_x] call SWLC_fnc_groupMen}, "ASCEND"] call BIS_fnc_sortBy;
				if (_sorted isNotEqualTo []) then {
					_w set ["scoutSent", true];
					private _g = _sorted # 0;
					private _tpos = [_target] call SWLC_fnc_adPos;
					private _spot = [_side, _tpos, _w get "bearing", CFG("scoutDist")] call SWLC_fnc_validHoldPoint;
					[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
					[_g, "Recon", _spot, "scout"] call SWLC_fnc_setState;
					private _limit = ((leader _g distance2D _spot) / CFG("footSpeedEstimate")) max CFG("scoutMaxSeconds") min CFG("scoutCapSeconds");
					_g setVariable ["SWLC_scoutUntil", time + _limit];
					_g setVariable ["SWLC_scoutVeh", objNull];
					_g setVariable ["SWLC_scoutSpot", _spot];
					private _men = [_g] call SWLC_fnc_groupMen;
					private _entry = [_cmd, _men] call SWLC_fnc_vehCheapestTransport;
					private _rode = false;
					if (_entry isNotEqualTo [] && {([_side] call SWLC_fnc_cpFree) >= (_entry # 1) + CFG("scoutVehicleSpareCP")} && {alive leader _g} && {[leader _g] call SWLC_fnc_adIsWarlord}) then {
						private _items = [_cmd, leader _g, [_entry # 0], _entry # 1, "scout"] call SWLC_fnc_logBuy;
						if (_items isNotEqualTo []) then {
							private _v = _items # 0;
							_v removeAllEventHandlers "GetIn";
							_v setVariable ["SWLC_side", _side];
							_g setVariable ["SWLC_scoutVeh", _v];
							private _bought = _cmd getOrDefault ["scoutVehicles", []];
							_bought pushBack [_v, _entry, _g];
							_cmd set ["scoutVehicles", _bought];
							_g setVariable ["SWLC_scoutUntil", time + _limit + CFG("scoutVehicleWait")];
							_rode = true;
						};
					};
					if (!_rode) then {[_g, [[_spot, "MOVE", 40]], "AWARE", "FULL", "WEDGE", "GREEN"] call SWLC_fnc_adSetOrder};
					_g setVariable ["SWLC_scoutMoving", !_rode];
					[_cmd, "scout", "sent", [["group", groupId _g], ["wave", _w get "id"], ["target", [_target] call SWLC_fnc_adName], ["vehicle", _rode]]] call SWLC_fnc_smartLog;
					[_side, "scout", [[_target] call SWLC_fnc_adName], _g] call SWLC_fnc_radio;
				};
			};
		};
	};

	{
		private _g = _x;
		if (([_g] call SWLC_fnc_state) == "Recon" && {!isNil {_g getVariable "SWLC_scoutUntil"}}) then {
			private _v = _g getVariable ["SWLC_scoutVeh", objNull];
			if (!(_g getVariable ["SWLC_scoutMoving", false]) && {!isNull _v} && {alive _v} && {isNull attachedTo _v} && {((getPosATL _v) # 2) < 2}) then {
				_g setVariable ["SWLC_scoutMoving", true];
				private _units = [_g] call SWLC_fnc_alive;
				_g addVehicle _v;
				(_units # 0) assignAsDriver _v;
				{_x assignAsCargo _v} forEach (_units - [_units # 0]);
				_units orderGetIn true;
				[_g, [[_g getVariable "SWLC_scoutSpot", "MOVE", 40]], "AWARE", "FULL", "WEDGE", "GREEN"] call SWLC_fnc_adSetOrder;
			};
			if (time >= (_g getVariable "SWLC_scoutUntil") || {(_g getVariable ["SWLC_scoutMoving", false]) && {[_g] call SWLC_fnc_adOrderDone}}) then {
				_g setVariable ["SWLC_scoutUntil", nil];
				if (!isNull _v) then {
					_g leaveVehicle _v;
					private _u = (units _g) select {alive _x};
					{unassignVehicle _x} forEach _u;
					_u orderGetIn false;
					{if (vehicle _x == _v) then {doGetOut _x}} forEach _u;
				};
				[_g] call SWLC_fnc_adClearOrder;
				[_g, "Unassigned", [], "scout_done"] call SWLC_fnc_setState;
				[_cmd, "scout", "done", [["group", groupId _g], ["alive", [_g] call SWLC_fnc_groupMen]]] call SWLC_fnc_smartLog;
			};
		};
	} forEach (_cmd get "groups");

	// A scout's vehicle joins the motor pool, parked, as soon as its group has finished with it,
	// including when the group was wiped out or stopped being the commander's.
	private _bought = _cmd getOrDefault ["scoutVehicles", []];
	if (_bought isNotEqualTo []) then {
		private _keep = [];
		{
			_x params ["_v", "_entry", "_g"];
			if ((_g in (_cmd get "groups")) && {([_g] call SWLC_fnc_state) == "Recon"}) then {
				_keep pushBack _x;
			} else {
				if (alive _v) then {
					_entry params ["_cls", "_cost", "_seats", "_role", "_heavy"];
					private _id = (_cmd get "vehCounter") + 1;
					_cmd set ["vehCounter", _id];
					(_cmd get "vehicles") pushBack (createHashMapFromArray [["id", _id], ["obj", _v], ["cls", _cls], ["role", _role], ["heavy", _heavy], ["seats", _seats], ["state", "parked"],
						["group", grpNull], ["wave", -1], ["boughtAt", time], ["stuck", 0], ["mounted", false]]);
				};
			};
		} forEach _bought;
		_cmd set ["scoutVehicles", _keep];
	};
};

// 8. Hunt unseen AT: something killed a vehicle and nobody saw who, so the nearest free group sweeps the area.
SWLC_fnc_smartHuntQueue = {
	params ["_cmd", "_pos"];
	if !(CFG("smartHunt")) exitWith {};
	// The shooter is unseen, so this is an estimate: from the wreck towards the objective, the likely side.
	private _target = _cmd get "target";
	private _towards = if (isNull _target) then {random 360} else {[_pos, [_target] call SWLC_fnc_adPos] call SWLC_fnc_bearing};
	private _firing = [_pos, _towards + (random 60 - 30), CFG("huntOffset")] call SWLC_fnc_offset;
	private _q = _cmd getOrDefault ["huntQueue", []];
	_q pushBack [_pos, _firing];
	_cmd set ["huntQueue", _q];
};

SWLC_fnc_smartHuntTick = {
	params ["_cmd"];
	if !(CFG("smartHunt")) exitWith {};
	private _queue = _cmd getOrDefault ["huntQueue", []];
	if (_queue isNotEqualTo []) then {
		_cmd set ["huntQueue", []];
		{
			_x params ["_pos", "_firing"];
			if (surfaceIsWater _firing || {[_cmd get "side", _firing] call SWLC_fnc_adRestricted}) then {_firing = +_pos};
			private _blocked = [_cmd get "side", _firing] call SWLC_fnc_adRestricted;
			private _free = (_cmd get "groups") select {!_blocked && {([_x] call SWLC_fnc_state) in ["Unassigned", "Mustering", "Reserve"]} && {(leader _x distance2D _firing) <= CFG("huntRadius")}};
			if (_free isNotEqualTo []) then {
				private _g = ([_free, [], {leader _x distance2D _firing}, "ASCEND"] call BIS_fnc_sortBy) # 0;
				[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
				[_g, "Hunting", _firing, "hunt"] call SWLC_fnc_setState;
				_g setVariable ["SWLC_huntUntil", time + ((leader _g distance2D _firing) / CFG("footSpeedEstimate")) + CFG("huntSeconds")];
				[_g, [[_firing, "SAD", 60]], "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
				[_cmd, "hunt", "sent", [["group", groupId _g], ["x", round (_firing # 0)], ["y", round (_firing # 1)], ["dist", round (leader _g distance2D _firing)]]] call SWLC_fnc_smartLog;
				[_cmd get "side", "hunt", [mapGridPosition _firing], _g] call SWLC_fnc_radio;
			} else {
				[_cmd, "hunt", "no_free_group", [["x", round (_firing # 0)], ["y", round (_firing # 1)], ["restricted", _blocked]]] call SWLC_fnc_smartLog;
			};
		} forEach _queue;
	};
	{
		if (([_x] call SWLC_fnc_state) == "Hunting" && {time >= (_x getVariable ["SWLC_huntUntil", 0])}) then {
			[_x] call SWLC_fnc_adClearOrder;
			[_x, "Unassigned", [], "hunt_done"] call SWLC_fnc_setState;
			[_cmd, "hunt", "done", [["group", groupId _x]]] call SWLC_fnc_smartLog;
		};
	} forEach (_cmd get "groups");
};

// 9. Dig in after capture: one group takes edge positions facing the likely counterattack.
SWLC_fnc_smartDigIn = {
	params ["_cmd", "_w", "_live"];
	if !(CFG("smartDigIn")) exitWith {};
	private _side = _cmd get "side";
	private _s = _w get "target";
	private _c = [_s] call SWLC_fnc_adPos;
	([_cmd, _s] call SWLC_fnc_defThreatAt) params ["_inf", "_arm", "_light", "_bearing"];
	private _from = "board";
	if ((_inf + _arm + _light) == 0) then {
		_from = "enemy_sector";
		private _enemy = SWLC_sectors select {([_x] call SWLC_fnc_adOwner) == ([_side] call SWLC_fnc_adEnemySide)};
		if (_enemy isNotEqualTo []) then {
			private _near = ([_enemy, [], {([_x] call SWLC_fnc_adPos) distance2D _c}, "ASCEND"] call BIS_fnc_sortBy) # 0;
			_bearing = [_c, [_near] call SWLC_fnc_adPos] call SWLC_fnc_bearing;
		};
	};
	private _spots = [_cmd, _s, _bearing] call SWLC_fnc_defSpots;
	{
		private _spot = _spots # (_forEachIndex mod count _spots);
		[_x, "Defending", _spot, "dig_in"] call SWLC_fnc_setState;
		_x setVariable ["SWLC_digUntil", time + CFG("digInSeconds")];
		_x setVariable ["SWLC_patrolAt", time];
		[_x, [[_spot, "MOVE", 15]], "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
		[_cmd, "digin", "position", [["group", groupId _x], ["sector", [_s] call SWLC_fnc_adName], ["facing", round _bearing], ["from", _from], ["x", round (_spot # 0)], ["y", round (_spot # 1)]]] call SWLC_fnc_smartLog;
	} forEach (_live select [0, CFG("digInGroups")]);
	if (_live isNotEqualTo []) then {[_side, "digin", [[_s] call SWLC_fnc_adName], _live # 0] call SWLC_fnc_radio};
};

SWLC_fnc_smartDigInTick = {
	params ["_cmd"];
	if !(CFG("smartDigIn")) exitWith {};
	{
		private _until = _x getVariable ["SWLC_digUntil", -1];
		if (_until >= 0 && {time >= _until}) then {
			_x setVariable ["SWLC_digUntil", -1];
			if (([_x] call SWLC_fnc_state) == "Defending") then {
				[_x] call SWLC_fnc_adClearOrder;
				[_x, "Unassigned", [], "dig_in_done"] call SWLC_fnc_setState;
			};
		};
	} forEach (_cmd get "groups");
};

// 10. Commander personality, picked once per round. Forceable with personalityForce.
SWLC_fnc_smartInit = {
	params ["_cmd"];
	private _force = CFG("personalityForce");
	private _name = if (_force != "") then {_force} else {selectRandom ["aggressive", "cautious", "sneaky"]};
	private _p = switch (_name) do {
		case "aggressive": {[["goWait", 0.75], ["combat", 1.3], ["momentum", 1.3]]};
		case "cautious": {[["goWait", 1.2], ["combat", 0.8], ["momentum", 0.7]]};
		default {[["goWait", 0.9], ["combat", 0.7], ["momentum", 1]]};
	};
	_cmd set ["persona", createHashMapFromArray (_p + [["name", _name]])];
	[_cmd, "personality", "chosen", [["name", _name], ["forced", _force != ""]]] call SWLC_fnc_smartLog;
};

// 11. Memory within a round: a direction that cost heavy losses isn't reused for that sector.
SWLC_fnc_smartRemember = {
	params ["_cmd", "_op", "_attackers"];
	if !(CFG("smartMemory")) exitWith {};
	private _launched = _op get "launchStrength";
	if (_launched < CFG("memoryMinMen")) exitWith {};
	private _left = [_attackers] call SWLC_fnc_groupsMen;
	if ((1 - (_left min _launched) / _launched) < CFG("memoryLossFraction")) exitWith {};
	private _name = [_op get "target"] call SWLC_fnc_adName;
	private _map = _cmd getOrDefault ["costly", createHashMap];
	private _list = _map getOrDefault [_name, []];
	_list pushBack (_op get "bearing");
	_map set [_name, _list];
	_cmd set ["costly", _map];
	[_cmd, "memory", "costly", [["sector", _name], ["bearing", round (_op get "bearing")], ["launched", _launched], ["left", _left]]] call SWLC_fnc_smartLog;
};

SWLC_fnc_smartAvoid = {
	params ["_cmd", "_target", "_bearing"];
	if !(CFG("smartMemory")) exitWith {_bearing};
	private _name = [_target] call SWLC_fnc_adName;
	private _list = (_cmd getOrDefault ["costly", createHashMap]) getOrDefault [_name, []];
	private _avoid = CFG("memoryAvoidDegrees");
	private _b = _bearing;
	{
		private _diff = ((((_b - _x) mod 360) + 540) mod 360) - 180;
		if ((abs _diff) < _avoid) then {
			private _sign = [1, -1] select (_diff < 0);
			_b = _x + _sign * (_avoid + 5);
			[_cmd, "memory", "avoid", [["sector", _name], ["costly", round _x], ["was", round _bearing], ["now", round _b]]] call SWLC_fnc_smartLog;
		};
	} forEach _list;
	_b
};

// 12. Join the player's push: free AI groups near a human moving on the target go with them.
// Orders only groups the commander already owns; never a player's group or AI.
SWLC_fnc_smartJoinHuman = {
	params ["_cmd", "_p"];
	private _target = _cmd get "target";
	if (isNull _target) exitWith {};
	private _tpos = [_target] call SWLC_fnc_adPos;
	private _free = (_cmd get "groups") select {([_x] call SWLC_fnc_state) in ["Unassigned", "Mustering", "Waiting"] && {(leader _x distance2D _p) <= CFG("joinPushRadius")}};
	private _free2 = [_free, [], {leader _x distance2D _p}, "ASCEND"] call BIS_fnc_sortBy;
	{
		[_cmd, _x] call SWLC_fnc_waveRemoveGroup;
		[_x, "Assaulting", _tpos, "join_push"] call SWLC_fnc_setState;
		_x setVariable ["SWLC_joinUntil", time + CFG("joinPushSeconds")];
		[_x, [[getPosATL _p, "MOVE", 30], [_tpos, "SAD", 60]], "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
		[_cmd, "joinpush", "attached", [["group", groupId _x], ["player", name _p]]] call SWLC_fnc_smartLog;
		[_cmd get "side", "joinpush", [name _p], _x] call SWLC_fnc_radio;
	} forEach (_free2 select [0, CFG("joinPushGroups")]);
};

SWLC_fnc_smartJoinTick = {
	params ["_cmd"];
	if !(CFG("smartJoinPush")) exitWith {};
	{
		private _until = _x getVariable ["SWLC_joinUntil", -1];
		if (_until >= 0 && {time >= _until}) then {
			_x setVariable ["SWLC_joinUntil", -1];
			[_x] call SWLC_fnc_adClearOrder;
			[_x, "Unassigned", [], "join_push_done"] call SWLC_fnc_setState;
		};
	} forEach (_cmd get "groups");

	private _target = _cmd get "target";
	if (isNull _target) exitWith {};
	private _side = _cmd get "side";
	private _tpos = [_target] call SWLC_fnc_adPos;
	{
		private _p = _x;
		if (alive _p && {side group _p == _side}) then {
			private _d = _p distance2D _tpos;
			private _last = _p getVariable ["SWLC_lastD", -1];
			_p setVariable ["SWLC_lastD", _d];
			if (_d <= CFG("joinPushRange") && {_last > 0} && {(_last - _d) >= CFG("joinPushMinMetres")}
				&& {(time - (_p getVariable ["SWLC_joinAt", -1e6])) >= CFG("joinPushCooldown")}) then {
				_p setVariable ["SWLC_joinAt", time];
				[_cmd, _p] call SWLC_fnc_smartJoinHuman;
			};
		};
	} forEach allPlayers;
};
