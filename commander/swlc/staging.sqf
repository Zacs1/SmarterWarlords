// Mustering: groups form up at the owned sector nearest them, several sectors at once, then leave for the rally.
#include "macros.hpp"

// selectBestPlaces is slow and the ground doesn't change, so each search is done once.
SWLC_stagingPlaces = createHashMap;

SWLC_fnc_stagingPlaces = {
	params ["_centre", "_radius"];
	private _key = [round (_centre # 0), round (_centre # 1), _radius];
	private _places = SWLC_stagingPlaces get _key;
	if (isNil "_places") then {
		_places = selectBestPlaces [_centre, _radius, CFG("stagingPlaceExpr"), 20, 40];
		SWLC_stagingPlaces set [_key, _places];
	};
	_places
};

SWLC_fnc_musterSpotRadius = {
	params ["_sector"];
	(([_sector] call SWLC_fnc_adSize) / 2 + 40) max 120
};

SWLC_fnc_defenceSpotRadius = {
	params ["_sector"];
	(([_sector] call SWLC_fnc_adSize) / 2 + 30) max 60
};

// Does every sector's searches at the start of the round, in separate frames, so none lands mid-fight.
SWLC_fnc_stagingWarm = {
	{
		private _s = _x;
		private _c = [_s] call SWLC_fnc_adPos;
		{
			[_c, _x] call SWLC_fnc_stagingPlaces;
			sleep 0.1;
		} forEach [[_s] call SWLC_fnc_musterSpotRadius, [_s] call SWLC_fnc_defenceSpotRadius];
	} forEach SWLC_sectors;
};

// Spread-out positions on the far side from the target, biased to buildings and trees.
SWLC_fnc_buildStagingSpots = {
	params ["_side", "_centre", "_tpos", ["_radius", 150]];
	private _places = [_centre, _radius] call SWLC_fnc_stagingPlaces;
	private _back = [_tpos, _centre] call SWLC_fnc_bearing;
	private _scored = [];
	{
		_x params ["_p", "_v"];
		private _pos = [_p # 0, _p # 1, 0];
		if (!surfaceIsWater _pos && {!([_side, _pos] call SWLC_fnc_adRestricted)}) then {
			private _bear = [_centre, _pos] call SWLC_fnc_bearing;
			private _away = cos (_bear - _back);
			_scored pushBack [_v + _away * 0.6, _pos];
		};
	} forEach _places;
	_scored sort false;
	private _spots = [];
	private _sep = CFG("stagingSpotSeparation");
	{
		private _p = _x # 1;
		if ((_spots findIf {_x distance2D _p < _sep}) < 0) then {_spots pushBack _p};
	} forEach _scored;
	if (_spots isEqualTo []) then {_spots = [_centre]};
	_spots
};

// The sector's muster record, set up for this operation. The crate and drop point stay for later operations.
SWLC_fnc_musterRec = {
	params ["_cmd", "_op", "_sector"];
	private _side = _cmd get "side";
	private _name = [_sector] call SWLC_fnc_adName;
	private _musters = _cmd get "musters";
	private _rec = _musters getOrDefault [_name, createHashMap];
	if (count _rec == 0) then {
		_rec = createHashMapFromArray [["sector", _sector], ["name", _name], ["pos", [_sector] call SWLC_fnc_adPos], ["groups", []], ["batch", []],
			["firstArrive", -1], ["goTime", -1], ["slot", 0], ["crate", objNull], ["helper", objNull], ["op", -1]];
		_musters set [_name, _rec];
	};
	if ((_rec get "op") != (_op get "id")) then {
		_rec set ["op", _op get "id"];
		_rec set ["slot", 0];
		private _spots = [_side, _rec get "pos", _op get "tpos", [_sector] call SWLC_fnc_musterSpotRadius] call SWLC_fnc_buildStagingSpots;
		_rec set ["spots", _spots];
		if (isNull (_rec get "crate")) then {
			private _anchor = _spots # 0;
			private _pos = _anchor findEmptyPosition [3, 30, "B_CargoNet_01_ammo_F"];
			if (_pos isEqualTo []) then {_pos = +_anchor};
			_rec set ["crate", createVehicle [["O_CargoNet_01_ammo_F", "B_CargoNet_01_ammo_F"] select (_side == west), _pos, [], 0, "NONE"]];
			_rec set ["helper", createVehicle ["Land_HelipadEmpty_F", _rec get "pos", [], 0, "CAN_COLLIDE"]];
		};
	};
	_rec
};

SWLC_fnc_musterNextSpot = {
	params ["_rec"];
	private _spots = _rec get "spots";
	private _i = _rec get "slot";
	_rec set ["slot", _i + 1];
	private _spot = _spots # (_i mod count _spots);
	if (_i >= count _spots) then {_spot = [_spot, random 360, 12 + random 15] call SWLC_fnc_offset};
	_spot
};

// [nearest owned sector, forward sector worth hopping to or objNull]
SWLC_fnc_musterChoose = {
	params ["_cmd", "_g", "_tpos"];
	private _side = _cmd get "side";
	private _owned = [_side] call SWLC_fnc_adOwned;
	if (_owned isEqualTo []) exitWith {[objNull, objNull]};
	private _here = getPosATL leader _g;
	private _near = ([_owned, _here] call SWLC_fnc_adNearest);
	private _threats = _cmd get "threats";
	private _safe = _owned select {!([_threats, _x] call SWLC_fnc_frontHot) && {[_side, _x] call SWLC_fnc_adCanFTTo}};
	private _forward = objNull;
	if (_safe isNotEqualTo []) then {
		private _best = ([_safe, _tpos] call SWLC_fnc_adNearest);
		private _gain = (([_near] call SWLC_fnc_adPos) distance2D _tpos) - (([_best] call SWLC_fnc_adPos) distance2D _tpos);
		if (_gain >= CFG("musterHopGain")) then {_forward = _best};
	};
	[_near, _forward]
};

// Fast travels the group to its spot in the sector when that's far. Returns true if it moved.
SWLC_fnc_musterHop = {
	params ["_g", "_sector", "_spot", "_tpos"];
	if ((leader _g distance2D _spot) <= CFG("stagingFarThreshold")) exitWith {false};
	private _landing = [_spot, ([_tpos, _spot] call SWLC_fnc_bearing) + (random 80 - 40), 15 + random 25] call SWLC_fnc_offset;
	if (surfaceIsWater _landing) then {_landing = _spot};
	[_g, _sector, _landing] call SWLC_fnc_adFastTravel
};

// An unassigned group joins the operation: straight to the rally if it's already close, otherwise it musters.
SWLC_fnc_musterAssign = {
	params ["_cmd", "_g"];
	private _op = _cmd get "op";
	private _tpos = _op get "tpos";
	_g setVariable ["SWLC_waveId", _op get "id"];
	(_op get "groups") pushBackUnique _g;
	([_cmd, _g, _tpos] call SWLC_fnc_musterChoose) params ["_near", "_forward"];
	if (isNull _near || {(leader _g distance2D (_op get "rally")) <= CFG("rallyJoinRadius")}) exitWith {
		[_g] call SWLC_fnc_waveGroupStart;
		[_cmd, _op, _g] call SWLC_fnc_waveFootOrder;
	};

	private _sector = _near;
	private _rec = createHashMap;
	private _spot = [];
	private _hopped = false;
	if (!isNull _forward && {_forward isNotEqualTo _near}) then {
		_rec = [_cmd, _op, _forward] call SWLC_fnc_musterRec;
		_spot = [_rec] call SWLC_fnc_musterNextSpot;
		_hopped = [_g, _forward, _spot, _tpos] call SWLC_fnc_musterHop;
		if (_hopped) then {_sector = _forward};
	};
	if (!_hopped) then {
		_rec = [_cmd, _op, _near] call SWLC_fnc_musterRec;
		_spot = [_rec] call SWLC_fnc_musterNextSpot;
		[_g, _near, _spot, _tpos] call SWLC_fnc_musterHop;
	};
	(_rec get "groups") pushBackUnique _g;
	_g setVariable ["SWLC_musterName", _rec get "name"];
	[_g, "Travelling", _spot, "muster"] call SWLC_fnc_setState;
	[_g, [[_spot, "MOVE", 20]]] call SWLC_fnc_adSetOrder;
	["C_WAVE", [["side", _cmd get "side"], ["wave", _op get "id"], ["event", "muster_assign"], ["group", groupId _g], ["sector", _rec get "name"], ["hopped", _hopped]]] call SWLC_fnc_log;
};

// Groups that have reached their spot start the sector's short wait.
SWLC_fnc_musterArrivals = {
	params ["_cmd", "_op"];
	private _r = CFG("arriveRadius");
	{
		private _rec = _y;
		{
			[_cmd, _x, "musterArrivals", {
				if (([_x] call SWLC_fnc_state) == "Travelling") then {
					private _goal = _x getVariable ["SWLC_goal", []];
					if (_goal isNotEqualTo [] && {(leader _x distance2D _goal) <= _r}) then {
						[_x, "Mustering", _goal, "arrived"] call SWLC_fnc_setState;
						if ((_rec get "firstArrive") < 0) then {_rec set ["firstArrive", time]};
						["C_WAVE", [["side", _cmd get "side"], ["wave", _op get "id"], ["event", "arrival"], ["group", groupId _x], ["sector", _rec get "name"]]] call SWLC_fnc_log;
						[_cmd get "side", "arrived", [], _x] call SWLC_fnc_radio;
					};
				};
			}] call SWLC_fnc_resGuarded;
		} forEach ((_rec get "groups") select {true});
	} forEach (_cmd get "musters");
};

// A sector lost while groups muster there: they find somewhere else, and its assets go.
SWLC_fnc_musterSweep = {
	params ["_cmd"];
	private _side = _cmd get "side";
	private _musters = _cmd get "musters";
	{
		private _rec = _musters get _x;
		if (([_rec get "sector"] call SWLC_fnc_adOwner) != _side) then {
			{
				[_cmd, _x, "musterSweep", {
					if (([_x] call SWLC_fnc_state) in ["Travelling", "Mustering", "Mounting"]) then {
						[_cmd, _x] call SWLC_fnc_waveRemoveGroup;
						[_x] call SWLC_fnc_adClearOrder;
						[_x, "Unassigned", [], "muster_lost"] call SWLC_fnc_setState;
					};
				}] call SWLC_fnc_resGuarded;
			} forEach ((_rec get "groups") + (_rec get "batch"));
			{
				private _o = _rec get _x;
				if (!isNull _o) then {deleteVehicle _o};
			} forEach ["crate", "helper"];
			_musters deleteAt _x;
		};
	} forEach (keys _musters);
};

SWLC_fnc_musterTick = {
	params ["_cmd", "_op", "_rec"];
	_cmd set ["crate", _rec get "crate"];
	_cmd set ["dropHelper", _rec get "helper"];
	private _isLive = {({alive _x} count units _x) > 0};
	_rec set ["groups", (_rec get "groups") select _isLive];
	_rec set ["batch", (_rec get "batch") select _isLive];
	private _arrived = (_rec get "groups") select {([_x] call SWLC_fnc_state) == "Mustering"};
	if (_arrived isNotEqualTo []) then {
		[_cmd, _op, _arrived, _rec get "pos"] call SWLC_fnc_shopTick;
		[_cmd, _op, _arrived] call SWLC_fnc_kitTick;
	};
	if ((_rec get "batch") isNotEqualTo []) then {
		[_cmd, _op, _rec, _rec get "batch"] call SWLC_fnc_musterMountTick;
	};
	if ((_rec get "batch") isNotEqualTo [] || {_arrived isEqualTo []}) exitWith {};

	private _first = _rec get "firstArrive";
	if (_first < 0) exitWith {};
	private _waited = time - _first;
	private _forced = _op getOrDefault ["forceGo", false];
	if (!_forced && {_waited < CFG("musterSeconds")}) exitWith {};
	// Men just bought are still on the way down: give them a little longer, so nobody is left behind.
	private _falling = (_arrived findIf {(units _x) findIf {alive _x && {((getPosATL _x) # 2) > 3 || {vehicle _x isKindOf "ParachuteBase"}}} >= 0}) >= 0;
	if (!_forced && {_falling} && {_waited < CFG("musterMaxSeconds")}) exitWith {};

	_rec set ["groups", (_rec get "groups") - _arrived];
	_rec set ["batch", _arrived];
	_rec set ["goTime", time];
	_rec set ["firstArrive", -1];
	{
		[_cmd, _x, "musterGo", {
			[_x] call SWLC_fnc_waveGroupStart;
			_x setVariable ["SWLC_mountGo", time];
			[_x, "Mounting", _op get "rally", "go"] call SWLC_fnc_setState;
		}] call SWLC_fnc_resGuarded;
	} forEach (+_arrived);
	["C_WAVE", [["side", _cmd get "side"], ["wave", _op get "id"], ["event", "muster_go"], ["sector", _rec get "name"], ["groups", count _arrived], ["wait", round _waited], ["forced", _forced]]] call SWLC_fnc_log;
	if (({count ([_x] call SWLC_fnc_vehRecOf) > 0} count _arrived) > 0) then {[_cmd get "side", "mount"] call SWLC_fnc_radio};
	[_cmd, _op, _rec, _arrived] call SWLC_fnc_musterMountTick;
};

SWLC_fnc_musterMountTick = {
	params ["_cmd", "_op", "_rec", "_batch"];
	[_cmd, _op, _batch] call SWLC_fnc_kitTick;
	{
		// Kit first, then board, so nobody climbs in on the way to the crate.
		[_cmd, _x, "musterMount", {
			if !([_x] call SWLC_fnc_kitPending) then {[_cmd, _x] call SWLC_fnc_vehMountGroup};
		}] call SWLC_fnc_resGuarded;
	} forEach (+_batch);
	if ((time - (_rec get "goTime")) >= CFG("mountCapSeconds") || {(_batch findIf {!([_x] call SWLC_fnc_groupReady)}) < 0}) then {
		[_cmd, _op, _rec, _batch] call SWLC_fnc_waveDepart;
	};
};
