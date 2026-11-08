// Staging sector choice, staging positions, and getting groups there.
#include "macros.hpp"

// Returns [sector or objNull, pos].
SWLC_fnc_chooseStaging = {
	params ["_cmd", "_target"];
	private _side = _cmd get "side";
	private _tpos = [_target] call SWLC_fnc_adPos;
	private _owned = [_side] call SWLC_fnc_adOwned;
	if (_owned isEqualTo []) exitWith {[objNull, [_side, _target] call SWLC_fnc_fallbackStagingPos]};

	private _near = _owned select {(([_x] call SWLC_fnc_adPos) distance2D _tpos) <= CFG("stagingMaxDist")};
	if (_near isEqualTo []) then {_near = _owned};

	private _best = objNull;
	private _bestScore = -1e9;
	{
		private _score = [_cmd, _x, _tpos] call SWLC_fnc_stagingScore;
		if (_score > _bestScore) then {_bestScore = _score; _best = _x};
	} forEach _near;
	["C_STAGING", [["side", _side], ["target", [_target] call SWLC_fnc_adName], ["staging", [_best] call SWLC_fnc_adName], ["score", _bestScore toFixed 2]]] call SWLC_fnc_log;
	[_best, [_best] call SWLC_fnc_adPos]
};

// Shorter distance is better; a threatened or enemy-close sector is penalised by the intel board.
SWLC_fnc_stagingScore = {
	params ["_cmd", "_s", "_tpos"];
	private _p = [_s] call SWLC_fnc_adPos;
	private _near = 0;
	{
		if (((_x get "pos") distance2D _p) <= 500) then {_near = _near + (_x get "count")};
	} forEach (_cmd get "board");
	-(_p distance2D _tpos) / 1000 - _near * CFG("stagingEnemyPenalty")
};

SWLC_fnc_fallbackStagingPos = {
	params ["_side", "_target"];
	private _tpos = [_target] call SWLC_fnc_adPos;
	private _base = [[_side] call SWLC_fnc_adBase] call SWLC_fnc_adPos;
	private _d = CFG("stagingFallbackMin") + random (CFG("stagingFallbackMax") - CFG("stagingFallbackMin"));
	[_tpos, [_tpos, _base] call SWLC_fnc_bearing, _d] call SWLC_fnc_offset
};

// Spread-out positions on the far side from the target, biased to buildings and trees.
SWLC_fnc_buildStagingSpots = {
	params ["_side", "_centre", "_tpos", ["_radius", 150]];
	private _places = selectBestPlaces [_centre, _radius, CFG("stagingPlaceExpr"), 20, 40];
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

SWLC_fnc_stagingName = {
	params ["_cmd"];
	private _s = _cmd get "stagingSector";
	if (isNull _s) exitWith {format ["grid %1", mapGridPosition (_cmd get "stagingPos")]};
	[_s] call SWLC_fnc_adName
};

SWLC_fnc_setStaging = {
	params ["_cmd"];
	private _target = _cmd get "target";
	(_cmd get "stagingChoice") params ["_sector", "_pos"];
	private _tpos = [_target] call SWLC_fnc_adPos;
	private _radius = if (isNull _sector) then {120} else {(([_sector] call SWLC_fnc_adSize) / 2 + 40) max 120};
	_cmd set ["stagingSector", _sector];
	_cmd set ["stagingPos", _pos];
	_cmd set ["stagingSpots", [_cmd get "side", _pos, _tpos, _radius] call SWLC_fnc_buildStagingSpots];
	_cmd set ["stagingSlot", 0];
	[_cmd] call SWLC_fnc_logStagingAssets;
};

SWLC_fnc_nextStagingSpot = {
	params ["_cmd"];
	private _spots = _cmd get "stagingSpots";
	private _i = _cmd get "stagingSlot";
	_cmd set ["stagingSlot", _i + 1];
	private _spot = _spots # (_i mod count _spots);
	if (_i >= count _spots) then {_spot = [_spot, random 360, 12 + random 15] call SWLC_fnc_offset};
	_spot
};

// Sends a group to the gather wave's staging position, by fast travel where allowed.
SWLC_fnc_sendToStaging = {
	params ["_cmd", "_g", ["_state", "Travelling"]];
	private _wave = _cmd get "gather";
	private _side = _cmd get "side";
	private _spot = [_cmd] call SWLC_fnc_nextStagingSpot;
	private _sector = _cmd get "stagingSector";
	private _tpos = [_cmd get "target"] call SWLC_fnc_adPos;

	_g setVariable ["SWLC_waveId", _wave get "id"];
	(_wave get "groups") pushBackUnique _g;
	[_g, _state, _spot] call SWLC_fnc_setState;
	[_g, [[_spot, "MOVE", 20]]] call SWLC_fnc_adSetOrder;

	if (!isNull _sector && {(leader _g distance2D _spot) > CFG("stagingFarThreshold")}) then {
		private _landing = [_spot, ([_tpos, _spot] call SWLC_fnc_bearing) + (random 80 - 40), 15 + random 25] call SWLC_fnc_offset;
		if (surfaceIsWater _landing) then {_landing = _spot};
		[_g, _sector, _landing] call SWLC_fnc_adFastTravel;
	};
};

// Groups that have reached their staging spot are marked Staging.
SWLC_fnc_stagingArrivals = {
	params ["_cmd"];
	private _r = CFG("arriveRadius");
	private _wave = _cmd get "gather";
	if (isNil "_wave") exitWith {};
	{
		private _st = [_x] call SWLC_fnc_state;
		if (_st in ["Travelling", "Regrouping"]) then {
			private _goal = _x getVariable ["SWLC_goal", []];
			if (_goal isNotEqualTo [] && {(leader _x distance2D _goal) <= _r}) then {
				[_x, "Staging", _goal, "arrived"] call SWLC_fnc_setState;
				if ((_wave get "firstArrive") < 0) then {_wave set ["firstArrive", time]};
				["C_WAVE", [["side", _cmd get "side"], ["wave", _wave get "id"], ["event", "arrival"], ["group", groupId _x]]] call SWLC_fnc_log;
				[_cmd get "side", "arrived", [], _x] call SWLC_fnc_radio;
			};
		};
	} forEach (_wave get "groups");
};
