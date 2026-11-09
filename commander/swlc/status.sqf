// What each AI commander is doing, in plain words, for the on-screen panel in client.sqf.
#include "macros.hpp"

SWLC_fnc_statusClock = {
	params ["_s"];
	private _t = floor (_s max 0);
	format ["%1:%2%3", floor (_t / 60), ["", "0"] select ((_t mod 60) < 10), _t mod 60]
};

// The name of the owned or contested sector nearest a position.
SWLC_fnc_statusPlace = {
	params ["_pos"];
	if (_pos isEqualTo []) exitWith {"-"};
	private _best = objNull;
	private _bestD = 1e9;
	{
		private _d = ([_x] call SWLC_fnc_adPos) distance2D _pos;
		if (_d < _bestD) then {_bestD = _d; _best = _x};
	} forEach SWLC_sectors;
	[_best] call SWLC_fnc_adName
};

// [name, job, place, reason, seconds in this job]
SWLC_fnc_statusRow = {
	params ["_cmd", "_g"];
	private _op = _cmd get "op";
	private _hasOp = !isNil "_op";
	private _state = [_g] call SWLC_fnc_state;
	private _since = round (time - (_g getVariable ["SWLC_stateSince", time]));
	private _goal = _g getVariable ["SWLC_goal", []];
	private _dist = if (_goal isEqualTo []) then {0} else {round (leader _g distance2D _goal)};
	private _tName = if (_hasOp) then {[_op get "target"] call SWLC_fnc_adName} else {"-"};
	private _job = _state;
	private _place = "-";
	private _reason = "";

	switch (_state) do {
		case "Unassigned": {
			_job = "Idle";
			_place = [getPosATL leader _g] call SWLC_fnc_statusPlace;
			_reason = if (_hasOp) then {"getting orders"} else {"no target yet, waiting for the vote"};
		};
		case "Travelling": {
			_job = "Moving";
			_place = "to " + (_g getVariable ["SWLC_musterName", "muster"]);
			_reason = format ["joining the muster, %1 m out", _dist];
		};
		case "Mustering": {
			_job = "Mustering";
			private _rec = (_cmd get "musters") getOrDefault [_g getVariable ["SWLC_musterName", ""], createHashMap];
			_place = _g getVariable ["SWLC_musterName", "-"];
			if (count _rec > 0) then {
				private _inbound = (_rec get "groups") select {([_x] call SWLC_fnc_state) == "Travelling"};
				private _left = ((_rec get "firstArrive") + CFG("musterSeconds")) - time;
				_reason = if (_inbound isNotEqualTo []) then {
					format ["waiting for %1 to arrive", groupId (_inbound # 0)]
				} else {
					if (_left > 0) then {format ["leaving in %1", [_left] call SWLC_fnc_statusClock]} else {"waiting for bought men to land"}
				};
			};
		};
		case "Mounting": {
			_job = "Boarding";
			_place = _g getVariable ["SWLC_musterName", "-"];
			_reason = if ([_g] call SWLC_fnc_kitPending) then {"drawing kit at the crate"} else {
				if (count ([_g] call SWLC_fnc_vehRecOf) > 0) then {"getting into the vehicle"} else {"ready to leave"}
			};
		};
		case "Advancing": {
			_job = "Moving";
			_place = "to rally";
			private _leg = _g getVariable ["SWLC_leg", ""];
			_reason = format ["%1, %2 m out", ["on foot", "driving"] select (_leg in ["DRIVE", "FOLLOW"]), _dist];
		};
		case "Engaged": {
			_job = "Fighting";
			_place = "on the way";
			_reason = ["moving to help", "in contact"] select ([_g] call SWLC_fnc_groupFighting);
		};
		case "Waiting": {
			_job = "Waiting";
			_place = "rally point";
			if (_hasOp) then {
				if (time < (_g getVariable ["SWLC_restUntil", -1])) then {
					_reason = "regrouping after falling back";
				} else {
					private _ready = {([_x] call SWLC_fnc_state) == "Waiting" && {time >= (_x getVariable ["SWLC_restUntil", -1])}} count ([_op] call SWLC_fnc_waveLive);
					private _need = (([_cmd, _op] call SWLC_fnc_stratGoCount) - _ready) max 0;
					private _first = _op get "firstAtRally";
					private _left = if (_first < 0) then {0} else {(_first + ([_cmd, _op] call SWLC_fnc_rallyLoneWait)) - time};
					_reason = if (_need > 0) then {format ["needs %1 more group to go, or alone in %2", _need, [_left] call SWLC_fnc_statusClock]} else {"going in now"};
				};
			};
		};
		case "Assaulting": {
			_job = "Attacking";
			_place = _tName;
			if (_g getVariable ["SWLC_joinUntil", -1] >= 0) then {
				_reason = "pushing with a player";
			} else {
				if (_hasOp) then {
					private _in = {([_x] call SWLC_fnc_state) == "Assaulting"} count ([_op] call SWLC_fnc_waveLive);
					private _known = ([_cmd, _op get "target"] call SWLC_fnc_threatOf) get "infantry";
					_reason = format ["%1 %2 in, %3 enemy known", _in, ["groups", "group"] select (_in == 1), _known];
					if ((_g getVariable ["SWLC_leg", ""]) == "FOLLOW") then {_reason = "combat vehicle, behind the infantry"};
				};
			};
		};
		case "Regrouping": {
			_job = "Falling back";
			_place = "rally point";
			_reason = format ["down to %1 men, %2 m out", [_g] call SWLC_fnc_groupMen, _dist];
		};
		case "Reserve": {
			_job = "Defending";
			_place = [_goal] call SWLC_fnc_statusPlace;
			_reason = "reserve, no threat right now";
		};
		case "Defending": {
			_job = "Defending";
			_place = [_goal] call SWLC_fnc_statusPlace;
			private _dig = _g getVariable ["SWLC_digUntil", -1];
			_reason = if (_dig >= time) then {"dug in, watching for a counterattack"} else {"responding to enemy near this sector"};
		};
		case "Borrowed": {
			_job = "With player";
			private _by = _g getVariable ["SWLC_borrowedBy", objNull];
			_place = if (isNull _by) then {"-"} else {name _by};
			_reason = "on loan to a player until released";
		};
		case "Pickup": {
			_job = "Pickup";
			_place = [_goal] call SWLC_fnc_statusPlace;
			_reason = "bringing a vehicle to a player";
		};
		case "Picket": {
			_job = "Picket";
			_place = [_goal] call SWLC_fnc_statusPlace;
			_reason = "watching the front line, will report and delay";
		};
		case "Raiding": {
			_job = "Raiding";
			_place = [_goal] call SWLC_fnc_statusPlace;
			_reason = "raid order, seizing it quietly";
		};
		case "Probing": {
			_job = "Scouting";
			_place = [_goal] call SWLC_fnc_statusPlace;
			_reason = "probing an enemy sector";
		};
		case "Recon": {
			_job = "Scouting";
			_place = _tName;
			_reason = "looking ahead of the attack";
		};
		case "Hunting": {
			_job = "Hunting";
			_place = mapGridPosition _goal;
			_reason = "hidden shooter hit a vehicle here";
		};
	};
	[groupId _g, _job, _place, _reason, _since]
};

// The panel's data, public so each client can read it. A side only gets published when someone can see it.
SWLC_fnc_statusPublish = {
	params ["_cmd"];
	private _side = _cmd get "side";
	private _debug = !isNil "SWLC_debug" && {SWLC_debug};
	if ((missionNamespace getVariable ["SWLC_statusDebug", false]) isNotEqualTo _debug) then {
		missionNamespace setVariable ["SWLC_statusDebug", _debug, true];
	};
	if (!_debug && {!CFG("planAlwaysPublish")} && {!([_side] call SWLC_fnc_adSideHasPlayers)}) exitWith {};
	if ((time - (_cmd getOrDefault ["statusAt", -1e6])) < CFG("statusPublishSeconds")) exitWith {};
	_cmd set ["statusAt", time];
	private _target = _cmd get "target";
	private _rows = (_cmd get "groups") apply {[_cmd, _x] call SWLC_fnc_statusRow};
	missionNamespace setVariable [format ["SWLC_status_%1", _side], [time, if (isNull _target) then {"none"} else {[_target] call SWLC_fnc_adName}, _rows, [_target, _side] call SWLC_fnc_capStatusText], true];
};
