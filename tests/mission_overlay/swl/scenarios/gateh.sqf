// Part H gates. Posture happens on its own. The rest are set up here because a short round can't be
// relied on to produce them: groups are small, nobody runs out of rockets, and a pinning MG has to be
// in the right place. Run with:
//   -Scenario gateh -Overrides "scoutMinGroups=99;scanBuying=false"

waitUntil {sleep 1; !isNil "SWLC_ready" && {!isNil "SWLC_cmd_WEST"}};

SWLG_emit = {
	params ["_type", "_fields"];
	diag_log text ((["SWL", _type, format ["t=%1", round time]] + _fields) joinString "|");
};

waitUntil {sleep 1; !isNull ([west] call SWLC_fnc_adTarget)};
SWLG_west = missionNamespace getVariable "SWLC_cmd_WEST";

["GH", [format ["event=begin|lambs=%1", SWLC_lambs]]] call SWLG_emit;

// Tops a group up to _size riflemen. Men are invulnerable so the behaviour gets time to show.
SWLG_topUp = {
	params ["_g", "_size"];
	private _pos = getPosATL leader _g;
	while {({alive _x} count units _g) < _size} do {
		private _u = _g createUnit ["B_T_Soldier_F", _pos, [], 6, "NONE"];
		[_u] joinSilent _g;
	};
	{_x allowDamage false} forEach units _g;
};

// Bounding needs squads big enough to split. Every op group waiting at the rally gets topped up.
[] spawn {
	private _deadline = time + 720;
	while {time < _deadline} do {
		sleep 2;
		private _w = SWLG_west get "op";
		if (!isNil "_w") then {
			{
				if (([_x] call SWLC_fnc_state) in ["Waiting", "Advancing", "Assaulting"] && {!(_x getVariable ["SWLG_big", false])} && {(_x getVariable ["SWLC_leg", ""]) == "FOOT"}) then {
					_x setVariable ["SWLG_big", true];
					[_x, 6] call SWLG_topUp;
					["GH", [format ["event=topped_up|group=%1|men=%2", groupId _x, {alive _x} count units _x]]] call SWLG_emit;
				};
			} forEach ([_w] call SWLC_fnc_waveLive);
		};
	};
};

