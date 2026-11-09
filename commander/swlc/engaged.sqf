// Fights on the way. A group in transit that meets the enemy stops and fights ("Engaged") instead of being put back on
// its route, reports it, can draw in nearby free groups, and carries on when the contact is clear. A much bigger enemy
// sends it back to the nearest owned sector and becomes a threat the commander answers. Also holds the fire tracking
// that decides whether a group is fighting, which resilience and other parts read.
#include "macros.hpp"

// ---- Fire tracking ----

// True if _shooter is on a side hostile to _unit. Friendly fire and self-inflicted damage aren't a fight.
SWLC_fnc_contactHostile = {
	params ["_unit", "_shooter"];
	if (isNull _shooter) exitWith {false};
	private _g = group _shooter;
	if (isNull _g) exitWith {false};
	((side _g) getFriend (side group _unit)) < 0.6
};

// One set of handlers per unit. FiredMan rather than Fired, so a gunner in a vehicle counts as firing.
SWLC_fnc_contactAttach = {
	params ["_u"];
	_u setVariable ["SWLC_contactEH", true];
	_u addEventHandler ["FiredMan", {
		params ["_unit", "_weapon", "", "", "_ammo"];
		if (_weapon == "Throw" && {((toLower _ammo) find "smoke") >= 0}) exitWith {};
		_unit setVariable ["SWLC_firedAt", time];
	}];
	_u addEventHandler ["Suppressed", {
		params ["_unit", "", "_shooter", "_instigator"];
		private _by = if (isNull _instigator) then {_shooter} else {_instigator};
		if ([_unit, _by] call SWLC_fnc_contactHostile) then {_unit setVariable ["SWLC_underFireAt", time]};
	}];
	_u addEventHandler ["Hit", {
		params ["_unit", "_source", "", "_instigator"];
		private _by = if (isNull _instigator) then {_source} else {_instigator};
		if ([_unit, _by] call SWLC_fnc_contactHostile) then {_unit setVariable ["SWLC_underFireAt", time]};
	}];
};

// Runs on every commander's tick, so it throttles itself. Every side, players included: other parts read these too.
SWLC_fnc_contactAttachAll = {
	if (time < (missionNamespace getVariable ["SWLC_contactScanNext", 0])) exitWith {};
	SWLC_contactScanNext = time + CFG("contactAttachSeconds");
	{[_x] call SWLC_fnc_contactAttach} forEach (allUnits select {!(_x getVariable ["SWLC_contactEH", false])});
};

// The only definition of "fighting": a living man fired or came under fire inside the window.
SWLC_fnc_groupFighting = {
	params ["_g"];
	private _t = time - CFG("fightingWindow");
	(units _g findIf {alive _x && {((_x getVariable ["SWLC_firedAt", -1e6]) >= _t) || {(_x getVariable ["SWLC_underFireAt", -1e6]) >= _t}}}) >= 0
};

SWLC_fnc_groupLastFire = {
	params ["_g"];
	private _last = -1e6;
	{
		if (alive _x) then {_last = _last max (_x getVariable ["SWLC_firedAt", -1e6]) max (_x getVariable ["SWLC_underFireAt", -1e6])};
	} forEach units _g;
	_last
};

// ---- What a group can see ----

