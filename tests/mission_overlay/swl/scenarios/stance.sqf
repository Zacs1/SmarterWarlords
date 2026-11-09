// Stance gate: a side made clearly weaker goes to hold, then rebuild, and comes back when it recovers. Run with:
//   -DurationMinutes 12 -Scenario stance -Overrides "stanceMinSeconds=90;stanceTickSeconds=10;stanceMemoryHalfLife=30;stanceOutcomeStep=0;ruleCommitTimer=false"
// Then: python tools/analyse_round.py <rpt> --gate stance
//
// TEST HOOK: SWLC_fnc_stanceKnown is replaced, so what the intel board "knows" comes from this script and not from sightings.
// WEST is told about a huge enemy and then about nothing. EAST is always told about nothing, so it must stay in attack: that's the per-side check.
// Own numbers are real. The commitment rule is off for the round, as the stance has to work without it, and the commit-timer
// rebuild is simulated by setting rebuildUntil, which is all the rule does to start one.

waitUntil {sleep 1; !isNil "SWLC_ready" && {!isNil "SWLC_cmd_WEST"} && {!isNil "SWLC_cmd_EAST"}};

SWLG_emit = {
	params ["_fields"];
	diag_log text ((["SWL", "GST", format ["t=%1", round time]] + _fields) joinString "|");
};

SWLG_knownWest = [0, 0, 0, 0];
SWLC_fnc_stanceKnown = {
	params ["_cmd"];
	if ((_cmd get "side") == west) then {+SWLG_knownWest} else {[0, 0, 0, 0]}
};

SWLG_waitStance = {
	params ["_wanted", "_timeout", "_label"];
	private _t0 = time;
	waitUntil {sleep 2; (([SWLC_cmd_WEST] call SWLC_fnc_stanceOf) == _wanted) || {(time - _t0) > _timeout}};
	private _ok = ([SWLC_cmd_WEST] call SWLC_fnc_stanceOf) == _wanted;
	[[format ["event=%1%2", ["fail_", ""] select _ok, _label], format ["stance=%1", [SWLC_cmd_WEST] call SWLC_fnc_stanceOf], format ["waited=%1", round (time - _t0)]]] call SWLG_emit;
	_ok
};

[[ "event=start", format ["min=%1", SWLC_settings get "stanceMinSeconds"]]] call SWLG_emit;
sleep 40;

// Far more enemy than the side can match, so the ratio is well under every threshold.
[["event=weak"]] call SWLG_emit;
SWLG_knownWest = [600, 0, 0, 0];
["hold", 40, "reached_hold"] call SWLG_waitStance;
["rebuild", 130, "reached_rebuild"] call SWLG_waitStance;

// The enemy stops being seen. The remembered peak fades, the ratio climbs, and the minimum time holds the side back on the way up.
[["event=recover"]] call SWLG_emit;
SWLG_knownWest = [0, 0, 0, 0];
["attack", 300, "reached_attack"] call SWLG_waitStance;
sleep 30;

// A commit-timer rebuild has to put the side in the rebuild stance at once and keep it there to the end.
private _until = time + 100;
SWLC_cmd_WEST set ["rebuildUntil", _until];
[["event=commit_set", format ["until=%1", round _until]]] call SWLG_emit;
["rebuild", 30, "commit_rebuild"] call SWLG_waitStance;
waitUntil {sleep 2; time >= _until};
[["event=commit_over"]] call SWLG_emit;
["attack", 200, "commit_attack"] call SWLG_waitStance;

[[format ["event=done"], format ["east=%1", [SWLC_cmd_EAST] call SWLC_fnc_stanceOf]]] call SWLG_emit;
