// "Cancel objective" on the menu, driven through the menu handler with an AI stand-in. Run with:
//   powershell -ExecutionPolicy Bypass -File tools\run-round.ps1 -DurationMinutes 8 -Name cancel -Scenario cancel -Overrides "scanBuying=false"
// Read the SWL|GCANCEL lines: press 1 asks, press 2 cancels, the target clears, and the next one isn't the cancelled sector.
// What a real player sees on the radio and the menu needs a person.

waitUntil {sleep 1; !isNil "SWLC_ready" && {!isNil "SWLC_cmd_WEST"}};

SWLG_say = {
	params ["_fields"];
	diag_log text ((["SWL", "GCANCEL", format ["t=%1", round time]] + _fields) joinString "|");
};

private _cmd = missionNamespace getVariable "SWLC_cmd_WEST";
SWLC_settings set ["menuCooldownSeconds", 0];
waitUntil {sleep 2; !isNull (_cmd get "target") && {!isNil {_cmd get "op"}} && {(count (_cmd getOrDefault ["groups", []])) >= 4}};
sleep 30;

private _who = leader ((_cmd get "groups") # 0);
private _t = _cmd get "target";
[[format ["event=start"], format ["target=%1", [_t] call SWLC_fnc_adName], format ["timer_left=%1", round ((_cmd get "commitUntil") - time)]]] call SWLG_say;

private _press = {
	params ["_n"];
	private _got = "";
	isNil {_got = [_cmd, _who, "cancel", []] call SWLC_fnc_menuHandle};
	[[format ["event=press"], format ["n=%1", _n], format ["got=%1", _got], format ["pending=%1", (_cmd getOrDefault ["switchPending", []]) isNotEqualTo []]]] call SWLG_say;
};

[1] call _press;
sleep 2;
[2] call _press;
sleep 2;
[3] call _press;

private _start = time;
waitUntil {sleep 2; (time - _start) > 300 || {(_cmd get "target") isNotEqualTo _t}};
[[format ["event=left"], format ["seconds=%1", round (time - _start)], format ["moved=%1", (_cmd get "target") isNotEqualTo _t]]] call SWLG_say;

_start = time;
waitUntil {sleep 2; (time - _start) > 120 || {!isNull (_cmd get "target")}};
private _now = _cmd get "target";
[[format ["event=next"], format ["seconds=%1", round (time - _start)], format ["target=%1", if (isNull _now) then {"none"} else {[_now] call SWLC_fnc_adName}], format ["same=%1", _now isEqualTo _t]]] call SWLG_say;

[4] call _press;
[["event=done"]] call SWLG_say;
