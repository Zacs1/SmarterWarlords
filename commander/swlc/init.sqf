// SmarterWarlords commander entry point. Run from initServer.sqf.
// Runs wherever isServer is true: dedicated server or a player hosting.
if (!isServer) exitWith {};

[] spawn {
	scriptName "SWLC init";

	call compile preprocessFileLineNumbers "swlc\settings.sqf";

	// Map overrides, then test overrides.
	private _mapFile = format ["swlc\maps\%1.sqf", worldName];
	if (fileExists _mapFile) then {
		{SWLC_settings set [_x # 0, _x # 1]} forEach (call compile preprocessFileLineNumbers _mapFile);
	};
	if (!isNil "SWLC_overrides") then {
		{SWLC_settings set [_x # 0, _x # 1]} forEach SWLC_overrides;
	};

	// Difficulty: the lobby parameter if there is one, then the preset. Explicit test overrides stay.
	private _lobby = ["SWLC_Difficulty", -1] call BIS_fnc_getParamValue;
	if (_lobby >= 0) then {SWLC_settings set ["difficulty", ["easy", "normal", "hard"] select (_lobby min 2)]};
	private _rules = ["SWLC_RulesVariant", -1] call BIS_fnc_getParamValue;
	if (_rules >= 0) then {SWLC_settings set ["rulesVariant", _rules == 1]};
	private _overridden = if (isNil "SWLC_overrides") then {[]} else {SWLC_overrides apply {_x # 0}};
	{
		if !((_x # 0) in _overridden) then {SWLC_settings set [_x # 0, _x # 1]};
	} forEach ((SWLC_settings get "difficultyPresets") getOrDefault [SWLC_settings get "difficulty", []]);

	{
		call compile preprocessFileLineNumbers format ["swlc\%1.sqf", _x];
	} forEach ["util", "adapter", "radio", "intel", "groups", "staging", "logistics", "vehicles", "wave", "watchdog", "resilience", "defence", "smart", "status", "rules", "raids", "pickets", "economy", "squads", "strategy", "menu", "commander", "debug"];

	waitUntil {sleep 1; [] call SWLC_fnc_adReady};
	[] call SWLC_fnc_adInit;
	[] call SWLC_fnc_lambsDetect;
	SWLC_ready = true;
	["C_READY", [["world", worldName], ["sectors", count SWLC_sectors], ["warlords", count BIS_WL_allWarlords], ["ftparam", missionNamespace getVariable ["BIS_WL_FTEnabled", -1]], ["difficulty", SWLC_settings get "difficulty"]]] call SWLC_fnc_log;

	if (SWLC_settings get "commanderEnabled") then {
		[] call SWLC_fnc_intelInstallHandlers;
		if (SWLC_settings get "rulesVariant") then {[] call SWLC_fnc_rulesInstall};
		[] call SWLC_fnc_econInit;
		[] spawn SWLC_fnc_stagingWarm;
		[west] call SWLC_fnc_startCommander;
		[east] call SWLC_fnc_startCommander;
		SWLC_debug = SWLC_settings get "debugOverlay";
		[] spawn SWLC_fnc_debugLoop;
	};
};
