// Test mission. Starts the passive observer, then the commander, then any test scenario.
[] execVM "swl\observer.sqf";

if (fileExists "swl\overrides.sqf") then {
	call compile preprocessFileLineNumbers "swl\overrides.sqf";
};

[] execVM "swlc\init.sqf";

if (fileExists "swl\scenario.sqf") then {
	[] execVM "swl\scenario.sqf";
};