// Pinned: once a topped-up squad is assaulting on foot, a crewed MG ahead of it keeps it under fire
// and its feet are held, so it can't make progress. Vanilla only, since flanking is off under LAMBS.
if (!SWLC_lambs) then {
	[] spawn {
		private _deadline = time + 720;
		private _g = grpNull;
		waitUntil {
			sleep 2;
			private _w = SWLG_west get "op";
			if (!isNil "_w") then {
				private _ready = ([_w] call SWLC_fnc_waveLive) select {([_x] call SWLC_fnc_state) == "Assaulting" && {(_x getVariable ["SWLC_leg", ""]) == "FOOT"} && {({alive _x} count units _x) >= 4} && {(_x getVariable ["SWLG_big", false])}};
				if (_ready isNotEqualTo []) then {_g = _ready # 0};
			};
			!isNull _g || {time > _deadline}
		};
		if (isNull _g) exitWith {["GH", ["event=pin_no_group"]] call SWLG_emit};

		// A bound in progress would keep the test waiting, so the squad starts this one standing still.
		private _l = leader _g;
		private _target = [west] call SWLC_fnc_adTarget;
		// The gun needs a clear line to the squad, or nothing ever suppresses it.
		private _toTarget = [getPosATL _l, [_target] call SWLC_fnc_adPos] call SWLC_fnc_bearing;
		private _spot = [];
		private _eye = eyePos _l;
		{
			private _try = [getPosATL _l, _toTarget + _x, 120] call SWLC_fnc_offset;
			if (_spot isEqualTo [] && {!surfaceIsWater _try} && {([objNull, "VIEW"] checkVisibility [ATLToASL [_try # 0, _try # 1, 2.5], _eye]) > 0.5}) then {_spot = _try};
		} forEach [0, 30, -30, 60, -60, 90, -90, 120, -120, 150, -150, 180];
		private _clear = _spot isNotEqualTo [];
		if (!_clear) then {
			_spot = [getPosATL _l, _toTarget, 120] call SWLC_fnc_offset;
			if (surfaceIsWater _spot) then {_spot = getPosATL _l};
		};
		private _mg = createVehicle ["O_HMG_01_high_F", _spot, [], 0, "NONE"];
		createVehicleCrew _mg;
		_mg allowDamage false;
		{_x allowDamage false} forEach crew _mg;
		(group gunner _mg) setCombatMode "RED";
		(group gunner _mg) reveal [_l, 4];
		{_x disableAI "PATH"; _x allowDamage false} forEach units _g;
		{_g reveal [_x, 4]} forEach crew _mg;
		["GH", [format ["event=pin|group=%1|men=%2|d_mg=%3|clear=%4", groupId _g, {alive _x} count units _g, round (_l distance2D _spot), _clear]]] call SWLG_emit;

		private _end = time + 240;
		private _traceAt = 0;
		waitUntil {
			// Real bullets over their heads. The gunner on its own often has no firing solution for prone men.
			for "_k" from 1 to 6 do {
				private _men = (units _g) select {alive _x};
				if (_men isNotEqualTo []) then {_mg fireAtTarget [selectRandom _men]};
				sleep 0.5;
			};
			_mg setVehicleAmmo 1;
			{(group gunner _mg) reveal [_x, 4]} forEach units _g;
			if (time > _traceAt) then {
				_traceAt = time + 9;
				private _sup = (units _g) select {alive _x} apply {getSuppression _x};
				["GH", [format ["event=pin_trace|avg=%1|max=%2|still=%3|beh=%4|state=%5", ((_sup call BIS_fnc_arithmeticMean) toFixed 2), ((selectMax _sup) toFixed 2), round (time - (_g getVariable ["SWLC_pinBestAt", time])), behaviour leader _g, [_g] call SWLC_fnc_state]]] call SWLG_emit;
			};
			(_g getVariable ["SWLC_squadTask", ""]) == "flank" || {time > _end}
		};
		{_x enableAI "PATH"; _x allowDamage true} forEach units _g;
		if ((_g getVariable ["SWLC_squadTask", ""]) == "flank") then {
			["GH", [format ["event=pin_flanking|group=%1", groupId _g]]] call SWLG_emit;
			sleep 90;
		} else {
			["GH", [format ["event=pin_no_flank|group=%1|suppression=%2|behaviour=%3", groupId _g, getSuppression leader _g, behaviour leader _g]]] call SWLG_emit;
		};
		deleteVehicleCrew _mg;
		deleteVehicle _mg;
	};
} else {
	["GH", ["event=pin_skipped_lambs"]] call SWLG_emit;
};

// AT soldier with no rockets, next to a crate that has some.
[] spawn {
	private _deadline = time + 420;
	private _g = grpNull;
	waitUntil {
		sleep 3;
		private _spare = (SWLG_west get "groups") select {([_x] call SWLC_fnc_state) in ["Mustering", "Waiting", "Reserve", "Unassigned"] && {vehicle leader _x == leader _x} && {!(_x getVariable ["SWLG_big", false])}};
		if (_spare isNotEqualTo []) then {_g = _spare # 0};
		!isNull _g || {time > _deadline}
	};
	if (isNull _g) exitWith {["GH", ["event=at_no_group"]] call SWLG_emit};

	_g setVariable ["SWLG_big", true];
	private _pos = getPosATL leader _g;
	private _u = _g createUnit ["B_T_Soldier_LAT_F", _pos, [], 3, "NONE"];
	[_u] joinSilent _g;
	_u allowDamage false;
	private _w = secondaryWeapon _u;
	private _mags = compatibleMagazines _w;
	{_u removeMagazines _x} forEach _mags;
	_u removeWeapon _w;
	_u addWeapon _w;

	private _cratePos = _pos findEmptyPosition [20, 45, "Box_NATO_Ammo_F"];
	if (_cratePos isEqualTo []) then {_cratePos = [_pos, 45, 30] call SWLC_fnc_offset};
	private _crate = createVehicle ["Box_NATO_Ammo_F", _cratePos, [], 0, "CAN_COLLIDE"];
	clearWeaponCargoGlobal _crate;
	clearMagazineCargoGlobal _crate;
	clearItemCargoGlobal _crate;
	_crate addMagazineCargoGlobal [_mags # 0, 4];
	_g setVariable ["SWLC_rearmNext", 0];
	["GH", [format ["event=at_setup|group=%1|weapon=%2|mag=%3|d_crate=%4|loaded=%5", groupId _g, _w, _mags # 0, round (_u distance2D _crate), count secondaryWeaponMagazine _u]]] call SWLG_emit;

	private _end = time + 150;
	[_u, _crate, _end] spawn {
		params ["_u", "_crate", "_end"];
		while {time < _end && {alive _u}} do {
			["GH", [format ["event=at_trace|d=%1|cmd=%2|ready=%3|speed=%4|pos=%5|beh=%6", round (_u distance2D _crate), currentCommand _u, unitReady _u, round speed _u, unitPos _u, behaviour _u]]] call SWLG_emit;
			sleep 6;
		};
	};
	_mags = _mags apply {toLower _x};
	private _mine = {
		params ["_u", "_mags"];
		count (((magazines _u) + (secondaryWeaponMagazine _u)) select {(toLower _x) in _mags})
	};
	waitUntil {sleep 2; ([_u, _mags] call _mine) > 0 || {time > _end} || {!alive _u}};
	private _have = [_u, _mags] call _mine;
	private _crateLeft = {(toLower _x) in _mags} count (magazineCargo _crate);
	["GH", [format ["event=%1|have=%2|crate_left=%3", ["at_not_restocked", "at_restocked"] select (_have > 0), _have, _crateLeft]]] call SWLG_emit;
	if (_have > 0) then {
		private _deadlineBack = time + 60;
		waitUntil {sleep 2; (_u distance2D leader _g) <= 40 || {time > _deadlineBack}};
		["GH", [format ["event=at_rejoined|dist=%1|group_same=%2", round (_u distance2D leader _g), group _u == _g]]] call SWLG_emit;
	};
};

// LAMBS: garrison a spare group at an owned sector, let go, then clear the same buildings and let go.
if (SWLC_lambs) then {
	[] spawn {
		sleep 60;
		private _deadline = time + 420;
		private _g = grpNull;
		private _s = objNull;
		waitUntil {
			sleep 5;
			private _spare = (SWLG_west get "groups") select {([_x] call SWLC_fnc_state) in ["Mustering", "Reserve", "Unassigned", "Travelling", "Waiting"] && {!(_x getVariable ["SWLG_big", false])} && {vehicle leader _x == leader _x}};
			if (_spare isNotEqualTo []) then {
				_g = _spare # 0;
				_s = [west] call SWLC_fnc_adBase;
			};
			!isNull _g || {time > _deadline}
		};
		if (isNull _g) exitWith {["GH", ["event=lambs_no_group"]] call SWLG_emit};

		[SWLG_west, _g] call SWLC_fnc_waveRemoveGroup;
		[_g, "Defending", [_s] call SWLC_fnc_adPos, "gateh"] call SWLC_fnc_setState;
		{_x allowDamage false} forEach units _g;
		private _ok = [SWLG_west, _g, _s] call SWLC_fnc_lambsHold;
		["GH", [format ["event=lambs_hold|group=%1|ok=%2|task=%3|waypoints=%4", groupId _g, _ok, _g getVariable ["SWLC_lambsTask", ""], count waypoints _g]]] call SWLG_emit;
		sleep 60;
		private _inside = {(insideBuilding _x) > 0.5} count (units _g select {alive _x});
		["GH", [format ["event=lambs_held|men=%1|indoors=%2|busy=%3", {alive _x} count units _g, _inside, [_g] call SWLC_fnc_lambsBusy]]] call SWLG_emit;
		[_g, true] call SWLC_fnc_lambsRelease;
		sleep 8;
		["GH", [format ["event=lambs_hold_released|task=%1|waypoints=%2", _g getVariable ["SWLC_lambsTask", ""], count waypoints _g]]] call SWLG_emit;

		[_g, "Assaulting", [_s] call SWLC_fnc_adPos, "gateh"] call SWLC_fnc_setState;
		_ok = [SWLG_west, _g, _s] call SWLC_fnc_lambsClear;
		["GH", [format ["event=lambs_clear|group=%1|ok=%2|task=%3", groupId _g, _ok, _g getVariable ["SWLC_lambsTask", ""]]]] call SWLG_emit;
		sleep 90;
		["GH", [format ["event=lambs_clearing|task=%1|handle_done=%2", _g getVariable ["SWLC_lambsTask", ""], scriptDone (_g getVariable ["SWLC_lambsHandle", scriptNull])]]] call SWLG_emit;
		[_g, true] call SWLC_fnc_lambsRelease;
		sleep 8;
		[_g, "Unassigned", [], "gateh"] call SWLC_fnc_setState;
		[_g] call SWLC_fnc_adClearOrder;
		{_x allowDamage true} forEach units _g;
		["GH", [format ["event=lambs_clear_released|task=%1|disable=%2", _g getVariable ["SWLC_lambsTask", ""], !isNil {_g getVariable "lambs_danger_disableGroupAI"}]]] call SWLG_emit;
	};
} else {
	["GH", ["event=lambs_absent"]] call SWLG_emit;
};