// What the leader knows of nearby: [infantry, armour, light, centre or []]. Aircraft alone don't stop a march.
SWLC_fnc_engagedContact = {
	params ["_g", "_range", "_hostile"];
	private _l = leader _g;
	if (!alive _l) exitWith {[0, 0, 0, []]};
	private _here = getPosATL _l;
	private _maxAge = CFG("engagedContactAge");
	private _minKnows = CFG("intelMinKnows");
	private _inf = 0;
	private _arm = 0;
	private _light = 0;
	private _sx = 0;
	private _sy = 0;
	private _n = 0;
	{
		_x params ["", "_t", "_tSide", "_type", "_pos"];
		if (_tSide in _hostile && {alive _t} && {(_pos distance2D _here) <= _range} && {(_l knowsAbout _t) >= _minKnows}) then {
			private _cat = [_type] call SWLC_fnc_intelCategory;
			if (_cat == "") then {_cat = [typeOf _t] call SWLC_fnc_intelCategory};
			private _counted = true;
			switch (_cat) do {
				case "infantry": {_inf = _inf + 1};
				case "tank": {_arm = _arm + 1};
				case "apc": {_arm = _arm + 1};
				case "light": {_light = _light + 1};
				case "static": {_light = _light + 1};
				default {_counted = false};
			};
			if (_counted) then {
				_sx = _sx + (_pos # 0);
				_sy = _sy + (_pos # 1);
				_n = _n + 1;
			};
		};
	} forEach (_l targetsQuery [objNull, sideUnknown, "", [], _maxAge]);
	[_inf, _arm, _light, [[], [_sx / (_n max 1), _sy / (_n max 1), 0]] select (_n > 0)]
};

// Same weights as the defence's threat strength.
SWLC_fnc_engagedStrength = {
	params ["_c"];
	(_c # 0) + 3 * (_c # 2) + 6 * (_c # 1)
};

SWLC_fnc_engagedDescribe = {
	params ["_c"];
	private _parts = [];
	if ((_c # 0) > 0) then {_parts pushBack format ["%1 infantry", _c # 0]};
	if ((_c # 1) > 0) then {_parts pushBack format ["%1 armour", _c # 1]};
	if ((_c # 2) > 0) then {_parts pushBack format ["%1 light vehicles", _c # 2]};
	if (_parts isEqualTo []) exitWith {"unknown strength"};
	_parts joinString ", "
};

// ---- Starting ----

// Fights close together are one fight, so joiners and the fallback judge them as a whole.
SWLC_fnc_engagedFightAt = {
	params ["_cmd", "_pos"];
	private _fights = _cmd getOrDefault ["engagedFights", []];
	_cmd set ["engagedFights", _fights];
	private _merge = CFG("engagedMergeMetres");
	private _near = _fights findIf {((_x get "pos") distance2D _pos) <= _merge};
	if (_near >= 0) exitWith {_fights # _near};
	private _id = (_cmd getOrDefault ["engagedSeq", 0]) + 1;
	_cmd set ["engagedSeq", _id];
	private _fight = createHashMapFromArray [["id", _id], ["pos", _pos], ["first", time], ["groups", []], ["strength", 0], ["peak", 0], ["contact", [0, 0, 0, []]], ["need", 1], ["reported", false]];
	_fights pushBack _fight;
	_fight
};

SWLC_fnc_engagedNote = {
	params ["_fight", "_c"];
	private _s = [_c] call SWLC_fnc_engagedStrength;
	_fight set ["contact", _c];
	_fight set ["strength", _s];
	_fight set ["peak", (_fight get "peak") max _s];
};

// Search and destroy at the contact where the group may go, otherwise stand and fight where it is.
SWLC_fnc_engagedOrder = {
	params ["_g", "_pos"];
	// More margin than the search radius, or the search walks them into Warlords' kill zone.
	private _open = !(surfaceIsWater _pos) && {!([side _g, _pos, 75] call SWLC_fnc_adRestricted)};
	private _wps = if (_open) then {[[_pos, "SAD", 60]]} else {[[getPosATL leader _g, "HOLD", 20]]};
	_g setVariable ["SWLC_engagedAim", _pos];
	[_g, _wps, "AWARE", "FULL", "WEDGE", "RED"] call SWLC_fnc_adSetOrder;
};

// A transport: passengers out where it stands, short of the contact. The driver takes it back the way it came and walks in.
SWLC_fnc_engagedDismount = {
	params ["_cmd", "_g", "_pos"];
	private _r = [_g] call SWLC_fnc_vehRecOf;
	if (count _r == 0 || {(_r get "role") != "transport"}) exitWith {};
	private _v = _r get "obj";
	private _men = (units _g) select {alive _x};
	private _driver = driver _v;
	private _canDrive = alive _driver && {_driver in _men} && {_driver != leader _g} && {canMove _v};
	private _out = if (_canDrive) then {_men - [_driver]} else {_men};
	_r set ["state", "parked"];
	_r set ["group", grpNull];
	_r deleteAt "sample";
	_g leaveVehicle _v;
	_g setVariable ["SWLC_rec", createHashMap];
	{unassignVehicle _x} forEach _out;
	_out orderGetIn false;
	{if (vehicle _x == _v) then {doGetOut _x}} forEach _out;
	private _p = getPosATL _v;
	["C_VEH", [["side", side _g], ["id", _r get "id"], ["event", "parked"], ["reason", "contact"], ["group", groupId _g], ["x", round (_p # 0)], ["y", round (_p # 1)]]] call SWLC_fnc_log;
	if (_canDrive) then {
		private _dest = [_p, [_pos, _p] call SWLC_fnc_bearing, CFG("engagedTransportBack")] call SWLC_fnc_offset;
		if (surfaceIsWater _dest || {[side _g, _dest, 50] call SWLC_fnc_adRestricted}) then {_dest = +_p};
		_driver assignAsDriver _v;
		[_driver] orderGetIn true;
		[_driver, _v, _g, _dest] spawn SWLC_fnc_engagedPullBack;
	};
};

SWLC_fnc_engagedPullBack = {
	params ["_d", "_v", "_g", "_dest"];
	scriptName "SWLC transport pull back";
	_d doMove _dest;
	private _until = time + CFG("engagedPullBackSeconds");
	waitUntil {sleep 1; !alive _d || {!alive _v} || {vehicle _d != _v} || {(_v distance2D _dest) < 25} || {time > _until}};
	private _moved = if (alive _v) then {round (_v distance2D _dest)} else {-1};
	["C_ENGAGED", [["side", side _g], ["event", "pullback"], ["group", groupId _g], ["left_m", _moved], ["vehicle_alive", alive _v]]] call SWLC_fnc_log;
	if (alive _d) then {
		unassignVehicle _d;
		[_d] orderGetIn false;
		if (vehicle _d == _v) then {doGetOut _d};
		_d doFollow leader _g;
	};
};

SWLC_fnc_engagedStart = {
	params ["_cmd", "_g", "_fight", "_why"];
	private _state = [_g] call SWLC_fnc_state;
	private _leg = _g getVariable ["SWLC_leg", ""];
	_g setVariable ["SWLC_engagedSaved", [_state, _g getVariable ["SWLC_goal", []], +(_g getVariable ["SWLC_order", []]), _leg, _g getVariable ["SWLC_waveId", -1]]];
	_g setVariable ["SWLC_engagedFight", _fight get "id"];
	(_fight get "groups") pushBackUnique _g;
	private _pos = _fight get "pos";
	if (CFG("engagedVehicles") && {_leg == "DRIVE"}) then {
		[_cmd, _g, _pos] call SWLC_fnc_engagedDismount;
		_g setVariable ["SWLC_leg", "FOOT"];
	};
	[_g, "Engaged", _pos, _why] call SWLC_fnc_setState;
	[_g, _pos] call SWLC_fnc_engagedOrder;
	private _side = _cmd get "side";
	private _c = _fight get "contact";
	private _here = getPosATL leader _g;
	["C_ENGAGED", [["side", _side], ["event", ["start", "joined"] select (_why == "joined")], ["group", groupId _g], ["fight", _fight get "id"], ["from", _state], ["leg", _leg],
		["x", round (_here # 0)], ["y", round (_here # 1)], ["cx", round (_pos # 0)], ["cy", round (_pos # 1)], ["inf", _c # 0], ["arm", _c # 1], ["light", _c # 2], ["strength", _fight get "strength"],
		["need", _fight get "need"], ["have", count (_fight get "groups")], ["fighting", [_g] call SWLC_fnc_groupFighting]]] call SWLC_fnc_log;
	if !(_fight get "reported") then {
		_fight set ["reported", true];
		[_side, "engaged", [[_c] call SWLC_fnc_engagedDescribe, [_pos] call SWLC_fnc_statusPlace], _g] call SWLC_fnc_radio;
	};
	if (_why == "joined") then {[_side, "engagedjoin", [[_pos] call SWLC_fnc_statusPlace], _g] call SWLC_fnc_radio};
};

// Groups in transit that have met the enemy.
SWLC_fnc_engagedDetect = {
	params ["_cmd", "_hostile"];
	private _states = CFG("engagedStates");
	private _op = _cmd get "op";
	private _range = CFG("engagedRange");
	private _close = CFG("engagedCloseRange");
	{
		private _g = _x;
		[_cmd, _g, "engagedDetect", {
			if (time < (_g getVariable ["SWLC_engagedNext", -1])) exitWith {};
			if (!([_g] call SWLC_fnc_resMayTouch) || {(_g getVariable ["SWLC_lambsTask", ""]) != ""}) exitWith {};
			private _here = getPosATL leader _g;
			// Inside the objective is the assault, which has its own rules.
			if (!isNil "_op" && {[_op get "target", _here, CFG("engagedObjectiveMargin")] call SWLC_fnc_adInSquare}) exitWith {};
			private _c = [_g, [_close, _range] select ([_g] call SWLC_fnc_groupFighting), _hostile] call SWLC_fnc_engagedContact;
			if ((_c # 3) isEqualTo []) exitWith {};
			private _fight = [_cmd, _c # 3] call SWLC_fnc_engagedFightAt;
			[_fight, _c] call SWLC_fnc_engagedNote;
			[_cmd, _g, _fight, "contact"] call SWLC_fnc_engagedStart;
		}] call SWLC_fnc_resGuarded;
	} forEach ((_cmd get "groups") select {([_x] call SWLC_fnc_state) in _states});
};

// ---- Joining ----

// The existing proportionate response, read directly so it holds with the rules variant off: enough groups for the
// force seen, capped, and a wave gives up no more than its usual share.
SWLC_fnc_engagedJoinTick = {
	params ["_cmd"];
	if !(CFG("engagedJoin")) exitWith {};
	private _fights = _cmd getOrDefault ["engagedFights", []];
	if (_fights isEqualTo []) exitWith {};
	private _op = _cmd get "op";
	private _opId = if (isNil "_op") then {-2} else {_op get "id"};
	private _cap = if (isNil "_op") then {0} else {floor ((count ([_op] call SWLC_fnc_waveLive)) * CFG("responseCapFraction"))};
	private _states = CFG("engagedJoinStates");
	private _radius = CFG("engagedJoinRadius");
	private _margin = CFG("responseMargin");
	private _perGroup = CFG("defenceMenPerGroup");
	private _maxGroups = CFG("defenceMaxGroups");
	{
		private _fight = _x;
		private _need = ((ceil (((_fight get "strength") * _margin) / _perGroup)) max 1) min _maxGroups;
		_fight set ["need", _need];
		private _have = count (_fight get "groups");
		if (_have < _need) then {
			private _c = _fight get "pos";
			private _pool = (_cmd get "groups") select {
				([_x] call SWLC_fnc_state) in _states
				&& {(_x getVariable ["SWLC_leg", ""]) in ["", "FOOT"]}
				&& {(behaviour leader _x) != "COMBAT"}
				&& {(leader _x distance2D _c) <= _radius}
				&& {(_x getVariable ["SWLC_lambsTask", ""]) == ""}
				&& {isNull (_x getVariable ["SWLC_counterFor", objNull])}
				&& {time >= (_x getVariable ["SWLC_engagedNext", -1])}
				&& {!([_x] call SWLC_fnc_groupFighting)}
				&& {[_x] call SWLC_fnc_resMayTouch}
			};
			private _peeled = {(_x getVariable ["SWLC_engagedJoinOp", -1]) == _opId && {([_x] call SWLC_fnc_state) == "Engaged"}} count (_cmd get "groups");
			{
				if (_have >= _need) exitWith {};
				private _g = _x;
				private _fromWave = (_g getVariable ["SWLC_waveId", -1]) == _opId;
				if (!_fromWave || {_peeled < _cap}) then {
					[_cmd, _g, "engagedJoin", {
						if (_fromWave) then {_g setVariable ["SWLC_engagedJoinOp", _opId]; _peeled = _peeled + 1};
						_have = _have + 1;
						[_cmd, _g, _fight, "joined"] call SWLC_fnc_engagedStart;
					}] call SWLC_fnc_resGuarded;
				};
			} forEach ([_pool, [], {leader _x distance2D _c}, "ASCEND"] call BIS_fnc_sortBy);
		};
	} forEach _fights;
};

// ---- Ending ----

SWLC_fnc_engagedClear = {
	params ["_g"];
	_g setVariable ["SWLC_engagedSaved", nil];
	_g setVariable ["SWLC_engagedFight", nil];
	_g setVariable ["SWLC_engagedAim", nil];
	_g setVariable ["SWLC_engagedJoinOp", nil];
};

SWLC_fnc_engagedEndLog = {
	params ["_cmd", "_g", "_fight", "_outcome", ["_to", "-"]];
	private _pos = if (isNull leader _g) then {_fight get "pos"} else {getPosATL leader _g};
	["C_ENGAGED", [["side", _cmd get "side"], ["event", "end"], ["outcome", _outcome], ["group", groupId _g], ["fight", _fight get "id"], ["to", _to],
		["x", round (_pos # 0)], ["y", round (_pos # 1)], ["duration", round (time - (_fight get "first"))], ["strength", _fight get "peak"]]] call SWLC_fnc_log;
};

// Back to what it was doing, if that still makes sense. Returns the job it went to.
SWLC_fnc_engagedResume = {
	params ["_cmd", "_g"];
	private _saved = _g getVariable ["SWLC_engagedSaved", []];
	[_g] call SWLC_fnc_engagedClear;
	_g setVariable ["SWLC_engagedNext", time + CFG("engagedRetriggerSeconds")];
	private _idle = {
		[_g] call SWLC_fnc_adClearOrder;
		[_g, "Unassigned", [], "engaged_over"] call SWLC_fnc_setState;
		"Unassigned"
	};
	if (_saved isEqualTo []) exitWith {call _idle};
	_saved params ["_state", "_goal", "_order", "_leg", "_wave"];
	private _op = _cmd get "op";
	private _waveOk = !isNil "_op" && {(_op get "id") == _wave};
	// The vehicle has gone, so this group walks the rest.
	if (_leg == "DRIVE" && {_waveOk}) exitWith {
		[_cmd, _op, _g] call SWLC_fnc_waveFootOrder;
		"Advancing"
	};
	if (_state == "Reserve") exitWith {
		_g setVariable ["SWLC_patrolAt", -1e6];
		[_g] call SWLC_fnc_adClearOrder;
		[_g, "Reserve", _goal, "engaged_over"] call SWLC_fnc_setState;
		"Reserve"
	};
	private _valid = _waveOk && {_order isNotEqualTo []} && {_state in ["Advancing", "Waiting", "Travelling"]};
	if (_valid && {_state == "Travelling"}) then {
		_valid = count ((_cmd get "musters") getOrDefault [_g getVariable ["SWLC_musterName", ""], createHashMap]) > 0;
	};
	if (!_valid) exitWith {call _idle};
	_g setVariable ["SWLC_leg", _leg];
	[_g, _state, _goal, "engaged_over"] call SWLC_fnc_setState;
	_order params ["_wps", "_beh", "_speed", "_form", "_combat"];
	[_g, _wps, _beh, _speed, _form, _combat] call SWLC_fnc_adSetOrder;
	_state
};

// A force clearly bigger than this fight can handle: back to the nearest owned sector, which goes on the threat list
// with that force's strength, so the normal defence answers it. Returns true if the groups fell back.
SWLC_fnc_engagedFallback = {
	params ["_cmd", "_fight", "_members", "_c"];
	private _side = _cmd get "side";
	private _owned = [_side] call SWLC_fnc_adOwned;
	if (_owned isEqualTo []) exitWith {false};
	private _s = [_owned, getPosATL leader (_members # 0)] call SWLC_fnc_adNearest;
	private _name = [_s] call SWLC_fnc_adName;
	private _strength = [_c] call SWLC_fnc_engagedStrength;
	private _bearing = [[_s] call SWLC_fnc_adPos, _c # 3] call SWLC_fnc_bearing;
	private _until = time + CFG("engagedFallbackHoldSeconds");
	private _threats = _cmd get "threats";
	private _threat = _threats getOrDefault [_name, createHashMap];
	if (count _threat == 0) then {
		_threat = createHashMapFromArray [["sector", _s], ["first", time], ["last", time], ["groups", []], ["slot", 0], ["requestedUntil", _until], ["strength", _strength], ["bearing", _bearing]];
		_threat set ["spots", [_cmd, _s, _bearing] call SWLC_fnc_defSpots];
		_threats set [_name, _threat];
		["C_DEF", [["side", _side], ["event", "detect"], ["sector", _name], ["inf", _c # 0], ["arm", _c # 1], ["light", _c # 2], ["seizing", false], ["bearing", round _bearing], ["source", "engaged_fallback"]]] call SWLC_fnc_log;
	} else {
		_threat set ["alertOnly", false];
		_threat set ["strength", (_threat get "strength") max _strength];
		_threat set ["requestedUntil", (_threat get "requestedUntil") max _until];
		_threat set ["last", time];
	};
	[_side, "engagedfall", [[_c] call SWLC_fnc_engagedDescribe, _name], _members # 0] call SWLC_fnc_radio;
	{
		private _g = _x;
		[_cmd, _g, "engagedFall", {
			[_cmd, _g, _fight, "fallback", _name] call SWLC_fnc_engagedEndLog;
			[_g] call SWLC_fnc_engagedClear;
			_g setVariable ["SWLC_engagedNext", time + CFG("engagedRetriggerSeconds")];
			[_cmd, _threat, _g, "engaged_fallback"] call SWLC_fnc_defSend;
		}] call SWLC_fnc_resGuarded;
	} forEach _members;
	[_cmd, _threat] call SWLC_fnc_defRespond;
	true
};

// One fight, one tick. Returns true once it's over.
SWLC_fnc_engagedFightTick = {
	params ["_cmd", "_fight", "_hostile"];
	private _id = _fight get "id";
	private _members = [];
	{
		private _g = _x;
		private _alive = ({alive _x} count units _g) > 0;
		if (_alive && {([_g] call SWLC_fnc_state) == "Engaged"} && {(_g getVariable ["SWLC_engagedFight", -1]) == _id}) then {
			_members pushBack _g;
		} else {
			[_cmd, _g, _fight, ["wiped", "released"] select _alive] call SWLC_fnc_engagedEndLog;
			if (_alive && {(_g getVariable ["SWLC_engagedFight", -1]) == _id}) then {[_g] call SWLC_fnc_engagedClear};
		};
	} forEach (_fight get "groups");
	_fight set ["groups", _members];
	if (_members isEqualTo []) exitWith {true};

	private _range = CFG("engagedRange");
	private _best = [0, 0, 0, []];
	private _bestS = -1;
	private _fire = _fight get "first";
	private _friendly = 0;
	{
		private _c = [_x, _range, _hostile] call SWLC_fnc_engagedContact;
		private _s = [_c] call SWLC_fnc_engagedStrength;
		if ((_c # 3) isNotEqualTo [] && {_s > _bestS}) then {_best = _c; _bestS = _s};
		_fire = _fire max ([_x] call SWLC_fnc_groupLastFire);
		_friendly = _friendly + ({alive _x} count units _x);
		private _r = [_x] call SWLC_fnc_vehRecOf;
		if (count _r > 0 && {(_r get "role") == "combat"} && {alive (_r get "obj")}) then {_friendly = _friendly + 5};
	} forEach _members;
	private _quiet = time - _fire;
	private _contact = (_best # 3) isNotEqualTo [];

	if (_contact) then {
		[_fight, _best] call SWLC_fnc_engagedNote;
		if (((_best # 3) distance2D (_fight get "pos")) > CFG("engagedReorderMetres")) then {
			_fight set ["pos", _best # 3];
			{
				private _g = _x;
				[_cmd, _g, "engagedAim", {[_g, _best # 3] call SWLC_fnc_engagedOrder}] call SWLC_fnc_resGuarded;
			} forEach _members;
		};
		if (CFG("engagedFallback")
			&& {_bestS >= CFG("engagedFallbackMinMen")}
			&& {_bestS >= (CFG("engagedFallbackRatio") * _friendly)}
			&& {[_cmd, _fight, _members, _best] call SWLC_fnc_engagedFallback}) exitWith {
			_fight set ["fellBack", true];
		};
	};
	if (_fight getOrDefault ["fellBack", false]) exitWith {true};

	// Clear: quiet and nobody known near. Past the fighting window it ends even with a sighting still on the list,
	// so nothing sits in this state without a shot being fired.
	if ((!_contact && {_quiet >= CFG("engagedClearSeconds")}) || {_quiet >= CFG("fightingWindow")}) exitWith {
		private _first = true;
		{
			private _g = _x;
			[_cmd, _g, "engagedResume", {
				private _to = [_cmd, _g] call SWLC_fnc_engagedResume;
				[_cmd, _g, _fight, ["quiet", "cleared"] select (!_contact), _to] call SWLC_fnc_engagedEndLog;
				if (_first) then {
					_first = false;
					[_cmd get "side", "engagedclear", [], _g] call SWLC_fnc_radio;
				};
			}] call SWLC_fnc_resGuarded;
		} forEach _members;
		true
	};
	false
};

SWLC_fnc_engagedTick = {
	params ["_cmd"];
	if !(CFG("behEngaged")) exitWith {};
	private _side = _cmd get "side";
	private _hostile = _cmd getOrDefault ["engagedHostile", []];
	if (_hostile isEqualTo []) then {
		_hostile = [west, east, resistance] select {[_side, _x] call BIS_fnc_sideIsEnemy};
		_cmd set ["engagedHostile", _hostile];
	};
	private _keep = [];
	{
		if !([_cmd, _x, _hostile] call SWLC_fnc_engagedFightTick) then {_keep pushBack _x};
	} forEach (_cmd getOrDefault ["engagedFights", []]);
	_cmd set ["engagedFights", _keep];
	[_cmd, _hostile] call SWLC_fnc_engagedDetect;
	[_cmd] call SWLC_fnc_engagedJoinTick;
};
