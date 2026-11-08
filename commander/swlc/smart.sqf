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
	// SMART_INIT
	[_cmd] call SWLC_fnc_smartBreakTick;
	[_cmd] call SWLC_fnc_smartRadioTick;
	[_cmd] call SWLC_fnc_smartReinforceTick;
	[_cmd] call SWLC_fnc_smartScoutTick;
	// SMART_CALLS
};

SWLC_fnc_smartOnSeized = {
	params ["_cmd", "_w", "_live"];
	[_cmd, _w, _live] call SWLC_fnc_smartCheer;
	[_cmd, _w, _live] call SWLC_fnc_smartMomentum;
	// SMART_SEIZED
};

// 1. Break and consolidate: a group down to about a third pulls back to staging and merges.
SWLC_fnc_smartBreakTick = {
	params ["_cmd"];
	if !(CFG("smartBreak")) exitWith {};
	{
		private _w = _x;
		if ((_w get "phase") in ["TO_HOLD", "ASSAULT"]) then {
			{
				private _g = _x;
				private _launch = _g getVariable ["SWLC_launchMen", 0];
				private _men = [_g] call SWLC_fnc_groupMen;
				if (_launch >= CFG("breakMinLaunchMen") && {(_g getVariable ["SWLC_leg", ""]) == "FOOT"} && {_men <= ((floor (_launch * CFG("breakFraction"))) max 1)}) then {
					[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
					_g setVariable ["SWLC_broke", true];
					if (!isNil {_cmd get "gather"}) then {
						[_cmd, _g, "Regrouping"] call SWLC_fnc_sendToStaging;
					} else {
						[_g] call SWLC_fnc_adClearOrder;
						[_g, "Unassigned", [], "broke"] call SWLC_fnc_setState;
					};
					[_cmd, "break", "retreat", [["group", groupId _g], ["men", _men], ["launched", _launch], ["wave", _w get "id"]]] call SWLC_fnc_smartLog;
					[_cmd get "side", "breaking", [], _g] call SWLC_fnc_radio;
				};
			} forEach ([_w] call SWLC_fnc_waveLive);
		};
	} forEach (_cmd get "flying");

	// Merge at staging. Warlords stay in their own groups, so only their bought men change group.
	private _groups = _cmd get "groups";
	{
		private _g = _x;
		private _partners = _groups select {
			_x isNotEqualTo _g && {([_x] call SWLC_fnc_state) == "Staging"}
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
	} forEach (_groups select {(_x getVariable ["SWLC_broke", false]) && {([_x] call SWLC_fnc_state) == "Staging"}});
};

// 2. Livelier radio: heavy-losses calls. Breaking and cheer calls are sent where those events happen.
SWLC_fnc_smartRadioTick = {
	params ["_cmd"];
	if !(CFG("smartRadio")) exitWith {};
	{
		if ((_x get "phase") in ["TO_HOLD", "ASSAULT"]) then {
			{
				private _g = _x;
				private _launch = _g getVariable ["SWLC_launchMen", 0];
				if (_launch >= 2 && {!(_g getVariable ["SWLC_heavyCalled", false])} && {([_g] call SWLC_fnc_groupMen) <= _launch * (1 - CFG("radioHeavyFraction"))}) then {
					_g setVariable ["SWLC_heavyCalled", true];
					[_cmd get "side", "heavy", [], _g] call SWLC_fnc_radio;
				};
			} forEach ([_x] call SWLC_fnc_waveLive);
		};
	} forEach (_cmd get "flying");
};

SWLC_fnc_smartCheer = {
	params ["_cmd", "_w", "_live"];
	if !(CFG("smartRadio")) exitWith {};
	if (_live isNotEqualTo []) then {[_cmd get "side", "cheer", [], selectRandom _live] call SWLC_fnc_radio};
};

// 3. Reinforce success: groups stalled on one approach follow an approach that has broken in.
SWLC_fnc_smartReinforceTick = {
	params ["_cmd"];
	if !(CFG("smartReinforce")) exitWith {};
	{
		private _w = _x;
		if ((_w get "phase") == "ASSAULT") then {
			private _target = _w get "target";
			private _tpos = [_target] call SWLC_fnc_adPos;
			private _live = [_w] call SWLC_fnc_waveLive;

			// Track each group's closest approach to the target.
			private _foot = _live select {(_x getVariable ["SWLC_leg", ""]) == "FOOT"};
			{
				private _d = (leader _x) distance2D _tpos;
				if (_d < ((_x getVariable ["SWLC_bestD", 1e9]) - CFG("reinforceMinMetres"))) then {
					_x setVariable ["SWLC_bestD", _d];
					_x setVariable ["SWLC_bestAt", time];
				};
			} forEach _foot;

			private _approaches = _w get "approaches";
			private _working = _approaches findIf {
				((_x get "groups") select {_x in _foot}) findIf {[_target, getPosATL leader _x] call SWLC_fnc_adInSquare} >= 0
			};
			if (_working >= 0) then {
				private _good = _approaches # _working;
				{
					private _a = _x;
					if (_forEachIndex != _working) then {
						{
							private _g = _x;
							if (_g in _foot && {!([_target, getPosATL leader _g] call SWLC_fnc_adInSquare)}
								&& {(time - (_g getVariable ["SWLC_bestAt", time])) >= CFG("reinforceStallSeconds")}
								&& {!(_g getVariable ["SWLC_reinforced", false])}) then {
								_g setVariable ["SWLC_reinforced", true];
								(_a get "groups") deleteAt ((_a get "groups") find _g);
								(_good get "groups") pushBackUnique _g;
								private _order = [[_good get "hold", "MOVE", 30]] + ([_target] call SWLC_fnc_sweepOrder);
								[_g, "Assaulting", _tpos, "reinforce"] call SWLC_fnc_setState;
								[_g, _order, "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
								[_cmd, "reinforce", "redirect", [["group", groupId _g], ["wave", _w get "id"], ["from_bearing", round (_a get "bearing")], ["to_bearing", round (_good get "bearing")]]] call SWLC_fnc_smartLog;
							};
						} forEach ((_a get "groups") select {true});
					};
				} forEach _approaches;
			};
		};
	} forEach (_cmd get "flying");
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
		private _a = _x;
		{
			private _u = leader _x;
			private _mag = (magazines _u) select {_x isKindOf ["SmokeShell", configFile >> "CfgMagazines"]};
			if (_x in _live && {alive _u} && {(_x getVariable ["SWLC_leg", ""]) == "FOOT"} && {_mag isNotEqualTo []}) then {
				private _here = getPosATL _u;
				private _p = [_here, [_here, _enemy] call SWLC_fnc_bearing, CFG("smokeThrowDist")] call SWLC_fnc_offset;
				_u removeMagazine (_mag # 0);
				createVehicle ["SmokeShell", _p, [], 0, "CAN_COLLIDE"];
				_thrown = _thrown + 1;
				[_cmd, "smoke", "thrown", [["group", groupId _x], ["x", round (_p # 0)], ["y", round (_p # 1)], ["known_enemy", _enemy isNotEqualTo ([_w get "target"] call SWLC_fnc_adPos)]]] call SWLC_fnc_smartLog;
			};
		} forEach (((_a get "groups") select {_x in _live}) select [0, CFG("smokeGroupsPerApproach")]);
	} forEach (_w get "approaches");
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
		alive _x && {getNumber (configOf _x >> "artilleryScanner") > 0} && {!isNull gunner _x} && {alive gunner _x} && {!isPlayer gunner _x} && {side group gunner _x == _side} && {local gunner _x}
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
			if ((_t get "armour") == 0 && {_known <= CFG("momentumWeakMen")} && {_known < _bestMen}) then {
				_best = _x;
				_bestMen = _known;
			};
		};
	} forEach ([_w get "target"] call SWLC_fnc_adLinks);
	if (isNull _best) exitWith {
		[_cmd, "momentum", "no_weak_neighbour", [["took", round _took]]] call SWLC_fnc_smartLog;
	};
	_cmd set ["momentum", [_best, time + CFG("momentumHoldSeconds")]];
	[_cmd, "momentum", "push", [["from", [_w get "target"] call SWLC_fnc_adName], ["to", [_best] call SWLC_fnc_adName], ["took", round _took], ["men", _men], ["known_defenders", _bestMen]]] call SWLC_fnc_smartLog;
	[_side, "momentum", [[_best] call SWLC_fnc_adName]] call SWLC_fnc_radio;
};

// 7. Scout first: a small group goes ahead while the wave gathers. Never holds up the go.
SWLC_fnc_smartScoutTick = {
	params ["_cmd"];
	if !(CFG("smartScout")) exitWith {};
	private _side = _cmd get "side";
	private _w = _cmd get "gather";
	if (!isNil "_w" && {!(_w getOrDefault ["scoutSent", false])}) then {
		private _target = _w get "target";
		private _groups = [_w] call SWLC_fnc_waveLive;
		if !(([_cmd, _target] call SWLC_fnc_threatOf) get "scouted") then {
			if ((count _groups) >= CFG("scoutMinGroups")) then {
				private _sorted = [_groups select {([_x] call SWLC_fnc_state) in ["Staging", "Travelling"]}, [], {[_x] call SWLC_fnc_groupMen}, "ASCEND"] call BIS_fnc_sortBy;
				if (_sorted isNotEqualTo []) then {
					_w set ["scoutSent", true];
					private _g = _sorted # 0;
					private _tpos = [_target] call SWLC_fnc_adPos;
					private _spot = [_side, _tpos, [_tpos, _cmd get "stagingPos"] call SWLC_fnc_bearing, CFG("scoutDist")] call SWLC_fnc_validHoldPoint;
					[_cmd, _g] call SWLC_fnc_waveRemoveGroup;
					[_g, "Recon", _spot, "scout"] call SWLC_fnc_setState;
					_g setVariable ["SWLC_scoutUntil", time + CFG("scoutMaxSeconds")];
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
							_g setVariable ["SWLC_scoutEntry", _entry];
							_g setVariable ["SWLC_scoutUntil", time + CFG("scoutMaxSeconds") + CFG("scoutVehicleWait")];
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
					// The vehicle joins the motor pool, parked, for a later wave.
					if (alive _v) then {
						(_g getVariable "SWLC_scoutEntry") params ["_cls", "_cost", "_seats", "_role", "_heavy"];
						private _id = (_cmd get "vehCounter") + 1;
						_cmd set ["vehCounter", _id];
						(_cmd get "vehicles") pushBack (createHashMapFromArray [["id", _id], ["obj", _v], ["cls", _cls], ["role", _role], ["heavy", _heavy], ["seats", _seats], ["state", "parked"],
							["group", grpNull], ["wave", -1], ["boughtAt", time], ["stuck", 0], ["mounted", false]]);
					};
				};
				[_g] call SWLC_fnc_adClearOrder;
				[_g, "Unassigned", [], "scout_done"] call SWLC_fnc_setState;
				[_cmd, "scout", "done", [["group", groupId _g], ["alive", [_g] call SWLC_fnc_groupMen]]] call SWLC_fnc_smartLog;
			};
		};
	} forEach (_cmd get "groups");
};
