// Phase 0 gate: adapter tracks target and ownership over time, and moves an owned AI group to a
// chosen sector without Warlords overriding the order. Also tests fast travel, vanilla vehicle
// suppression, and logs seize-area counts to learn the capture threshold.

waitUntil {sleep 1; !isNil "SWLC_ready"};

SWLG_emit = {
	params ["_type", "_fields"];
	diag_log text ((["SWL", _type, format ["t=%1", round time]] + _fields) joinString "|");
};

// Adapter state readout every 5 s, compared later against the observer's TARGET/CAPTURE lines.
[] spawn {
	scriptName "gate0 adapter log";
	while {true} do {
		{
			private _side = _x;
			private _target = [_side] call SWLC_fnc_adTarget;
			private _owned = [_side] call SWLC_fnc_adOwned;
			["ADAPTER", [
				format ["side=%1", _side],
				format ["target=%1", if (isNull _target) then {"-"} else {str ([_target] call SWLC_fnc_adPos)}],
				format ["owned=%1", (_owned apply {str ([_x] call SWLC_fnc_adPos)}) joinString ";"],
				format ["cp=%1", round ([_side] call SWLC_fnc_adSideCP)],
				format ["groups=%1", count ([_side] call SWLC_fnc_adOwnableGroups)]
			]] call SWLG_emit;
		} forEach [west, east];
		sleep 5;
	};
};

// Seize-area census: who stands in each current target's square, and the capture countdown.
[] spawn {
	scriptName "gate0 seize log";
	waitUntil {sleep 1; !isNil "BIS_WL_sectors"};
	while {true} do {
		{
			private _t = [_x] call SWLC_fnc_adTarget;
			if (!isNull _t) then {
				private _units = [_t] call SWLC_fnc_adUnitsInSquare;
				["SEIZE", [
					format ["target_of=%1", _x],
					format ["sector=%1", [_t] call SWLC_fnc_adName],
					format ["owner=%1", [_t] call SWLC_fnc_adOwner],
					format ["w=%1", {side group _x == west} count _units],
					format ["e=%1", {side group _x == east} count _units],
					format ["g=%1", {side group _x == resistance} count _units],
					format ["cdw=%1", _t getVariable ["BIS_WL_timeoutCur_WEST", -1]],
					format ["cde=%1", _t getVariable ["BIS_WL_timeoutCur_EAST", -1]]
				]] call SWLG_emit;
			};
		} forEach [west, east];
		sleep 10;
	};
};

// Stop vanilla vehicle buying on every AI warlord. Log whether it took.
[] spawn {
	scriptName "gate0 vehicle suppression";
	while {true} do {
		{
			[_x] call SWLC_fnc_adSuppressVanillaVehicles;
		} forEach (([west] call SWLC_fnc_adAIWarlords) + ([east] call SWLC_fnc_adAIWarlords));
		sleep 15;
	};
};

// The move test: wait until WEST has a target and groups are out, take one WEST group and
// send it to a point short of a chosen sector that is not its target. Waypoints must hold.
sleep 90;
private _groups = ([west] call SWLC_fnc_adOwnableGroups) select {!([_x] call SWLC_fnc_adGroupHasPlayer)};
private _g = _groups # 0;
private _target = [west] call SWLC_fnc_adTarget;
private _chosen = objNull;
private _best = -1;
{
	if (_x != _target && {!([_x] call SWLC_fnc_adIsBase)}) then {
		private _d = (getPosATL leader _g) distance2D ([_x] call SWLC_fnc_adPos);
		if (_d > _best) then {_best = _d; _chosen = _x};
	};
} forEach SWLC_sectors;

private _sectorPos = [_chosen] call SWLC_fnc_adPos;
private _size = [_chosen] call SWLC_fnc_adSize;
private _dest = [_sectorPos, [_sectorPos, getPosATL leader _g] call SWLC_fnc_bearing, _size / 2 + 150] call SWLC_fnc_offset;
SWLG_testGroup = _g;
["MOVE_TEST", [
	"event=order",
	format ["group=%1", groupId _g],
	format ["netid=%1", netId _g],
	format ["sector=%1", [_chosen] call SWLC_fnc_adName],
	format ["x=%1", round (_dest # 0)],
	format ["y=%1", round (_dest # 1)]
]] call SWLG_emit;

[_g, [[_dest, "MOVE", 30]], "AWARE", "FULL", "WEDGE", "YELLOW"] call SWLC_fnc_adSetOrder;

[_g, _dest] spawn {
	params ["_g", "_dest"];
	scriptName "gate0 move guard";
	private _reassert = 0;
	private _arrived = false;
	private _startDist = (getPosATL leader _g) distance2D _dest;
	private _endAt = time + 900;
	while {time < _endAt} do {
		sleep 3;
		if ([_g] call SWLC_fnc_adGuardOrder) then {
			_reassert = _reassert + 1;
			["MOVE_TEST", ["event=reassert", format ["count=%1", _reassert]]] call SWLG_emit;
		};
		if (floor (time / 15) != floor ((time - 3) / 15)) then {
			private _pos = getPosATL leader _g;
			private _wpIdx = currentWaypoint _g;
			private _wpPos = if (_wpIdx < count waypoints _g) then {waypointPosition [_g, _wpIdx]} else {[-1, -1, -1]};
			private _dist = _pos distance2D _dest;
			["MOVE_TEST", [
				"event=track",
				format ["dist=%1", round _dist],
				format ["wpdist=%1", round (_wpPos distance2D _dest)],
				format ["wp=%1/%2", _wpIdx, count waypoints _g],
				format ["alive=%1", {alive _x} count units _g],
				format ["beh=%1", behaviour leader _g]
			]] call SWLG_emit;
			if (!_arrived && {_dist < 60}) then {
				_arrived = true;
				["MOVE_TEST", ["event=arrived", format ["start_dist=%1", round _startDist]]] call SWLG_emit;
			};
		};
	};
};

// Fast travel test: 3 minutes later, teleport a different group to its own base through the adapter.
sleep 180;
private _others = (([west] call SWLC_fnc_adOwnableGroups) - [_g]) select {
	(!([_x] call SWLC_fnc_adGroupHasPlayer)) && {(leader _x distance2D ([[west] call SWLC_fnc_adBase] call SWLC_fnc_adPos)) > 600}
};
if (_others isNotEqualTo []) then {
	private _ft = _others # 0;
	private _base = [west] call SWLC_fnc_adBase;
	private _bp = [_base] call SWLC_fnc_adPos;
	private _land = [_bp, [_bp, getPosATL leader _ft] call SWLC_fnc_bearing, 80] call SWLC_fnc_offset;
	private _before = getPosATL leader _ft;
	private _ok = [_ft, _base, _land] call SWLC_fnc_adFastTravel;
	sleep 1;
	["FT_TEST", [
		format ["group=%1", groupId _ft],
		format ["ok=%1", _ok],
		format ["from=%1", round (_before distance2D _bp)],
		format ["to=%1", round ((getPosATL leader _ft) distance2D _bp)],
		format ["cp=%1", leader _ft getVariable ["BIS_WL_funds", -1]]
	]] call SWLG_emit;
} else {
	["FT_TEST", ["ok=skipped", "reason=no_group_far_from_base"]] call SWLG_emit;
};

// Contested fast travel refusal test: try to teleport to an unowned sector.
private _unowned = SWLC_sectors select {([_x] call SWLC_fnc_adOwner) != west};
if (_unowned isNotEqualTo [] && {_groups isNotEqualTo []}) then {
	private _test = (_groups - [_g]) param [0, grpNull];
	if (!isNull _test) then {
		private _s = _unowned # 0;
		private _ok = [_test, _s, [_s] call SWLC_fnc_adPos] call SWLC_fnc_adFastTravel;
		["FT_REFUSE", [format ["ok=%1", _ok], format ["sector=%1", [_s] call SWLC_fnc_adName]]] call SWLG_emit;
	};
};
